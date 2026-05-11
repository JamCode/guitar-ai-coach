import SwiftUI
import PhotosUI
import Core
import Metronome
import Practice
import UIKit

struct SheetLibraryView: View {
    @ObservedObject var vm: SheetLibraryViewModel
    @State private var pickerItems: [PhotosPickerItem] = []
    /// `PhotosPicker` 用 `isPresented` 在工具栏按钮外弹出系统相册，避免嵌在 `Menu` 内时部分系统点击无效。
    @State private var showingPhotoLibrary = false
    @State private var showingDraft = false
    @State private var draftImageData: [Data] = []
    @State private var renameDraft = ""

    var body: some View {
        Group {
            if vm.loading, !vm.hasLoadedOnce {
                ProgressView()
            } else if let error = vm.error {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(SwiftAppTheme.muted)
                    Button(LocalizedStringResource("sheets_button_retry", bundle: .main)) { Task { await vm.reload() } }.appPrimaryButton()
                }
            } else if vm.entries.isEmpty {
                VStack(alignment: .center, spacing: 16) {
                    Text(LocalizedStringResource("sheets_empty_message", bundle: .main))
                        .multilineTextAlignment(.center)
                    Text(LocalizedStringResource("sheets_privacy_notice", bundle: .main))
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                listView
            }
        }
        .navigationTitle(LocalizedStringResource("sheets_screen_title", bundle: .main))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPhotoLibrary = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(LocalizedStringResource("sheets_a11y_add_from_album", bundle: .main))
                .accessibilityIdentifier("sheets.addFromAlbum")
            }
        }
        .photosPicker(
            isPresented: $showingPhotoLibrary,
            selection: $pickerItems,
            maxSelectionCount: 20,
            matching: .images
        )
        .task { await vm.reload() }
        .onChange(of: pickerItems) { _, newItems in
            Task {
                let images = await decodePhotosItems(newItems)
                if images.isEmpty { return }
                draftImageData = images
                showingDraft = true
                pickerItems = []
            }
        }
        .sheet(isPresented: $showingDraft) {
            SheetDraftView(imagesData: draftImageData) { name, data in
                Task {
                    await vm.saveDraft(name: name, imagesData: data)
                }
            }
        }
        .appPageBackground()
        .refreshable { await vm.reload() }
        .alert(LocalizedStringResource("common_notice_title", bundle: .main), isPresented: Binding(get: { vm.toast != nil }, set: { _ in vm.toast = nil })) {
            Button(LocalizedStringResource("button_ok", bundle: .main), role: .cancel) { vm.toast = nil }
        } message: {
            Text(vm.toast ?? "")
        }
        .alert(LocalizedStringResource("sheets_rename_title", bundle: .main), isPresented: Binding(get: { vm.renamingEntry != nil }, set: { if !$0 { vm.renamingEntry = nil } })) {
            TextField(AppL10n.t("sheets_rename_placeholder"), text: $renameDraft)
            Button(LocalizedStringResource("sheets_draft_cancel", bundle: .main), role: .cancel) {
                vm.renamingEntry = nil
            }
            Button(LocalizedStringResource("sheets_rename_confirm", bundle: .main)) {
                Task { await vm.confirmRename(to: renameDraft) }
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(LocalizedStringResource("sheets_rename_message", bundle: .main))
        }
        .onChange(of: vm.renamingEntry) { _, entry in
            renameDraft = entry?.displayName ?? ""
        }
        .onChange(of: vm.selectedEntry) { _, entry in
            guard entry == nil else { return }
            Task { await vm.reloadPracticeDurations() }
        }
        .navigationDestination(item: $vm.selectedEntry) { entry in
            TabBarHiddenContainer {
                SheetDetailView(entry: entry, store: vm.store)
            }
        }
        .accessibilityIdentifier("screen.sheets.library")
    }

    private var listView: some View {
        List {
            Section {
                ForEach(vm.entries) { entry in
                    Button {
                        vm.selectedEntry = entry
                    } label: {
                        HStack(spacing: 12) {
                            SheetCoverThumbnail(store: vm.store, entry: entry)
                                .frame(width: 68, height: 68)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.displayName)
                                    .foregroundStyle(SwiftAppTheme.text)
                                    .lineLimit(1)
                                Text(String(format: AppL10n.t("sheets_list_meta_format"), Int64(entry.pageCount), dateText(entry.addedAtMs)))
                                    .font(.caption)
                                    .foregroundStyle(SwiftAppTheme.muted)
                                Text(String(format: AppL10n.t("sheets_status_line_format"), localizedSheetParseStatus(entry.parseStatus)))
                                    .font(.caption2)
                                    .foregroundStyle(SwiftAppTheme.muted)
                                if let seconds = vm.practiceDurationSeconds(for: entry), seconds > 0 {
                                    Label(formatPracticeDuration(seconds), systemImage: "timer")
                                        .font(.caption2)
                                        .foregroundStyle(SwiftAppTheme.muted)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(SwiftAppTheme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            vm.startRename(entry)
                        } label: {
                            Text(LocalizedStringResource("sheets_action_rename", bundle: .main))
                        }
                        .tint(.blue)

                        Button(role: .destructive) {
                            Task { await vm.remove(entry: entry) }
                        } label: {
                            Text(LocalizedStringResource("sheets_action_delete", bundle: .main))
                        }
                    }
                    .contextMenu {
                        Button {
                            vm.startRename(entry)
                        } label: {
                            Label(
                                LocalizedStringResource("sheets_action_rename", bundle: .main),
                                systemImage: "pencil"
                            )
                        }

                        Button(role: .destructive) {
                            Task { await vm.remove(entry: entry) }
                        } label: {
                            Label(
                                LocalizedStringResource("sheets_action_delete", bundle: .main),
                                systemImage: "trash"
                            )
                        }
                    }
                }
            } footer: {
                Text(LocalizedStringResource("sheets_privacy_notice", bundle: .main))
                    .font(.caption2)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func localizedSheetParseStatus(_ raw: String) -> String {
        let key = "sheet_status_\(raw)"
        let out = AppL10n.t(key)
        if out == key { return raw }
        return out
    }

    private func dateText(_ ms: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func formatPracticeDuration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes < 1 {
            return AppL10n.t("sheets_practice_duration_under_minute")
        }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        if hours > 0, remainMinutes > 0 {
            return String(format: AppL10n.t("sheets_practice_duration_hours_minutes"), Int64(hours), Int64(remainMinutes))
        }
        if hours > 0 {
            return String(format: AppL10n.t("sheets_practice_duration_hours"), Int64(hours))
        }
        return String(format: AppL10n.t("sheets_practice_duration_minutes"), Int64(minutes))
    }

    private func decodePhotosItems(_ items: [PhotosPickerItem]) async -> [Data] {
        var out: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                out.append(data)
            }
        }
        return out
    }
}

@MainActor
final class SheetLibraryViewModel: ObservableObject {
    /// 仅在从未成功拉取过列表时配合 `loading` 显示全屏 Progress，避免切 Tab 反复 `reload` 造成闪屏。
    @Published private(set) var hasLoadedOnce = false
    @Published var loading = true
    @Published var entries: [SheetEntry] = []
    @Published var error: String?
    @Published var toast: String?
    @Published var selectedEntry: SheetEntry?
    @Published var renamingEntry: SheetEntry?

    let store = SheetLibraryStore()
    private let practiceStore = PracticeLocalStore()
    private var practiceDurationBySheet: [String: Int] = [:]

    func reload() async {
        if !hasLoadedOnce {
            loading = true
        }
        error = nil
        entries = await store.loadAll()
        await reloadPracticeDurations()
        loading = false
        hasLoadedOnce = true
    }

    func reloadPracticeDurations() async {
        let sessions = (try? await practiceStore.loadSessions()) ?? []
        practiceDurationBySheet = sessions.reduce(into: [String: Int]()) { acc, session in
            guard session.completed, session.taskId == kSheetPracticeTask.id, let sheetId = session.sheetId else { return }
            acc[sheetId, default: 0] += max(0, session.durationSeconds)
        }
        objectWillChange.send()
    }

    func practiceDurationSeconds(for entry: SheetEntry) -> Int? {
        practiceDurationBySheet[entry.id]
    }

    func saveDraft(name: String, imagesData: [Data]) async {
        do {
            let urls = try imagesData.compactMap { data -> URL? in
                let f = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".jpg")
                try data.write(to: f)
                return f
            }
            _ = try await store.importSheetPages(sources: urls, displayName: name)
            await cleanup(urls)
            await reload()
        } catch {
            toast = String(format: AppL10n.t("sheets_toast_save_failed"), error.localizedDescription)
        }
    }

    func remove(entry: SheetEntry) async {
        do {
            try await store.remove(id: entry.id)
            await reload()
        } catch {
            toast = String(format: AppL10n.t("sheets_toast_delete_failed"), error.localizedDescription)
        }
    }

    func startRename(_ entry: SheetEntry) {
        renamingEntry = entry
    }

    func confirmRename(to displayName: String) async {
        guard let entry = renamingEntry else { return }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renamingEntry = nil
            toast = AppL10n.t("sheets_toast_rename_empty")
            return
        }
        do {
            try await store.rename(id: entry.id, displayName: trimmed)
            renamingEntry = nil
            await reload()
            if selectedEntry?.id == entry.id {
                selectedEntry = entries.first(where: { $0.id == entry.id })
            }
        } catch {
            renamingEntry = nil
            toast = String(format: AppL10n.t("sheets_toast_rename_failed"), error.localizedDescription)
        }
    }

    private func cleanup(_ urls: [URL]) async {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }
}

