import ChordChart
import Chords
import Core
import Practice
import SwiftUI

/// 练琴「和弦切换」：进入即练习；题目仅来自 `ChordSwitchGenerator`。
struct ChordPracticeSessionView: View {
    let task: PracticeTask
    let store: PracticeSessionStore

    @State private var exercise: ChordSwitchExercise = Self.bootstrapExercise()

    @Environment(\.dismiss) private var dismiss

    @State private var startedAt: Date?
    @State private var elapsedSeconds: Int = 0
    @State private var running: Bool = false

    @State private var showFinishSheet: Bool = false
    @State private var noteText: String = ""

    @State private var showNeedStartHint: Bool = false
    @State private var savingError: String?
    @State private var savedToast: Bool = false

    @State private var showPracticeSettings: Bool = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var referenceKeyLabel: String {
        ChordSwitchKeyResolver.referenceMajorKeyLabel(for: exercise)
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("本组练习")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.muted)
                    Spacer()
                    Text(exercise.difficulty.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SwiftAppTheme.brandSoft)
                        .clipShape(Capsule())
                }
                ChordPracticeDiagramStrip(chordSymbols: exercise.flattenedChords)
                Text(exercise.bpmHintZh)
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
                Text(exercise.promptZh)
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.text)
                    .lineLimit(8)

                Button("下一组") { advanceToNextGroup() }
                    .appSecondaryButton()
                    .frame(maxWidth: .infinity)
            }
            .appCard()

            Spacer()

            Text(formatDurationLocal(elapsedSeconds))
                .font(.system(size: 54, weight: .semibold, design: .rounded))
                .foregroundStyle(SwiftAppTheme.text)
                .monospacedDigit()

            HStack(spacing: 12) {
                if !running {
                    Button("开始") { start() }
                        .appPrimaryButton()
                } else {
                    Button("暂停") { pause() }
                        .appSecondaryButton()
                }

                Button("结束") { finishTapped() }
                    .buttonStyle(.bordered)
                    .tint(SwiftAppTheme.brandSoft)
            }

            Spacer()
        }
        .padding(SwiftAppTheme.pagePadding)
        .navigationTitle("和弦切换练习")
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
                    showPracticeSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("参考调性")
            }
        }
        .sheet(isPresented: $showPracticeSettings) {
            NavigationStack {
                Form {
                    Section("参考调性") {
                        Text(referenceKeyLabel)
                            .font(.title3.weight(.semibold))
                        Text(
                            "根据本组和弦符号自动推断最可能的自然大调主音；题目由 `ChordSwitchGenerator` 生成。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("练习说明")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { showPracticeSettings = false }
                    }
                }
            }
        }
        .onReceive(ticker) { _ in
            guard running else { return }
            elapsedSeconds += 1
        }
        .alert("先开始练习再结束哦", isPresented: $showNeedStartHint) {
            Button("知道了", role: .cancel) {}
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
                title: "本次练习完成",
                showCompletedGoal: true,
                noteText: $noteText,
                onCancel: { showFinishSheet = false },
                onSave: { result in
                    showFinishSheet = false
                    Task { await save(result: result) }
                }
            )
        }
        .appPageBackground()
    }

    private static func bootstrapExercise() -> ChordSwitchExercise {
        var rng = SystemRandomNumberGenerator()
        return ChordSwitchGenerator.buildExercise(difficulty: .初级, using: &rng)
    }

    /// 初 → 中 → 高 → 初，每次用 `ChordSwitchGenerator` 重新随机组卷。
    private func advanceToNextGroup() {
        running = false
        var rng = SystemRandomNumberGenerator()
        let nextDifficulty: ChordSwitchDifficulty = switch exercise.difficulty {
        case .初级: .中级
        case .中级: .高级
        case .高级: .初级
        }
        exercise = ChordSwitchGenerator.buildExercise(difficulty: nextDifficulty, using: &rng)
    }

    private func start() {
        guard !running else { return }
        startedAt = startedAt ?? Date()
        running = true
    }

    private func pause() {
        running = false
    }

    private func finishTapped() {
        guard elapsedSeconds > 0 else {
            showNeedStartHint = true
            return
        }
        pause()
        showFinishSheet = true
    }

    @MainActor
    private func save(result: PracticeFinishResult) async {
        guard let startedAt else { return }
        do {
            try await store.saveSession(
                task: task,
                startedAt: startedAt,
                endedAt: Date(),
                durationSeconds: elapsedSeconds,
                completed: result.completed,
                difficulty: result.difficulty,
                note: result.note,
                progressionId: exercise.id,
                musicKey: referenceKeyLabel,
                complexity: exercise.difficulty.rawValue,
                rhythmPatternId: nil
            )
            savedToast = true
        } catch {
            savingError = String(describing: error)
        }
    }
}

private func formatDurationLocal(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let m = String(format: "%02d", s / 60)
    let r = String(format: "%02d", s % 60)
    return "\(m):\(r)"
}
