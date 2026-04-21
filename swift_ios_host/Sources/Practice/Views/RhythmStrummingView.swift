import SwiftUI
import Core

/// 节奏扫弦练习：按内置常用扫弦型展示 4/4 八分网格图示；可选保存记录（对齐 Flutter）。
struct RhythmStrummingView: View {
    let task: PracticeTask
    let store: PracticeSessionStore

    @Environment(\.dismiss) private var dismiss

    @State private var selectedDifficulty: StrummingDifficulty = .初级
    @State private var pattern: StrummingPattern = StrummingPatternGenerator.defaultPattern(for: .初级)
    @State private var openedAt: Date = Date()

    @State private var showSettings: Bool = false
    @State private var showHelp: Bool = false
    @State private var showFinishSheet: Bool = false
    @State private var noteText: String = ""

    @State private var savingError: String?
    @State private var savedToast: Bool = false

    private let beatLabels: [String] = ["1", "&", "2", "&", "3", "&", "4", "&"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(task.description)
                    .foregroundStyle(SwiftAppTheme.text)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("本组练习")
                            .appSectionTitle()
                        Spacer()
                        Text(selectedDifficulty.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SwiftAppTheme.brand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(SwiftAppTheme.brandSoft)
                            .clipShape(Capsule())
                    }
                    Text("当前节奏：\(pattern.name) · \(pattern.subtitle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                        .lineLimit(2)
                    Text("点击「下一组」按当前难度抽取常用扫弦型；难度在右上角齿轮设置。")
                        .font(.footnote)
                        .foregroundStyle(SwiftAppTheme.muted)
                }
                .appCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("一小节（4/4，八分音符网格）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                    StrummingGrid(cells: pattern.cells, beatLabels: beatLabels)
                }
                .appCard()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(SwiftAppTheme.brand)
                    Text(pattern.tip)
                        .foregroundStyle(SwiftAppTheme.text)
                        .font(.subheadline)
                }
                .appCard()

                Button("下一组") { nextPattern() }
                    .appSecondaryButton()
                    .frame(maxWidth: .infinity)

            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(task.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("返回")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("练习设置")
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("难度") {
                        Picker("难度", selection: $selectedDifficulty) {
                            ForEach(StrummingDifficulty.allCases, id: \.self) { lv in
                                Text(lv.rawValue).tag(lv)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("选择后会立即按该难度抽取新的扫弦型。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("图示说明") {
                        Text(
                            """
                            每一格对应一拍里的两个八分位置之一，顺序为「1 & 2 & 3 & 4 &」。

                            「下」「上」表示扫弦方向；「休」表示该位置不扫弦，可做空拍或制音准备。

                            本页为 4/4 常用型，可与节拍器或歌曲一起练习；本期不含内置节拍器与音频。
                            """
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("练习设置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { showSettings = false }
                    }
                }
            }
        }
        .alert("图示说明", isPresented: $showHelp) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(
                """
                每一格对应一拍里的两个八分位置之一，顺序为「1 & 2 & 3 & 4 &」。

                「下」「上」表示扫弦方向；「休」表示该位置不扫弦，可做空拍或制音准备。

                本页为 4/4 常用型，可与节拍器或歌曲一起练习；本期不含内置节拍器与音频。
                """
            )
        }
        .alert("保存失败", isPresented: Binding(get: { savingError != nil }, set: { if !$0 { savingError = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(savingError ?? "")
        }
        .alert("记录已保存", isPresented: $savedToast) {
            Button("返回", role: .cancel) { dismiss() }
        }
        .sheet(isPresented: $showFinishSheet) {
            PracticeFinishDialog(
                title: "本次练习",
                showCompletedGoal: false,
                noteText: $noteText,
                onCancel: { showFinishSheet = false },
                onSave: { result in
                    showFinishSheet = false
                    Task { await save(result: result) }
                }
            )
        }
        .appPageBackground()
        .onAppear {
            openedAt = Date()
            // 首次进入按默认难度抽一次，避免每次都固定显示池子首项。
            nextPattern()
        }
        .onChange(of: selectedDifficulty) { _, _ in
            nextPattern()
        }
    }

    private func nextPattern() {
        var rng = SystemRandomNumberGenerator()
        pattern = StrummingPatternGenerator.nextPattern(
            difficulty: selectedDifficulty,
            excluding: pattern.id,
            using: &rng
        )
    }

    @MainActor
    private func save(result: PracticeFinishResult) async {
        do {
            try await store.saveSession(
                task: task,
                startedAt: openedAt,
                endedAt: Date(),
                durationSeconds: 0,
                completed: result.completed,
                difficulty: result.difficulty,
                note: result.note,
                progressionId: nil,
                musicKey: nil,
                complexity: nil,
                rhythmPatternId: pattern.id,
                scaleWarmupDrillId: nil
            )
            savedToast = true
        } catch {
            savingError = String(describing: error)
        }
    }
}

private struct StrummingGrid: View {
    let cells: [StrumCellKind]
    let beatLabels: [String]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                ForEach(0..<8, id: \.self) { i in
                    Spacer(minLength: 0)
                    Text(beatLabels[i])
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { i in
                    StrumCellChip(kind: cells[safe: i] ?? .rest)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct StrumCellChip: View {
    let kind: StrumCellKind

    var body: some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch kind {
            case .down: ("下", SwiftAppTheme.brandSoft, SwiftAppTheme.brand)
            case .up: ("上", SwiftAppTheme.surfaceSoft, SwiftAppTheme.text)
            case .rest: ("休", SwiftAppTheme.surfaceSoft, SwiftAppTheme.muted)
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SwiftAppTheme.line, lineWidth: 1)
                )
            Text(label)
                .font(.title3.weight(.semibold))
                .foregroundStyle(fg)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        guard idx >= 0, idx < count else { return nil }
        return self[idx]
    }
}

