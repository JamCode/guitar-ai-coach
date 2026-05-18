import SwiftUI

import Foundation

@MainActor
final class FocusedEarTrainingViewModel: ObservableObject {
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
    @Published private(set) var isPlaying = false
    @Published private(set) var isPreviewingOption = false
    @Published private(set) var playError: String?

    let fixedKind: AdaptiveEarQuestionKind

    private let store: AdaptiveEarTrainingStoring
    private let intervalPlayer: IntervalTonePlaying
    private let chordPlayer: EarChordPlaying
    private let rhythmPlayer = RhythmAudioPlayer()
    private var rng = SystemRandomNumberGenerator()
    private var questionStartedAt = Date()
    private var previousIntervalLowMidi: Int?
    private var previousSingleNoteMidi: Int?
    private var playTask: Task<Void, Never>?

    init(
        kind: AdaptiveEarQuestionKind,
        store: AdaptiveEarTrainingStoring = UserDefaultsAdaptiveEarTrainingStore(),
        intervalPlayer: IntervalTonePlaying = IntervalTonePlayer(),
        chordPlayer: EarChordPlaying = EarChordPlayer()
    ) {
        self.fixedKind = kind
        self.store = store
        self.intervalPlayer = intervalPlayer
        self.chordPlayer = chordPlayer
    }

    var kindAccuracyText: String {
        guard let accuracy = AdaptiveEarTrainingEngine.recentAccuracy(for: fixedKind, records: records, limit: 12) else {
            return "近12题 --"
        }
        return "近12题 \(Int((accuracy * 100).rounded()))%"
    }

    var ratingDisplay: Int {
        Int(state.rating(for: fixedKind).rounded())
    }

    var kindTitle: String { fixedKind.title }
    var kindShortTitle: String { fixedKind.shortTitle }

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

    private static func playbackChordLabel(_ label: String, root: String?) -> String {
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

    private static func midiNotesForChordLabel(_ label: String, defaultRoot: String? = nil) -> [Int] {
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
        let (parsedRoot, quality) = Self.parseChordLabel(raw)
        let finalRoot = parsedRoot.isEmpty ? (defaultRoot ?? "C") : parsedRoot
        let baseMidi = Self.noteNameToMidi(finalRoot)
        guard baseMidi >= 0 else { return [] }
        let intervals: [Int]
        let normalizedQuality = Self.normalizeChordQuality(quality)
        switch normalizedQuality {
        case "m", "min", "minor": intervals = [0, 3, 7]
        case "7", "dom7", "dominant7": intervals = [0, 4, 7, 10]
        case "m7", "min7", "minor7": intervals = [0, 3, 7, 10]
        case "maj7", "Δ": intervals = [0, 4, 7, 11]
        case "dim", "°": intervals = [0, 3, 6]
        case "dim7", "°7": intervals = [0, 3, 6, 9]
        case "sus4": intervals = [0, 5, 7]
        default: intervals = [0, 4, 7]
        }
        return intervals.map { baseMidi + $0 }
    }

    private static func parseChordLabel(_ label: String) -> (root: String, quality: String) {
        let s = label.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return ("", "") }
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
        return ("", s)
    }



    private static func normalizeChordQuality(_ raw: String) -> String {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch q {
        case "大三", "major", "maj": return ""
        case "小三", "minor", "min", "m": return "m"
        case "属七", "7", "dom7", "dominant7": return "7"
        case "大七", "maj7", "major7", "delta", "△7": return "maj7"
        case "小七", "m7", "min7", "minor7": return "m7"
        default: return q
        }
    }

