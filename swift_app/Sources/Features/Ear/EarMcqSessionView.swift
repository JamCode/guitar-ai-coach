import SwiftUI
import Core

public struct EarMcqSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EarMcqSessionViewModel
    @State private var showSummary = false
    private let onSessionComplete: ((Int, Int) -> Void)?
    private let autoDismissOnComplete: Bool

    public init(
        title: String,
        bank: String,
        totalQuestions: Int = 10,
        chordDifficulty: EarChordMcqDifficulty = .初级,
        onSessionComplete: ((Int, Int) -> Void)? = nil,
        autoDismissOnComplete: Bool = true
    ) {
        _viewModel = StateObject(
            wrappedValue: EarMcqSessionViewModel(
                title: title,
                bank: bank,
                totalQuestions: totalQuestions,
                chordDifficulty: chordDifficulty
            )
        )
        self.onSessionComplete = onSessionComplete
        self.autoDismissOnComplete = autoDismissOnComplete
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.loading {
                    ProgressView("加载中…")
                        .tint(SwiftAppTheme.brand)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                } else if let err = viewModel.loadError {
                    Text(err).foregroundStyle(.red).appCard()
                } else if let q = viewModel.question {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("题目").appSectionTitle()
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(q.promptZh).foregroundStyle(SwiftAppTheme.text)
                            if viewModel.bank == "A" {
                                Self.chordDifficultyBadge(viewModel.chordDifficulty)
                            }
                        }
                        if let hint = q.hintZh, !hint.isEmpty {
                            Text(hint).foregroundStyle(SwiftAppTheme.muted)
                        }
                        Text("使用吉他采样合成，与预录音色可能略有差异。")
                            .font(.caption)
                            .foregroundStyle(SwiftAppTheme.muted)
                        Text(viewModel.sessionStatsLine)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SwiftAppTheme.muted)
                        if let playError = viewModel.playError {
                            Text(playError).foregroundStyle(.red)
                        }
                        Button("播放") { Task { await viewModel.playCurrent() } }
                            .appPrimaryButton()
                            .disabled(viewModel.isPlaybackInProgress)
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("四选一").appSectionTitle()
                        ForEach(Array(q.options.enumerated()), id: \.offset) { idx, opt in
                            let rowShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                            let isCorrect = opt.key == q.correctOptionKey
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
                                    Text(opt.label).foregroundStyle(SwiftAppTheme.text)
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
                            .buttonStyle(.borderless)
                            .disabled(viewModel.revealed)
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
                            let ok = q.options[picked].key == q.correctOptionKey
                            let answer = q.options.first(where: { $0.key == q.correctOptionKey })?.label ?? "--"
                            Text(ok ? "回答正确：\(answer)" : "回答错误：正确答案是 \(answer)")
                                .foregroundStyle(ok ? SwiftAppTheme.dynamic(.green, .green) : .red)
                        }
                        if viewModel.revealed {
                            let strip = q.playbackChromaticStripMidis
                            let highlights = q.playbackHighlightMidiSet
                            if !strip.isEmpty {
                                let firstRowCount = (strip.count + 1) / 2
                                let row1 = Array(strip.prefix(firstRowCount))
                                let row2 = Array(strip.suffix(strip.count - firstRowCount))
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("本题音区（可点试听，至少一个八度）")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(SwiftAppTheme.muted)
                                    VStack(alignment: .leading, spacing: 6) {
                                        mcqChromaticPillRow(midis: row1, highlights: highlights)
                                        mcqChromaticPillRow(midis: row2, highlights: highlights)
                                    }
                                }
                            }
                        }
                    }
                    .appCard()

                    if viewModel.revealed {
                        Button(viewModel.pageIndex >= viewModel.session.count - 1 ? "查看结果" : "下一题") {
                            viewModel.nextOrFinish()
                            if viewModel.finished { showSummary = true }
                        }
                        .appPrimaryButton()
                    }
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(viewModel.title)
        .appPageBackground()
        .task {
            if viewModel.loading {
                await viewModel.bootstrap()
            }
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

    @ViewBuilder
    private func mcqChromaticPillRow(midis: [Int], highlights: Set<Int>) -> some View {
        HStack(spacing: 6) {
            ForEach(midis, id: \.self) { midi in
                let isHl = highlights.contains(midi)
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
                            isHl ? SwiftAppTheme.brand : SwiftAppTheme.line,
                            lineWidth: isHl ? 2 : 1
                        )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func scientificPitchLabel(midi: Int) -> String {
        "\(PitchMath.midiToNoteName(midi))\(midi / 12 - 1)"
    }

    private static func chordDifficultyBadge(_ d: EarChordMcqDifficulty) -> some View {
        Text(d.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(SwiftAppTheme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(SwiftAppTheme.surfaceSoft)
            .clipShape(Capsule())
            .accessibilityLabel("难度 \(d.rawValue)")
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
