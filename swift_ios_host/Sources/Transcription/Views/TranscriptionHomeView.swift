import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Core

struct TranscriptionHomeView: View {
    @StateObject private var vm = TranscriptionHomeViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var showingPurchase = false
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                startTranscriptionCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            } header: {
                Text("开始扒歌")
            }

            if let activeTask = vm.activeTask {
                Section {
                    TranscriptionActiveTaskCard(
                        task: activeTask,
                        queuedCount: vm.queuedTaskCount,
                        onOpen: vm.showProcessingDetails,
                        onCancel: vm.cancelProcessing,
                        onOpenChordResult: { entry in vm.selectedEntry = entry },
                        onOpenStemResult: { result in vm.selectedStemResult = result }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text(activeTask.progressState.stage == .completed ? "最近完成" : "正在处理")
                }
            }

            Section {
                if vm.recentHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("还没有 AI 扒歌谱")
                            .font(.headline)
                            .foregroundStyle(SwiftAppTheme.text)
                        Text("导入一首歌后，AI 生成的和弦时间轴和参考和弦谱会保存在这里。")
                            .font(.footnote)
                            .foregroundStyle(SwiftAppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(vm.recentHistory.prefix(3), id: \.id) { entry in
                        TranscriptionHomeRecentRow(
                            entry: entry,
                            onRename: { vm.beginRenameChordEntry(entry) },
                            onDelete: { await vm.delete(entry) }
                        )
                    }
                }
            } header: {
                Text("我的 AI 扒歌谱")
            }

            Section {
                if vm.recentStemResults.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("还没有分轨结果")
                            .font(.headline)
                            .foregroundStyle(SwiftAppTheme.text)
                        Text("选择“分离人声/伴奏”导入歌曲后，分离出的本地音轨会保存在这里。")
                            .font(.footnote)
                            .foregroundStyle(SwiftAppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(vm.recentStemResults.prefix(3), id: \.id) { result in
                        StemSeparationHomeRecentRow(
                            result: result,
                            onRename: { vm.beginRenameStemResult(result) },
                            onDelete: { await vm.deleteStemResult(result) }
                        )
                    }
                }
            } header: {
                Text("我的分轨结果")
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
                        TabBarHiddenContainer {
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
        }
        .task {
            await vm.reload()
            if !purchaseManager.canAccessTranscription {
                await purchaseManager.loadProduct()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await vm.reload() }
        }
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
        .sheet(isPresented: $vm.showingProcessingDetails) {
            NavigationStack {
                if let state = vm.activeTask {
                    TranscriptionProcessingView(
                        fileName: state.fileName,
                        progressState: state.progressState,
                        onCollapse: vm.hideProcessingDetails,
                        onCancel: vm.cancelProcessing,
                        onRetry: vm.retryProcessing
                    )
                }
            }
        }
        .navigationDestination(item: $vm.selectedEntry) { entry in
            TabBarHiddenContainer {
                TranscriptionResultView(entry: entry)
            }
        }
        .navigationDestination(item: $vm.selectedStemResult) { result in
            TabBarHiddenContainer {
                StemSeparationResultView(result: result)
            }
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
            Button(vm.confirmImportButtonTitle) {
                vm.confirmImport()
            }
        } message: {
            Text("名称支持重复，后续历史和结果页会显示这个名字。")
        }
        .sheet(isPresented: $showingPurchase) {
            PurchaseView()
        }
        .alert("修改记录名称", isPresented: $vm.showingRenamePrompt) {
            TextField("例如：周杰伦-晴天", text: $vm.renameDraft)
            Button("取消", role: .cancel) {
                vm.cancelRename()
            }
            Button("保存") {
                Task { await vm.confirmRename() }
            }
        } message: {
            Text("修改后会在历史列表和结果页显示新名称。")
        }
        .accessibilityIdentifier("screen.transcription.home")
    }

    private var startTranscriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择一段歌曲音频或视频")
                .font(.headline)
                .foregroundStyle(SwiftAppTheme.text)

            VStack(alignment: .leading, spacing: 8) {
                Text("选择处理方式")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.text)

                ForEach(TranscriptionProcessingMode.allCases) { mode in
                    TranscriptionProcessingModeRow(
                        mode: mode,
                        isSelected: vm.selectedProcessingMode == mode
                    ) {
                        vm.selectedProcessingMode = mode
                    }
                }
            }

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
            .accessibilityIdentifier("transcription.importPhotos")
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
            .accessibilityIdentifier("transcription.importFiles")

            Text(LocalizedStringResource("transcribe_formats_hint", bundle: .main))
                .font(.footnote)
                .foregroundStyle(SwiftAppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !purchaseManager.canAccessTranscription {
                Text("未解锁时点击导入会打开购买页。")
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SwiftAppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
        .accessibilityIdentifier("transcription.startCard")
    }
}

