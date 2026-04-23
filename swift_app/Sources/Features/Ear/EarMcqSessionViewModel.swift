import Foundation

@MainActor
public final class EarMcqSessionViewModel: ObservableObject {
    @Published public private(set) var loading = true
    @Published public private(set) var loadError: String?
    @Published public private(set) var session: [EarBankItem] = []
    @Published public private(set) var pageIndex = 0
    @Published public private(set) var correctCount = 0
    @Published public private(set) var answeredCount = 0
    @Published public private(set) var question: EarBankItem?
    @Published public var selectedChoiceIndex: Int?
    @Published public private(set) var revealed = false
    @Published public private(set) var finished = false
    @Published public private(set) var playError: String?
    /// 整段和弦（或进行）播放结束前为 `true`，用于禁用「播放」。
    @Published public private(set) var isPlaybackInProgress = false
    /// 当前题是否已至少成功完整试听一次；未满足前不可选答案。
    @Published public private(set) var hasCompletedInitialAudition = false

    public let title: String
    public let bank: String
    /// `nil`（默认）为不限题量，可持续「下一题」；非 `nil` 为本轮题量上限（末题后「查看结果」）。
    /// `bank == "B"` 且有上限时预生成 `maxQuestions` 道程序化题；无上限时每题现算。
    public let maxQuestions: Int?

    /// 仅 `bank == "A"`（和弦听辨）时使用：程序化出题难度；未揭示前可 `setChordDifficultyIfChanged`。
    @Published public private(set) var chordDifficulty: EarChordMcqDifficulty
    /// 仅 `bank == "B"`（和弦进行）时使用：程序化出题难度；未揭示前可 `setProgressionDifficultyIfChanged`。
    @Published public private(set) var progressionDifficulty: EarProgressionMcqDifficulty

    private let loader: EarSeedLoader
    private let player: EarChordPlaying
    private let historyStore: any EarMcqHistoryStoring
    private var chordRng = SystemRandomNumberGenerator()
    private var playTask: Task<Void, Never>?
    /// 与 `playCurrent` / `cancelPlayback` 配合，避免旧任务的 `defer` 误清 `isPlaybackInProgress`。
    private var playGeneration = 0
    /// 非 Bank B 时仍用于 `ear_seed` 抽题；Bank B 程序化后不再使用。
    private var bankBSourcePool: [EarBankItem] = []
    private var bankBDealingQueue: [EarBankItem] = []
    /// Bank B 无限模式：尽量避免与上一题完全相同的「调 + 进行 + 选项集合」。
    private var lastBankBSignature: String?

    public init(
        title: String,
        bank: String,
        maxQuestions: Int? = nil,
        chordDifficulty: EarChordMcqDifficulty = .初级,
        progressionDifficulty: EarProgressionMcqDifficulty = .初级,
        loader: EarSeedLoader = .shared,
        player: EarChordPlaying = EarChordPlayer(),
        historyStore: any EarMcqHistoryStoring = EarMcqFileHistoryStore.shared
    ) {
        self.title = title
        self.bank = bank
        self.maxQuestions = maxQuestions.map { max(1, $0) }
        self.chordDifficulty = chordDifficulty
        self.progressionDifficulty = progressionDifficulty
        self.loader = loader
        self.player = player
        self.historyStore = historyStore
    }

    /// 离开页面或切换难度时打断试听。
    public func cancelPlayback() {
        playGeneration += 1
        playTask?.cancel()
        playTask = nil
        isPlaybackInProgress = false
        player.cancelChordPlayback()
    }

    /// `bank == "A"` 且本题未揭示时切换难度并重出一题（有题量上限时同时重生成剩余题）。
    public func setChordDifficultyIfChanged(_ newValue: EarChordMcqDifficulty) {
        guard bank == "A" else { return }
        guard newValue != chordDifficulty else { return }
        guard !revealed else { return }
        cancelPlayback()
        chordDifficulty = newValue
        selectedChoiceIndex = nil
        if maxQuestions == nil {
            let avoid = Self.chordAvoidPair(from: question)
            installQuestion(EarChordMcqGenerator.makeQuestion(difficulty: chordDifficulty, avoid: avoid, using: &chordRng))
        } else if !session.isEmpty, pageIndex < session.count {
            let remaining = session.count - pageIndex
            let tail = EarChordMcqGenerator.buildSession(count: remaining, difficulty: chordDifficulty, using: &chordRng)
            session.replaceSubrange(pageIndex..., with: tail)
            installQuestion(session[pageIndex])
        }
    }