private struct SheetCoverThumbnail: View {
    let store: SheetLibraryStore
    let entry: SheetEntry
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(SwiftAppTheme.surface)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note.list")
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .task {
            if let url = try? await store.resolveFirstStoredFile(entry),
               let img = UIImage(contentsOfFile: url.path) {
                image = img
            }
        }
    }
}

private struct SheetDraftView: View {
    let imagesData: [Data]
    let onSave: (String, [Data]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField(AppL10n.t("sheets_draft_name_placeholder"), text: $name)
                    .textFieldStyle(.roundedBorder)
                Text(String(format: AppL10n.t("sheets_draft_page_count"), Int64(imagesData.count)))
                    .foregroundStyle(SwiftAppTheme.muted)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(imagesData.enumerated()), id: \.offset) { _, data in
                            if let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle(AppL10n.t("sheets_draft_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppL10n.t("sheets_draft_cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppL10n.t("sheets_draft_save")) {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? AppL10n.t("sheets_untitled") : trimmed, imagesData)
                        dismiss()
                    }
                }
            }
        }
    }
}

enum SheetPageTurnDirection {
    case forward
    case backward

    var insertionEdge: Edge {
        switch self {
        case .forward:
            return .trailing
        case .backward:
            return .leading
        }
    }

    var removalEdge: Edge {
        switch self {
        case .forward:
            return .leading
        case .backward:
            return .trailing
        }
    }
}

