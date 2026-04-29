import OSLog
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Core

struct TranscriptionHomeView: View {
    @StateObject private var vm = TranscriptionHomeViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var showingPurchase = false
    @EnvironmentObject private var purchaseManager: PurchaseManager

    var body: some View {
        List {
            Section {
                Button {
                    if purchaseManager.canAccessTranscription {
                        showingPhotoPicker = true
                    } else {
                        showingPurchase = true
                    }
                } label: {
                    Text(LocalizedStringResource("transcribe_import_from_photos", bundle: .main))
                        .frame(maxWidth: .infinity)
                }
                .appPrimaryButton()
                .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .videos)

                Button {
                    if purchaseManager.canAccessTranscription {
                        showingFileImporter = true
                    } else {
                        showingPurchase = true
                    }
                } label: {
                    Text("从文件导入音频/视频")
                        .frame(maxWidth: .infinity)
                }
                .appSecondaryButton()
                Text(LocalizedStringResource("transcribe_formats_hint", bundle: .main))
                    .font(.footnote)
                    .foregroundStyle(SwiftAppTheme.muted)
                Text("内购环境：\(purchaseManager.runtimeEnvironment.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(SwiftAppTheme.muted)
            }

            if !vm.recentHistory.isEmpty {
                Section {
                    ForEach(vm.recentHistory.prefix(3), id: \.id) { entry in
                        TranscriptionHomeRecentRow(entry: entry, onDelete: { await vm.delete(entry) })
                    }
                } header: {
                    Text(LocalizedStringResource("transcribe_section_recent", bundle: .main))
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text(LocalizedStringResource("transcribe_privacy_notice", bundle: .main))
                    .font(.caption2)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .navigationTitle(LocalizedStringResource("transcribe_screen_title", bundle: .main))
        .toolbar {
            if !vm.recentHistory.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(LocalizedStringResource("transcribe_toolbar_history", bundle: .main)) {
                        TranscriptionHistoryView(
                            entries: vm.recentHistory,
                            onDelete: { entry in
                                Task { await vm.delete(entry) }
                            },
                            onRename: { entry, newName in
                                Task { await vm.rename(entry, to: newName) }
                            }
                        )
                    }
                }
            }
        }
        .task { await vm.reload() }
        .appPageBackground()
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await vm.importPhotoItem(newValue)
                selectedPhotoItem = nil
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.audio, .movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task {
                    await vm.importExternalFile(url)
                }
            case let .failure(error):
                vm.showImportError(error.localizedDescription)
            }
        }
        .sheet(item: $vm.processingState) { state in
            NavigationStack {
                TranscriptionProcessingView(
                    fileName: state.fileName,
                    progressState: state.progressState,
                    onCancel: vm.cancelProcessing,
                    onRetry: vm.retryProcessing
                )
            }
        }
        .navigationDestination(item: $vm.selectedEntry) { entry in
            TranscriptionResultView(entry: entry)
        }
        .alert(LocalizedStringResource("common_notice_title", bundle: .main), isPresented: $vm.showingAlert) {
            Button(LocalizedStringResource("button_ok", bundle: .main), role: .cancel) {}
        } message: {
            Text(vm.alertMessage)
        }
        .alert("给这首歌起个名字", isPresented: $vm.showingImportNamingPrompt) {
            TextField("例如：周杰伦-晴天", text: $vm.pendingImportCustomName)
            Button("取消", role: .cancel) {
                vm.cancelPendingImport()
            }
            Button("生成参考和弦") {
                vm.confirmImport()
            }
        } message: {
            Text("名称支持重复，后续历史和结果页会显示这个名字。")
        }
        .sheet(isPresented: $showingPurchase) {
            PurchaseView()
        }
    }
}

private struct TranscriptionHomeRecentRow: View {
    let entry: TranscriptionHistoryEntry
    let onDelete: () async -> Void

