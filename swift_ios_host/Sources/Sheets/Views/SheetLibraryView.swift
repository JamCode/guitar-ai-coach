import SwiftUI
import PhotosUI
import Core
import Chords
import UIKit

struct SheetLibraryView: View {
    @StateObject private var vm = SheetLibraryViewModel()
    @State private var pickerItems: [PhotosPickerItem] = []
    /// `PhotosPicker` 放在 `Menu` 里在部分系统版本上点击无效；用 `isPresented` 方式在菜单外弹出系统相册。
    @State private var showingPhotoLibrary = false
    @State private var showingDraft = false
    @State private var showingCamera = false
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
                Text("暂无谱子。点击右上角 +：拍照或相册多选；起名后保存到本地。")
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
                Menu {
                    Button {
                        // 等 `Menu` 收起后再 presentation，避免与菜单动画冲突导致相册不出现。
                        DispatchQueue.main.async {
                            showingPhotoLibrary = true
                        }
                    } label: {
                        Label("从相册添加", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showingCamera = true
                    } label: {
                        Label("拍照添加", systemImage: "camera")
                    }
                } label: {
                    Image(systemName: "plus")
                }
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
        .sheet(isPresented: $showingCamera) {
            MultiCaptureSheet { capturedData in
                showingCamera = false
                guard !capturedData.isEmpty else { return }
                draftImageData = capturedData
                showingDraft = true
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
                SheetDetailView(entry: entry, store: vm.store) {
                    Task { await vm.reload() }
                }
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
            toast = "已保存到「我的谱」"
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

private struct MultiCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var images: [Data] = []
    let onDone: ([Data]) -> Void
    @State private var showingCamera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if images.isEmpty {
                    Text("还未拍照，点击下方按钮开始拍摄。").foregroundStyle(SwiftAppTheme.muted)
                } else {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(Array(images.enumerated()), id: \.offset) { idx, data in
                                if let img = UIImage(data: data) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 90, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                images.remove(at: idx)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                            }
                                            .buttonStyle(.plain)
                                            .padding(4)
                                        }
                                }
                            }
                        }
                    }
                }
                Button("继续拍摄") { showingCamera = true }
                    .appPrimaryButton()
                Spacer()
            }
            .padding()
            .navigationTitle("连续拍摄")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onDone(images)
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraCaptureView { data in
                if let data { images.append(data) }
                showingCamera = false
            }
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onPick: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onPick: (Data?) -> Void
        init(onPick: @escaping (Data?) -> Void) { self.onPick = onPick }
        func imagePickerControllerDidCancel(_: UIImagePickerController) { onPick(nil) }
        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            let data = image?.jpegData(compressionQuality: 0.9)
            onPick(data)
        }
    }
}

private struct SheetDetailView: View {
    let entry: SheetEntry
    let store: SheetLibraryStore
    let onUpdated: () -> Void
    @State private var files: [URL] = []
    @State private var parsed: SheetParsedData?
    @State private var loading = true
    @State private var showingReview = false
    @State private var showingTranspose = false
    @State private var startedAt = Date()
    @State private var toast: String?
    private let practiceStore = PracticeLocalStore()

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if files.isEmpty {
                Text("未找到谱面图片").foregroundStyle(SwiftAppTheme.muted)
            } else {
                TabView {
                    ForEach(Array(files.enumerated()), id: \.offset) { idx, url in
                        VStack(spacing: 8) {
                            if let img = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                RoundedRectangle(cornerRadius: 8).fill(SwiftAppTheme.surface)
                            }
                            Text("第 \(idx + 1) 页").font(.caption).foregroundStyle(SwiftAppTheme.muted)
                        }
                        .padding()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
        .navigationTitle(entry.displayName)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("识别校对") { Task { await runOCR() } }
                Button("变调预览") { showingTranspose = true }
                    .disabled(parsed == nil)
            }
        }
        .task {
            startedAt = Date()
            await load()
        }
        .onDisappear {
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
        .sheet(isPresented: $showingReview) {
            SheetOCRReviewView(initial: parsed) { updated in
                Task {
                    do {
                        try await store.saveParsed(updated)
                        parsed = updated
                        onUpdated()
                    } catch {
                        toast = "保存识别结果失败：\(error.localizedDescription)"
                    }
                }
            }
        }
        .sheet(isPresented: $showingTranspose) {
            if let parsed {
                SheetTransposePreviewView(parsed: parsed)
            }
        }
        .alert("提示", isPresented: Binding(get: { toast != nil }, set: { _ in toast = nil })) {
            Button("确定", role: .cancel) { toast = nil }
        } message: {
            Text(toast ?? "")
        }
    }

