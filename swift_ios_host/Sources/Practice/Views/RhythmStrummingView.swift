import SwiftUI
import Core
import Metronome
import Practice

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
    @StateObject private var metronomeVM = MetronomeViewModel()
    @State private var metronomeBPM: Int = 72
    @State private var selectedTimeSignature: MetronomeTimeSignature = .fourFour

    private let beatLabels: [String] = ["1", "&", "2", "&", "3", "&", "4", "&"]
    private let defaultRecommendedBPM = 72
    private let bpmMin = 40
    private let bpmMax = 220

    private var recommendedBPM: Int {
        pattern.recommendedBPM ?? defaultRecommendedBPM
    }

    private var subdivisionLabel: String {
        pattern.subdivision.labelZh
    }

    private var startPauseTitle: String {
        metronomeVM.transport == .running ? "⏸ 暂停" : "▶ 开始"
    }

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
                    Text("一小节（\(pattern.timeSignature)，\(subdivisionLabel)六线谱）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                    StrummingTabStaffView(
                        patternSteps: pattern.patternSteps,
                        beatLabels: beatLabels
                    )
                }
                .appCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("节拍器")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                    HStack(spacing: 10) {
                        Button("-") { updateBPM(delta: -5) }
                            .appSecondaryButton()
                        Text("\(metronomeBPM) BPM")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SwiftAppTheme.text)
                            .frame(minWidth: 84, alignment: .center)
                        Button("+") { updateBPM(delta: 5) }
                            .appSecondaryButton()
                        Spacer(minLength: 8)
                        Button(startPauseTitle) { toggleMetronome() }
                            .appSecondaryButton()
                    }
                    Picker("拍号", selection: $selectedTimeSignature) {
                        Text("4/4").tag(MetronomeTimeSignature.fourFour)
                        Text("3/4").tag(MetronomeTimeSignature.threeFour)
                        Text("6/8").tag(MetronomeTimeSignature.sixEight)
                    }
                    .pickerStyle(.segmented)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    stopMetronome()
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

                            六线谱弦序固定为：① 在上、⑥ 在下（最粗弦在最下）。

                            在该弦序下：↑ 表示下扫，↓ 表示上扫，· 表示空拍，× 表示拍弦/切音。

                            本页可用下方轻量节拍器控制条调速与拍号；不跟随箭头逐格高亮。
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

                六线谱弦序固定为：① 在上、⑥ 在下（最粗弦在最下）。

                在该弦序下：↑ 表示下扫，↓ 表示上扫，· 表示空拍，× 表示拍弦/切音。

                本页支持轻量节拍器控制；可调 BPM 与拍号后开始/暂停。
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
        .onChange(of: selectedTimeSignature) { _, newSig in
            metronomeVM.setTimeSignature(newSig)
        }
        .onDisappear {
            stopMetronome()
        }
    }

    private func nextPattern() {
        stopMetronome()
        var rng = SystemRandomNumberGenerator()
        pattern = StrummingPatternGenerator.nextPattern(
            difficulty: selectedDifficulty,
            excluding: pattern.id,
            using: &rng
        )
        syncMetronomeDefaultsFromPattern()
    }

    private func toggleMetronome() {
        switch metronomeVM.transport {
        case .running:
            metronomeVM.pause()
        case .paused, .stopped:
            metronomeVM.setTimeSignature(selectedTimeSignature)
            metronomeVM.setBPM(metronomeBPM)
            metronomeVM.start()
        }
    }

    private func updateBPM(delta: Int) {
        let next = max(bpmMin, min(bpmMax, metronomeBPM + delta))
        guard next != metronomeBPM else { return }
        metronomeBPM = next
        metronomeVM.setBPM(metronomeBPM)
    }

    private func syncMetronomeDefaultsFromPattern() {
        metronomeBPM = max(bpmMin, min(bpmMax, recommendedBPM))
        selectedTimeSignature = parseTimeSignature(pattern.timeSignature) ?? .fourFour
        metronomeVM.setTimeSignature(selectedTimeSignature)
        metronomeVM.setBPM(metronomeBPM)
    }

    private func parseTimeSignature(_ value: String) -> MetronomeTimeSignature? {
        switch value.replacingOccurrences(of: " ", with: "") {
        case "4/4": .fourFour
        case "3/4": .threeFour
        case "6/8": .sixEight
        default: nil
        }
    }

    private func stopMetronome() {
        metronomeVM.stop()
    }

    @MainActor
    private func save(result: PracticeFinishResult) async {
        do {
            let endedAt = Date()
            let durationSeconds = max(0, Int(endedAt.timeIntervalSince(openedAt)))
            guard durationSeconds >= PracticeRecordingPolicy.minForegroundSecondsToPersist else { return }
            try await store.saveSession(
                task: task,
                startedAt: openedAt,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
                completed: result.completed,
                difficulty: result.difficulty,
                note: result.note,
                progressionId: nil,
                musicKey: nil,
                complexity: nil,
                rhythmPatternId: pattern.id,
                scaleWarmupDrillId: nil,
                earAnsweredCount: nil,
                earCorrectCount: nil
            )
            savedToast = true
        } catch {
            savingError = String(describing: error)
        }
    }
}

enum StrummingTabStaffGlyph: Equatable {
    case downStroke
    case upStroke
    case rest
    case mute

    static func from(kind: StrumCellKind) -> Self {
        switch kind {
        case .down: .downStroke
        case .up: .upStroke
        case .rest: .rest
        case .mute: .mute
        }
    }

    static func from(action kind: StrumActionKind) -> Self {
        switch kind {
        case .down: .downStroke
        case .up: .upStroke
        case .rest: .rest
        case .mute: .mute
        }
    }

    var symbol: String {
        switch self {
        case .downStroke: "↑" // 下扫（①上⑥下坐标系）
        case .upStroke: "↓" // 上扫
        case .rest: "·" // 空拍
        case .mute: "×" // 拍弦/切音
        }
    }
}

private struct StrummingTabStaffView: View {
    let patternSteps: [StrumCellKind]
    let beatLabels: [String]
    private let stringLabels = ["①", "②", "③", "④", "⑤", "⑥"]
    private var totalUnits: Int { max(1, patternSteps.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(" ")
                    .frame(width: 18)
                ForEach(0..<totalUnits, id: \.self) { i in
                    Text(beatLabels[safe: i] ?? "")
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(stringLabels, id: \.self) { label in
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SwiftAppTheme.muted)
                            .frame(width: 18, height: 10)
                    }
                }
                .padding(.top, 6)

                ZStack {
                    VStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { _ in
                            Rectangle()
                                .fill(SwiftAppTheme.line)
                                .frame(height: 1)
                        }
                    }

                    HStack(spacing: 6) {
                        ForEach(0..<totalUnits, id: \.self) { i in
                            let glyph = StrummingTabStaffGlyph.from(kind: patternSteps[safe: i] ?? .rest)
                            Text(glyph.symbol)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(SwiftAppTheme.text)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .padding(10)
                .background(SwiftAppTheme.surfaceSoft.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SwiftAppTheme.line, lineWidth: 1)
                )
            }

            Text("图例：↑ 下扫，↓ 上扫，· 空拍，× 拍弦；弦序为 ① 在上、⑥ 在下（最粗弦）。")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
        }
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        guard idx >= 0, idx < count else { return nil }
        return self[idx]
    }
}