enum SheetPageTurnAnimation {
    static func transition(direction: SheetPageTurnDirection, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: direction.insertionEdge).combined(with: .opacity),
            removal: .move(edge: direction.removalEdge).combined(with: .opacity)
        )
    }
}

enum SheetReadingMode {
    case paged
    case continuous

    var toggled: SheetReadingMode {
        switch self {
        case .paged:
            return .continuous
        case .continuous:
            return .paged
        }
    }

    var toolbarTitleKey: String {
        switch self {
        case .paged:
            return "sheets_reading_mode_continuous"
        case .continuous:
            return "sheets_reading_mode_paged"
        }
    }
}

private struct SheetDetailView: View {
    let entry: SheetEntry
    let store: SheetLibraryStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var files: [URL] = []
    /// 预解码，避免切换沉浸/布局时反复 `UIImage(contentsOfFile:)` 造成掉帧。
    @State private var pageImages: [UIImage?] = []
    @State private var loading = true
    /// 当前这一段处于前台、且谱面已就绪的起算时刻；退后台时暂停累加。
    @State private var foregroundSegmentStartedAt: Date?
    /// 已累计的前台可读谱秒数（不含加载转圈、不含退后台）。
    @State private var accumulatedForegroundSeconds: TimeInterval = 0
    /// 轻点谱面进入全屏阅读（隐藏导航栏、铺满可视区域）；再点一次恢复。
    @State private var immersiveReading = false
    @State private var currentPageIndex = 0
    @State private var currentPageScale: CGFloat = 1
    @State private var currentPageOffset: CGSize = .zero
    @State private var pageTurnDirection: SheetPageTurnDirection = .forward
    @State private var readingMode: SheetReadingMode = .paged
    @State private var continuousAutoScrollEnabled = false
    @State private var continuousAutoScrollSpeed: Double = SheetAutoScrollConfig.defaultSpeed
    @State private var showingPageOrderEditor = false
    @State private var showingReaderSettings = false
    @State private var detailNotice: String?
    @StateObject private var metronomeVM = MetronomeViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let practiceStore = PracticeLocalStore()

