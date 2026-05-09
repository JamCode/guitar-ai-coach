import Chords
import Foundation

// MARK: - 和弦切换自动出题（大调功能进行 + 级数；模板基于 C，可按主音移调）

public enum ChordSwitchGenerator {
    /// 模板与级数推理的基准主音（和弦符号在内部先生成于本音上再移调）。
    public static let templateTonic: String = "C"

    /// 默认调性文案（主音为 C）。
    public static var defaultKeyZh: String { keyZhLabel(tonic: defaultTonic) }

    /// 默认主音（与设置、出题默认一致）。
    public static let defaultTonic: String = "C"

    /// 设置里可选的主音列表（与 `ChordTransposeLocal` 根音命名一致）。
    public static let selectableTonics: [String] = [
        "C", "G", "D", "A", "E", "B", "F#", "C#",
        "F", "Bb", "Eb", "Ab", "Db", "Gb",
    ]

    public static func keyZhLabel(tonic: String) -> String {
        "\(tonic) 调"
    }

    /// 从 `keyZh`（如 `G 调`）解析主音字母；失败时为 `defaultTonic`。
    public static func parseTonicKey(from keyZh: String) -> String {
        var s = keyZh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasSuffix("调") else { return defaultTonic }
        s.removeLast()
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return selectableTonics.contains(t) ? t : defaultTonic
    }

    // MARK: 和弦池（与难度/指法表约定一致；符号相对于 **C 大调模板**，校验时可先移回 C）

    /// 初级：C 大调自然和弦三和弦，开放/常用把位。
    public static let beginnerPool: [String] = ["C", "Dm", "Em", "F", "G", "Am"]

    /// 中级：自然七和弦与属七等（仍围绕 C 大调功能）。
    public static let intermediatePool: [String] = [
        "C", "Dm", "Em", "F", "G", "Am",
        "Cmaj7", "Dm7", "Em7", "G7", "Am7",
    ]

    /// 高级：扩展色彩（仍对应 C 大调内的级数功能）。
    public static let advancedPool: [String] = [
        "Cmaj7", "Dm7", "Em7", "Fmaj9", "G7", "G9", "G13", "Am7",
        "Cmaj9", "Gmaj7",
    ]

    // MARK: 进行模板（级数 + **C 调** 符号）

    private typealias Step = (roman: String, chord: String)

    private static let beginnerTemplates: [[Step]] = [
        [("I", "C"), ("ii", "Dm"), ("V", "G"), ("I", "C")],
        [("I", "C"), ("V", "G"), ("vi", "Am"), ("IV", "F")],
        [("vi", "Am"), ("IV", "F"), ("I", "C"), ("V", "G")],
        [("I", "C"), ("vi", "Am"), ("ii", "Dm"), ("V", "G")],
        [("I", "C"), ("IV", "F"), ("V", "G"), ("I", "C")],
        [("ii", "Dm"), ("V", "G"), ("I", "C"), ("IV", "F")],
        [("I", "C"), ("iii", "Em"), ("vi", "Am")],
        [("I", "C"), ("V", "G"), ("I", "C")],
    ]

    private static let intermediateTemplates: [[Step]] = [
        [("ii7", "Dm7"), ("V7", "G7"), ("I", "C"), ("IV", "F")],
        [("Imaj7", "Cmaj7"), ("vi", "Am"), ("ii7", "Dm7"), ("V7", "G7")],
        [("vi7", "Am7"), ("IV", "F"), ("I", "C"), ("V7", "G7")],
        [("I", "C"), ("vi7", "Am7"), ("IV", "F"), ("V", "G"), ("I", "C")],
        [("I", "C"), ("ii7", "Dm7"), ("V7", "G7"), ("vi", "Am"), ("IV", "F"), ("V", "G")],
        [("ii7", "Dm7"), ("V7", "G7"), ("I", "C"), ("vi", "Am"), ("ii7", "Dm7"), ("V7", "G7")],
        [("I", "C"), ("iii7", "Em7"), ("vi7", "Am7"), ("ii7", "Dm7"), ("V7", "G7")],
        [("vi", "Am"), ("IV", "F"), ("I", "C"), ("V7", "G7"), ("vi7", "Am7"), ("IV", "F")],
    ]

    private static let advancedTemplates: [[Step]] = [
        [("ii7", "Dm7"), ("V9", "G9"), ("Imaj7", "Cmaj7"), ("vi7", "Am7"), ("IVmaj9", "Fmaj9"), ("V13", "G13")],
        [("Imaj7", "Cmaj7"), ("iii7", "Em7"), ("vi7", "Am7"), ("ii7", "Dm7"), ("V7", "G7"), ("Imaj9", "Cmaj9")],
        [("ii7", "Dm7"), ("V7", "G7"), ("Imaj7", "Cmaj7"), ("IVmaj9", "Fmaj9"), ("iii7", "Em7"), ("vi7", "Am7"), ("ii7", "Dm7"), ("V7", "G7")],
        [("vi7", "Am7"), ("ii7", "Dm7"), ("V9", "G9"), ("Imaj7", "Cmaj7"), ("IVmaj9", "Fmaj9"), ("V13", "G13")],
        [("Imaj7", "Cmaj7"), ("ii7", "Dm7"), ("V7", "G7"), ("Imaj9", "Cmaj9"), ("vi7", "Am7"), ("ii7", "Dm7"), ("V13", "G13"), ("Imaj7", "Cmaj7")],
        [("ii7", "Dm7"), ("V7", "G7"), ("Imaj9", "Cmaj9"), ("vi7", "Am7"), ("IVmaj9", "Fmaj9"), ("V7", "G7")],
    ]