private struct TranscriptionProcessingModeRow: View {
    let mode: TranscriptionProcessingMode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? SwiftAppTheme.brand : SwiftAppTheme.muted)
                    .frame(width: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? SwiftAppTheme.brand : SwiftAppTheme.line)
                    .padding(.top, 1)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? SwiftAppTheme.brand.opacity(0.08) : SwiftAppTheme.surfaceSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? SwiftAppTheme.brand.opacity(0.45) : SwiftAppTheme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TranscriptionHomeRecentRow: View {
    let entry: TranscriptionHistoryEntry
    let onRename: () -> Void
    let onDelete: () async -> Void

    var body: some View {
        let keyLine = String(format: AppL10n.t("transcribe_original_key"), entry.originalKey)
        return NavigationLink {
            TabBarHiddenContainer {
                TranscriptionResultView(entry: entry)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                TranscriptionHistoryBadge(entry: entry)
                Text(entry.displayName)
                    .foregroundStyle(SwiftAppTheme.text)
                Text(keyLine)
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onRename) {
                Label("改名", systemImage: "pencil")
            }
            .tint(SwiftAppTheme.brand)
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

private struct StemSeparationHomeRecentRow: View {
    let result: StemSeparationResult
    let onRename: () -> Void
    let onDelete: () async -> Void

    var body: some View {
        NavigationLink {
            TabBarHiddenContainer {
                StemSeparationResultView(result: result)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("人声/伴奏分轨")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SwiftAppTheme.brand.opacity(0.16))
                    .clipShape(Capsule())
                Text(result.displayName)
                    .foregroundStyle(SwiftAppTheme.text)
                Text("\(result.durationText) · \(Int(result.sampleRate.rounded())) Hz")
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onRename) {
                Label("改名", systemImage: "pencil")
            }
            .tint(SwiftAppTheme.brand)
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

private struct TranscriptionActiveTaskCard: View {
    let task: TranscriptionProcessingState
    let queuedCount: Int
    let onOpen: () -> Void
    let onCancel: () -> Void
    let onOpenChordResult: (TranscriptionHistoryEntry) -> Void
    let onOpenStemResult: (StemSeparationResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: task.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(task.progressState.isFailed ? .orange : SwiftAppTheme.brand)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.fileName)
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                        .lineLimit(1)
                    Text(task.mode.title)
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                }

                Spacer(minLength: 8)

                Text("\(task.progressState.percentage)%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.text)
            }

            ProgressView(value: task.progressState.clampedProgress)
                .progressViewStyle(.linear)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.progressState.message)
                    .font(.footnote)
                    .foregroundStyle(task.progressState.isFailed ? .orange : SwiftAppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let etaText = task.progressState.estimatedRemainingText {
                    Text(etaText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SwiftAppTheme.muted)
                }
            }

            if queuedCount > 0 {
                Text("后面还有 \(queuedCount) 首等待处理")
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
            }

            HStack(spacing: 10) {
                if task.progressState.stage == .completed {
                    Button("查看结果") {
                        if let entry = task.completedEntry {
                            onOpenChordResult(entry)
                        } else if let result = task.completedStemResult {
                            onOpenStemResult(result)
                        }
                    }
                    .appPrimaryButton()
                } else {
                    Button("查看进度", action: onOpen)
                        .appPrimaryButton()
                    Button("取消", action: onCancel)
                        .appSecondaryButton()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SwiftAppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }
}

struct TranscriptionHistoryBadge: View {
    let entry: TranscriptionHistoryEntry

    private var title: String {
        if entry.editedChordChartSegments?.isEmpty == false {
            return "已编辑参考谱"
        }
        return "AI 扒歌谱"
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(SwiftAppTheme.brand)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(SwiftAppTheme.brand.opacity(0.16))
            .clipShape(Capsule())
    }
}

@MainActor
final class TranscriptionHomeViewModel: ObservableObject {
    @Published var recentHistory: [TranscriptionHistoryEntry] = []
    @Published var recentStemResults: [StemSeparationResult] = []
    @Published var showingAlert = false
    @Published var alertMessage = ""
    @Published var activeTask: TranscriptionProcessingState?
    @Published var showingProcessingDetails = false
    @Published var selectedEntry: TranscriptionHistoryEntry?
    @Published var selectedStemResult: StemSeparationResult?
    @Published var selectedProcessingMode: TranscriptionProcessingMode = .chordOnlyFast
    @Published var showingImportNamingPrompt = false
    @Published var pendingImportCustomName = ""
    @Published var showingRenamePrompt = false
    @Published var renameDraft = ""

    private let historyStore = TranscriptionHistoryStore()
    private let stemStoreRootURL: URL?
    private let stemTaskStoreRootURL: URL?
    private var currentTask: Task<Void, Never>?
    private var analyzingProgressTask: Task<Void, Never>?
    private var pendingImportRequest: PendingImportRequest?
    private var queuedImports: [QueuedImportRequest] = []
    private var pendingRenameTarget: RenameTarget?
    private var lastProgressPublishAt: Date?
    private var lastProgressPublishPercentage: Int?
    private var lastProgressPublishStage: TranscriptionProgressStage?
    private var processingETAStart: (date: Date, progress: Double)?
    private var lastEstimatedRemainingSeconds: Int?
    private var isIdleTimerProtected = false

    var queuedTaskCount: Int {
        queuedImports.count
    }

    init() {
        stemStoreRootURL = Self.defaultStemStoreRootURL()
        stemTaskStoreRootURL = Self.defaultStemTaskStoreRootURL()
    }

    deinit {
        currentTask?.cancel()
        analyzingProgressTask?.cancel()
        if isIdleTimerProtected {
            Task { @MainActor in
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    func reload() async {
        recentHistory = await historyStore.loadAll()
        if let stemStoreRootURL {
            recentStemResults = await StemSeparationStore(rootURL: stemStoreRootURL).loadAll()
        }
        resumePendingStemTaskIfNeeded()
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

    func deleteStemResult(_ result: StemSeparationResult) async {
        guard let stemStoreRootURL else { return }
        do {
            try await StemSeparationStore(rootURL: stemStoreRootURL).remove(id: result.id)
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

    func beginRenameChordEntry(_ entry: TranscriptionHistoryEntry) {
        pendingRenameTarget = .chord(entry)
        renameDraft = entry.displayName
        showingRenamePrompt = true
    }

    func beginRenameStemResult(_ result: StemSeparationResult) {
        pendingRenameTarget = .stem(result)
        renameDraft = result.displayName
        showingRenamePrompt = true
    }

    func cancelRename() {
        pendingRenameTarget = nil
        renameDraft = ""
        showingRenamePrompt = false
    }

    func confirmRename() async {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertMessage = "名称不能为空"
            showingAlert = true
            return
        }
        guard let pendingRenameTarget else { return }
        do {
            switch pendingRenameTarget {
            case let .chord(entry):
                try await historyStore.rename(id: entry.id, customName: trimmed)
            case let .stem(result):
                guard let stemStoreRootURL else { return }
                try await StemSeparationStore(rootURL: stemStoreRootURL).rename(id: result.id, customName: trimmed)
            }
            cancelRename()
            await reload()
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    func importPhotoItem(_ item: PhotosPickerItem) async {
        preparePhotoImport(item)
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
        enqueueImport(
            source: pendingImportRequest.source,
            customName: customName,
            mode: pendingImportRequest.mode
        )
    }

    func cancelProcessing() {
        let persistentStemTaskID = activeTask?.persistentStemTaskID
        currentTask?.cancel()
        currentTask = nil
        stopAnalyzingTimer()
        logProgress("cancelled")
        activeTask = nil
        showingProcessingDetails = false
        resetProgressPublishThrottle()
        resetProcessingETA()
        setIdleTimerProtection(false)
        removePersistentStemTaskIfNeeded(id: persistentStemTaskID)
        startNextQueuedImportIfNeeded()
    }

    func retryProcessing() {
        guard let state = activeTask else { return }
        logProgress("retry tapped")
        activeTask = nil
        currentTask?.cancel()
        currentTask = nil
        resetProgressPublishThrottle()
        resetProcessingETA()
        setIdleTimerProtection(false)
        startImportNow(state.request)
    }

    func showProcessingDetails() {
        guard activeTask != nil else { return }
        showingProcessingDetails = true
    }

    func hideProcessingDetails() {
        showingProcessingDetails = false
    }

    private func prepareImport(url: URL, sourceType: TranscriptionSourceType, requiresSecurityScopedAccess: Bool) {
        pendingImportRequest = PendingImportRequest(
            source: .file(url: url, sourceType: sourceType, requiresSecurityScopedAccess: requiresSecurityScopedAccess),
            mode: selectedProcessingMode
        )
        pendingImportCustomName = defaultCustomName(from: url)
        showingImportNamingPrompt = true
    }

    private func preparePhotoImport(_ item: PhotosPickerItem) {
        pendingImportRequest = PendingImportRequest(
            source: .photoItem(item),
            mode: selectedProcessingMode
        )
        pendingImportCustomName = "相册导入"
        showingImportNamingPrompt = true
    }

    private func enqueueImport(
        source: ImportRequestSource,
        customName: String,
        mode: TranscriptionProcessingMode
    ) {
        let request = QueuedImportRequest(
            source: source,
            customName: customName,
            mode: mode
        )
        if activeTask == nil, currentTask == nil {
            startImportNow(request)
        } else {
            queuedImports.append(request)
        }
    }

    private func startNextQueuedImportIfNeeded() {
        guard activeTask == nil, currentTask == nil, !queuedImports.isEmpty else { return }
        let next = queuedImports.removeFirst()
        startImportNow(next)
    }

    private func startImportNow(_ request: QueuedImportRequest, showDetails: Bool = true) {
        stopAnalyzingTimer()
        resetProgressPublishThrottle()
        resetProcessingETA()
        setIdleTimerProtection(true)
        let initialSource = request.source.initialProcessingSource
        activeTask = TranscriptionProcessingState(
            fileName: request.customName,
            request: request,
            url: initialSource.url,
            sourceType: initialSource.sourceType,
            requiresSecurityScopedAccess: initialSource.requiresSecurityScopedAccess,
            mode: request.mode,
            persistentStemTaskID: request.persistentStemTaskID,
            progressState: .preparing()
        )
        showingProcessingDetails = showDetails
        logProgress("start import", state: .preparing())
        let processingID = activeTask?.id
        let historyStore = self.historyStore
        let stemStoreRootURL = self.stemStoreRootURL
        let stemTaskStoreRootURL = self.stemTaskStoreRootURL
        let mode = request.mode
        let customName = request.customName

        currentTask = Task { [weak self] in
            guard let self else { return }
            var stemTaskIDForCleanup = request.persistentStemTaskID
            do {
                await MainActor.run {
                    guard self.activeTask?.id == processingID else { return }
                    self.applyProgress(.preparing(0.01))
                }
                var resolvedSource = try await Self.resolveImportSource(request.source)
                try Task.checkCancellation()
                await MainActor.run {
                    guard let current = self.activeTask, current.id == processingID else { return }
                    self.activeTask = current.withResolvedSource(
                        url: resolvedSource.url,
                        sourceType: resolvedSource.sourceType,
                        requiresSecurityScopedAccess: resolvedSource.requiresSecurityScopedAccess
                    )
                }

                switch mode {
                case .chordOnlyFast:
                    let saved = try await Self.processImportedMedia(
                        url: resolvedSource.url,
                        sourceType: resolvedSource.sourceType,
                        requiresSecurityScopedAccess: resolvedSource.requiresSecurityScopedAccess,
                        customName: customName,
                        historyStore: historyStore
                    ) { progressState in
                        await MainActor.run {
                            guard self.activeTask?.id == processingID else { return }
                            self.applyProgress(progressState)
                        }
                    }

                    await MainActor.run {
                        guard self.activeTask?.id == processingID else { return }
                        self.stopAnalyzingTimer()
                        self.applyProgress(.completed(), completedEntry: saved, completedStemResult: nil)
                        self.showingProcessingDetails = false
                    }
                case .stemSeparationOnly:
                    guard let stemStoreRootURL, let stemTaskStoreRootURL else {
                        throw StemSeparationError.outputWriteFailed
                    }
                    let stemTaskStore = StemSeparationTaskStore(rootURL: stemTaskStoreRootURL)
                    var persistentStemTaskID = request.persistentStemTaskID
                    if let taskID = persistentStemTaskID, let existingTask = await stemTaskStore.load(id: taskID) {
                        stemTaskIDForCleanup = taskID
                        let inputURL = await stemTaskStore.inputURL(for: existingTask)
                        resolvedSource = ResolvedImportSource(
                            url: inputURL,
                            sourceType: .files,
                            requiresSecurityScopedAccess: false
                        )
                    } else {
                        let originalURL = resolvedSource.url
                        let originalSourceType = resolvedSource.sourceType
                        let didAccess = resolvedSource.requiresSecurityScopedAccess
                            ? originalURL.startAccessingSecurityScopedResource()
                            : false
                        do {
                            let task = try await stemTaskStore.createTask(
                                from: originalURL,
                                customName: customName,
                                originalFileName: originalURL.lastPathComponent
                            )
                            persistentStemTaskID = task.id
                            stemTaskIDForCleanup = task.id
                            let inputURL = await stemTaskStore.inputURL(for: task)
                            resolvedSource = ResolvedImportSource(
                                url: inputURL,
                                sourceType: .files,
                                requiresSecurityScopedAccess: false
                            )
                        } catch {
                            if didAccess {
                                originalURL.stopAccessingSecurityScopedResource()
                            }
                            throw error
                        }
                        if didAccess {
                            originalURL.stopAccessingSecurityScopedResource()
                        }
                        if originalSourceType == .photoLibrary {
                            Self.removeTemporaryImportFileIfNeeded(at: originalURL)
                        }
                    }
                    try Task.checkCancellation()
                    if let persistentStemTaskID {
                        try? await stemTaskStore.mark(id: persistentStemTaskID, state: .running)
                        await MainActor.run {
                            guard let current = self.activeTask, current.id == processingID else { return }
                            self.activeTask = current
                                .withPersistentStemTaskID(persistentStemTaskID)
                                .withResolvedSource(
                                    url: resolvedSource.url,
                                    sourceType: resolvedSource.sourceType,
                                    requiresSecurityScopedAccess: resolvedSource.requiresSecurityScopedAccess
                                )
                        }
                    }
                    let saved = try await Self.processStemSeparatedMedia(
                        url: resolvedSource.url,
                        sourceType: resolvedSource.sourceType,
                        requiresSecurityScopedAccess: resolvedSource.requiresSecurityScopedAccess,
                        customName: customName,
                        stemStoreRootURL: stemStoreRootURL
                    ) { progressState in
                        await MainActor.run {
                            guard self.activeTask?.id == processingID else { return }
                            self.applyProgress(progressState)
                        }
                    }
                    if let persistentStemTaskID {
                        try? await stemTaskStore.remove(id: persistentStemTaskID)
                    }

                    await MainActor.run {
                        guard self.activeTask?.id == processingID else { return }
                        self.stopAnalyzingTimer()
                        self.applyProgress(.completedStems(), completedEntry: nil, completedStemResult: saved)
                        self.showingProcessingDetails = false
                    }
                }
                await reload()
                await MainActor.run {
                    guard self.activeTask?.id == processingID else { return }
                    self.currentTask = nil
                    if !self.queuedImports.isEmpty {
                        self.activeTask = nil
                        self.resetProcessingETA()
                        self.setIdleTimerProtection(false)
                        self.startNextQueuedImportIfNeeded()
                    } else {
                        self.setIdleTimerProtection(false)
                    }
                }
            } catch is CancellationError {
                let cancelledTaskID = await MainActor.run { () -> String? in
                    guard self.activeTask?.id == processingID else { return nil }
                    return self.activeTask?.persistentStemTaskID
                } ?? stemTaskIDForCleanup
                if let cancelledTaskID, let stemTaskStoreRootURL {
                    try? await StemSeparationTaskStore(rootURL: stemTaskStoreRootURL).remove(id: cancelledTaskID)
                }
                await MainActor.run {
                    guard self.activeTask?.id == processingID else { return }
                    self.stopAnalyzingTimer()
                    self.logProgress("task cancelled")
                    self.activeTask = nil
                    self.showingProcessingDetails = false
                    self.currentTask = nil
                    self.resetProgressPublishThrottle()
                    self.resetProcessingETA()
                    self.setIdleTimerProtection(false)
                    self.startNextQueuedImportIfNeeded()
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "识别失败，请稍后重试"
                let failedTaskID = await MainActor.run { () -> String? in
                    guard self.activeTask?.id == processingID else { return nil }
                    return self.activeTask?.persistentStemTaskID
                }
                if let failedTaskID, let stemTaskStoreRootURL {
                    try? await StemSeparationTaskStore(rootURL: stemTaskStoreRootURL).mark(
                        id: failedTaskID,
                        state: .failed,
                        errorMessage: message
                    )
                }
                await MainActor.run {
                    guard self.activeTask?.id == processingID else { return }
                    self.stopAnalyzingTimer()
                    let failed = (self.activeTask?.progressState ?? .preparing()).failed(message: message)
                    self.applyProgress(failed)
                    self.currentTask = nil
                    self.setIdleTimerProtection(false)
                }
            }
        }
    }

    private static func resolveImportSource(_ source: ImportRequestSource) async throws -> ResolvedImportSource {
        switch source {
        case let .file(url, sourceType, requiresSecurityScopedAccess):
            return ResolvedImportSource(
                url: url,
                sourceType: sourceType,
                requiresSecurityScopedAccess: requiresSecurityScopedAccess
            )
        case let .photoItem(item):
            guard let file = try await item.loadTransferable(type: PickedMovieFile.self) else {
                throw TranscriptionImportError.audioTrackReadFailed
            }
            return ResolvedImportSource(
                url: file.url,
                sourceType: .photoLibrary,
                requiresSecurityScopedAccess: false
            )
        }
    }

    private func applyProgress(
        _ progressState: TranscriptionProgressState,
        completedEntry: TranscriptionHistoryEntry? = nil,
        completedStemResult: StemSeparationResult? = nil
    ) {
        guard let current = activeTask else { return }
        let progressState = progressState.withEstimatedRemainingSeconds(
            estimatedRemainingSeconds(for: progressState, mode: current.mode)
        )
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
        let isForcedUpdate = progressState.stage != current.progressState.stage
            || progressState.stage == .failed
            || progressState.stage == .completed
            || completedEntry != nil
            || completedStemResult != nil
        guard shouldPublishProgress(progressState, force: isForcedUpdate) else {
            return
        }
        activeTask = current.with(
            progressState: progressState,
            completedEntry: completedEntry ?? current.completedEntry,
            completedStemResult: completedStemResult ?? current.completedStemResult
        )
        logProgress("state update", state: progressState)
    }

    private func shouldPublishProgress(_ progressState: TranscriptionProgressState, force: Bool) -> Bool {
        if force {
            rememberPublishedProgress(progressState)
            return true
        }
        let now = Date()
        let percentage = progressState.percentage
        if lastProgressPublishStage == progressState.stage,
           lastProgressPublishPercentage == percentage {
            return false
        }
        if let lastProgressPublishAt,
           now.timeIntervalSince(lastProgressPublishAt) < 0.25 {
            return false
        }
        rememberPublishedProgress(progressState, at: now)
        return true
    }

    private func rememberPublishedProgress(_ progressState: TranscriptionProgressState, at date: Date = Date()) {
        lastProgressPublishAt = date
        lastProgressPublishPercentage = progressState.percentage
        lastProgressPublishStage = progressState.stage
    }

    private func resetProgressPublishThrottle() {
        lastProgressPublishAt = nil
        lastProgressPublishPercentage = nil
        lastProgressPublishStage = nil
    }

    private func estimatedRemainingSeconds(
        for progressState: TranscriptionProgressState,
        mode: TranscriptionProcessingMode
    ) -> Int? {
        guard progressState.isActive else {
            return nil
        }
        switch progressState.stage {
        case .preparing, .analyzing, .generatingChart:
            return estimatedRemainingSeconds(
                for: progressState,
                targetProgress: mode == .chordOnlyFast ? 0.96 : 0.92,
                resetThreshold: 0.03,
                minimumElapsed: 1.5,
                minimumProgressDelta: 0.01
            )
        case .separatingStems:
            return estimatedRemainingSeconds(
                for: progressState,
                targetProgress: mode == .chordOnlyFast ? 0.96 : 0.92,
                resetThreshold: 0.11,
                minimumElapsed: 2.0,
                minimumProgressDelta: 0.02
            )
        case .savingStems:
            let estimated = min(lastEstimatedRemainingSeconds ?? 20, 20)
            lastEstimatedRemainingSeconds = estimated
            return estimated
        default:
            return lastEstimatedRemainingSeconds
        }
    }

    private func estimatedRemainingSeconds(
        for progressState: TranscriptionProgressState,
        targetProgress: Double,
        resetThreshold: Double,
        minimumElapsed: TimeInterval,
        minimumProgressDelta: Double
    ) -> Int? {
        let now = Date()
        if processingETAStart == nil || progressState.clampedProgress <= resetThreshold {
            processingETAStart = (now, progressState.clampedProgress)
            lastEstimatedRemainingSeconds = nil
            return nil
        }
        guard let start = processingETAStart else { return nil }
        let elapsed = now.timeIntervalSince(start.date)
        let progressDelta = progressState.clampedProgress - start.progress
        guard elapsed >= minimumElapsed, progressDelta >= minimumProgressDelta else {
            return lastEstimatedRemainingSeconds
        }
        let progressPerSecond = progressDelta / elapsed
        guard progressPerSecond > 0 else { return lastEstimatedRemainingSeconds }
        let remainingProgress = max(0.0, targetProgress - progressState.clampedProgress)
        let estimated = max(1, Int((remainingProgress / progressPerSecond).rounded()))
        lastEstimatedRemainingSeconds = estimated
        return estimated
    }

    private func resetProcessingETA() {
        processingETAStart = nil
        lastEstimatedRemainingSeconds = nil
    }

    private func setIdleTimerProtection(_ enabled: Bool) {
        guard isIdleTimerProtected != enabled else { return }
        isIdleTimerProtected = enabled
        UIApplication.shared.isIdleTimerDisabled = enabled
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
                        let current = self.activeTask,
                        current.progressState.stage == .analyzing
                    else { return }
                    let nextProgress = min(0.88, current.progressState.clampedProgress + 0.01)
                    guard nextProgress > current.progressState.clampedProgress else { return }
                    self.applyProgress(.analyzing(nextProgress))
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
        let resolved = state ?? activeTask?.progressState
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

        await onProgress(.preparing(0.02))
        let tempM4a = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        defer {
            try? FileManager.default.removeItem(at: tempM4a)
        }

        let decoded = try await TranscriptionMediaDecoder.decode(url: url)
        try Task.checkCancellation()

        await onProgress(.preparing(0.08))
        try await TranscriptionMediaDecoder.exportM4A(from: url, to: tempM4a)
        try Task.checkCancellation()

        await onProgress(.analyzing())
        let appToken = Secrets.chordOnnxAppToken
        let local = try await RemoteChordRecognitionService.transcribeAudio(
            fileURL: tempM4a,
            appToken: appToken,
            progressHandler: { fraction in
                Task { @MainActor in
                    await onProgress(.analyzing(0.45 + fraction * 0.43))
                }
            }
        )
        let rawSegments = local.segments
        let displaySegments = local.displaySegments
        let resolvedChartSegments = local.chordChartSegments
        try Task.checkCancellation()

        await onProgress(.generatingChart())
        let durationMs = local.durationMs
        let resolvedKey = local.originalKey
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
            timingVariants: local.timingVariants,
            timingVariantStats: local.timingVariantStats,
            backend: "remote",
            waveform: []
        )
        if sourceType == .photoLibrary {
            Self.removeTemporaryImportFileIfNeeded(at: url)
        }
        return entry
    }

    private static func processStemSeparatedMedia(
        url: URL,
        sourceType: TranscriptionSourceType,
        requiresSecurityScopedAccess: Bool,
        customName: String,
        stemStoreRootURL: URL,
        onProgress: @escaping @Sendable (TranscriptionProgressState) async -> Void
    ) async throws -> StemSeparationResult {
        let didAccess = requiresSecurityScopedAccess ? url.startAccessingSecurityScopedResource() : false
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let originalDurationMs = try await TranscriptionMediaDecoder.probeDuration(url: url)
        try TranscriptionImportService.validate(fileName: url.lastPathComponent, durationMs: originalDurationMs)
        try Task.checkCancellation()

        await onProgress(.preparing(0.05))
        let decoded = try await TranscriptionMediaDecoder.decode(url: url)
        try Task.checkCancellation()

        await onProgress(.separatingStems(0))
        let engine = StemSeparationEngine(modelRunner: try CoreMLStemSeparationRunner())
        let result = try await engine.separate(
            media: DecodedTranscriptionMedia(
                fileName: customName,
                durationMs: decoded.durationMs,
                pcmSamples: decoded.pcmSamples,
                sampleRate: decoded.sampleRate
            ),
            outputDirectory: stemStoreRootURL
        ) { progress in
            Task {
                switch progress.stage {
                case .preparing:
                    await onProgress(.preparing(0.08))
                case .separating:
                    await onProgress(.separatingStems(progress.fraction))
                case .writing:
                    await onProgress(.savingStems())
                case .completed:
                    await onProgress(.completedStems())
                }
            }
        }
        try Task.checkCancellation()

        await onProgress(.savingStems())
        try await StemSeparationStore(rootURL: stemStoreRootURL).save(result)
        if sourceType == .photoLibrary {
            Self.removeTemporaryImportFileIfNeeded(at: url)
        }
        return result
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

    private func resumePendingStemTaskIfNeeded() {
        guard activeTask == nil, currentTask == nil, let stemTaskStoreRootURL else { return }
        Task { [weak self] in
            let store = StemSeparationTaskStore(rootURL: stemTaskStoreRootURL)
            guard let task = await store.loadResumable().first else { return }
            let inputURL = await store.inputURL(for: task)
            await MainActor.run {
                guard let self, self.activeTask == nil, self.currentTask == nil else { return }
                self.startImportNow(
                    QueuedImportRequest(
                        source: .file(
                            url: inputURL,
                            sourceType: .files,
                            requiresSecurityScopedAccess: false
                        ),
                        customName: task.customName,
                        mode: .stemSeparationOnly,
                        persistentStemTaskID: task.id
                    ),
                    showDetails: false
                )
            }
        }
    }

    private func removePersistentStemTaskIfNeeded(id: String?) {
        guard let id, let stemTaskStoreRootURL else { return }
        Task {
            try? await StemSeparationTaskStore(rootURL: stemTaskStoreRootURL).remove(id: id)
        }
    }

    private static func defaultStemStoreRootURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("stem_separation", isDirectory: true)
    }

    private static func defaultStemTaskStoreRootURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("stem_separation_tasks", isDirectory: true)
    }

    var confirmImportButtonTitle: String {
        switch pendingImportRequest?.mode ?? selectedProcessingMode {
        case .chordOnlyFast:
            return "生成参考和弦"
        case .stemSeparationOnly:
            return "分离人声/伴奏"
        }
    }
}

struct PendingImportRequest {
    let source: ImportRequestSource
    let mode: TranscriptionProcessingMode
}

struct QueuedImportRequest {
    let source: ImportRequestSource
    let customName: String
    let mode: TranscriptionProcessingMode
    let persistentStemTaskID: String?

    init(
        source: ImportRequestSource,
        customName: String,
        mode: TranscriptionProcessingMode,
        persistentStemTaskID: String? = nil
    ) {
        self.source = source
        self.customName = customName
        self.mode = mode
        self.persistentStemTaskID = persistentStemTaskID
    }

    func withPersistentStemTaskID(_ id: String) -> QueuedImportRequest {
        QueuedImportRequest(
            source: source,
            customName: customName,
            mode: mode,
            persistentStemTaskID: id
        )
    }
}

enum ImportRequestSource {
    case file(url: URL, sourceType: TranscriptionSourceType, requiresSecurityScopedAccess: Bool)
    case photoItem(PhotosPickerItem)

    var initialProcessingSource: ResolvedImportSource {
        switch self {
        case let .file(url, sourceType, requiresSecurityScopedAccess):
            return ResolvedImportSource(
                url: url,
                sourceType: sourceType,
                requiresSecurityScopedAccess: requiresSecurityScopedAccess
            )
        case .photoItem:
            return ResolvedImportSource(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("photo-library-import"),
                sourceType: .photoLibrary,
                requiresSecurityScopedAccess: false
            )
        }
    }
}

struct ResolvedImportSource {
    let url: URL
    let sourceType: TranscriptionSourceType
    let requiresSecurityScopedAccess: Bool
}

private enum RenameTarget {
    case chord(TranscriptionHistoryEntry)
    case stem(StemSeparationResult)
}

struct TranscriptionProcessingState: Identifiable {
    let id: UUID
    let fileName: String
    let request: QueuedImportRequest
    let url: URL
    let sourceType: TranscriptionSourceType
    let requiresSecurityScopedAccess: Bool
    let mode: TranscriptionProcessingMode
    let persistentStemTaskID: String?
    let progressState: TranscriptionProgressState
    let completedEntry: TranscriptionHistoryEntry?
    let completedStemResult: StemSeparationResult?

    init(
        id: UUID = UUID(),
        fileName: String,
        request: QueuedImportRequest,
        url: URL,
        sourceType: TranscriptionSourceType,
        requiresSecurityScopedAccess: Bool,
        mode: TranscriptionProcessingMode,
        persistentStemTaskID: String? = nil,
        progressState: TranscriptionProgressState,
        completedEntry: TranscriptionHistoryEntry? = nil,
        completedStemResult: StemSeparationResult? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.request = request
        self.url = url
        self.sourceType = sourceType
        self.requiresSecurityScopedAccess = requiresSecurityScopedAccess
        self.mode = mode
        self.persistentStemTaskID = persistentStemTaskID
        self.progressState = progressState
        self.completedEntry = completedEntry
        self.completedStemResult = completedStemResult
    }

    func with(
        progressState: TranscriptionProgressState,
        completedEntry: TranscriptionHistoryEntry? = nil,
        completedStemResult: StemSeparationResult? = nil
    ) -> TranscriptionProcessingState {
        TranscriptionProcessingState(
            id: id,
            fileName: fileName,
            request: request,
            url: url,
            sourceType: sourceType,
            requiresSecurityScopedAccess: requiresSecurityScopedAccess,
            mode: mode,
            persistentStemTaskID: persistentStemTaskID,
            progressState: progressState,
            completedEntry: completedEntry ?? self.completedEntry,
            completedStemResult: completedStemResult ?? self.completedStemResult
        )
    }

    func withResolvedSource(
        url: URL,
        sourceType: TranscriptionSourceType,
        requiresSecurityScopedAccess: Bool
    ) -> TranscriptionProcessingState {
        TranscriptionProcessingState(
            id: id,
            fileName: fileName,
            request: request,
            url: url,
            sourceType: sourceType,
            requiresSecurityScopedAccess: requiresSecurityScopedAccess,
            mode: mode,
            persistentStemTaskID: persistentStemTaskID,
            progressState: progressState,
            completedEntry: completedEntry,
            completedStemResult: completedStemResult
        )
    }

    func withPersistentStemTaskID(_ id: String) -> TranscriptionProcessingState {
        TranscriptionProcessingState(
            id: self.id,
            fileName: fileName,
            request: request.withPersistentStemTaskID(id),
            url: url,
            sourceType: sourceType,
            requiresSecurityScopedAccess: requiresSecurityScopedAccess,
            mode: mode,
            persistentStemTaskID: id,
            progressState: progressState,
            completedEntry: completedEntry,
            completedStemResult: completedStemResult
        )
    }

    var iconName: String {
        if progressState.isFailed {
            return "exclamationmark.triangle.fill"
        }
        if progressState.stage == .completed {
            return "checkmark.circle.fill"
        }
        return mode.iconName
    }
}

enum TranscriptionProcessingMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case chordOnlyFast
    case stemSeparationOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chordOnlyFast:
            return "快速扒歌"
        case .stemSeparationOnly:
            return "分离人声/伴奏"
        }
    }

    var subtitle: String {
        switch self {
        case .chordOnlyFast:
            return "直接识别和弦，速度最快"
        case .stemSeparationOnly:
            return "本地分离人声和伴奏，结果保存在手机里"
        }
    }

    var iconName: String {
        switch self {
        case .chordOnlyFast:
            return "music.note.list"
        case .stemSeparationOnly:
            return "waveform"
        }
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