    /// 至少多少秒才落一条记录，避免点进即返回产生噪声。

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if files.isEmpty {
                Text(AppL10n.t("sheets_no_images")).foregroundStyle(SwiftAppTheme.muted)
            } else {
                sheetReader
            }
        }
        .navigationTitle(entry.displayName)
        .toolbar(immersiveReading ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            if pageImages.count > 1 && !immersiveReading {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppL10n.t(readingMode.toolbarTitleKey)) {
                        toggleReadingMode()
                    }
                    .accessibilityIdentifier("sheets.toggleReadingMode")
                }
                if readingMode == .continuous {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingReaderSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("阅读设置")
                        .accessibilityIdentifier("sheets.readerSettings")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedStringResource("sheets_reorder_toolbar", bundle: .main)) {
                        showingPageOrderEditor = true
                    }
                    .accessibilityIdentifier("sheets.reorderPages")
                }
            }
        }
        .sheet(isPresented: $showingReaderSettings) {
            SheetContinuousPracticeSettings(
                autoScrollEnabled: $continuousAutoScrollEnabled,
                autoScrollSpeed: $continuousAutoScrollSpeed,
                metronomeVM: metronomeVM
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPageOrderEditor) {
            SheetPageOrderEditor(
                pageItems: pageOrderItems,
                onSave: { names in
                    await savePageOrder(names)
                }
            )
        }
        .alert(LocalizedStringResource("common_notice_title", bundle: .main), isPresented: Binding(get: { detailNotice != nil }, set: { if !$0 { detailNotice = nil } })) {
            Button(LocalizedStringResource("button_ok", bundle: .main), role: .cancel) { detailNotice = nil }
        } message: {
            Text(detailNotice ?? "")
        }
        .task {
            await load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                resumeForegroundClockIfEligible()
            case .inactive, .background:
                continuousAutoScrollEnabled = false
                metronomeVM.stop()
                pauseForegroundClock()
            @unknown default:
                continuousAutoScrollEnabled = false
                metronomeVM.stop()
                pauseForegroundClock()
            }
        }
        .onDisappear {
            immersiveReading = false
            continuousAutoScrollEnabled = false
            metronomeVM.stop()
            pauseForegroundClock()
            let totalForeground = accumulatedForegroundSeconds
            Task {
                let durationSeconds = Int(totalForeground.rounded(.down))
                guard durationSeconds >= PracticeRecordingPolicy.minForegroundSecondsToPersist else { return }
                let endedAt = Date()
                let startedAt = endedAt.addingTimeInterval(-Double(durationSeconds))
                try? await practiceStore.saveSession(
                    task: kSheetPracticeTask,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSeconds: durationSeconds,
                    completed: true,
                    difficulty: 3,
                    note: String(format: AppL10n.t("sheets_practice_note_format"), entry.displayName, Int64(entry.pageCount)),
                    sheetId: entry.id,
                    progressionId: nil,
                    musicKey: nil,
                    complexity: nil,
                    rhythmPatternId: nil,
                    scaleWarmupDrillId: nil,
                    earAnsweredCount: nil,
                    earCorrectCount: nil
                )
            }
        }
    }

    private func pauseForegroundClock() {
        guard let start = foregroundSegmentStartedAt else { return }
        accumulatedForegroundSeconds += Date().timeIntervalSince(start)
        foregroundSegmentStartedAt = nil
    }

    private func resumeForegroundClockIfEligible() {
        guard !loading, !files.isEmpty else { return }
        guard foregroundSegmentStartedAt == nil else { return }
        foregroundSegmentStartedAt = Date()
    }

    private func load() async {
        loading = true
        let urls = (try? await store.resolveStoredFiles(entry)) ?? []
        files = urls
        pageImages = urls.map { UIImage(contentsOfFile: $0.path) }
        currentPageIndex = 0
        currentPageScale = Self.minReadableScale
        currentPageOffset = .zero
        loading = false
        if scenePhase == .active {
            resumeForegroundClockIfEligible()
        }
    }

    private static let minReadableScale: CGFloat = 1
    private static let immersiveSpring = Animation.spring(response: 0.32, dampingFraction: 0.94)
    private static let pageTurnAnimation = Animation.spring(response: 0.26, dampingFraction: 0.9)

    private var pageOrderItems: [SheetPageOrderItem] {
        files.enumerated().map { idx, url in
            SheetPageOrderItem(
                storedFileName: url.lastPathComponent,
                image: pageImages.indices.contains(idx) ? pageImages[idx] : nil
            )
        }
    }

    @ViewBuilder
    private var sheetReader: some View {
        switch readingMode {
        case .paged:
            pagedReader
        case .continuous:
            continuousReader
        }
    }

    private var pagedReader: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black
                    .opacity(immersiveReading ? 1 : 0)
                    .allowsHitTesting(false)
                if pageImages.indices.contains(currentPageIndex) {
                    sheetPage(image: pageImages[currentPageIndex], pageIndex: currentPageIndex + 1, containerSize: size)
                        .id(currentPageIndex)
                        .transition(SheetPageTurnAnimation.transition(direction: pageTurnDirection, reduceMotion: reduceMotion))
                        .gesture(pageDragGesture, including: allowsPageSwipe ? .gesture : .none)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var continuousReader: some View {
        ContinuousZoomableSheetReader(
            images: pageImages,
            immersiveReading: $immersiveReading,
            autoScrollEnabled: $continuousAutoScrollEnabled,
            autoScrollSpeed: continuousAutoScrollSpeed
        )
        .background(Color.black.opacity(immersiveReading ? 1 : 0))
    }

    @ViewBuilder
    private func sheetPage(image: UIImage?, pageIndex: Int, containerSize: CGSize) -> some View {
        ZoomableSheetPage(
            image: image,
            pageIndex: pageIndex,
            totalPages: pageImages.count,
            containerSize: containerSize,
            immersiveReading: $immersiveReading
        ) { scale, offset in
            currentPageScale = scale
            currentPageOffset = offset
        }
    }

    private var allowsPageSwipe: Bool {
        currentPageScale <= SheetImageGesturePolicy.pagingScaleThreshold
    }

    private var pageDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                logGesture(
                    "page drag changed translation=\(format(value.translation))"
                )
            }
            .onEnded { value in
                let translation = value.translation
                let horizontalEnough = abs(translation.width) > 60
                    && abs(translation.width) > abs(translation.height) * 1.3
                let previousIndex = currentPageIndex
                var didChangePage = false

                guard allowsPageSwipe else {
                    logGesture("page drag ended ignored translation=\(format(translation)) didChangePage=false")
                    return
                }

                if horizontalEnough, translation.width < -60, currentPageIndex < pageImages.count - 1 {
                    turnPage(to: currentPageIndex + 1, direction: .forward)
                    didChangePage = true
                } else if horizontalEnough, translation.width > 60, currentPageIndex > 0 {
                    turnPage(to: currentPageIndex - 1, direction: .backward)
                    didChangePage = true
                }

                logGesture(
                    "page drag ended translation=\(format(translation)) horizontalEnough=\(horizontalEnough) from=\(previousIndex + 1) to=\(currentPageIndex + 1) didChangePage=\(didChangePage)"
                )
            }
    }

    private func turnPage(to newIndex: Int, direction: SheetPageTurnDirection) {
        pageTurnDirection = direction
        let updates = {
            currentPageIndex = newIndex
            currentPageScale = Self.minReadableScale
            currentPageOffset = .zero
        }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.14), updates)
        } else {
            withAnimation(Self.pageTurnAnimation, updates)
        }
    }

    private func toggleReadingMode() {
        readingMode = readingMode.toggled
        immersiveReading = false
        if readingMode != .continuous {
            continuousAutoScrollEnabled = false
            showingReaderSettings = false
            metronomeVM.stop()
        }
        currentPageScale = Self.minReadableScale
        currentPageOffset = .zero
    }

    private func savePageOrder(_ storedFileNames: [String]) async -> Bool {
        do {
            try await store.reorderPages(id: entry.id, storedFileNames: storedFileNames)
            await load()
            return true
        } catch {
            detailNotice = String(format: AppL10n.t("sheets_reorder_failed"), error.localizedDescription)
            return false
        }
    }

    private func logGesture(_ message: String) {
        print(
            "[SheetImageViewer] \(message) scale=\(format(currentPageScale)) offset=\(format(currentPageOffset)) allowPageSwipe=\(allowsPageSwipe) allowImageDrag=\(!allowsPageSwipe)"
        )
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.3f", Double(value))
    }

    private func format(_ size: CGSize) -> String {
        "(x:\(format(size.width)), y:\(format(size.height)))"
    }
}

