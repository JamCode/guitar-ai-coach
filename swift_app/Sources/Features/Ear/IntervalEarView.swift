import SwiftUI
import Core

public struct IntervalEarView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: IntervalEarSessionViewModel
    @State private var showSummary = false
    private let onSessionComplete: ((Int, Int) -> Void)?
    private let autoDismissOnComplete: Bool

    /// - Parameters:
    ///   - maxQuestions: 题量上限；`nil`（默认）为不限题量，可一直「下一题」并由算法续出题。
    ///   - onSessionComplete: 仅在有题量上限且用户点「查看结果」并确认小结后回调 `(答对数, 已答题数)`。
    public init(
        maxQuestions: Int? = nil,
        difficulty: IntervalEarDifficulty = .初级,
        onSessionComplete: ((Int, Int) -> Void)? = nil,
        autoDismissOnComplete: Bool = true
    ) {
        _viewModel = StateObject(
            wrappedValue: IntervalEarSessionViewModel(maxQuestions: maxQuestions, difficulty: difficulty)
        )
        self.onSessionComplete = onSessionComplete
        self.autoDismissOnComplete = autoDismissOnComplete
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("说明").appSectionTitle()
                    Text("听两个音，选择它们之间的音程。")
                        .foregroundStyle(SwiftAppTheme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker("难度", selection: difficultyBinding) {
                        ForEach(IntervalEarDifficulty.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewModel.revealed)
                    if let hint = IntervalEarDifficulty.helpText[viewModel.difficulty] {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(SwiftAppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("先播较低音，再播较高音；需要时可多次点击「播放」。")
                        .foregroundStyle(SwiftAppTheme.muted)
                    Text(viewModel.sessionStatsLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SwiftAppTheme.muted)
                    if let playError = viewModel.playError {
                        Text(playError).foregroundStyle(.red)
                    }
                    HStack(alignment: .center, spacing: 10) {
                        Button("播放") { Task { await viewModel.playPair() } }
                            .appPrimaryButton()
                            .disabled(viewModel.isPlaybackInProgress)
                            .fixedSize(horizontal: true, vertical: false)
                        if viewModel.revealed, let q = viewModel.question {
                            Text(
                                "\(Self.scientificPitchLabel(midi: q.lowMidi)) → \(Self.scientificPitchLabel(midi: q.highMidi))"
                            )
                            .font(.subheadline.weight(.medium).monospaced())
                            .foregroundStyle(SwiftAppTheme.text)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .appCard()

                if let q = viewModel.question {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("四选一").appSectionTitle()
                        ForEach(Array(q.choices.enumerated()), id: \.offset) { idx, choice in
                            let rowShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                            let isCorrect = choice.semitones == q.answer.semitones
                            let isPicked = viewModel.selectedChoiceIndex == idx
                            let borderColor = Self.choiceRowBorderColor(
                                revealed: viewModel.revealed,
                                isCorrect: isCorrect,
                                isPicked: isPicked
                            )
                            let borderWidth: CGFloat = viewModel.revealed && (isCorrect || (isPicked && !isCorrect)) ? 2 : (isPicked ? 1.5 : 1)
                            Button {
                                viewModel.selectChoice(idx)
                            } label: {
                                HStack {
                                    Text(choice.nameZh).foregroundStyle(SwiftAppTheme.text)
                                    Spacer()
                                    if viewModel.revealed {
                                        if isCorrect {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(SwiftAppTheme.dynamic(.green, .green))
                                        } else if isPicked {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.red)
                                        }
                                    } else if isPicked {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(SwiftAppTheme.brand)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(rowShape)
                            }
                            // `ScrollView` 内用 borderless，避免与滚动手势抢首点；`contentShape` 让整行可点。
                            .buttonStyle(.borderless)
                            .disabled(viewModel.revealed || !viewModel.hasCompletedInitialAudition)
                            .opacity(viewModel.hasCompletedInitialAudition || viewModel.revealed ? 1 : 0.45)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                viewModel.revealed && isPicked && !isCorrect
                                    ? Color.red.opacity(0.06)
                                    : (viewModel.revealed && isCorrect ? SwiftAppTheme.brandSoft.opacity(0.35) : SwiftAppTheme.surfaceSoft)
                            )
                            .clipShape(rowShape)
                            .overlay(
                                rowShape.stroke(borderColor, lineWidth: borderWidth)
                            )
                        }
                        if viewModel.revealed, let picked = viewModel.selectedChoiceIndex {
                            let ok = q.choices[picked].semitones == q.answer.semitones
                            Text(ok ? "回答正确：\(q.answer.nameZh)。" : "回答错误：正确答案是 \(q.answer.nameZh)。")
                                .foregroundStyle(ok ? SwiftAppTheme.dynamic(.green, .green) : .red)
                        }
                        if viewModel.revealed {
                            let strip = IntervalChromaticStrip.midisCoveringOctaveIncluding(
                                lowMidi: q.lowMidi,
                                highMidi: q.highMidi
                            )
                            let firstRowCount = (strip.count + 1) / 2
                            let row1 = Array(strip.prefix(firstRowCount))
                            let row2 = Array(strip.suffix(strip.count - firstRowCount))
                            VStack(alignment: .leading, spacing: 8) {
                                Text("本题音区（可点试听，至少一个八度）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SwiftAppTheme.muted)
                                VStack(alignment: .leading, spacing: 6) {
                                    chromaticPillRow(midis: row1, question: q)
                                    chromaticPillRow(midis: row2, question: q)
                                }
                            }
                        }
                    }
                    .appCard()
                }

                if viewModel.revealed {
                    Button(
                        viewModel.hasSessionCap && viewModel.isOnLastCappedQuestion ? "查看结果" : "下一题"
                    ) {
                        viewModel.nextOrFinish()
                        if viewModel.hasSessionCap, viewModel.finished { showSummary = true }
                    }
                    .appPrimaryButton()
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("音程识别")
        .appPageBackground()
        .onDisappear {
            viewModel.cancelPlayback()
        }
        .alert("本轮完成", isPresented: $showSummary) {
            Button("确定") {
                onSessionComplete?(viewModel.correctCount, viewModel.answeredCount)
                if autoDismissOnComplete {
                    dismiss()
                }
            }
        } message: {
            Text(viewModel.summaryText)
        }
    }

    private var difficultyBinding: Binding<IntervalEarDifficulty> {
        Binding(
            get: { viewModel.difficulty },
            set: { viewModel.setDifficultyIfChanged($0) }
        )
    }

    @ViewBuilder
    private func chromaticPillRow(midis: [Int], question: IntervalQuestion) -> some View {
        HStack(spacing: 6) {
            ForEach(midis, id: \.self) { midi in
                let isQuestionNote = midi == question.lowMidi || midi == question.highMidi
                Button {
                    Task { await viewModel.playPreviewNote(midi: midi) }
                } label: {
                    Text(Self.scientificPitchLabel(midi: midi))
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(SwiftAppTheme.text)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .background(SwiftAppTheme.surfaceSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isQuestionNote ? SwiftAppTheme.brand : SwiftAppTheme.line,
                            lineWidth: isQuestionNote ? 2 : 1
                        )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 科学音高记谱，如 MIDI 48 → `C3`（与播放顺序一致：先低后高）。
    private static func scientificPitchLabel(midi: Int) -> String {
        "\(PitchMath.midiToNoteName(midi))\(midi / 12 - 1)"
    }

    private static func choiceRowBorderColor(revealed: Bool, isCorrect: Bool, isPicked: Bool) -> Color {
        if revealed {
            if isCorrect { return SwiftAppTheme.dynamic(.green, .green) }
            if isPicked, !isCorrect { return .red }
            return SwiftAppTheme.line
        }
        if isPicked { return SwiftAppTheme.brand }
        return SwiftAppTheme.line
    }
}
