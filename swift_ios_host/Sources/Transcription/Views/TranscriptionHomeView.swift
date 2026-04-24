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
                        NavigationLink {
                            TranscriptionResultView(entry: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.fileName)
                                    .foregroundStyle(SwiftAppTheme.text)
                                Text(String(format: AppL10n.t("transcribe_original_key"), entry.originalKey))
                                    .font(.caption)
                                    .foregroundStyle(SwiftAppTheme.muted)
                            }
                        }
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
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await vm.importPhotoItem(newValue)
                selectedPhotoItem = nil
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            vm.handleFileImportResult(result.map { $0.first })
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
    }
}

@MainActor
final class TranscriptionHomeViewModel: ObservableObject {
    @Published var recentHistory: [TranscriptionHistoryEntry] = []
    @Published var showingAlert = false
    @Published var alertMessage = ""
    @Published var processingState: TranscriptionProcessingState?
    @Published var selectedEntry: TranscriptionHistoryEntry?

    private let historyStore = TranscriptionHistoryStore()
    private var currentTask: Task<Void, Never>?

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
            startImport(url: url, sourceType: .files, requiresSecurityScopedAccess: true)
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
            startImport(url: file.url, sourceType: .photoLibrary, requiresSecurityScopedAccess: false)
        } catch {
            alertMessage = (error as? LocalizedError)?.errorDescription ?? AppL10n.t("transcribe_error_audio_read_failed")
            showingAlert = true
        }
    }

    func cancelProcessing() {
        currentTask?.cancel()
        currentTask = nil
        processingState = nil
    }

    private func startImport(url: URL, sourceType: TranscriptionSourceType, requiresSecurityScopedAccess: Bool) {
        currentTask?.cancel()
        let fileName = url.lastPathComponent
        processingState = TranscriptionProcessingState(fileName: fileName, stepText: "transcribe_step_extract_audio")
        let historyStore = self.historyStore

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await Self.processImportedMedia(
                    url: url,
                    sourceType: sourceType,
                    requiresSecurityScopedAccess: requiresSecurityScopedAccess,
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
        return try await historyStore.saveResult(
            sourceURL: url,
            sourceType: sourceType,
            fileName: payload.fileName,
            durationMs: payload.durationMs,
            originalKey: payload.originalKey,
            segments: payload.segments,
            waveform: payload.waveform
        )
    }
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
