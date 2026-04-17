import Foundation

// MARK: - 和弦切换自动出题（完全可码规则）

public enum ChordSwitchGenerator {
    // MARK: 和弦池（与产品约定一致，可按曲库再扩展）

    /// 初级：开放和弦，无横按。
    public static let beginnerPool: [String] = ["C", "G", "Am", "Em", "D"]

    /// 中级：开放 + 小横按 + 简单七和弦。
    public static let intermediatePool: [String] = [
        "C", "G", "Am", "Em", "D", "F", "Bb", "Am7", "Cmaj7",
    ]

    /// 高级：大横按 / 封闭 / 高把位与 maj7、m7、add9 等（符号层，具体品位由指法图模块解释）。
    public static let advancedPool: [String] = [
        "F", "Bb", "Bm", "Cm7", "Fmaj7", "Gm7", "Dm7", "Ebmaj7",
        "Bbm7", "Cadd9", "Aadd9", "Gmaj7", "Am7", "C#m7",
    ]

    // MARK: 对外 API

    public static func recommendedExercises(
        using rng: inout some RandomNumberGenerator
    ) -> [ChordSwitchExercise] {
        [
            buildExercise(difficulty: .初级, using: &rng),
            buildExercise(difficulty: .中级, using: &rng),
            buildExercise(difficulty: .高级, using: &rng),
        ]
    }

    public static func buildExercise(
        difficulty: ChordSwitchDifficulty,
        using rng: inout some RandomNumberGenerator
    ) -> ChordSwitchExercise {
        switch difficulty {
        case .初级:
            return buildBeginner(using: &rng)
        case .中级:
            return buildIntermediate(using: &rng)
        case .高级:
            return buildAdvanced(using: &rng)
        }
    }

    // MARK: - 初级：开放和弦、2 个一组、每和弦 2 拍、BPM 50–70

    private static func buildBeginner(
        using rng: inout some RandomNumberGenerator
    ) -> ChordSwitchExercise {
        let pairCount = 5
        let segments = (0 ..< pairCount).map { _ in
            ChordSwitchSegment(chords: randomPair(from: beginnerPool, using: &rng))
        }
        let bpm = Int.random(in: 50 ... 70, using: &rng)
        let prompt = makePrompt(
            difficulty: .初级,
            segments: segments,
            bpmMin: bpm,
            bpmMax: bpm,
            beatsPerChord: 2,
            extraLines: [ChordSwitchPromptTemplate.ruleNoBarre, "每组 2 个和弦，顺序弹奏。"]
        )
        return ChordSwitchExercise(
            id: "CS-L1-\(UUID().uuidString.prefix(8))",
            difficulty: .初级,
            segments: segments,
            bpmMin: bpm,
            bpmMax: bpm,
            beatsPerChord: 2,
            promptZh: prompt,
            goalsZh: [
                "熟悉 C / G / Am / Em / D 之间的左手切换。",
                "保持每和弦 2 拍，换和弦落在拍点上前一拍预备。",
                "无横按，专注指尖触弦与消音。",
            ]
        )
    }

    // MARK: - 中级：开放+小横按+七和弦、每组 3～4 个、每和弦 1 拍、BPM 70–90

    private static func buildIntermediate(
        using rng: inout some RandomNumberGenerator
    ) -> ChordSwitchExercise {
        let groupCount = Int.random(in: 4 ... 6, using: &rng)
        let segments = (0 ..< groupCount).map { _ -> ChordSwitchSegment in
            let size = Int.random(in: 3 ... 4, using: &rng)
            return ChordSwitchSegment(
                chords: randomSequence(length: size, pool: intermediatePool, using: &rng)
            )
        }
        let bpmLo = Int.random(in: 70 ... 80, using: &rng)
        let bpmHi = Int.random(in: max(bpmLo, 81) ... 90, using: &rng)
        let prompt = makePrompt(
            difficulty: .中级,
            segments: segments,
            bpmMin: bpmLo,
            bpmMax: bpmHi,
            beatsPerChord: 1,
            extraLines: [
                ChordSwitchPromptTemplate.ruleMiniBarre,
                "每组 3～4 个和弦，每和弦 1 拍。",
                "含简单七和弦：Am7、Cmaj7 等。",
            ]
        )
        return ChordSwitchExercise(
            id: "CS-L2-\(UUID().uuidString.prefix(8))",
            difficulty: .中级,
            segments: segments,
            bpmMin: bpmLo,
            bpmMax: bpmHi,
            beatsPerChord: 1,
            promptZh: prompt,
            goalsZh: [
                "在开放与小横按之间建立稳定节拍切换。",
                "七和弦指型下压清晰，避免闷音。",
                "保持 1 拍一和弦的颗粒感。",
            ]
        )
    }