private enum SheetImageGesturePolicy {
    static let minScale: CGFloat = 1
    static let pagingScaleThreshold: CGFloat = 1.02
    static let maxScale: CGFloat = 4
    static let doubleTapScale: CGFloat = 2
}

private enum SheetAutoScrollConfig {
    static let minSpeed: Double = 18
    static let maxSpeed: Double = 140
    static let defaultSpeed: Double = 46
}

struct SheetPageOrderItem: Identifiable, Equatable {
    let storedFileName: String
    let image: UIImage?

    var id: String { storedFileName }

    static func == (lhs: SheetPageOrderItem, rhs: SheetPageOrderItem) -> Bool {
        lhs.storedFileName == rhs.storedFileName
    }
}

private struct ContinuousZoomableSheetReader: UIViewRepresentable {
    let images: [UIImage?]
    @Binding var immersiveReading: Bool
    @Binding var autoScrollEnabled: Bool
    let autoScrollSpeed: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(
            immersiveReading: $immersiveReading,
            autoScrollEnabled: $autoScrollEnabled
        )
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.minimumZoomScale = SheetImageGesturePolicy.minScale
        scrollView.maximumZoomScale = SheetImageGesturePolicy.maxScale
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.toggleChrome))
        tap.numberOfTapsRequired = 1
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)

        context.coordinator.scrollView = scrollView
        context.coordinator.contentView = contentView
        context.coordinator.stackView = stackView
        context.coordinator.rebuildPages(images)
        context.coordinator.applyChrome(immersiveReading)
        context.coordinator.updateAutoScroll(enabled: autoScrollEnabled, speed: autoScrollSpeed)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.immersiveReading = $immersiveReading
        context.coordinator.autoScrollEnabled = $autoScrollEnabled
        context.coordinator.rebuildPagesIfNeeded(images)
        context.coordinator.applyChrome(immersiveReading)
        context.coordinator.updateAutoScroll(enabled: autoScrollEnabled, speed: autoScrollSpeed)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var immersiveReading: Binding<Bool>
        var autoScrollEnabled: Binding<Bool>
        weak var scrollView: UIScrollView?
        weak var contentView: UIView?
        weak var stackView: UIStackView?

        private var displayLink: CADisplayLink?
        private var lastTick: CFTimeInterval?
        private var currentSpeed: Double = SheetAutoScrollConfig.defaultSpeed
        private var imageSignature: [String] = []

        init(immersiveReading: Binding<Bool>, autoScrollEnabled: Binding<Bool>) {
            self.immersiveReading = immersiveReading
            self.autoScrollEnabled = autoScrollEnabled
        }

        deinit {
            displayLink?.invalidate()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            contentView
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            if autoScrollEnabled.wrappedValue {
                autoScrollEnabled.wrappedValue = false
                updateAutoScroll(enabled: false, speed: currentSpeed)
            }
        }

        @objc func toggleChrome() {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.94)) {
                immersiveReading.wrappedValue.toggle()
            }
        }

        func rebuildPagesIfNeeded(_ images: [UIImage?]) {
            let next = signature(for: images)
            guard next != imageSignature else { return }
            rebuildPages(images)
        }

        func rebuildPages(_ images: [UIImage?]) {
            imageSignature = signature(for: images)
            guard let stackView else { return }
            stackView.arrangedSubviews.forEach { view in
                stackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }

            for (idx, image) in images.enumerated() {
                stackView.addArrangedSubview(makePageView(image: image, pageIndex: idx + 1, totalPages: images.count))
            }
        }

        func applyChrome(_ immersive: Bool) {
            scrollView?.showsVerticalScrollIndicator = !immersive
            scrollView?.backgroundColor = immersive ? .black : .clear
            stackView?.spacing = immersive ? 0 : 10
            stackView?.layoutMargins = .zero
        }

        func updateAutoScroll(enabled: Bool, speed: Double) {
            currentSpeed = min(SheetAutoScrollConfig.maxSpeed, max(SheetAutoScrollConfig.minSpeed, speed))
            if enabled {
                startDisplayLinkIfNeeded()
            } else {
                stopDisplayLink()
            }
        }

        private func startDisplayLinkIfNeeded() {
            guard displayLink == nil else { return }
            lastTick = nil
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
            lastTick = nil
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let scrollView else { return }
            guard scrollView.window != nil else { return }
            let previous = lastTick ?? link.timestamp
            let dt = max(0, min(0.08, link.timestamp - previous))
            lastTick = link.timestamp

            let maxY = max(
                -scrollView.adjustedContentInset.top,
                scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            )
            let nextY = min(maxY, scrollView.contentOffset.y + CGFloat(currentSpeed * dt))
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: nextY), animated: false)

            if nextY >= maxY - 0.5 {
                autoScrollEnabled.wrappedValue = false
                updateAutoScroll(enabled: false, speed: currentSpeed)
            }
        }

        private func makePageView(image: UIImage?, pageIndex: Int, totalPages: Int) -> UIView {
            let container = UIView()
            container.backgroundColor = .clear
            container.translatesAutoresizingMaskIntoConstraints = false

            if let image {
                let imageView = UIImageView(image: image)
                imageView.contentMode = .scaleAspectFit
                imageView.backgroundColor = .systemBackground
                imageView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(imageView)
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    imageView.topAnchor.constraint(equalTo: container.topAnchor),
                    imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: image.size.height / max(image.size.width, 1))
                ])
            } else {
                let placeholder = UIImageView(image: UIImage(systemName: "photo"))
                placeholder.contentMode = .center
                placeholder.tintColor = .secondaryLabel
                placeholder.backgroundColor = .secondarySystemBackground
                placeholder.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(placeholder)
                NSLayoutConstraint.activate([
                    placeholder.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                    placeholder.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                    placeholder.topAnchor.constraint(equalTo: container.topAnchor),
                    placeholder.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    placeholder.heightAnchor.constraint(equalToConstant: 280)
                ])
            }

            container.accessibilityLabel = String(format: AppL10n.t("sheets_page_indicator"), pageIndex, totalPages)
            return container
        }

        private func signature(for images: [UIImage?]) -> [String] {
            images.map { image in
                guard let image else { return "nil" }
                return "\(Int(image.size.width))x\(Int(image.size.height))-\(image.hash)"
            }
        }
    }
}