    /// `bank == "B"` 且本题未揭示时切换难度并重出一题（有题量上限时同时重生成剩余题）。
    public func setProgressionDifficultyIfChanged(_ newValue: EarProgressionMcqDifficulty) {
        guard bank == "B" else { return }
        guard newValue != progressionDifficulty else { return }
        guard !revealed else { return }
        cancelPlayback()
        progressionDifficulty = newValue
        selectedChoiceIndex = nil
        lastBankBSignature = nil
        if maxQuestions == nil {
            installQuestion(
                Self.makeDistinctBankBQuestion(
                    difficulty: progressionDifficulty,
                    avoidSignatures: [],
                    using: &chordRng
                )
            )
            if let q = question {
                lastBankBSignature = Self.bankBSignature(q)
            }
        } else if !session.isEmpty, pageIndex < session.count {
            let remaining = session.count - pageIndex
            var built: [EarBankItem] = []
            var seen = Set<String>()
            built.reserveCapacity(remaining)
            while built.count < remaining {
                let q = Self.makeDistinctBankBQuestion(
                    difficulty: progressionDifficulty,
                    avoidSignatures: seen,
                    using: &chordRng
                )
                let sig = Self.bankBSignature(q)
                seen.insert(sig)
                built.append(q)
            }
            session.replaceSubrange(pageIndex..., with: built)
            installQuestion(session[pageIndex])
            lastBankBSignature = Self.bankBSignature(session[pageIndex])
        }
    }

    public var hasSessionCap: Bool { maxQuestions != nil }

    /// 有上限时，当前题是否为最后一题（揭示后按钮文案为「查看结果」）。
    public var isOnLastCappedQuestion: Bool {
        guard hasSessionCap else { return false }
        guard !session.isEmpty else { return false }
        return pageIndex >= session.count - 1
    }

    /// 与音程练耳一致：不限题量会话内持续累计正确率（本题判分前 `answeredCount` 不含当前题）。
    public var sessionStatsLine: String {
        if answeredCount == 0 {
            return "作答后在此累计正确率"
        }
        let pct = (Double(correctCount) / Double(answeredCount) * 100).rounded()
        return "已答 \(answeredCount) 题 · 答对 \(correctCount) · 正确率 \(Int(pct))%"
    }

    public func bootstrap() async {
        loading = true
        loadError = nil
        if bank == "A" {
            bankBSourcePool = []
            bankBDealingQueue = []
            if let cap = maxQuestions {
                session = EarChordMcqGenerator.buildSession(
                    count: cap,
                    difficulty: chordDifficulty,
                    using: &chordRng
                )
                installQuestion(session.first)
            } else {
                session = []
                installQuestion(EarChordMcqGenerator.makeQuestion(
                    difficulty: chordDifficulty,
                    avoid: nil,
                    using: &chordRng
                ))
            }
            pageIndex = 0
            correctCount = 0
            answeredCount = 0
            selectedChoiceIndex = nil
            revealed = false
            finished = false
            loading = false
            return
        }
        if bank == "B" {
            bankBSourcePool = []
            bankBDealingQueue = []
            lastBankBSignature = nil
            if let cap = maxQuestions {
                var built: [EarBankItem] = []
                var seen = Set<String>()
                built.reserveCapacity(cap)
                while built.count < cap {
                    let q = Self.makeDistinctBankBQuestion(
                        difficulty: progressionDifficulty,
                        avoidSignatures: seen,
                        using: &chordRng
                    )
                    let sig = Self.bankBSignature(q)
                    seen.insert(sig)
                    built.append(q)
                }
                session = built
                installQuestion(session.first)
            } else {
                session = []
                let q = Self.makeDistinctBankBQuestion(
                    difficulty: progressionDifficulty,
                    avoidSignatures: lastBankBSignature.map { Set([$0]) } ?? [],
                    using: &chordRng
                )
                installQuestion(q)
                lastBankBSignature = Self.bankBSignature(q)
            }
            pageIndex = 0
            correctCount = 0
            answeredCount = 0
            selectedChoiceIndex = nil
            revealed = false
            finished = false
            loading = false
            return
        }
        do {
            let doc = try await loader.load()
            let pool = doc.bankA
            if pool.isEmpty {
                loadError = "题库为空（bank \(bank)）"
                loading = false
                return
            }
            bankBSourcePool = pool
            if maxQuestions == nil {
                session = []
                bankBDealingQueue = bankBSourcePool.shuffled()
                installQuestion(bankBDealingQueue.isEmpty ? nil : bankBDealingQueue.removeFirst())
            } else {
                bankBDealingQueue = []
                let cap = max(1, maxQuestions ?? 10)
                session = Array(pool.shuffled().prefix(min(cap, pool.count)))
                installQuestion(session.first)
            }
            pageIndex = 0
            correctCount = 0
            answeredCount = 0
            selectedChoiceIndex = nil
            revealed = false
            finished = false
            loading = false
        } catch {
            loadError = "\(error.localizedDescription)"
            loading = false
        }
    }

