import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Core

struct TranscriptionHomeView: View {
    @StateObject private var vm = TranscriptionHomeViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingFileImporter = false

    var body: some View {
        List {
            Section {
                PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                    Text(LocalizedStringResource("transcribe_import_from_photos", bundle: .main))
                        .frame(maxWidth: .infinity)
                }
                    .appPrimaryButton()
                Button(LocalizedStringResource("transcribe_import_from_files", bundle: .main)) { showingFileImporter = true }
                    .appSecondaryButton()
                Text(LocalizedStringResource("transcribe_formats_hint", bundle: .main))
                    .font(.footnote)
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
                        TranscriptionHistoryView(entries: vm.recentHistory) { entry in
                            Task { await vm.delete(entry) }
                        }
                    }
                }
            }
        }
        .task { await vm.reload() }
        .appPageBackground()
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.audio, .movie, .mpeg4Movie, .mp3],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let first = urls.first {
                    vm.handleFileImportResult(.success(first))
                } else {
                    vm.handleFileImportResult(.success(nil))
                }
            case let .failure(error):
                vm.handleFileImportResult(.failure(error))
            }
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await vm.importPhotoItem(newValue)
                selectedPhotoItem = nil
            }
        }
        .sheet(item: $vm.processingState) { state in
            NavigationStack {
                TranscriptionProcessingView(
                    fileName: state.fileName,
                    stepText: state.stepText,
                    onCancel: vm.cancelProcessing
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
            Button("开始识别") {
                vm.confirmImport()
            }
        } message: {
            Text("名称支持重复，后续历史和结果页会显示这个名字。")
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

    private let historyStore = TranscriptionHistoryStore()
    private var currentTask: Task<Void, Never>?
    private var pendingImportRequest: PendingImportRequest?

    deinit {
        currentTask?.cancel()
    }

    func reload() async {
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

    func handleFileImportResult(_ result: Result<URL?, Error>) {
        switch result {
        case let .success(.some(url)):
            prepareImport(url: url, sourceType: .files, requiresSecurityScopedAccess: true)
        case .success(.none):
            break
        case let .failure(error):
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
        processingState = nil
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
        processingState = TranscriptionProcessingState(fileName: customName, stepText: "transcribe_step_extract_audio")
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
                ) { stepText in
                    await MainActor.run {
                        guard let current = self.processingState else { return }
                        self.processingState = current.with(stepText: stepText)
                    }
                }

                await MainActor.run {
                    self.processingState = nil
                    self.selectedEntry = saved
                }
                await reload()
            } catch is CancellationError {
                await MainActor.run {
                    self.processingState = nil
                }
            } catch {
                await MainActor.run {
                    self.processingState = nil
                    self.alertMessage = (error as? LocalizedError)?.errorDescription ?? AppL10n.t("transcribe_error_chord_unstable")
                    self.showingAlert = true
                }
            }
        }
    }

    private static func processImportedMedia(
        url: URL,
        sourceType: TranscriptionSourceType,
        requiresSecurityScopedAccess: Bool,
        customName: String,
        historyStore: TranscriptionHistoryStore,
        onStep: @escaping @Sendable (String) async -> Void
    ) async throws -> TranscriptionHistoryEntry {
        let didAccess = requiresSecurityScopedAccess ? url.startAccessingSecurityScopedResource() : false
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let durationMs = try await TranscriptionMediaDecoder.probeDuration(url: url)
        try TranscriptionImportService.validate(fileName: url.lastPathComponent, durationMs: durationMs)
        try Task.checkCancellation()

        await onStep("transcribe_step_extract_audio")
        let decoded = try await TranscriptionMediaDecoder.decode(url: url)
        try Task.checkCancellation()

        await onStep("transcribe_step_recognize_chords")
        let payload = try await TranscriptionOrchestrator(recognizer: OnnxChordRecognizer()).recognize(
            fileName: decoded.fileName,
            durationMs: decoded.durationMs,
            samples: decoded.pcmSamples,
            sampleRate: decoded.sampleRate
        )
        guard !payload.segments.isEmpty else {
            throw TranscriptionImportError.noStableChordDetected
        }
        try Task.checkCancellation()

        await onStep("transcribe_step_finalize")
        let tempM4a = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        defer {
            try? FileManager.default.removeItem(at: tempM4a)
        }
        try await TranscriptionMediaDecoder.exportM4A(from: url, to: tempM4a)
        try Task.checkCancellation()

        let stem = (payload.fileName as NSString).deletingPathExtension
        let displayFileName = stem.isEmpty ? "recording.m4a" : "\(stem).m4a"

        let entry = try await historyStore.saveResult(
            sourceURL: tempM4a,
            sourceType: sourceType,
            fileName: displayFileName,
            customName: customName,
            durationMs: payload.durationMs,
            originalKey: payload.originalKey,
            segments: payload.segments,
            waveform: payload.waveform
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
}

private struct PendingImportRequest {
    let url: URL
    let sourceType: TranscriptionSourceType
    let requiresSecurityScopedAccess: Bool
}

struct TranscriptionProcessingState: Identifiable {
    let id: UUID
    let fileName: String
    let stepText: String

    init(id: UUID = UUID(), fileName: String, stepText: String) {
        self.id = id
        self.fileName = fileName
        self.stepText = stepText
    }

    func with(stepText: String) -> TranscriptionProcessingState {
        TranscriptionProcessingState(id: id, fileName: fileName, stepText: stepText)
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
