import SwiftUI
import Core
import Chords

public struct EarMcqSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EarMcqSessionViewModel
    @State private var showSummary = false
    private let onSessionComplete: ((Int, Int) -> Void)?
    private let autoDismissOnComplete: Bool

    /// - Parameters:
    ///   - maxQuestions: `nil`（默认）为不限题量；非 `nil` 为本轮题量，末题后可「查看结果」。
    ///     `bank == "B"` 且有上限时从题库至多抽取该题数；缺省上限的旧调用可用 `maxQuestions: 10`。
    public init(
        title: String,
        bank: String,
        maxQuestions: Int? = nil,
        chordDifficulty: EarChordMcqDifficulty = .初级,
        onSessionComplete: ((Int, Int) -> Void)? = nil,
        autoDismissOnComplete: Bool = true
    ) {
        _viewModel = StateObject(
            wrappedValue: EarMcqSessionViewModel(
                title: title,
                bank: bank,
                maxQuestions: maxQuestions,
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
                        Text(
                            Self.usesVoicingPlaybackCaption(for: q)
                                ? "试听与「常用和弦」一致：先分解琶音（低音→高音），再柱式和弦；钢弦 SF2 采样。"
                                : "使用吉他采样合成，与预录音色可能略有差异。"
                        )
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
                            let suffix = Self.feedbackChordSuffix(for: q)
                            Text(Self.feedbackLine(ok: ok, answerLabel: answer, suffix: suffix))
                                .foregroundStyle(ok ? SwiftAppTheme.dynamic(.green, .green) : .red)
                        }
                        if viewModel.revealed {
                            if viewModel.bank == "A", let frets = q.playbackFretsSixToOne, frets.count == 6 {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("本题指法（与试听相同）")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(SwiftAppTheme.muted)
                                    ChordDiagramView(frets: frets)
                                        .frame(maxWidth: 184, maxHeight: 142)
                                        .clipped()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else if let seq = EarProgressionPlayback.playbackFretsSequence(for: q),
                                      !seq.isEmpty,
                                      q.questionType == "progression_recognition" || viewModel.bank == "B" {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("本段和声指法（与试听顺序一致，左→右）")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(SwiftAppTheme.muted)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 10) {
                                            ForEach(0 ..< seq.count, id: \.self) { idx in
                                                ChordDiagramView(frets: seq[idx])
                                                    .frame(maxWidth: 132, maxHeight: 108)
                                                    .clipped()
                                            }
                                        }
                                    }
                                }
                            } else {
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
                    }
                    .appCard()

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

    private static func usesVoicingPlaybackCaption(for q: EarBankItem) -> Bool {
        if q.questionType == "progression_recognition" || q.mode == "B" {
            return EarProgressionPlayback.playbackFretsSequence(for: q) != nil
        }
        return q.mode == "A"
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

    /// 如 `Dm`、`G7`，与出题 `target_quality` + 根音一致。
    private static func chordMarkText(for q: EarBankItem) -> String? {
        guard let root = q.root, !root.isEmpty else { return nil }
        let qualityId = qualityIdForChordMark(q.targetQuality)
        let sym = ChordSymbolBuilder.build(root: root, qualityId: qualityId, bassId: "")
        return sym.isEmpty ? nil : sym
    }

    private static func qualityIdForChordMark(_ token: String?) -> String {
        guard let raw = token?.lowercased(), !raw.isEmpty else { return "" }
        switch raw {
        case "major", "maj": return ""
        case "minor", "min", "m": return "m"
        case "dominant7", "7", "dom7": return "7"
        case "major7", "maj7", "m7maj", "delta": return "maj7"
        case "minor7", "min7", "m7": return "m7"
        default: return ""
        }
    }

    private static func feedbackChordSuffix(for q: EarBankItem) -> String {
        if q.mode == "B" || q.questionType == "progression_recognition" {
            let t = EarProgressionPlayback.progressionMarkText(for: q)
            return t.isEmpty ? "" : "（\(t)）"
        }
        if let m = chordMarkText(for: q), !m.isEmpty { return "（\(m)）" }
        return ""
    }

    private static func feedbackLine(ok: Bool, answerLabel: String, suffix: String) -> String {
        if ok {
            return "回答正确：\(answerLabel)\(suffix)"
        }
        return "回答错误：正确答案是 \(answerLabel)\(suffix)"
    }
}