    public func playCurrent() {
        playTask?.cancel()
        playTask = nil
        isPlaybackInProgress = false
        playGeneration += 1
        let gen = playGeneration
        let work = Task { @MainActor in
            guard let q = self.question else { return }
            self.isPlaybackInProgress = true
            defer {
                if gen == self.playGeneration {
                    self.isPlaybackInProgress = false
                }
            }
            do {
                if q.mode == "B" || q.questionType == "progression_recognition" {
                    if let seq = EarProgressionPlayback.playbackFretsSequence(for: q), !seq.isEmpty {
                        try await self.player.playProgressionFromFretsSixToOne(seq)
                    } else {
                        try await self.player.playChordSequence(EarPlaybackMidi.forProgression(q))
                    }
                } else if let frets = q.playbackFretsSixToOne, frets.count == 6 {
                    try await self.player.playChordFromFretsSixToOne(frets)
                } else {
                    try await self.player.playChordMidis(EarPlaybackMidi.forSingleChord(q))
                }
                self.playError = nil
                self.hasCompletedInitialAudition = true
            } catch is CancellationError {
                self.player.cancelChordPlayback()
            } catch {
                self.playError = "播放失败：\(error.localizedDescription)"
            }
        }
        playTask = work
    }

    public func playPreviewNote(midi: Int) async {
        do {
            try await player.playSinglePreview(midi: midi)
        } catch {}
    }

    public func selectChoice(_ index: Int) {
        guard hasCompletedInitialAudition else { return }
        guard !revealed, let q = question, q.options.indices.contains(index) else { return }
        selectedChoiceIndex = index
        submit()
    }

    public func submit() {
        guard let q = question, let idx = selectedChoiceIndex, !revealed else { return }
        let picked = q.options[idx]
        let ok = picked.key == q.correctOptionKey
        if ok {
            correctCount += 1
        }
        answeredCount += 1
        let record = EarMcqAttemptRecord(
            bank: bank,
            title: title,
            questionId: q.id,
            questionType: q.questionType,
            promptZh: q.promptZh,
            optionKeys: q.options.map(\.key),
            optionLabels: q.options.map(\.label),
            selectedIndex: idx,
            selectedKey: picked.key,
            correctOptionKey: q.correctOptionKey,
            wasCorrect: ok,
            pageIndex: pageIndex,
            chordDifficultyRaw: bank == "A" ? chordDifficulty.rawValue : nil
        )
        revealed = true
        let store = historyStore
        Task { await store.appendAttempt(record) }
    }

    public func nextOrFinish() {
        if bank == "A", maxQuestions == nil {
            let avoid = Self.chordAvoidPair(from: question)
            pageIndex += 1
            selectedChoiceIndex = nil
            revealed = false
            installQuestion(EarChordMcqGenerator.makeQuestion(
                difficulty: chordDifficulty,
                avoid: avoid,
                using: &chordRng
            ))
            return
        }
        if bank == "B", maxQuestions == nil {
            pageIndex += 1
            selectedChoiceIndex = nil
            revealed = false
            let avoid = lastBankBSignature.map { Set([$0]) } ?? []
            let q = Self.makeDistinctBankBQuestion(
                difficulty: progressionDifficulty,
                avoidSignatures: avoid,
                using: &chordRng
            )
            installQuestion(q)
            lastBankBSignature = Self.bankBSignature(q)
            return
        }
        if pageIndex >= session.count - 1 {
            finished = true
            return
        }
        pageIndex += 1
        installQuestion(session[pageIndex])
        selectedChoiceIndex = nil
        revealed = false
    }

    public var summaryText: String {
        let pct = answeredCount == 0 ? 0 : Int((Double(correctCount) / Double(answeredCount) * 100).rounded())
        if maxQuestions == nil {
            return "累计 \(answeredCount) 题 · 答对 \(correctCount) · 正确率 \(pct)%"
        }
        let total = max(session.count, 1)
        return "共 \(total) 题 · 答对 \(correctCount) / \(answeredCount) · 正确率 \(pct)%"
    }

    private static func chordAvoidPair(from item: EarBankItem?) -> (root: String, quality: EarChordQuality)? {
        guard let item,
              let r = item.root,
              let tok = item.targetQuality,
              let qual = EarChordQuality(targetQualityToken: tok)
        else { return nil }
        return (r, qual)
    }

    /// 调 + 罗马进行 + 四选项标签集合（排序后），用于 Bank B 去重。
    private static func bankBSignature(_ q: EarBankItem) -> String {
        let labels = q.options.map(\.label).sorted().joined(separator: "|")
        return "\(q.musicKey ?? "")|\(q.progressionRoman ?? "")|\(labels)"
    }

    private func installQuestion(_ newQuestion: EarBankItem?) {
        question = newQuestion
        hasCompletedInitialAudition = false
    }

    private static func makeDistinctBankBQuestion(
        difficulty: EarProgressionMcqDifficulty,
        avoidSignatures: Set<String>,
        using rng: inout some RandomNumberGenerator
    ) -> EarBankItem {
        for _ in 0 ..< 48 {
            let q = EarProgressionProceduralGenerator.makeQuestion(difficulty: difficulty, using: &rng)
            if !avoidSignatures.contains(bankBSignature(q)) {
                return q
            }
        }
        return EarProgressionProceduralGenerator.makeQuestion(difficulty: difficulty, using: &rng)
    }
}