    private func load() async {
        loading = true
        files = (try? await store.resolveStoredFiles(entry)) ?? []
        parsed = await store.loadParsed(sheetId: entry.id)
        loading = false
    }

    private func runOCR() async {
        if parsed != nil {
            showingReview = true
            return
        }
        let ocr = SheetOCRService()
        let segments = await ocr.recognizeSheetSegments(pageURLs: files)
        parsed = SheetParsedData(
            sheetId: entry.id,
            parseStatus: .draft,
            originalKey: "C",
            segments: segments,
            updatedAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
        showingReview = true
    }
}

private struct SheetOCRReviewView: View {
    let initial: SheetParsedData?
    let onSave: (SheetParsedData) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var originalKey = "C"
    @State private var chordsText = ""
    @State private var melodyText = ""
    @State private var lyricsText = ""

    private let allKeys = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("原调", selection: $originalKey) {
                    ForEach(allKeys, id: \.self) { Text($0) }
                }
                section("和弦（每行一段）", text: $chordsText)
                section("旋律（每行一段）", text: $melodyText)
                section("歌词（每行一段）", text: $lyricsText)
            }
            .navigationTitle("识别结果校对")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let initial else { return }
                        let result = buildParsed(initial.sheetId)
                        onSave(result)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard let initial else { return }
                originalKey = initial.originalKey
                chordsText = initial.segments.map { $0.chords.joined(separator: " ") }.joined(separator: "\n")
                melodyText = initial.segments.map { $0.melody }.joined(separator: "\n")
                lyricsText = initial.segments.map { $0.lyrics }.joined(separator: "\n")
            }
        }
    }

    private func section(_ title: String, text: Binding<String>) -> some View {
        Section(title) {
            TextEditor(text: text)
                .frame(minHeight: 120)
        }
    }

    private func buildParsed(_ sheetId: String) -> SheetParsedData {
        let chordLines = splitLines(chordsText)
        let melodyLines = splitLines(melodyText)
        let lyricLines = splitLines(lyricsText)
        let maxCount = max(chordLines.count, max(melodyLines.count, lyricLines.count))
        var segments: [SheetSegment] = []
        for idx in 0..<maxCount {
            let line = idx < chordLines.count ? chordLines[idx] : ""
            segments.append(
                SheetSegment(
                    chords: line.split(whereSeparator: \.isWhitespace).map(String.init),
                    melody: idx < melodyLines.count ? melodyLines[idx] : "",
                    lyrics: idx < lyricLines.count ? lyricLines[idx] : ""
                )
            )
        }
        return SheetParsedData(
            sheetId: sheetId,
            parseStatus: .ready,
            originalKey: originalKey,
            segments: segments,
            updatedAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
    }

    private func splitLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
    }
}

private struct SheetTransposePreviewView: View {
    let parsed: SheetParsedData
    @State private var targetKey = "C"
    private let allKeys = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    var body: some View {
        NavigationStack {
            List {
                Picker("目标调", selection: $targetKey) {
                    ForEach(allKeys, id: \.self) { Text($0) }
                }
                Section("和弦预览") {
                    ForEach(Array(parsed.segments.enumerated()), id: \.offset) { _, seg in
                        let line = seg.chords.map {
                            ChordTransposeLocal.transposeChordSymbol($0, from: parsed.originalKey, to: targetKey)
                        }.joined(separator: " ")
                        Text(line.isEmpty ? "（无和弦）" : line)
                    }
                }
            }
            .navigationTitle("一键变调预览")
        }
    }
}