    // MARK: 对外 API

    public static func recommendedExercises(
        using rng: inout some RandomNumberGenerator
    ) -> [ChordSwitchExercise] {
        [
            buildExercise(difficulty: .初级, tonic: defaultTonic, using: &rng),
            buildExercise(difficulty: .中级, tonic: defaultTonic, using: &rng),
            buildExercise(difficulty: .高级, tonic: defaultTonic, using: &rng),
        ]
    }

    public static func buildExercise(
        difficulty: ChordSwitchDifficulty,
        tonic: String = defaultTonic,
        using rng: inout some RandomNumberGenerator
    ) -> ChordSwitchExercise {
        let t = selectableTonics.contains(tonic) ? tonic : defaultTonic
        switch difficulty {
        case .初级:
            return buildBeginner(tonic: t, using: &rng)
        case .中级:
            return buildIntermediate(tonic: t, using: &rng)
        case .高级:
            return buildAdvanced(tonic: t, using: &rng)
        }
    }

    /// 保持同一组级数与难度，仅将和弦符号从当前 `keyZh` 主音移到新主音，并刷新文案。
    public static func withTonic(_ exercise: ChordSwitchExercise, to newTonic: String) -> ChordSwitchExercise {
        let to = selectableTonics.contains(newTonic) ? newTonic : defaultTonic
        let from = parseTonicKey(from: exercise.keyZh)
        guard from != to else { return exercise }
        let newSegments = exercise.segments.map { seg in
            ChordSwitchSegment(chords: seg.chords.map {
                ChordTransposeLocal.transposeChordSymbol($0, from: from, to: to)
            })
        }
        let keyZh = keyZhLabel(tonic: to)
        let maj = majorKeyPhrase(tonic: to)
        let extras = extraPromptLines(difficulty: exercise.difficulty, majorPhrase: maj)
        let prompt = makePrompt(
            difficulty: exercise.difficulty,
            keyZh: keyZh,
            romanNumerals: exercise.romanNumerals,
            segments: newSegments,
            bpmMin: exercise.bpmMin,
            bpmMax: exercise.bpmMax,
            beatsPerChord: exercise.beatsPerChord,
            extraLines: extras
        )
        let goals = makeGoals(
            difficulty: exercise.difficulty,
            keyZh: keyZh,
            majorPhrase: maj,
            romans: exercise.romanNumerals
        )
        return ChordSwitchExercise(
            id: exercise.id,
            difficulty: exercise.difficulty,
            segments: newSegments,
            keyZh: keyZh,
            romanNumerals: exercise.romanNumerals,
            bpmMin: exercise.bpmMin,
            bpmMax: exercise.bpmMax,
            beatsPerChord: exercise.beatsPerChord,
            promptZh: prompt,
            goalsZh: goals
        )
    }

    // MARK: - Builders

    private static func buildBeginner(
        tonic: String,
        using rng: inout some RandomNumberGenerator
    ) -> ChordSwitchExercise {
        let template = beginnerTemplates.randomElement(using: &rng)!
        let romans = template.map(\.roman)
        let chordsC = template.map(\.chord)
        let bpm = Int.random(in: 50 ... 70, using: &rng)
        return assemble(
            idPrefix: "CS-L1",
            difficulty: .初级,
            tonic: tonic,
            romans: romans,
            chordsInC: chordsC,
            bpmMin: bpm,
            bpmMax: bpm,
            beatsPerChord: 2
        )
    }

    private static func buildIntermediate(
        tonic: String,
        using rng: inout some RandomNumberGenerator
    ) -> ChordSwitchExercise {
        let candidates = intermediateTemplates.filter { (4 ... 6).contains($0.count) }
        let template = (candidates.isEmpty ? intermediateTemplates : candidates).randomElement(using: &rng)!
        let romans = template.map(\.roman)
        let chordsC = template.map(\.chord)
        let bpmLo = Int.random(in: 70 ... 80, using: &rng)
        let bpmHi = Int.random(in: max(bpmLo, 81) ... 90, using: &rng)
        return assemble(
            idPrefix: "CS-L2",
            difficulty: .中级,
            tonic: tonic,
            romans: romans,
            chordsInC: chordsC,
            bpmMin: bpmLo,
            bpmMax: bpmHi,
            beatsPerChord: 1
        )
    }