    // MARK: - 高级：横按/封闭/扩展、每组 4 个、每和弦 ½ 拍、BPM 90–120

    private static func buildAdvanced(
        using rng: inout some RandomNumberGenerator
    ) -> ChordSwitchExercise {
        let groupCount = Int.random(in: 5 ... 8, using: &rng)
        let segments = (0 ..< groupCount).map { _ in
            ChordSwitchSegment(
                chords: randomSequence(length: 4, pool: advancedPool, using: &rng)
            )
        }
        let bpmLo = Int.random(in: 90 ... 102, using: &rng)
        let bpmHi = Int.random(in: max(bpmLo, 103) ... 120, using: &rng)
        let prompt = makePrompt(
            difficulty: .高级,
            segments: segments,
            bpmMin: bpmLo,
            bpmMax: bpmHi,
            beatsPerChord: 0.5,
            extraLines: [
                ChordSwitchPromptTemplate.ruleFullBarre,
                "每组 4 个和弦，每和弦 ½ 拍（高速切换）。",
                "和弦类型含 maj7、m7、add9 等。",
            ]
        )
        return ChordSwitchExercise(
            id: "CS-L3-\(UUID().uuidString.prefix(8))",
            difficulty: .高级,
            segments: segments,
            bpmMin: bpmLo,
            bpmMax: bpmHi,
            beatsPerChord: 0.5,
            promptZh: prompt,
            goalsZh: [
                "强化大横按与封闭和弦的快速落指。",
                "半拍一和弦下保持右手节奏骨架稳定。",
                "扩展和弦（maj7 / m7 / add9）指型记忆与预备动作。",
            ]
        )
    }

    // MARK: - 随机工具

    /// 两个和弦一组，尽量不重复同和弦；若池过小则允许重复。
    private static func randomPair(from pool: [String], using rng: inout some RandomNumberGenerator) -> [String] {
        let a = pool.randomElement(using: &rng)!
        var b = pool.randomElement(using: &rng)!
        var guardCount = 0
        while b == a, pool.count > 1, guardCount < 8 {
            b = pool.randomElement(using: &rng)!
            guardCount += 1
        }
        return [a, b]
    }

    /// 生成长度为 `length` 的序列，尽量避免相邻相同和弦。
    private static func randomSequence(
        length: Int,
        pool: [String],
        using rng: inout some RandomNumberGenerator
    ) -> [String] {
        precondition(length >= 1, "length")
        var out: [String] = []
        out.reserveCapacity(length)
        for _ in 0 ..< length {
            var c = pool.randomElement(using: &rng)!
            if let last = out.last, c == last, pool.count > 1 {
                var tries = 0
                while c == last, tries < 24 {
                    c = pool.randomElement(using: &rng)!
                    tries += 1
                }
                if c == last, let alt = pool.filter({ $0 != last }).randomElement(using: &rng) {
                    c = alt
                }
            }
            out.append(c)
        }
        return out
    }

    private static func makePrompt(
        difficulty: ChordSwitchDifficulty,
        segments: [ChordSwitchSegment],
        bpmMin: Int,
        bpmMax: Int,
        beatsPerChord: Double,
        extraLines: [String]
    ) -> String {
        var lines: [String] = []
        let beatRule: String
        if beatsPerChord == 2 { beatRule = "每和弦 2 拍" }
        else if beatsPerChord == 1 { beatRule = "每和弦 1 拍" }
        else { beatRule = "每和弦 ½ 拍" }
        lines.append("【\(difficulty.rawValue)】和弦切换 · \(beatRule) · BPM \(bpmMin)–\(bpmMax)")
        for (i, seg) in segments.enumerated() {
            lines.append("第\(i + 1)组：\(seg.summaryZh)")
        }
        lines.append("顺序全长：\(segments.flatMap(\.chords).joined(separator: " → "))")
        lines.append(contentsOf: extraLines)
        return lines.joined(separator: "\n")
    }
}
