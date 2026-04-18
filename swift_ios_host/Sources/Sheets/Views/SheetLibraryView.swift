import SwiftUI
import PhotosUI
import Core
import UIKit

struct SheetLibraryView: View {
    @StateObject private var vm = SheetLibraryViewModel()
    @State private var pickerItems: [PhotosPickerItem] = []
    /// `PhotosPicker` 用 `isPresented` 在工具栏按钮外弹出系统相册，避免嵌在 `Menu` 内时部分系统点击无效。
    @State private var showingPhotoLibrary = false
    @State private var showingDraft = false
    @State private var draftImageData: [Data] = []

    var body: some View {
        Group {
            if vm.loading {
                ProgressView()
            } else if let error = vm.error {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(SwiftAppTheme.muted)
                    Button("重试") { Task { await vm.reload() } }.appPrimaryButton()
                }
            } else if vm.entries.isEmpty {
                Text("暂无谱子。点击右上角 + 从相册多选；起名后保存到本地。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .padding()
            } else {
                listView
            }
        }
        .navigationTitle("我的谱")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPhotoLibrary = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("从相册添加")
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
        .alert("提示", isPresented: Binding(get: { vm.toast != nil }, set: { _ in vm.toast = nil })) {
            Button("知道了", role: .cancel) { vm.toast = nil }
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
                            Text("\(entry.pageCount) 页 · \(dateText(entry.addedAtMs))")
                                .font(.caption)
                                .foregroundStyle(SwiftAppTheme.muted)
                            Text("状态：\(entry.parseStatus)")
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
                        Text("删除")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
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
    @Published var loading = true
    @Published var entries: [SheetEntry] = []
    @Published var error: String?
    @Published var toast: String?
    @Published var selectedEntry: SheetEntry?

    let store = SheetLibraryStore()

    func reload() async {
        loading = true
        error = nil
        entries = await store.loadAll()
        loading = false
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
            toast = "保存失败：\(error.localizedDescription)"
        }
    }

    func remove(entry: SheetEntry) async {
        do {
            try await store.remove(id: entry.id)
            await reload()
        } catch {
            toast = "删除失败：\(error.localizedDescription)"
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
                TextField("输入谱名", text: $name)
                    .textFieldStyle(.roundedBorder)
                Text("共 \(imagesData.count) 页")
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
            .navigationTitle("保存谱子")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? "未命名谱子" : trimmed, imagesData)
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
    @State private var files: [URL] = []
    @State private var loading = true
    @State private var startedAt = Date()
    /// 轻点谱面进入全屏阅读（隐藏导航栏、铺满可视区域）；再点一次恢复。
    @State private var immersiveReading = false
    private let practiceStore = PracticeLocalStore()

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if files.isEmpty {
                Text("未找到谱面图片").foregroundStyle(SwiftAppTheme.muted)
            } else {
                ZStack {
                    if immersiveReading {
                        Color.black.ignoresSafeArea()
                    }
                    TabView {
                        ForEach(Array(files.enumerated()), id: \.offset) { idx, url in
                            sheetPage(url: url, pageIndex: idx + 1)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: immersiveReading ? .vertical : [])
            }
        }
        .navigationTitle(entry.displayName)
        .toolbar(immersiveReading ? .hidden : .automatic, for: .navigationBar)
        .animation(.easeInOut(duration: 0.2), value: immersiveReading)
        .task {
            startedAt = Date()
            await load()
        }
        .onDisappear {
            immersiveReading = false
            Task {
                let endedAt = Date()
                let seconds = Int(endedAt.timeIntervalSince(startedAt))
                if seconds >= 30 {
                    try? await practiceStore.saveSession(
                        task: kSheetPracticeTask,
                        startedAt: startedAt,
                        endedAt: endedAt,
                        durationSeconds: seconds,
                        completed: true,
                        difficulty: 3,
                        note: "曲谱：\(entry.displayName)",
                        progressionId: nil,
                        musicKey: nil,
                        complexity: nil,
                        rhythmPatternId: nil
                    )
                }
            }
        }
    }

    private func load() async {
        loading = true
        files = (try? await store.resolveStoredFiles(entry)) ?? []
        loading = false
    }

    @ViewBuilder
    private func sheetPage(url: URL, pageIndex: Int) -> some View {
        GeometryReader { proxy in
            ZStack {
                if let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SwiftAppTheme.surface)
                        .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                immersiveReading.toggle()
            }
            .accessibilityHint("轻点以显示或隐藏标题栏")
            .overlay(alignment: .bottom) {
                if !immersiveReading {
                    Text("第 \(pageIndex) 页 · 共 \(files.count) 页")
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .padding(.bottom, 6)
                }
            }
        }
    }
}