    private static func buildAdvanced(
        tonic: String,
        using rng: inout some RandomNumberGenerator
    ) -> ChordSwitchExercise {
        let candidates = advancedTemplates.filter { (4 ... 8).contains($0.count) }
        let template = (candidates.isEmpty ? advancedTemplates : candidates).randomElement(using: &rng)!
        let romans = template.map(\.roman)
        let chordsC = template.map(\.chord)
        let bpmLo = Int.random(in: 90 ... 102, using: &rng)
        let bpmHi = Int.random(in: max(bpmLo, 103) ... 120, using: &rng)
        return assemble(
            idPrefix: "CS-L3",
            difficulty: .高级,
            tonic: tonic,
            romans: romans,
            chordsInC: chordsC,
            bpmMin: bpmLo,
            bpmMax: bpmHi,
            beatsPerChord: 0.5
        )
    }

    private static func assemble(
        idPrefix: String,
        difficulty: ChordSwitchDifficulty,
        tonic: String,
        romans: [String],
        chordsInC: [String],
        bpmMin: Int,
        bpmMax: Int,
        beatsPerChord: Double
    ) -> ChordSwitchExercise {
        let chords = chordsInC.map { ChordTransposeLocal.transposeChordSymbol($0, from: templateTonic, to: tonic) }
        let segment = ChordSwitchSegment(chords: chords)
        let keyZh = keyZhLabel(tonic: tonic)
        let maj = majorKeyPhrase(tonic: tonic)
        let extras = extraPromptLines(difficulty: difficulty, majorPhrase: maj)
        let prompt = makePrompt(
            difficulty: difficulty,
            keyZh: keyZh,
            romanNumerals: romans,
            segments: [segment],
            bpmMin: bpmMin,
            bpmMax: bpmMax,
            beatsPerChord: beatsPerChord,
            extraLines: extras
        )
        let goals = makeGoals(difficulty: difficulty, keyZh: keyZh, majorPhrase: maj, romans: romans)
        return ChordSwitchExercise(
            id: "\(idPrefix)-\(UUID().uuidString.prefix(8))",
            difficulty: difficulty,
            segments: [segment],
            keyZh: keyZh,
            romanNumerals: romans,
            bpmMin: bpmMin,
            bpmMax: bpmMax,
            beatsPerChord: beatsPerChord,
            promptZh: prompt,
            goalsZh: goals
        )
    }

    private static func majorKeyPhrase(tonic: String) -> String {
        "\(tonic) 大调"
    }

    private static func extraPromptLines(difficulty: ChordSwitchDifficulty, majorPhrase: String) -> [String] {
        switch difficulty {
        case .初级:
            return [
                ChordSwitchPromptTemplate.ruleNoBarre,
                "本题为 \(majorPhrase) 内自然和弦进行；按级数理解主、下属、属与副和弦关系。",
            ]
        case .中级:
            return [
                ChordSwitchPromptTemplate.ruleMiniBarre,
                "\(majorPhrase) 内 ii7–V7、属七解决等功能进行；每和弦 1 拍。",
            ]
        case .高级:
            return [
                ChordSwitchPromptTemplate.ruleFullBarre,
                "\(majorPhrase) 内高色彩和弦（maj9、属九/十三等），仍遵循 ii–V–I 与环式进行逻辑。",
                "每和弦 ½ 拍（高速切换）。",
            ]
        }
    }

    private static func makeGoals(
        difficulty: ChordSwitchDifficulty,
        keyZh: String,
        majorPhrase: String,
        romans: [String]
    ) -> [String] {
        let joined = romanProgressionJoined(romans)
        switch difficulty {
        case .初级:
            return [
                "在 \(keyZh)（\(majorPhrase)）下熟悉 \(joined) 的左手切换。",
                "每和弦 2 拍，换和弦落在拍点上前一拍预备。",
                "以级数记忆进行，便于将来移调。",
            ]
        case .中级:
            return [
                "掌握 \(keyZh)（\(majorPhrase)）下 \(joined) 的七和弦手型。",
                "注意 ii7–V7–I 的导向与属七解决感。",
                "保持 1 拍一和弦的颗粒感。",
            ]
        case .高级:
            return [
                "在 \(keyZh)（\(majorPhrase)）下完成 \(joined) 的快速落指。",
                "半拍一和弦时保持右手节奏骨架稳定。",
                "结合级数理解延伸和弦的声部功能。",
            ]
        }
    }

    private static func romanProgressionJoined(_ romans: [String]) -> String {
        romans.joined(separator: " → ")
    }

    private static func makePrompt(
        difficulty: ChordSwitchDifficulty,
        keyZh: String,
        romanNumerals: [String],
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
        lines.append("【\(difficulty.rawValue)】\(keyZh) 和弦切换 · \(beatRule) · BPM \(bpmMin)–\(bpmMax)")
        lines.append("级数进行：\(romanProgressionJoined(romanNumerals))")
        lines.append("和弦符号（\(keyZh)）：\(segments.flatMap(\.chords).joined(separator: " → "))")
        for (i, seg) in segments.enumerated() {
            lines.append("第\(i + 1)组：\(seg.summaryZh)")
        }
        lines.append("顺序全长：\(segments.flatMap(\.chords).joined(separator: " → "))")
        lines.append(contentsOf: extraLines)
        return lines.joined(separator: "\n")
    }
}