private struct SheetContinuousPracticeSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var autoScrollEnabled: Bool
    @Binding var autoScrollSpeed: Double
    @ObservedObject var metronomeVM: MetronomeViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("自动下滑") {
                    Toggle(isOn: $autoScrollEnabled) {
                        Label(autoScrollEnabled ? "正在自动下滑" : "开启自动下滑", systemImage: autoScrollEnabled ? "pause.fill" : "play.fill")
                    }
                    .tint(SwiftAppTheme.brand)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("速度")
                            Spacer()
                            Text("\(Int(autoScrollSpeed.rounded()))")
                                .foregroundStyle(SwiftAppTheme.muted)
                        }
                        Slider(
                            value: $autoScrollSpeed,
                            in: SheetAutoScrollConfig.minSpeed...SheetAutoScrollConfig.maxSpeed,
                            step: 1
                        )
                        .tint(SwiftAppTheme.brand)
                    }
                }

                Section("节拍器") {
                    Button {
                        metronomeVM.toggleStartPause()
                    } label: {
                        Label(metronomeVM.transport == .running ? "暂停节拍器" : "开始节拍器", systemImage: "metronome")
                    }
                    .tint(SwiftAppTheme.brand)

                    Stepper("\(metronomeVM.config.bpm) BPM", value: Binding(
                        get: { metronomeVM.config.bpm },
                        set: { metronomeVM.setBPM($0) }
                    ), in: MetronomeConfig.bpmRange, step: 1)

                    Picker("拍号", selection: Binding(
                        get: { metronomeVM.config.timeSignature },
                        set: { metronomeVM.setTimeSignature($0) }
                    )) {
                        Text("4/4").tag(MetronomeTimeSignature.fourFour)
                        Text("3/4").tag(MetronomeTimeSignature.threeFour)
                        Text("6/8").tag(MetronomeTimeSignature.sixEight)
                    }
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("提示", isPresented: Binding(
                get: { metronomeVM.errorMessage != nil },
                set: { if !$0 { metronomeVM.errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { metronomeVM.errorMessage = nil }
            } message: {
                Text(metronomeVM.errorMessage ?? "")
            }
        }
    }
}

private struct SheetPageOrderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pageItems: [SheetPageOrderItem]
    @State private var saving = false
    let onSave: ([String]) async -> Bool

    init(pageItems: [SheetPageOrderItem], onSave: @escaping ([String]) async -> Bool) {
        _pageItems = State(initialValue: pageItems)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(pageItems.enumerated()), id: \.element.id) { idx, item in
                        HStack(spacing: 12) {
                            Text("\(idx + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(SwiftAppTheme.muted)
                                .frame(width: 28, alignment: .trailing)
                            pageThumbnail(item.image)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: AppL10n.t("sheets_reorder_page_title"), Int64(idx + 1)))
                                    .foregroundStyle(SwiftAppTheme.text)
                                Text(AppL10n.t("sheets_reorder_drag_hint"))
                                    .font(.caption)
                                    .foregroundStyle(SwiftAppTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(SwiftAppTheme.muted)
                        }
                        .accessibilityLabel(String(format: AppL10n.t("sheets_reorder_page_title"), Int64(idx + 1)))
                    }
                    .onMove { source, destination in
                        pageItems.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text(LocalizedStringResource("sheets_reorder_footer", bundle: .main))
                }
            }
            .navigationTitle(LocalizedStringResource("sheets_reorder_title", bundle: .main))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringResource("sheets_draft_cancel", bundle: .main)) { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringResource("sheets_reorder_save", bundle: .main)) {
                        Task { await save() }
                    }
                    .disabled(saving)
                }
            }
            .environment(\.editMode, .constant(.active))
        }
    }

    @ViewBuilder
    private func pageThumbnail(_ image: UIImage?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(SwiftAppTheme.surface)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .frame(width: 56, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func save() async {
        saving = true
        let didSave = await onSave(pageItems.map(\.storedFileName))
        saving = false
        if didSave {
            dismiss()
        }
    }
}

private struct ZoomableSheetPage: View {
    let image: UIImage?
    let pageIndex: Int
    let totalPages: Int
    let containerSize: CGSize
    @Binding var immersiveReading: Bool
    let onInteractionChanged: (CGFloat, CGSize) -> Void

    @State private var currentScale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var currentOffset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private static let immersiveSpring = Animation.spring(response: 0.32, dampingFraction: 0.94)

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: containerSize.width, height: containerSize.height)
                    .scaleEffect(currentScale)
                    .offset(currentOffset)
                    .gesture(imageDragGesture, including: allowsImageDrag ? .gesture : .none)
                    .simultaneousGesture(magnificationGesture)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(SwiftAppTheme.surface)
                    .padding(24)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .contentShape(Rectangle())
        .simultaneousGesture(tapGesture)
        .onAppear { notifyInteraction("appear") }
        .accessibilityHint(AppL10n.t("sheets_a11y_toggle_chrome"))
        .overlay(alignment: .bottom) {
            Text(String(format: AppL10n.t("sheets_page_indicator"), pageIndex, totalPages))
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
                .padding(.bottom, 6)
                .opacity(immersiveReading ? 0 : 1)
                .allowsHitTesting(!immersiveReading)
        }
    }

    private var allowsImageDrag: Bool {
        currentScale > SheetImageGesturePolicy.pagingScaleThreshold
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let scaled = baseScale * value
                currentScale = min(SheetImageGesturePolicy.maxScale, max(SheetImageGesturePolicy.minScale, scaled))
                if currentScale <= SheetImageGesturePolicy.pagingScaleThreshold {
                    currentOffset = .zero
                } else {
                    currentOffset = clampedOffset(baseOffset, for: currentScale)
                }
                notifyInteraction("magnify changed")
            }
            .onEnded { _ in
                baseScale = currentScale
                if currentScale <= SheetImageGesturePolicy.pagingScaleThreshold {
                    baseScale = SheetImageGesturePolicy.minScale
                    currentScale = SheetImageGesturePolicy.minScale
                    baseOffset = .zero
                    currentOffset = .zero
                } else {
                    baseOffset = clampedOffset(currentOffset, for: currentScale)
                    currentOffset = baseOffset
                }
                notifyInteraction("magnify ended")
            }
    }

    private var imageDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard allowsImageDrag else {
                    notifyInteraction("image drag changed ignored translation=\(format(value.translation))")
                    return
                }
                let candidate = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
                currentOffset = clampedOffset(candidate, for: currentScale)
                notifyInteraction("image drag changed translation=\(format(value.translation))")
            }
            .onEnded { value in
                guard allowsImageDrag else {
                    baseOffset = .zero
                    currentOffset = .zero
                    notifyInteraction("image drag ended ignored translation=\(format(value.translation))")
                    return
                }
                baseOffset = clampedOffset(currentOffset, for: currentScale)
                currentOffset = baseOffset
                notifyInteraction("image drag ended translation=\(format(value.translation))")
            }
    }

    private var tapGesture: some Gesture {
        ExclusiveGesture(TapGesture(count: 2), TapGesture(count: 1))
            .onEnded { value in
                switch value {
                case .first:
                    toggleDoubleTapZoom()
                case .second:
                    withAnimation(Self.immersiveSpring) {
                        immersiveReading.toggle()
                    }
                    notifyInteraction("single tap toggle chrome")
                }
            }
    }

    private func toggleDoubleTapZoom() {
        withAnimation(Self.immersiveSpring) {
            if currentScale > SheetImageGesturePolicy.pagingScaleThreshold {
                currentScale = SheetImageGesturePolicy.minScale
                baseScale = SheetImageGesturePolicy.minScale
                currentOffset = .zero
                baseOffset = .zero
            } else {
                currentScale = SheetImageGesturePolicy.doubleTapScale
                baseScale = SheetImageGesturePolicy.doubleTapScale
                currentOffset = .zero
                baseOffset = .zero
            }
        }
        notifyInteraction("double tap zoom")
    }

    private func clampedOffset(_ offset: CGSize, for scale: CGFloat) -> CGSize {
        guard scale > SheetImageGesturePolicy.pagingScaleThreshold else { return .zero }
        let fittedSize = fittedImageSize()
        let maxX = max(0, (fittedSize.width * scale - containerSize.width) / 2)
        let maxY = max(0, (fittedSize.height * scale - containerSize.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func fittedImageSize() -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return containerSize
        }
        let widthRatio = containerSize.width / image.size.width
        let heightRatio = containerSize.height / image.size.height
        let ratio = min(widthRatio, heightRatio)
        return CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    }

    private func notifyInteraction(_ event: String) {
        onInteractionChanged(currentScale, currentOffset)
        print(
            "[SheetImageViewer] \(event) scale=\(format(currentScale)) offset=\(format(currentOffset)) allowPageSwipe=\(!allowsImageDrag) allowImageDrag=\(allowsImageDrag)"
        )
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.3f", Double(value))
    }

    private func format(_ size: CGSize) -> String {
        "(x:\(format(size.width)), y:\(format(size.height)))"
    }
}
