import SwiftUI


struct AdaptiveEarTrainingView: View {
    let sessions: [PracticeSession]

    @StateObject private var vm = AdaptiveEarTrainingViewModel()
    @AppStorage("adaptive_ear_auto_play_next") private var autoPlayNext = false
    @AppStorage("adaptive_ear_show_explanation") private var showExplanation = true
    @State private var showingCombinedStats = false
    @State private var showHintStrip = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                abilityCard

                if vm.loading {
                    ProgressView("生成练耳题中…")
                        .frame(maxWidth: .infinity)
                        .appCard()
                } else if let error = vm.loadError {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error)
                            .foregroundStyle(SwiftAppTheme.text)
                        Button("重试") {
                            Task { await vm.bootstrap() }
                        }
                        .appPrimaryButton()
                    }
                    .appCard()
                } else if vm.isPreparingQuestion {
                    ProgressView("正在准备下一题…")
                        .frame(maxWidth: .infinity)
                        .appCard()
                } else if let question = vm.currentQuestion {
                    questionCard(question)
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .practiceAdaptiveScrollBackground()
        .refreshable { await vm.bootstrap() }
        .task { await vm.bootstrap() }
        .task(id: vm.questionToken) {
            showHintStrip = false
            guard autoPlayNext else { return }
            await vm.playCurrent()
        }
        .sheet(isPresented: $showingCombinedStats) {
            NavigationStack {
                CombinedStatsView(
                    state: vm.state,
                    records: vm.records,
                    sessions: sessions
                )
            }
        }
        .onDisappear {
            vm.cancelPlayback()
        }
    }

    private var abilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("听力值 \(vm.state.roundedOverallRating)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(SwiftAppTheme.text)
                        .monospacedDigit()
                    Text(vm.recommendationLine)
                        .font(.footnote)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(vm.state.levelTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(SwiftAppTheme.brandSoft)
                        .clipShape(Capsule())
                    Text(vm.recentAccuracyText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(vm.todayCountText)
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                }
            }

            HStack(spacing: 8) {
                ratingChip(title: "音程", value: vm.state.intervalRating)
                ratingChip(title: "和弦", value: vm.state.chordRating)
                ratingChip(title: "进行", value: vm.state.progressionRating)
                ratingChip(title: "单音", value: vm.state.singleNoteRating)
                ratingChip(title: "节奏", value: vm.state.rhythmRating)
            }
        }
        .appCard()
        .accessibilityIdentifier("adaptiveEar.abilityCard")
    }

    private func ratingChip(title: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
            Text("\(Int(value.rounded()))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.text)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(SwiftAppTheme.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func questionCard(_ question: AdaptiveEarQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(question.kind.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(SwiftAppTheme.brandSoft)
                    .clipShape(Capsule())
                Text(question.difficulty.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                Spacer()
                Text("第 \(vm.state.totalAnswered + 1) 题")
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
            }

            Text(question.prompt)
                .font(.title3.weight(.bold))
                .foregroundStyle(SwiftAppTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            playButton

            if case .interval = question {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showHintStrip.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showHintStrip ? "lightbulb.fill" : "lightbulb")
                            .font(.caption)
                        Text(showHintStrip ? "收起提示" : "提示")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(SwiftAppTheme.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SwiftAppTheme.brandSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                if showHintStrip {
                    hintChromaticStrip(for: question)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if case .chord = question {
                chordHintOptionsView(for: question)
            }

            if case .progression = question {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showHintStrip.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showHintStrip ? "lightbulb.fill" : "lightbulb")
                            .font(.caption)
                        Text(showHintStrip ? "收起提示" : "逐和弦试听")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(SwiftAppTheme.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SwiftAppTheme.brandSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                if showHintStrip {
                    progressionHintOptionsView(for: question)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if case .singleNote = question {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showHintStrip.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showHintStrip ? "lightbulb.fill" : "lightbulb")
                            .font(.caption)
                        Text(showHintStrip ? "收起提示" : "逐音试听")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(SwiftAppTheme.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SwiftAppTheme.brandSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                if showHintStrip {
                    singleNoteHintView(for: question)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // 节奏题图例：解释选项中的符号含义
            if case .rhythm = question {
                rhythmLegend
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(question.choices) { choice in
                    answerButton(choice: choice, question: question)
                }
            }

            if let feedback = vm.feedback {
                feedbackCard(feedback, question: question)
            }

            HStack(spacing: 10) {
                Button("下一题") {
                    Task { await vm.nextQuestion() }
                }
                .appPrimaryButton()
                .frame(maxWidth: .infinity)
                .disabled(!vm.hasRevealed)
            }
        }
        .appCard()
        .accessibilityIdentifier("adaptiveEar.questionCard")
    }

    private var playButton: some View {
        Button {
            Task { await vm.playCurrent() }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: vm.isPlaying ? "waveform" : "play.circle.fill")
                    .font(.system(size: 48, weight: .semibold))
                Text(vm.isPlaying ? "播放中…" : "播放题目")
                    .font(.headline)
            }
            .foregroundStyle(SwiftAppTheme.brand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(SwiftAppTheme.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(vm.isPlaying)
    }

    private var rhythmLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("简谱记法说明")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.muted)
            HStack(spacing: 14) {
                legendItem("X", "四分（一拍）")
                legendItem("X\u{0332}", "八分（半拍）")
                legendItem("0", "四分休止")
                legendItem("0\u{0332}X\u{0332}", "休止+八分")
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private func legendItem(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(symbol)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(SwiftAppTheme.brand)
            Text(label)
                .font(.caption2)
                .foregroundStyle(SwiftAppTheme.muted)
                .lineLimit(1)
        }
    }

    private func answerButton(choice: AdaptiveEarChoice, question: AdaptiveEarQuestion) -> some View {
        let state = vm.answerVisualState(choice: choice, question: question)
        return Button {
            vm.submit(choice)
        } label: {
            Text(choice.label)
                .font(.headline.weight(.semibold))
                .foregroundStyle(state.textColor)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 8)
                .background(state.background)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(state.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(vm.hasRevealed)
    }

    private func feedbackCard(_ feedback: AdaptiveEarFeedback, question: AdaptiveEarQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: feedback.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(feedback.wasCorrect ? Color.green : Color.red)
                Text(feedback.title)
                    .font(.headline)
                    .foregroundStyle(SwiftAppTheme.text)
            }
            Text("正确答案：\(question.correctAnswerText)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.text)
            if !feedback.wasCorrect, showExplanation {
                Text(question.explanation)
                    .font(.footnote)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !feedback.wasCorrect {
                intervalChromaticStrip(for: question)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((feedback.wasCorrect ? Color.green : Color.red).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Interval Strip

    @ViewBuilder
    private func intervalChromaticStrip(for question: AdaptiveEarQuestion) -> some View {
        if case let .interval(interval, _, _) = question {
            let strip = IntervalChromaticStrip.midisCoveringOctaveIncluding(
                lowMidi: interval.lowMidi,
                highMidi: interval.highMidi
            )
            let firstRowCount = (strip.count + 1) / 2
            let row1 = Array(strip.prefix(firstRowCount))
            let row2 = Array(strip.suffix(strip.count - firstRowCount))

            VStack(alignment: .leading, spacing: 8) {
                Text("本题音区（可点试听，至少一个八度）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                VStack(alignment: .leading, spacing: 6) {
                    intervalChromaticPillRow(midis: row1, question: interval)
                    intervalChromaticPillRow(midis: row2, question: interval)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func hintChromaticStrip(for question: AdaptiveEarQuestion) -> some View {
        if case let .interval(interval, _, _) = question {
            let strip = IntervalChromaticStrip.midisCoveringOctaveIncluding(
                lowMidi: interval.lowMidi,
                highMidi: interval.highMidi
            )
            let firstRowCount = (strip.count + 1) / 2
            let row1 = Array(strip.prefix(firstRowCount))
            let row2 = Array(strip.suffix(strip.count - firstRowCount))

            VStack(alignment: .leading, spacing: 8) {
                Text("点击各音试听，找出本题的两个音")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                VStack(alignment: .leading, spacing: 6) {
                    hintChromaticPillRow(midis: row1, question: interval)
                    hintChromaticPillRow(midis: row2, question: interval)
                }
            }
            .padding(.top, 4)
        }
    }

    private func intervalChromaticPillRow(midis: [Int], question: IntervalQuestion) -> some View {
        HStack(spacing: 6) {
            ForEach(midis, id: \.self) { midi in
                let isQuestionNote = midi == question.lowMidi || midi == question.highMidi
                Button {
                    Task { await vm.playPreviewNote(midi: midi) }
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

    private func hintChromaticPillRow(midis: [Int], question: IntervalQuestion) -> some View {
        HStack(spacing: 6) {
            ForEach(midis, id: \.self) { midi in
                Button {
                    Task { await vm.playPreviewNote(midi: midi) }
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
                        .stroke(SwiftAppTheme.line, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chord Hint

    @ViewBuilder
    private func chordHintOptionsView(for question: AdaptiveEarQuestion) -> some View {
        if case let .chord(q, _, _) = question {
            let symbols = question.choices.map { Self.chordSymbol(from: $0, root: q.root) }
            ChordPreviewRow(symbols: symbols, isDisabled: vm.isPreviewingOption) { idx in
                let choice = question.choices[idx]
                Task { await vm.playChordForLabel(choice.label, root: q.root) }
            }
        }
    }

    /// 从选项标签 + 题目根音构建和弦符号（如 C、Cm、C7）
    private static func chordSymbol(from choice: AdaptiveEarChoice, root: String?) -> String {
        guard let root, !root.isEmpty,
              let quality = EarChordQuality(optionLabel: choice.label)
        else { return choice.label }
        let qualityId: String
        switch quality {
        case .major: qualityId = ""
        case .minor: qualityId = "m"
        case .dominant7: qualityId = "7"
        case .major7: qualityId = "maj7"
        case .minor7: qualityId = "m7"
        }
        let sym = ChordSymbolBuilder.build(root: root, qualityId: qualityId, bassId: "")
        return sym.isEmpty ? choice.label : sym
    }

    // MARK: - Progression Hint

    @ViewBuilder
    private func progressionHintOptionsView(for question: AdaptiveEarQuestion) -> some View {
        if case let .progression(item, _, _) = question {
            let key = item.musicKey ?? "C"
            let roman = item.progressionRoman ?? ""
            let chords = EarPlaybackMidi.letterChordSymbols(key: key, progressionRoman: roman)
            if !chords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("点击各和弦试听，拆解本题进行")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.brand)
                    HStack(spacing: 8) {
                        ForEach(chords, id: \.self) { chord in
                            Button {
                                Task { await vm.playChordForLabel(chord) }
                            } label: {
                                Text(chord)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SwiftAppTheme.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(SwiftAppTheme.surfaceSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(SwiftAppTheme.line, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Single Note Hint

    private func singleNoteHintView(for question: AdaptiveEarQuestion) -> some View {
        let range = singleNoteHintMidiRange(for: question)
        let allNotes = Array(range)
        let row1 = Array(allNotes.prefix((allNotes.count + 1) / 2))
        let row2 = Array(allNotes.suffix(allNotes.count - row1.count))
        return VStack(alignment: .leading, spacing: 8) {
            Text("标准音 A4（可点击重复播放）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.brand)
            Button {
                Task { await vm.playReferenceA4() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2")
                        .font(.caption)
                    Text("播放 A4（440Hz）")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(SwiftAppTheme.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(SwiftAppTheme.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("点击下方各音试听，自行判断本题的音")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.brand)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                singleNotePillRow(midis: row1)
                singleNotePillRow(midis: row2)
            }
        }
        .padding(.top, 4)
    }

    /// 根据单音题目难度，返回与 `makeSingleNoteQuestion` 音池匹配的半音 MIDI 范围
    private func singleNoteHintMidiRange(for question: AdaptiveEarQuestion) -> ClosedRange<Int> {
        guard case let .singleNote(_, difficulty, _) = question else {
            return 60...71
        }
        switch difficulty {
        case .beginner:
            return 60...72   // C4–C5，匹配 beginner 池 [60,62,64,65,67,69,71,72]
        case .intermediate:
            return 60...71   // C4–B4，匹配 intermediate 池 (60...71)
        case .advanced:
            return 52...76   // E3–E5，匹配 advanced 池 (52...76)
        }
    }

    private func singleNotePillRow(midis: [Int]) -> some View {
        HStack(spacing: 6) {
            ForEach(midis, id: \.self) { midi in
                Button {
                    Task { await vm.playPreviewNote(midi: midi) }
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
                        .stroke(SwiftAppTheme.line, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func scientificPitchLabel(midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pc = midi % 12
        let octave = (midi / 12) - 1
        return "\(names[pc])\(octave)"
    }
}

private struct AdaptiveAnswerVisualState {
    let background: Color
    let border: Color
    let textColor: Color
}

private extension AdaptiveEarTrainingViewModel {
    func answerVisualState(choice: AdaptiveEarChoice, question: AdaptiveEarQuestion) -> AdaptiveAnswerVisualState {
        guard hasRevealed else {
            return AdaptiveAnswerVisualState(
                background: SwiftAppTheme.surfaceSoft,
                border: SwiftAppTheme.line,
                textColor: SwiftAppTheme.text
            )
        }
        if choice.id == question.correctChoiceId {
            return AdaptiveAnswerVisualState(
                background: Color.green.opacity(0.14),
                border: Color.green.opacity(0.65),
                textColor: SwiftAppTheme.text
            )
        }
        if choice.id == selectedChoiceID {
            return AdaptiveAnswerVisualState(
                background: Color.red.opacity(0.12),
                border: Color.red.opacity(0.55),
                textColor: SwiftAppTheme.text
            )
        }
        return AdaptiveAnswerVisualState(
            background: SwiftAppTheme.surfaceSoft,
            border: SwiftAppTheme.line,
            textColor: SwiftAppTheme.muted
        )
    }
}

struct AdaptiveEarFeedback: Equatable {
    let wasCorrect: Bool
    let title: String
}

@MainActor
final class AdaptiveEarTrainingViewModel: ObservableObject {
    @Published private(set) var loading = true
    @Published private(set) var loadError: String?
    @Published private(set) var state: AdaptiveEarAbilityState = .initial
    @Published private(set) var records: [AdaptiveEarAttemptRecord] = []
    @Published private(set) var currentQuestion: AdaptiveEarQuestion?
    @Published private(set) var questionToken = UUID()
    @Published private(set) var isPreparingQuestion = false
    @Published private(set) var selectedChoiceID: String?
    @Published private(set) var hasRevealed = false
    @Published private(set) var feedback: AdaptiveEarFeedback?
    @Published private(set) var isPreviewingOption = false
    @Published private(set) var isPlaying = false
    @Published private(set) var playError: String?

    private let store: AdaptiveEarTrainingStoring
    private let intervalPlayer: IntervalTonePlaying
    private let chordPlayer: EarChordPlaying
    private let rhythmPlayer = RhythmAudioPlayer()
    private var rng = SystemRandomNumberGenerator()
    private var questionStartedAt = Date()
    private var previousIntervalLowMidi: Int?
    private var previousSingleNoteMidi: Int?
    private var playTask: Task<Void, Never>?
    private var prefetchTask: Task<AdaptiveEarQuestion, Never>?

    init(
        store: AdaptiveEarTrainingStoring = UserDefaultsAdaptiveEarTrainingStore(),
        intervalPlayer: IntervalTonePlaying = IntervalTonePlayer(),
        chordPlayer: EarChordPlaying = EarChordPlayer()
    ) {
        self.store = store
        self.intervalPlayer = intervalPlayer
        self.chordPlayer = chordPlayer
    }

    var recentAccuracyText: String {
        guard let accuracy = AdaptiveEarTrainingEngine.recentAccuracy(records: records) else {
            return "近20题 --"
        }
        return "近20题 \(Int((accuracy * 100).rounded()))%"
    }

    var todayCountText: String {
        let calendar = Calendar(identifier: .gregorian)
        let count = records.filter { calendar.isDateInToday($0.answeredAt) }.count
        return "今日 \(count) 题"
    }

    var recommendationLine: String {
        AdaptiveEarTrainingEngine.recommendationLine(state: state, records: records)
    }

    var mistakeCountText: String {
        let count = records.filter { !$0.wasCorrect }.count
        return count == 0 ? "暂无错题" : "\(count) 道错题"
    }

    func bootstrap() async {
        loading = true
        loadError = nil
        state = await store.loadState()
        records = await store.loadAttempts()
        loading = false
        if currentQuestion == nil {
            await nextQuestion()
        }
    }

    func playCurrent() async {
        playTask?.cancel()
        playTask = nil
        // 不调 cancelPlayback，让旧音频自然衰减与新音叠加，
        // 消除快速重播的卡顿感。离开页面时 onDisappear 会走 cancelPlayback 全停。
        guard let question = currentQuestion else { return }
        isPlaying = true
        let work = Task { @MainActor in
            do {
                switch question {
                case let .interval(q, _, _):
                    try await intervalPlayer.playAscendingPair(lowMidi: q.lowMidi, highMidi: q.highMidi)
                case let .chord(q, _, _):
                    if let frets = q.playbackFretsSixToOne, frets.count == 6 {
                        try await chordPlayer.playChordFromFretsSixToOne(frets)
                    } else {
                        try await chordPlayer.playChordMidis(EarPlaybackMidi.forSingleChord(q))
                    }
                case let .progression(q, _, _):
                    if let seq = EarProgressionPlayback.playbackFretsSequence(for: q), !seq.isEmpty {
                        try await chordPlayer.playProgressionFromFretsSixToOne(seq)
                    } else {
                        try await chordPlayer.playChordSequence(EarPlaybackMidi.forProgression(q))
                    }
                case let .singleNote(q, _, _):
                    try await intervalPlayer.playAscendingPair(lowMidi: 69, highMidi: q.midi)
                case let .rhythm(q, _, _, _):
                    rhythmPlayer.play(pattern: q)
                }
                playError = nil
            } catch is CancellationError {
                // 被替换（用户点了重播）时静默退出，
                // 不调 cancelPlayback，让旧音自然衰减与新音叠加。
            } catch {
                playError = "播放失败：\(error.localizedDescription)"
            }
            isPlaying = false
        }
        playTask = work
        await work.value
    }

    func cancelPlayback() {
        playTask?.cancel()
        playTask = nil
        intervalPlayer.cancelIntervalPlayback()
        chordPlayer.cancelChordPlayback()
        rhythmPlayer.stop()
        isPlaying = false
        isPreviewingOption = false
    }

    func playPreviewNote(midi: Int) async {
        playTask?.cancel()
        playTask = nil
        // 不调 cancelIntervalPlayback()：让前一个音自然衰减而非 abrupt stop，消除连续点击的停顿感
        let work = Task { @MainActor in
            do {
                try await intervalPlayer.playQuickPreview(midi: midi)
                playError = nil
            } catch is CancellationError {
                cancelPlayback()
            } catch {
                playError = "播放失败：\(error.localizedDescription)"
            }
        }
        playTask = work
        await work.value
    }

    /// 播放标准音 A4（440Hz），供单音题提示用。
    func playReferenceA4() async {
        playTask?.cancel()
        playTask = nil
        intervalPlayer.cancelIntervalPlayback()
        let work = Task { @MainActor in
            do {
                try await intervalPlayer.playSinglePreview(midi: 69)
                playError = nil
            } catch is CancellationError {
                cancelPlayback()
            } catch {
                playError = "播放失败：\(error.localizedDescription)"
            }
        }
        playTask = work
        await work.value
    }

    /// 试听和弦——优先使用实际吉他把位（与「播放题目」同音质），回退到 MIDI 合成。
    func playChordForLabel(_ label: String, root: String? = nil) async {
        playTask?.cancel()
        playTask = nil
        intervalPlayer.cancelIntervalPlayback()
        chordPlayer.cancelChordPlayback()
        isPreviewingOption = true
        let playbackLabel = Self.playbackChordLabel(label, root: root)
        let work = Task { @MainActor in
            defer { self.isPreviewingOption = false }
            do {
                if let payload = OfflineChordBuilder.buildPayload(displaySymbol: playbackLabel),
                   let frets = payload.voicings.first?.explain.frets,
                   frets.count == 6 {
                    try await chordPlayer.playChordFromFretsSixToOne(frets)
                } else {
                    let midis = Self.midiNotesForChordLabel(label, defaultRoot: root)
                    guard !midis.isEmpty else {
                        playError = "无法解析和弦：\(label)"
                        return
                    }
                    try await chordPlayer.playChordMidis(midis)
                }
                playError = nil
            } catch is CancellationError {
                cancelPlayback()
            } catch {
                playError = "播放失败：\(error.localizedDescription)"
            }
        }
        playTask = work
        await work.value
    }

    nonisolated private static func playbackChordLabel(_ label: String, root: String?) -> String {
        let raw = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quality = EarChordQuality(optionLabel: raw) else { return raw }
        let playbackRoot = (root?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? root! : "C"
        let qualityId: String
        switch quality {
        case .major: qualityId = ""
        case .minor: qualityId = "m"
        case .dominant7: qualityId = "7"
        case .major7: qualityId = "maj7"
        case .minor7: qualityId = "m7"
        }
        let symbol = ChordSymbolBuilder.build(root: playbackRoot, qualityId: qualityId, bassId: "")
        return symbol.isEmpty ? raw : symbol
    }

    nonisolated private static func midiNotesForChordLabel(_ label: String, defaultRoot: String? = nil) -> [Int] {
        let raw = label.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return [] }
        // 先尝试把 label 当作中文性质名解析（如"大三"、"小三"）
        if let quality = EarChordQuality(optionLabel: label), let root = defaultRoot {
            let baseMidi = Self.noteNameToMidi(root)
            guard baseMidi >= 0 else { return [] }
            let intervals: [Int]
            switch quality {
            case .minor: intervals = [0, 3, 7]
            case .dominant7: intervals = [0, 4, 7, 10]
            case .major7: intervals = [0, 4, 7, 11]
            case .minor7: intervals = [0, 3, 7, 10]
            default: intervals = [0, 4, 7]
            }
            return intervals.map { baseMidi + $0 }
        }
        // 否则当作和弦符号解析（如 "C"、"Cm"、"C7"）
        let (root, quality) = Self.parseChordLabel(raw)
        let baseMidi = Self.noteNameToMidi(root.isEmpty ? (defaultRoot ?? "C") : root)
        guard baseMidi >= 0 else { return [] }
        let intervals: [Int]
        switch quality {
        case "m", "min", "minor":
            intervals = [0, 3, 7]
        case "7", "dom7", "dominant7":
            intervals = [0, 4, 7, 10]
        case "m7", "min7", "minor7":
            intervals = [0, 3, 7, 10]
        case "maj7", "Δ":
            intervals = [0, 4, 7, 11]
        case "dim", "°":
            intervals = [0, 3, 6]
        case "dim7", "°7":
            intervals = [0, 3, 6, 9]
        case "sus4":
            intervals = [0, 5, 7]
        default:
            intervals = [0, 4, 7]
        }
        return intervals.map { baseMidi + $0 }
    }

    nonisolated private static func parseChordLabel(_ label: String) -> (root: String, quality: String) {
        let s = label.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return ("C", "") }
        let doubleRoot = String(s.prefix(2))
        let sharpFlatRoots = ["C#", "Db", "D#", "Eb", "F#", "Gb", "G#", "Ab", "A#", "Bb"]
        if sharpFlatRoots.contains(doubleRoot) {
            let rest = String(s.dropFirst(2))
            return (doubleRoot, rest)
        }
        let singleRoot = String(s.prefix(1))
        let roots = ["C", "D", "E", "F", "G", "A", "B"]
        if roots.contains(singleRoot) {
            let rest = String(s.dropFirst())
            return (singleRoot, rest)
        }
        return ("C", "")
    }

    nonisolated private static func noteNameToMidi(_ name: String) -> Int {
        let normalized = name.uppercased().trimmingCharacters(in: .whitespaces)
        let map: [String: Int] = [
            "C": 0, "C#": 1, "DB": 1,
            "D": 2, "D#": 3, "EB": 3,
            "E": 4,
            "F": 5, "F#": 6, "GB": 6,
            "G": 7, "G#": 8, "AB": 8,
            "A": 9, "A#": 10, "BB": 10,
            "B": 11
        ]
        guard let pc = map[normalized] else { return -1 }
        return 60 + pc
    }

    func submit(_ choice: AdaptiveEarChoice) {
        guard !hasRevealed, let question = currentQuestion else { return }
        selectedChoiceID = choice.id
        let correct = choice.id == question.correctChoiceId
        saveAnswer(question: question, selectedAnswer: choice.label, wasCorrect: correct, skipped: false)
        feedback = AdaptiveEarFeedback(wasCorrect: correct, title: correct ? "答对了" : "再听一遍这个差异")
        hasRevealed = true
        startPrefetchingNextQuestion()
    }

    func markTooHard() {
        guard !hasRevealed, let question = currentQuestion else { return }
        saveAnswer(question: question, selectedAnswer: nil, wasCorrect: false, skipped: true)
        feedback = AdaptiveEarFeedback(wasCorrect: false, title: "已标记太难")
        hasRevealed = true
        startPrefetchingNextQuestion()
    }

    func skipQuestion() {
        guard !hasRevealed else { return }
        Task { await nextQuestion() }
    }

    func nextQuestion() async {
        cancelPlayback()
        isPreparingQuestion = true
        let question: AdaptiveEarQuestion
        if let prefetchTask {
            question = await prefetchTask.value
            self.prefetchTask = nil
        } else {
            question = await Self.makeQuestion(request: makeNextQuestionRequest())
        }
        currentQuestion = question
        rememberPreviousMidi(from: question)
        selectedChoiceID = nil
        hasRevealed = false
        feedback = nil
        questionStartedAt = Date()
        questionToken = UUID()
        isPreparingQuestion = false
    }

    private func startPrefetchingNextQuestion() {
        prefetchTask?.cancel()
        let request = makeNextQuestionRequest()
        prefetchTask = Task.detached(priority: .utility) {
            await Self.makeQuestion(request: request)
        }
    }

    private func makeNextQuestionRequest() -> AdaptiveEarQuestionRequest {
        let kind = AdaptiveEarTrainingEngine.selectNextKind(
            state: state,
            records: records,
            roll: Double.random(in: 0 ..< 1, using: &rng)
        )
        let difficulty = AdaptiveEarTrainingEngine.difficulty(for: kind, state: state)
        let score = AdaptiveEarTrainingEngine.difficultyScore(kind: kind, difficulty: difficulty)
        return AdaptiveEarQuestionRequest(
            kind: kind,
            difficulty: difficulty,
            score: score,
            previousIntervalLowMidi: previousIntervalLowMidi,
            previousSingleNoteMidi: previousSingleNoteMidi
        )
    }

    nonisolated private static func makeQuestion(request: AdaptiveEarQuestionRequest) async -> AdaptiveEarQuestion {
        var rng = SystemRandomNumberGenerator()
        switch request.kind {
        case .interval:
            let q = IntervalQuestionGenerator.next(
                difficulty: request.difficulty.intervalDifficulty,
                antiAbsolutePitch: antiAbsolutePitch(
                    for: request.difficulty.intervalDifficulty,
                    previousIntervalLowMidi: request.previousIntervalLowMidi
                ),
                using: &rng
            )
            return .interval(q, difficulty: request.difficulty, difficultyScore: request.score)
        case .chord:
            let q = EarChordMcqGenerator.makeQuestion(
                difficulty: request.difficulty.chordDifficulty,
                avoid: nil,
                using: &rng
            )
            return .chord(q, difficulty: request.difficulty, difficultyScore: request.score)
        case .progression:
            let q = EarProgressionProceduralGenerator.makeQuestion(
                difficulty: request.difficulty.progressionDifficulty,
                using: &rng
            )
            return .progression(q, difficulty: request.difficulty, difficultyScore: request.score)
        case .singleNote:
            let q = Self.makeSingleNoteQuestion(
                difficulty: request.difficulty,
                avoidMidi: request.previousSingleNoteMidi,
                using: &rng
            )
            return .singleNote(q, difficulty: request.difficulty, difficultyScore: request.score)
        case .rhythm:
            let result = RhythmQuestionGenerator.makeQuestion(
                difficulty: request.difficulty.rhythmDifficulty,
                using: &rng
            )
            return .rhythm(result.correct, choices: result.choices,
                           difficulty: request.difficulty, difficultyScore: request.score)
        }
    }

    /// 生成单音测试题。
    nonisolated private static func makeSingleNoteQuestion(
        difficulty: AdaptiveEarDifficulty,
        avoidMidi: Int?,
        using rng: inout some RandomNumberGenerator
    ) -> SingleNoteQuestion {
        // 根据难度确定可用音，全部显示含八度的音名（如 C4、F#4）
        let pool: [(midi: Int, label: String)]
        switch difficulty {
        case .beginner:
            let naturals = [60, 62, 64, 65, 67, 69, 71, 72]
            pool = naturals.map { ($0, Self.noteLabelWithOctave(midi: $0)) }
        case .intermediate:
            pool = (60...71).map { ($0, Self.noteLabelWithOctave(midi: $0)) }
        case .advanced:
            pool = (52...76).map { ($0, Self.noteLabelWithOctave(midi: $0)) }
        }

        // 选目标音（避开上一题的音）
        var candidates = pool
        if let avoid = avoidMidi {
            candidates = candidates.filter { $0.midi != avoid }
        }
        if candidates.isEmpty {
            candidates = pool
        }
        let target = candidates.randomElement(using: &rng) ?? pool[0]

        // 生成 4 个选项（含正确答案）
        var choicePool = pool.filter { $0.midi != target.midi }
        if choicePool.count > 3 {
            choicePool.shuffle(using: &rng)
        }
        let wrongs = Array(choicePool.prefix(3))
        var choices = wrongs.map { SingleNoteQuestion.SingleNoteChoice(id: "\($0.midi)", label: $0.label) }
        choices.append(SingleNoteQuestion.SingleNoteChoice(id: "\(target.midi)", label: target.label))
        choices.shuffle(using: &rng)

        return SingleNoteQuestion(midi: target.midi, noteLabel: target.label, choices: choices)
    }

    nonisolated private static func noteLabelWithOctave(midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pc = midi % 12
        let octave = (midi / 12) - 1
        return "\(names[pc])\(octave)"
    }

    private func rememberPreviousMidi(from question: AdaptiveEarQuestion) {
        switch question {
        case let .interval(q, _, _):
            previousIntervalLowMidi = q.lowMidi
            previousSingleNoteMidi = nil
        case let .singleNote(q, _, _):
            previousSingleNoteMidi = q.midi
            previousIntervalLowMidi = nil
        default:
            previousIntervalLowMidi = nil
            previousSingleNoteMidi = nil
        }
    }

    private func saveAnswer(
        question: AdaptiveEarQuestion,
        selectedAnswer: String?,
        wasCorrect: Bool,
        skipped: Bool
    ) {
        let beforeState = state
        let beforeKind = beforeState.rating(for: question.kind)
        let nextState = AdaptiveEarTrainingEngine.stateAfterAnswer(
            state: beforeState,
            kind: question.kind,
            difficultyScore: question.difficultyScore,
            wasCorrect: wasCorrect
        )
        state = nextState
        let record = AdaptiveEarAttemptRecord(
            id: UUID().uuidString,
            questionKindRaw: question.kind.rawValue,
            questionId: question.stableQuestionId,
            difficultyRaw: question.difficulty.rawValue,
            difficultyScore: question.difficultyScore,
            correctAnswer: question.correctAnswerText,
            selectedAnswer: selectedAnswer,
            wasCorrect: wasCorrect,
            responseTimeMs: max(0, Int(Date().timeIntervalSince(questionStartedAt) * 1000)),
            answeredAt: Date(),
            ratingBeforeOverall: beforeState.overallEarRating,
            ratingAfterOverall: nextState.overallEarRating,
            ratingBeforeKind: beforeKind,
            ratingAfterKind: nextState.rating(for: question.kind),
            skipped: skipped
        )
        records.append(record)
        Task {
            await store.saveState(nextState)
            await store.appendAttempt(record)
        }
    }

    nonisolated private static func antiAbsolutePitch(
        for difficulty: IntervalEarDifficulty,
        previousIntervalLowMidi: Int?
    ) -> IntervalAntiAbsolutePitch? {
        guard let previousIntervalLowMidi else { return nil }
        switch difficulty {
        case .初级:
            return nil
        case .中级:
            return IntervalAntiAbsolutePitch(previousLowerMidi: previousIntervalLowMidi, minSemitoneDelta: 3)
        case .高级:
            return IntervalAntiAbsolutePitch(previousLowerMidi: previousIntervalLowMidi, minSemitoneDelta: 5)
        }
    }
}

private struct AdaptiveEarQuestionRequest: Sendable {
    let kind: AdaptiveEarQuestionKind
    let difficulty: AdaptiveEarDifficulty
    let score: Int
    let previousIntervalLowMidi: Int?
    let previousSingleNoteMidi: Int?

    init(
        kind: AdaptiveEarQuestionKind,
        difficulty: AdaptiveEarDifficulty,
        score: Int,
        previousIntervalLowMidi: Int? = nil,
        previousSingleNoteMidi: Int? = nil
    ) {
        self.kind = kind
        self.difficulty = difficulty
        self.score = score
        self.previousIntervalLowMidi = previousIntervalLowMidi
        self.previousSingleNoteMidi = previousSingleNoteMidi
    }
}

private struct CombinedStatsView: View {
    let state: AdaptiveEarAbilityState
    let records: [AdaptiveEarAttemptRecord]
    let sessions: [PracticeSession]

    var body: some View {
        List {
            Section("听力能力") {
                statsRow("总听力值", "\(state.roundedOverallRating) · \(state.levelTitle)")
                statsRow("音程", "\(Int(state.intervalRating.rounded()))")
                statsRow("和弦", "\(Int(state.chordRating.rounded()))")
                statsRow("和弦进行", "\(Int(state.progressionRating.rounded()))")
                statsRow("单音", "\(Int(state.singleNoteRating.rounded()))")
                statsRow("节奏", "\(Int(state.rhythmRating.rounded()))")
            }
            Section("近期表现") {
                statsRow("总题数", "\(records.count)")
                statsRow("近 20 题正确率", recentAccuracyText)
                statsRow("连续答对", "\(state.consecutiveCorrect)")
                statsRow("连续答错", "\(state.consecutiveWrong)")
                statsRow("今日题数", "\(todayCount)")
            }
            Section("最近 7 天练习") {
                let s = computeRollingSevenDayPracticeStats(sessions, now: Date())
                statsRow("练习次数", "\(s.sessionCount) 次")
                statsRow("总时长", "\(s.totalDurationSeconds / 60) 分钟")
            }
        }
        .navigationTitle("训练统计")
    }

    private var recentAccuracyText: String {
        guard let accuracy = AdaptiveEarTrainingEngine.recentAccuracy(records: records) else { return "--" }
        return "\(Int((accuracy * 100).rounded()))%"
    }

    private var todayCount: Int {
        let calendar = Calendar(identifier: .gregorian)
        return records.filter { calendar.isDateInToday($0.answeredAt) }.count
    }

    private func statsRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

private extension View {
    func practiceAdaptiveScrollBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(SwiftAppTheme.bg.ignoresSafeArea())
            .tint(SwiftAppTheme.brand)
    }
}
