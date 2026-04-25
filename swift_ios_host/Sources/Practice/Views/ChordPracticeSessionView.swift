import ChordChart
import Core
import Metronome
import Practice
import SwiftUI

/// 练琴「和弦切换」：题目来自 `ChordSwitchGenerator`。
/// 「下一组」按练习设置里的**难度**与**调性**重新出题；在设置里改**调性**会立即移调当前题（级数不变）。
struct ChordPracticeSessionView: View {
    @State private var exercise: ChordSwitchExercise = Self.bootstrapExercise()

    @State private var showPracticeSettings: Bool = false

    /// 「下一组」使用的难度（默认与首题一致）。
    @State private var selectedDifficulty: ChordSwitchDifficulty = .初级

    /// 当前调性主音；修改后立即作用到 `exercise`。
    @State private var selectedTonic: String = ChordSwitchGenerator.defaultTonic

    @StateObject private var metronomeVM = MetronomeViewModel()
    @State private var metronomeBPM: Int = 60
    @State private var selectedTimeSignature: MetronomeTimeSignature = .fourFour

    /// 练习页一行说明：本组和弦所在调性（与出题 `keyZh` 一致）。
    private var practiceKeyDescriptionLine: String {
        let t = ChordSwitchGenerator.parseTonicKey(from: exercise.keyZh)
        return "本组和弦为 \(exercise.keyZh) 的 \(t) 自然大调进行；和弦符号、指法与级数均相对该调。"
    }

    private var recommendedBPM: Int {
        let candidate: Int
        if exercise.bpmMin > 0, exercise.bpmMax > 0 {
            candidate = (exercise.bpmMin + exercise.bpmMax) / 2
        } else if exercise.bpmMin > 0 {
            candidate = exercise.bpmMin
        } else if exercise.bpmMax > 0 {
            candidate = exercise.bpmMax
        } else {
            candidate = 60
        }
        return MetronomeConfig.clampBPM(candidate)
    }

    private let bpmMin = 40
    private let bpmMax = 220

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
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

                    Text(practiceKeyDescriptionLine)
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    // 题面变长（高级和弦更多、提示文案更长）时允许页面纵向滚动，
                    // 避免 `aspectRatio(..., .fit)` 的指法图区为适配可用高度而整体缩小。
                    ChordPracticeDiagramStrip(chordSymbols: exercise.flattenedChords)

                    Text(exercise.bpmHintZh)
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .padding(.top, 4)

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
                            Button {
                                togglePracticeMetronome()
                            } label: {
                                Text(metronomeVM.transport == .running ? "⏸ 暂停" : "▶ 开始")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .appSecondaryButton()
                        }
                        Picker("拍号", selection: $selectedTimeSignature) {
                            Text("4/4").tag(MetronomeTimeSignature.fourFour)
                            Text("3/4").tag(MetronomeTimeSignature.threeFour)
                            Text("6/8").tag(MetronomeTimeSignature.sixEight)
                        }
                        .pickerStyle(.segmented)
                        if let err = metronomeVM.errorMessage, !err.isEmpty {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Text(exercise.promptZh)
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.text)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("下一组") { advanceToNextGroup() }
                        .appSecondaryButton()
                        .frame(maxWidth: .infinity)
                }
                .appCard()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("和弦切换练习")
        .navigationBarTitleDisplayMode(.inline)
        // 勿隐藏系统返回：否则禁用边缘右滑 pop（见 swift_app SightSingingViews 注释）。
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    stopMetronome()
                    showPracticeSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("练习设置")
            }
        }
        .onAppear {
            syncBPMFromExercise()
        }
        .onChange(of: selectedTimeSignature) { _, newValue in
            metronomeVM.setTimeSignature(newValue)
        }
        .onDisappear {
            stopMetronome()
        }
        .sheet(isPresented: $showPracticeSettings) {
            NavigationStack {
                Form {
                    Section("难度") {
                        Picker("难度", selection: $selectedDifficulty) {
                            ForEach(ChordSwitchDifficulty.allCases, id: \.self) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("选择后点击「下一组」按该难度重新随机出题。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("调性") {
                        Picker("调性", selection: $selectedTonic) {
                            ForEach(ChordSwitchGenerator.selectableTonics, id: \.self) { t in
                                Text(ChordSwitchGenerator.keyZhLabel(tonic: t)).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("更改后立即按新调性移调当前和弦与指法（级数不变）。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("练习设置")
                .onAppear {
                    // 仅同步调性：避免覆盖用户已选、尚未点「下一组」的难度。
                    selectedTonic = ChordSwitchGenerator.parseTonicKey(from: exercise.keyZh)
                }
                .onChange(of: selectedTonic) { _, newValue in
                    stopMetronome()
                    exercise = ChordSwitchGenerator.withTonic(exercise, to: newValue)
                    syncBPMFromExercise()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { showPracticeSettings = false }
                    }
                }
            }
        }
        .appPageBackground()
    }

    private static func bootstrapExercise() -> ChordSwitchExercise {
        var rng = SystemRandomNumberGenerator()
        return ChordSwitchGenerator.buildExercise(
            difficulty: .初级,
            tonic: ChordSwitchGenerator.defaultTonic,
            using: &rng
        )
    }

    private func togglePracticeMetronome() {
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

    private func syncBPMFromExercise() {
        metronomeBPM = max(bpmMin, min(bpmMax, recommendedBPM))
        metronomeVM.setBPM(metronomeBPM)
    }

    private func stopMetronome() {
        metronomeVM.stop()
    }

    private func advanceToNextGroup() {
        var rng = SystemRandomNumberGenerator()
        stopMetronome()
        exercise = ChordSwitchGenerator.buildExercise(
            difficulty: selectedDifficulty,
            tonic: selectedTonic,
            using: &rng
        )
        syncBPMFromExercise()
    }
}
