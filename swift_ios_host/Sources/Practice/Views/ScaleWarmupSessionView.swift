import SwiftUI
import Core
import Practice

/// 爬格子热身：随机题卡 + 练习顺序说明 + 带编号指板示意；难度在齿轮内选择。不含页面内计时器。
struct ScaleWarmupSessionView: View {
    let task: PracticeTask
    let store: PracticeSessionStore

    @Environment(\.dismiss) private var dismiss

    @AppStorage("practice.scaleWarmup.difficultyRaw") private var difficultyRaw: String = ScaleWarmupDifficulty.初级.rawValue

    @State private var drill: ScaleWarmupDrill = ScaleWarmupGenerator.drills(for: .初级)[0]
    @State private var openedAt: Date = Date()

    @State private var showSettings: Bool = false
    @State private var showFinishSheet: Bool = false
    @State private var noteText: String = ""

    @State private var savingError: String?
    @State private var savedToast: Bool = false

    private var selectedDifficulty: ScaleWarmupDifficulty {
        ScaleWarmupDifficulty(rawValue: difficultyRaw) ?? .初级
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
                    Text(drill.titleLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(drill.detailLine)
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.text)
                        .lineLimit(3)
                    Text(drill.tip)
                        .font(.footnote)
                        .foregroundStyle(SwiftAppTheme.muted)
                    Text("每次进入或点「下一组」会按当前难度随机抽题卡；可与外置节拍器同练，本页不含音频节拍器。")
                        .font(.footnote)
                        .foregroundStyle(SwiftAppTheme.muted)
                }
                .appCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("练习顺序")
                        .appSectionTitle()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(drill.sequenceBullets.enumerated()), id: \.offset) { _, line in
                            Text("· \(line)")
                                .font(.footnote)
                                .foregroundStyle(SwiftAppTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .appCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("指板示意")
                        .appSectionTitle()
                    Text("TAB：① 弦在最上，⑥ 弦在最下；格内数字为弹奏先后（方案 3）。")
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                    ScaleWarmupFretMiniGrid(drill: drill)
                }
                .appCard()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(drill.sequenceBullets.joined(separator: " "))

                Button("下一组") { nextDrill() }
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
                        Picker("难度", selection: Binding(
                            get: { ScaleWarmupDifficulty(rawValue: difficultyRaw) ?? .初级 },
                            set: { difficultyRaw = $0.rawValue }
                        )) {
                            ForEach(ScaleWarmupDifficulty.allCases) { lv in
                                Text(lv.rawValue).tag(lv)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("选择后会立即按该难度抽取新的题卡。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("说明") {
                        Text(
                            """
                            题卡为常见爬格子热身示意（弦范围、品位、建议速度与轮数），请按自身手型微调。

                            「练习顺序」与指板数字为建议顺序；往返题型请结合文案原路返回。

                            本页不包含内置节拍器或音频，建议配合外置节拍器或慢速曲目练习。
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
            reshuffleDrill(excluding: nil)
        }
        .onChange(of: difficultyRaw) { _, _ in
            reshuffleDrill(excluding: nil)
        }
    }

    private func nextDrill() {
        reshuffleDrill(excluding: drill.id)
    }

    private func reshuffleDrill(excluding: String?) {
        var rng = SystemRandomNumberGenerator()
        drill = ScaleWarmupGenerator.nextDrill(
            difficulty: selectedDifficulty,
            excluding: excluding,
            using: &rng
        )
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
                rhythmPatternId: nil,
                scaleWarmupDrillId: drill.id
            )
            savedToast = true
        } catch {
            savingError = String(describing: error)
        }
    }
}

// MARK: - 指板小格（TAB 向 + 编号）

private struct ScaleWarmupFretMiniGrid: View {
    let drill: ScaleWarmupDrill

    private var frets: [Int] {
        Array(drill.fretStart ... drill.fretEnd)
    }

    /// TAB：1=① 在最上行。
    private let stringNumbersTopToBottom = [1, 2, 3, 4, 5, 6]

    private var orderByCell: [String: Int] {
        var m: [String: Int] = [:]
        for s in drill.orderedSteps {
            m["\(s.stringNumber)-\(s.fret)"] = s.order
        }
        return m
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(" ")
                    .frame(width: 26, height: 26)
                ForEach(frets, id: \.self) { f in
                    Text("\(f)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(SwiftAppTheme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .border(SwiftAppTheme.line, width: 0.5)
                }
            }
            ForEach(stringNumbersTopToBottom, id: \.self) { s in
                HStack(spacing: 0) {
                    Text(circleStringName(s))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(SwiftAppTheme.muted)
                        .frame(width: 26, height: 28)
                        .border(SwiftAppTheme.line, width: 0.5)
                    ForEach(frets, id: \.self) { f in
                        cell(string: s, fret: f)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func cell(string s: Int, fret f: Int) -> some View {
        let inRegion = drill.stringsIncluded.contains(s) && frets.contains(f)
        let key = "\(s)-\(f)"
        let ord = orderByCell[key]
        ZStack {
            Rectangle()
                .fill(inRegion ? SwiftAppTheme.brandSoft.opacity(0.35) : SwiftAppTheme.surfaceSoft.opacity(0.2))
            if let ord {
                Text("\(ord)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(SwiftAppTheme.text)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .border(SwiftAppTheme.line, width: 0.5)
    }

    private func circleStringName(_ n: Int) -> String {
        switch n {
        case 1: return "①"
        case 2: return "②"
        case 3: return "③"
        case 4: return "④"
        case 5: return "⑤"
        case 6: return "⑥"
        default: return "\(n)"
        }
    }
}
