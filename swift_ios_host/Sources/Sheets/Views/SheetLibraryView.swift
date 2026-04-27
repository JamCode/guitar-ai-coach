import SwiftUI
import PhotosUI
import Core
import Practice
import UIKit

struct SheetLibraryView: View {
    @ObservedObject var vm: SheetLibraryViewModel
    @State private var pickerItems: [PhotosPickerItem] = []
    /// `PhotosPicker` 用 `isPresented` 在工具栏按钮外弹出系统相册，避免嵌在 `Menu` 内时部分系统点击无效。
    @State private var showingPhotoLibrary = false
    @State private var showingDraft = false
    @State private var draftImageData: [Data] = []

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
        .navigationDestination(item: $vm.selectedEntry) { entry in
            TabBarHiddenContainer {
                SheetDetailView(entry: entry, store: vm.store)
            }
        }
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
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(SwiftAppTheme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await vm.remove(entry: entry) }
                        } label: {
                            Text(LocalizedStringResource("sheets_action_delete", bundle: .main))
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

    let store = SheetLibraryStore()

    func reload() async {
        if !hasLoadedOnce {
            loading = true
        }
        error = nil
        entries = await store.loadAll()
        loading = false
        hasLoadedOnce = true
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
    private let practiceStore = PracticeLocalStore()

    /// 至少多少秒才落一条记录，避免点进即返回产生噪声。

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if files.isEmpty {
                Text(AppL10n.t("sheets_no_images")).foregroundStyle(SwiftAppTheme.muted)
            } else {
                GeometryReader { geo in
                    let size = geo.size
                    ZStack {
                        Color.black
                            .opacity(immersiveReading ? 1 : 0)
                            .allowsHitTesting(false)
                        if pageImages.indices.contains(currentPageIndex) {
                            sheetPage(image: pageImages[currentPageIndex], pageIndex: currentPageIndex + 1, containerSize: size)
                                .id(currentPageIndex)
                                .gesture(pageDragGesture, including: allowsPageSwipe ? .gesture : .none)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(entry.displayName)
        .toolbar(immersiveReading ? .hidden : .automatic, for: .navigationBar)
        .task {
            await load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                resumeForegroundClockIfEligible()
            case .inactive, .background:
                pauseForegroundClock()
            @unknown default:
                pauseForegroundClock()
            }
        }
        .onDisappear {
            immersiveReading = false
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
        )
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
                    currentPageIndex += 1
                    didChangePage = true
                } else if horizontalEnough, translation.width > 60, currentPageIndex > 0 {
                    currentPageIndex -= 1
                    didChangePage = true
                }

                if didChangePage {
                    currentPageScale = Self.minReadableScale
                    currentPageOffset = .zero
                }
                logGesture(
                    "page drag ended translation=\(format(translation)) horizontalEnough=\(horizontalEnough) from=\(previousIndex + 1) to=\(currentPageIndex + 1) didChangePage=\(didChangePage)"
                )
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