    var body: some View {
        let keyLine = String(format: AppL10n.t("transcribe_original_key"), entry.originalKey)
        return NavigationLink {
            TranscriptionResultView(entry: entry)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .foregroundStyle(SwiftAppTheme.text)
                Text(keyLine)
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await onDelete() }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

@MainActor
final class TranscriptionHomeViewModel: ObservableObject {
    @Published var recentHistory: [TranscriptionHistoryEntry] = []
    @Published var showingAlert = false
    @Published var alertMessage = ""
    @Published var processingState: TranscriptionProcessingState?
    @Published var selectedEntry: TranscriptionHistoryEntry?
    @Published var showingImportNamingPrompt = false
    @Published var pendingImportCustomName = ""

    @AppStorage("transcription_remote_preflight_done") private var didRunNetworkPreflight = false

    private let historyStore = TranscriptionHistoryStore()
    private var currentTask: Task<Void, Never>?
    private var analyzingProgressTask: Task<Void, Never>?
    private var pendingImportRequest: PendingImportRequest?

    deinit {
        currentTask?.cancel()
        analyzingProgressTask?.cancel()
    }

    func reload() async {
        await ensureNetworkPreflightIfNeeded()
        recentHistory = await historyStore.loadAll()
    }

    func delete(_ entry: TranscriptionHistoryEntry) async {
        do {
            try await historyStore.remove(id: entry.id)
            await reload()
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    func rename(_ entry: TranscriptionHistoryEntry, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertMessage = "名称不能为空"
            showingAlert = true
            return
        }
        do {
            try await historyStore.rename(id: entry.id, customName: trimmed)
            await reload()
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    func importPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let file = try await item.loadTransferable(type: PickedMovieFile.self) else {
                throw TranscriptionImportError.audioTrackReadFailed
            }
            prepareImport(url: file.url, sourceType: .photoLibrary, requiresSecurityScopedAccess: false)
        } catch {
            alertMessage = (error as? LocalizedError)?.errorDescription ?? AppL10n.t("transcribe_error_audio_read_failed")
            showingAlert = true
        }
    }

    func importExternalFile(_ url: URL) async {
        prepareImport(url: url, sourceType: .files, requiresSecurityScopedAccess: true)
    }

    func showImportError(_ message: String) {
        alertMessage = message
        showingAlert = true
    }

    func cancelPendingImport() {
        pendingImportRequest = nil
        pendingImportCustomName = ""
        showingImportNamingPrompt = false
    }

    func confirmImport() {
        let customName = pendingImportCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !customName.isEmpty else {
            alertMessage = "请先输入名称"
            showingAlert = true
            return
        }
        guard let pendingImportRequest else { return }
        showingImportNamingPrompt = false
        pendingImportCustomName = ""
        self.pendingImportRequest = nil
        startImport(
            url: pendingImportRequest.url,
            sourceType: pendingImportRequest.sourceType,
            requiresSecurityScopedAccess: pendingImportRequest.requiresSecurityScopedAccess,
            customName: customName
        )
    }

    func cancelProcessing() {
        currentTask?.cancel()
        currentTask = nil
        stopAnalyzingTimer()
        logProgress("cancelled")
        processingState = nil
    }

    func retryProcessing() {
        guard let state = processingState else { return }
        logProgress("retry tapped")
        startImport(
            url: state.url,
            sourceType: state.sourceType,
            requiresSecurityScopedAccess: state.requiresSecurityScopedAccess,
            customName: state.fileName
        )
    }

    private func prepareImport(url: URL, sourceType: TranscriptionSourceType, requiresSecurityScopedAccess: Bool) {
        pendingImportRequest = PendingImportRequest(
            url: url,
            sourceType: sourceType,
            requiresSecurityScopedAccess: requiresSecurityScopedAccess
        )
        pendingImportCustomName = defaultCustomName(from: url)
        showingImportNamingPrompt = true
    }

    private func startImport(
        url: URL,
        sourceType: TranscriptionSourceType,
        requiresSecurityScopedAccess: Bool,
        customName: String
    ) {
        currentTask?.cancel()
        stopAnalyzingTimer()
        processingState = TranscriptionProcessingState(
            fileName: customName,
            url: url,
            sourceType: sourceType,
            requiresSecurityScopedAccess: requiresSecurityScopedAccess,
            progressState: .preparing()
        )
        logProgress("start import", state: .preparing())
        let processingID = processingState?.id
        let historyStore = self.historyStore

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await Self.processImportedMedia(
                    url: url,
                    sourceType: sourceType,
                    requiresSecurityScopedAccess: requiresSecurityScopedAccess,
                    customName: customName,
                    historyStore: historyStore
                ) { progressState in
                    await MainActor.run {
                        guard self.processingState?.id == processingID else { return }
                        self.applyProgress(progressState)
                    }
                }

                await MainActor.run {
                    guard self.processingState?.id == processingID else { return }
                    self.stopAnalyzingTimer()
                    self.applyProgress(.completed())
                    self.processingState = nil
                    self.selectedEntry = saved
                }
                await reload()
            } catch is CancellationError {
                await MainActor.run {
                    guard self.processingState?.id == processingID else { return }
                    self.stopAnalyzingTimer()
                    self.logProgress("task cancelled")
                    self.processingState = nil
                }
            } catch {
                await MainActor.run {
                    guard self.processingState?.id == processingID else { return }
                    self.stopAnalyzingTimer()
                    let message = (error as? LocalizedError)?.errorDescription ?? "识别失败，请稍后重试"
                    let failed = (self.processingState?.progressState ?? .preparing()).failed(message: message)
                    self.applyProgress(failed)
                }
            }
        }
    }

    private func applyProgress(_ progressState: TranscriptionProgressState) {
        guard let current = processingState else { return }
        if current.progressState.stage == .failed, progressState.stage != .preparing {
            return
        }
        if progressState.stage != .preparing,
           progressState.stage != .failed,
           progressState.clampedProgress < current.progressState.clampedProgress {
            logProgress("ignored stale progress", state: progressState)
            return
        }
        if progressState.stage == .analyzing {
            startAnalyzingTimerIfNeeded()
        }
        if progressState.stage == .failed || progressState.stage == .completed {
            stopAnalyzingTimer()
        }
        processingState = current.with(progressState: progressState)
        logProgress("state update", state: progressState)
    }

    private func startAnalyzingTimerIfNeeded() {
        guard analyzingProgressTask == nil else { return }
        logProgress("start analyzing timer")
        analyzingProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    guard
                        let self,
                        let current = self.processingState,
                        current.progressState.stage == .analyzing
                    else { return }
                    let nextProgress = min(0.88, current.progressState.clampedProgress + 0.01)
                    guard nextProgress > current.progressState.clampedProgress else { return }
                    self.processingState = current.with(progressState: .analyzing(nextProgress))
                    self.logProgress("analyzing timer", state: .analyzing(nextProgress))
                }
            }
        }
    }

    private func stopAnalyzingTimer() {
        analyzingProgressTask?.cancel()
        analyzingProgressTask = nil
    }

    private func logProgress(_ event: String, state: TranscriptionProgressState? = nil) {
        #if DEBUG
        let resolved = state ?? processingState?.progressState
        if let resolved {
            print("[TranscriptionProgress] \(event) stage=\(resolved.stage.rawValue) progress=\(resolved.percentage)% message=\(resolved.message)")
        } else {
            print("[TranscriptionProgress] \(event)")
        }
        #endif
    }

    private static func processImportedMedia(
        url: URL,
        sourceType: TranscriptionSourceType,
        requiresSecurityScopedAccess: Bool,
        customName: String,
        historyStore: TranscriptionHistoryStore,
        onProgress: @escaping @Sendable (TranscriptionProgressState) async -> Void
    ) async throws -> TranscriptionHistoryEntry {
        let didAccess = requiresSecurityScopedAccess ? url.startAccessingSecurityScopedResource() : false
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let originalDurationMs = try await TranscriptionMediaDecoder.probeDuration(url: url)
        try TranscriptionImportService.validate(fileName: url.lastPathComponent, durationMs: originalDurationMs)
        try Task.checkCancellation()

        let originalMediaBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue

        await onProgress(.preparing(0.02))
        let tempCompressedM4A = FileManager.default.temporaryDirectory
            .appendingPathComponent("chord-upload-\(UUID().uuidString).m4a")

        let tempWav = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        let tempM4a = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        defer {
            try? FileManager.default.removeItem(at: tempCompressedM4A)
            try? FileManager.default.removeItem(at: tempWav)
            try? FileManager.default.removeItem(at: tempM4a)
        }

        var uploadFileURL = tempCompressedM4A
        var multipartFilename = "compressed.m4a"
        do {
            try await TranscriptionMediaDecoder.exportCompressedM4AForRemoteUpload(
                from: url,
                to: tempCompressedM4A,
                aacBitrate: 96_000
            )
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "SwiftEarHost", category: "RemoteChord").warning(
                "compressed m4a export failed, using WAV fallback (large upload): \(String(describing: error))"
            )
            #if DEBUG
            print("[RemoteChord] compressed m4a export failed, fallback wav: \(error)")
            #endif
            let decoded = try await TranscriptionMediaDecoder.decode(url: url)
            try TranscriptionMediaDecoder.writeWAV(
                samples: decoded.pcmSamples,
                sampleRate: decoded.sampleRate,
                to: tempWav
            )
            uploadFileURL = tempWav
            multipartFilename = "fallback.wav"
        }
        try Task.checkCancellation()

        await onProgress(.preparing(0.08))
        try await TranscriptionMediaDecoder.exportM4A(from: url, to: tempM4a)
        try Task.checkCancellation()

        await onProgress(.uploading(uploadFraction: 0.0))
        let outcome = try await RemoteChordRecognitionService.transcribeAudio(
            fileURL: uploadFileURL,
            multipartFilename: multipartFilename,
            originalMediaBytes: originalMediaBytes,
            onUploadProgress: { fraction in
                Task { await onProgress(.uploading(uploadFraction: fraction)) }
            },
            onAnalyzingStarted: {
                Task { await onProgress(.analyzing()) }
            }
        )
        let remote = outcome.result
        #if DEBUG
        let st = remote.timing
        print(
            String(
                format: "[RemoteChord][summary] originalBytes=%@ m4aOrWavUploadBytes=%d uploadSec=%@ clientTotalSec=%.3f serverInferSec=%.3f serverTotalSec=%.3f",
                originalMediaBytes.map { String($0) } ?? "nil",
                outcome.uploadFileBytes,
                outcome.uploadSeconds.map { String(format: "%.3f", $0) } ?? "nil",
                outcome.clientTotalSeconds,
                st?.inferenceSec ?? -1,
                st?.totalSec ?? -1
            )
        )
        #endif
        let rawSegments = remote.segments.map { $0.toTranscriptionSegment() }
        let displaySegments = remote.displaySegments.map { $0.toTranscriptionSegment() }
        let simplifiedSegments = (remote.simplifiedDisplaySegments ?? []).map { $0.toTranscriptionSegment() }
        let chartSegments = (remote.chordChartSegments ?? []).map { $0.toTranscriptionSegment() }
        let resolvedChartSegments: [TranscriptionSegment] = {
            if !chartSegments.isEmpty { return chartSegments }
            if !simplifiedSegments.isEmpty { return simplifiedSegments }
            return displaySegments
        }()

        guard !displaySegments.isEmpty else {
            throw TranscriptionImportError.noStableChordDetected
        }
        try Task.checkCancellation()

        await onProgress(.generatingChart())
        let durationMs = Int(((remote.duration ?? 0) * 1000).rounded())
        let resolvedKey = (remote.key?.isEmpty == false) ? remote.key! : "C"
        #if DEBUG
        print("[RemoteChord] key=\(resolvedKey) displaySegments=\(displaySegments.count) chordChartSegments=\(resolvedChartSegments.count)")
        #endif

        let stem = (url.lastPathComponent as NSString).deletingPathExtension
        let displayFileName = stem.isEmpty ? "recording.m4a" : "\(stem).m4a"

        let entry = try await historyStore.saveResult(
            sourceURL: tempM4a,
            sourceType: sourceType,
            fileName: displayFileName,
            customName: customName,
            durationMs: durationMs > 0 ? durationMs : originalDurationMs,
            originalKey: resolvedKey,
            segments: rawSegments,
            displaySegments: displaySegments,
            chordChartSegments: resolvedChartSegments,
            timingVariants: remote.timingVariants,
            timingVariantStats: remote.timingVariantStats,
            backend: "remote",
            waveform: []
        )
        if sourceType == .photoLibrary {
            Self.removeTemporaryImportFileIfNeeded(at: url)
        }
        return entry
    }

    /// 相册导入时拷贝到 tmp 的整段视频，长期仅存 m4a 后可删除，避免双份大文件。
    private static func removeTemporaryImportFileIfNeeded(at url: URL) {
        let tmpRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let resolved = url.resolvingSymlinksInPath()
        let tmpPath = tmpRoot.path
        let path = resolved.path
        guard path == tmpPath || path.hasPrefix(tmpPath + "/") else { return }
        try? FileManager.default.removeItem(at: resolved)
    }

    private func defaultCustomName(from url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? url.lastPathComponent : base
    }

    private func ensureNetworkPreflightIfNeeded() async {
        guard !didRunNetworkPreflight else { return }
        didRunNetworkPreflight = true
        await RemoteChordRecognitionService.preflightNetworkAccess()
    }
}

