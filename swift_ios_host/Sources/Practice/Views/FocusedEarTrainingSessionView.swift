import SwiftUI


struct FocusedEarTrainingSessionView: View {
    let kind: AdaptiveEarQuestionKind

    @StateObject private var vm: FocusedEarTrainingViewModel
    @State private var showHintStrip = false

    init(kind: AdaptiveEarQuestionKind) {
        self.kind = kind
        _vm = StateObject(wrappedValue: FocusedEarTrainingViewModel(kind: kind))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ratingCard

                if vm.loading {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity)
                        .appCard()
                } else if let error = vm.loadError {
                    Text(error).foregroundStyle(.red).appCard()
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
        .appPageBackground()
        .task { await vm.bootstrap() }
        .task(id: vm.questionToken) {
            showHintStrip = false
        }
        .onDisappear { vm.cancelPlayback() }
    }

    private var ratingCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.kindTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(SwiftAppTheme.text)
                Text(vm.kindAccuracyText)
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(vm.ratingDisplay)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(SwiftAppTheme.brand)
                    .monospacedDigit()
                Text("听力值")
                    .font(.caption2)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .padding(14)
        .background(SwiftAppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(SwiftAppTheme.line, lineWidth: 1))
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
            }

            Text(question.prompt)
                .font(.title3.weight(.bold))
                .foregroundStyle(SwiftAppTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            playButton

            if case .interval = question {
                hintButton("提示", active: $showHintStrip) {
                    hintChromaticStrip(for: question)
                }
            }
            if case .chord = question {
                chordHintOptionsView(for: question)
            }
            if case .progression = question {
                hintButton("逐和弦试听", active: $showHintStrip) {
                    progressionHintOptionsView(for: question)
                }
            }
            if case .singleNote = question {
                hintButton("逐音试听", active: $showHintStrip) {
                    singleNoteHintView(for: question)
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

            if vm.hasRevealed {
                Button("下一题") {
                    Task { await vm.nextQuestion() }
                }
                .appPrimaryButton()
                .frame(maxWidth: .infinity)
            }
        }
        .appCard()
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
            Text("符号说明")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.muted)
            HStack(spacing: 14) {
                legendItem("X", "一拍")
                legendItem("XX", "两个八分")
                legendItem("X·", "附点")
                legendItem("·X", "弱起八分")
                legendItem(".", "休止")
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

    private func hintButton<Content: View>(
        _ title: String,
        active: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    active.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: active.wrappedValue ? "lightbulb.fill" : "lightbulb")
                        .font(.caption)
                    Text(active.wrappedValue ? "收起提示" : title)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(SwiftAppTheme.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(SwiftAppTheme.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            if active.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 8)
            }
        }
    }

    private func answerButton(choice: AdaptiveEarChoice, question: AdaptiveEarQuestion) -> some View {
        let state = answerVisualState(choice: choice, question: question)
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

    private func answerVisualState(choice: AdaptiveEarChoice, question: AdaptiveEarQuestion) -> AdaptiveAnswerVisualState {
        guard vm.hasRevealed else {
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
        if choice.id == vm.selectedChoiceID {
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

    private struct AdaptiveAnswerVisualState {
        let background: Color
        let border: Color
        let textColor: Color
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((feedback.wasCorrect ? Color.green : Color.red).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Hint strips

    @ViewBuilder
    private func hintChromaticStrip(for question: AdaptiveEarQuestion) -> some View {
        if case let .interval(q, _, _) = question {
            let strip = IntervalChromaticStrip.midisCoveringOctaveIncluding(lowMidi: q.lowMidi, highMidi: q.highMidi)
            chromaticPillGrid(strip: strip, highlightSet: [q.lowMidi, q.highMidi])
        }
    }

    @ViewBuilder
    private func chordHintOptionsView(for question: AdaptiveEarQuestion) -> some View {
        if case .chord = question {
            let symbols: [String] = question.choices.map { choice in
                guard let root = question.root, !root.isEmpty,
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
            ChordPreviewRow(symbols: symbols, isDisabled: vm.isPreviewingOption) { idx in
                let choice = question.choices[idx]
                Task { await vm.playChordForLabel(choice.label, root: question.root) }
            }
        }
    }

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
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(SwiftAppTheme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func singleNoteHintView(for question: AdaptiveEarQuestion) -> some View {
        let range = singleNoteHintMidiRange(for: question)
        let allNotes = Array(range)
        return VStack(alignment: .leading, spacing: 8) {
            Text("标准音 A4（可点击重复播放）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.brand)
            Button {
                Task { await vm.playReferenceA4() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2").font(.caption)
                    Text("播放 A4（440Hz）").font(.subheadline.weight(.medium))
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

            chromaticPillGrid(strip: allNotes, highlightSet: [])
        }
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

    @ViewBuilder
    private func chromaticPillGrid(strip: [Int], highlightSet: Set<Int>) -> some View {
        let firstRowCount = (strip.count + 1) / 2
        let row1 = Array(strip.prefix(firstRowCount))
        let row2 = Array(strip.suffix(strip.count - firstRowCount))
        VStack(alignment: .leading, spacing: 6) {
            chromaticPillRow(midis: row1, highlights: highlightSet)
            chromaticPillRow(midis: row2, highlights: highlightSet)
        }
    }

    private func chromaticPillRow(midis: [Int], highlights: Set<Int>) -> some View {
        HStack(spacing: 6) {
            ForEach(midis, id: \.self) { midi in
                let isHl = highlights.contains(midi)
                Button {
                    Task { await vm.playPreviewNote(midi: midi) }
                } label: {
                    Text(scientificPitchLabel(midi: midi))
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
                        .stroke(isHl ? SwiftAppTheme.brand : SwiftAppTheme.line, lineWidth: isHl ? 2 : 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scientificPitchLabel(midi: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let pc = midi % 12
        let octave = (midi / 12) - 1
        return "\(names[pc])\(octave)"
    }
}