    private static func noteNameToMidi(_ name: String) -> Int {
        let normalized = name.uppercased().trimmingCharacters(in: .whitespaces)
        let map: [String: Int] = [
            "C":0,"C#":1,"DB":1,"D":2,"D#":3,"EB":3,"E":4,
            "F":5,"F#":6,"GB":6,"G":7,"G#":8,"AB":8,"A":9,"A#":10,"BB":10,"B":11
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
    }

    func nextQuestion() async {
        cancelPlayback()
        isPreparingQuestion = true
        let request = makeNextQuestionRequest()
        let question = await Self.makeQuestion(request: request)
        currentQuestion = question
        rememberPreviousMidi(from: question)
        selectedChoiceID = nil
        hasRevealed = false
        feedback = nil
        questionStartedAt = Date()
        questionToken = UUID()
        isPreparingQuestion = false
    }

    private func makeNextQuestionRequest() -> AdaptiveEarQuestionRequest {
        let difficulty = AdaptiveEarTrainingEngine.difficulty(for: fixedKind, state: state)
        let score = AdaptiveEarTrainingEngine.difficultyScore(kind: fixedKind, difficulty: difficulty)
        return AdaptiveEarQuestionRequest(
            kind: fixedKind,
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
            let q = makeSingleNoteQuestion(
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

    nonisolated private static func antiAbsolutePitch(
        for difficulty: IntervalEarDifficulty,
        previousIntervalLowMidi: Int?
    ) -> IntervalAntiAbsolutePitch? {
        guard let previousIntervalLowMidi else { return nil }
        switch difficulty {
        case .初级: return nil
        case .中级: return IntervalAntiAbsolutePitch(previousLowerMidi: previousIntervalLowMidi, minSemitoneDelta: 3)
        case .高级: return IntervalAntiAbsolutePitch(previousLowerMidi: previousIntervalLowMidi, minSemitoneDelta: 5)
        }
    }

    nonisolated private static func makeSingleNoteQuestion(
        difficulty: AdaptiveEarDifficulty,
        avoidMidi: Int?,
        using rng: inout some RandomNumberGenerator
    ) -> SingleNoteQuestion {
        let pool: [(midi: Int, label: String)]
        switch difficulty {
        case .beginner:
            let naturals = [60,62,64,65,67,69,71,72]
            pool = naturals.map { ($0, Self.noteLabelWithOctave(midi: $0)) }
        case .intermediate:
            pool = (60...71).map { ($0, Self.noteLabelWithOctave(midi: $0)) }
        case .advanced:
            pool = (52...76).map { ($0, Self.noteLabelWithOctave(midi: $0)) }
        }
        var candidates = pool
        if let avoid = avoidMidi {
            candidates = candidates.filter { $0.midi != avoid }
        }
        if candidates.isEmpty { candidates = pool }
        let target = candidates.randomElement(using: &rng) ?? pool[0]
        var choicePool = pool.filter { $0.midi != target.midi }
        if choicePool.count > 3 { choicePool.shuffle(using: &rng) }
        let wrongs = Array(choicePool.prefix(3))
        var choices = wrongs.map { SingleNoteQuestion.SingleNoteChoice(id: "\($0.midi)", label: $0.label) }
        choices.append(SingleNoteQuestion.SingleNoteChoice(id: "\(target.midi)", label: target.label))
        choices.shuffle(using: &rng)
        return SingleNoteQuestion(midi: target.midi, noteLabel: target.label, choices: choices)
    }

    nonisolated private static func noteLabelWithOctave(midi: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
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
        let beforeKind = beforeState.rating(for: fixedKind)
        let nextState = AdaptiveEarTrainingEngine.stateAfterAnswer(
            state: beforeState,
            kind: fixedKind,
            difficultyScore: question.difficultyScore,
            wasCorrect: wasCorrect
        )
        state = nextState
        let record = AdaptiveEarAttemptRecord(
            id: UUID().uuidString,
            questionKindRaw: fixedKind.rawValue,
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
            ratingAfterKind: nextState.rating(for: fixedKind),
            skipped: skipped
        )
        records.append(record)
        Task {
            await store.saveState(nextState)
            await store.appendAttempt(record)
        }
    }
}

// MARK: - Question request (local copy of private struct from AdaptiveEarTrainingView)
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