private struct PendingImportRequest {
    let url: URL
    let sourceType: TranscriptionSourceType
    let requiresSecurityScopedAccess: Bool
}

struct TranscriptionProcessingState: Identifiable {
    let id: UUID
    let fileName: String
    let url: URL
    let sourceType: TranscriptionSourceType
    let requiresSecurityScopedAccess: Bool
    let progressState: TranscriptionProgressState

    init(
        id: UUID = UUID(),
        fileName: String,
        url: URL,
        sourceType: TranscriptionSourceType,
        requiresSecurityScopedAccess: Bool,
        progressState: TranscriptionProgressState
    ) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.sourceType = sourceType
        self.requiresSecurityScopedAccess = requiresSecurityScopedAccess
        self.progressState = progressState
    }

    func with(progressState: TranscriptionProgressState) -> TranscriptionProcessingState {
        TranscriptionProcessingState(
            id: id,
            fileName: fileName,
            url: url,
            sourceType: sourceType,
            requiresSecurityScopedAccess: requiresSecurityScopedAccess,
            progressState: progressState
        )
    }
}

private struct PickedMovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let fileName = received.file.deletingPathExtension().lastPathComponent.isEmpty
                ? "photo-video"
                : received.file.deletingPathExtension().lastPathComponent
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(fileName)-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: received.file, to: dst)
            return PickedMovieFile(url: dst)
        }
    }
}
