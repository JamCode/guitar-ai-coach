import Core
import Foundation
import Fretboard

// MARK: - 音阶训练出题（可量化规则，供 SwiftUI 调用）

/// 吉他音阶训练自动出题：自然大/小调、大小调五声；Mi/Sol/La 指型（根音在六/五/四弦）。
public enum ScaleTrainingGenerator {
    private static let openMidi = FretboardMath.openMidiStrings

    // MARK: 对外 API

    /// 工具页卡片：初 / 中 / 高各一题。
    public static func recommendedExercises(
        using rng: inout some RandomNumberGenerator
    ) -> [ScaleTrainingExercise] {
        [
            buildExercise(difficulty: .初级, using: &rng),
            buildExercise(difficulty: .中级, using: &rng),
            buildExercise(difficulty: .高级, using: &rng),
        ]
    }

    public static func buildExercise(
        difficulty: ScaleTrainingDifficulty,
        using rng: inout some RandomNumberGenerator
    ) -> ScaleTrainingExercise {
        switch difficulty {
        case .初级:
            return buildBeginner(using: &rng)
        case .中级:
            return buildIntermediate(using: &rng)
        case .高级:
            return buildAdvanced(using: &rng)
        }
    }

    // MARK: - 初级

    /// 规则：固定 C 大调、Mi 指型、一个八度、上行/下行/上下行三选一、八分音符、BPM 60–70、无模进、无跳进。
    private static func buildBeginner(
        using rng: inout some RandomNumberGenerator
    ) -> ScaleTrainingExercise {
        let key = "C"
        let scale: ScaleTrainingScaleKind = .自然大调
        let pattern: ScaleTrainingFingerPattern = .Mi
        let direction = [ScaleTrainingPlayDirection.上行, .下行, .上下行].randomElement(using: &rng)!
        let bpm = Int.random(in: 60 ... 70, using: &rng)
        let intervals = scale.intervalsOneOctaveInclusive()
        let rootPc = pitchClass(forKeyName: key)
        let rootMidi = anchorRootMidi(keyPc: rootPc, pattern: pattern)
        let spine = midisFromDegrees(
            rootMidi: rootMidi,
            intervals: intervals,
            degreeIndices: degreeSpineOneOctave(
                degreeCount: intervals.count,
                direction: direction,
                leap: .none,
                using: &rng
            )
        )
        let placed = placeOnFretboard(
            midis: spine,
            pattern: pattern,
            anchorFret: anchorFretForKey(pattern: pattern, keyPc: rootPc),
            span: 5,
            widenOnFailure: false
        )!
        let steps = makeSteps(placed: placed)
        let prompt = promptText(
            difficulty: .初级,
            keyDisplay: "\(key)大调",
            scale: scale,
            pattern: pattern,
            direction: direction,
            rhythm: .八分音符,
            bpmMin: bpm,
            bpmMax: bpm,
            extras: []
        )
        return ScaleTrainingExercise(
            id: "ST-L1-\(UUID().uuidString.prefix(8))",
            difficulty: .初级,
            keyName: key,
            scaleKind: scale,
            pattern: pattern,
            direction: direction,
            rhythm: .八分音符,
            bpmMin: bpm,
            bpmMax: bpm,
            allowsSequenceShift: false,
            allowsDegreeLeap: false,
            usesAllStrings: false,
            retrogradeApplied: false,
            promptZh: prompt,
            goalsZh: beginnerGoals(),
            steps: steps
        )
    }

    // MARK: - 中级

    /// 规则：调 ∈ {C,G,D,F}；指型 Mi/Sol/La 随机；音阶四类随机；一个八度；八分音符为主 BPM 70–85；
    /// 允许一次「跳过一个音级」的跳进、末尾两段 1213 模进；完整上下行与上行/下行仍随机。
    private static func buildIntermediate(
        using rng: inout some RandomNumberGenerator
    ) -> ScaleTrainingExercise {
        let keys = ["C", "G", "D", "F"]
        let key = keys.randomElement(using: &rng)!
        let pattern = ScaleTrainingFingerPattern.allCases.randomElement(using: &rng)!
        let scale = ScaleTrainingScaleKind.allCases.randomElement(using: &rng)!
        let direction = [ScaleTrainingPlayDirection.上行, .下行, .上下行].randomElement(using: &rng)!
        let bpmLo = Int.random(in: 70 ... 78, using: &rng)
        let bpmHi = Int.random(in: max(bpmLo, 79) ... 85, using: &rng)
        let intervals = scale.intervalsOneOctaveInclusive()
        let rootPc = pitchClass(forKeyName: key)
        let rootMidi = anchorRootMidi(keyPc: rootPc, pattern: pattern)
        let leap: LeapKind = Bool.random(using: &rng) ? .skipOneScaleDegreeOnce : .none
        let deg = degreeSpineOneOctave(
            degreeCount: intervals.count,
            direction: direction,
            leap: leap,
            using: &rng
        )
        var spine = midisFromDegrees(rootMidi: rootMidi, intervals: intervals, degreeIndices: deg)
        spine += motif1213Midis(rootMidi: rootMidi, intervals: intervals, cycles: 2)
        let anchorFret = anchorFretForKey(pattern: pattern, keyPc: rootPc)
        let placed = placeOnFretboard(
            midis: spine,
            pattern: pattern,
            anchorFret: anchorFret,
            span: 6,
            widenOnFailure: true
        )!
        let steps = makeSteps(placed: placed)
        let keyDisp = keyDisplayName(key: key, scale: scale)
        var extras: [String] = []
        extras.append("含 2 组「1-2-1-3」级数模进（每组内级数 +1 平移）。")
        if leap != .none { extras.append("含一次「跳过一个音级」的级进跳进（近似三度距离）。") }
        let prompt = promptText(
            difficulty: .中级,
            keyDisplay: keyDisp,
            scale: scale,
            pattern: pattern,
            direction: direction,
            rhythm: .八分音符,
            bpmMin: bpmLo,
            bpmMax: bpmHi,
            extras: extras
        )
        return ScaleTrainingExercise(
            id: "ST-L2-\(UUID().uuidString.prefix(8))",
            difficulty: .中级,
            keyName: key,
            scaleKind: scale,
            pattern: pattern,
            direction: direction,
            rhythm: .八分音符,
            bpmMin: bpmLo,
            bpmMax: bpmHi,
            allowsSequenceShift: true,
            allowsDegreeLeap: leap != .none,
            usesAllStrings: false,
            retrogradeApplied: false,
            promptZh: prompt,
            goalsZh: intermediateGoals(),
            steps: steps
        )
    }

    // MARK: - 高级

    /// 规则：调七选一；三指型；两八度；十六分音符 BPM 85–110；允许一次四度级跳进、多组模进、可反向整段；
    /// 全弦使用（六根弦均至少出现一次落点）。
    private static func buildAdvanced(
        using rng: inout some RandomNumberGenerator
    ) -> ScaleTrainingExercise {
        for attempt in 0 ..< 24 {
            let keys = ["C", "G", "D", "A", "E", "F", "Bb"]
            let key = keys.randomElement(using: &rng)!
            let pattern = ScaleTrainingFingerPattern.allCases.randomElement(using: &rng)!
            let scale = ScaleTrainingScaleKind.allCases.randomElement(using: &rng)!
            let direction = [ScaleTrainingPlayDirection.上行, .下行].randomElement(using: &rng)!
            let retro = Bool.random(using: &rng)
            let bpmLo = Int.random(in: 85 ... 95, using: &rng)
            let bpmHi = Int.random(in: max(bpmLo, 96) ... 110, using: &rng)
            let intervals = intervalsTwoOctaves(scale: scale)
            let rootPc = pitchClass(forKeyName: key)
            let rootMidi = anchorRootMidi(keyPc: rootPc, pattern: pattern)
            let leap: LeapKind = Bool.random(using: &rng) ? .skipTwoScaleDegreesOnce : .skipOneScaleDegreeOnce
            let deg = degreeSpineTwoOctaves(direction: direction, leap: leap, intervals: intervals, using: &rng)
            var spine = midisFromDegrees(rootMidi: rootMidi, intervals: intervals, degreeIndices: deg)
            spine += motif1213MidisAdvanced(rootMidi: rootMidi, intervals: intervals, cycles: 3)
            if retro { spine.reverse() }
            let anchorFret = anchorFretForKey(pattern: pattern, keyPc: rootPc)
            let requireAll = attempt < 20
            if let placed = placeAllStrings(
                midis: spine,
                anchorFret: anchorFret,
                using: &rng,
                requireSixStrings: requireAll
            ) {
                let steps = makeSteps(placed: placed)
                let keyDisp = keyDisplayName(key: key, scale: scale)
                var extras: [String] = ["两八度音域。", "含 3 组扩展模进片段。"]
                if Set(placed.map(\.0)).count == 6 {
                    extras.append("六根弦均需落指。")
                }
                if retro { extras.append("整段采用反向演奏顺序。") }
                if leap == .skipTwoScaleDegreesOnce {
                    extras.append("含一次「跳过两个音级」的跳进（近似四度距离）。")
                } else {
                    extras.append("含一次「跳过一个音级」的跳进。")
                }
                let usesAll = Set(placed.map(\.0)).count == 6
                let prompt = promptText(
                    difficulty: .高级,
                    keyDisplay: keyDisp,
                    scale: scale,
                    pattern: pattern,
                    direction: direction,
                    rhythm: .十六分音符,
                    bpmMin: bpmLo,
                    bpmMax: bpmHi,
                    extras: extras
                )
                return ScaleTrainingExercise(
                    id: "ST-L3-\(UUID().uuidString.prefix(8))",
                    difficulty: .高级,
                    keyName: key,
                    scaleKind: scale,
                    pattern: pattern,
                    direction: direction,
                    rhythm: .十六分音符,
                    bpmMin: bpmLo,
                    bpmMax: bpmHi,
                    allowsSequenceShift: true,
                    allowsDegreeLeap: true,
                    usesAllStrings: usesAll,
                    retrogradeApplied: retro,
                    promptZh: prompt,
                    goalsZh: advancedGoals(),
                    steps: steps
                )
            }
        }
        return buildAdvancedRelaxed(using: &rng)
    }

    /// 兜底：不强制六根弦全覆盖，但仍保持两八度 / 十六分音符 / 跳进 / 模进规则。
    private static func buildAdvancedRelaxed(
        using rng: inout some RandomNumberGenerator
    ) -> ScaleTrainingExercise {
        let keys = ["C", "G", "D", "A", "E", "F", "Bb"]
        let key = keys.randomElement(using: &rng)!
        let pattern = ScaleTrainingFingerPattern.allCases.randomElement(using: &rng)!
        let scale = ScaleTrainingScaleKind.allCases.randomElement(using: &rng)!
        let direction = [ScaleTrainingPlayDirection.上行, .下行].randomElement(using: &rng)!
        let retro = Bool.random(using: &rng)
        let bpmLo = Int.random(in: 85 ... 95, using: &rng)
        let bpmHi = Int.random(in: max(bpmLo, 96) ... 110, using: &rng)
        let intervals = intervalsTwoOctaves(scale: scale)
        let rootPc = pitchClass(forKeyName: key)
        let rootMidi = anchorRootMidi(keyPc: rootPc, pattern: pattern)
        let leap: LeapKind = Bool.random(using: &rng) ? .skipTwoScaleDegreesOnce : .skipOneScaleDegreeOnce
        let deg = degreeSpineTwoOctaves(direction: direction, leap: leap, intervals: intervals, using: &rng)
        var spine = midisFromDegrees(rootMidi: rootMidi, intervals: intervals, degreeIndices: deg)
        spine += motif1213MidisAdvanced(rootMidi: rootMidi, intervals: intervals, cycles: 3)
        if retro { spine.reverse() }
        let anchorFret = anchorFretForKey(pattern: pattern, keyPc: rootPc)
        let placed =
            placeAllStrings(midis: spine, anchorFret: anchorFret, using: &rng, requireSixStrings: false)
            ?? placeOnFretboard(
                midis: spine,
                pattern: pattern,
                anchorFret: anchorFret,
                span: 12,
                widenOnFailure: true
            )
            ?? placeGreedy(midis: spine, anchorFret: anchorFret, span: 14, preferCoverage: false)!
        let steps = makeSteps(placed: placed)
        let keyDisp = keyDisplayName(key: key, scale: scale)
        let usesAll = Set(placed.map(\.0)).count == 6
        let prompt = promptText(
            difficulty: .高级,
            keyDisplay: keyDisp,
            scale: scale,
            pattern: pattern,
            direction: direction,
            rhythm: .十六分音符,
            bpmMin: bpmLo,
            bpmMax: bpmHi,
            extras: [
                "两八度音域。", "含 3 组扩展模进片段。",
                usesAll ? "六根弦均已落指。" : "本组为兜底把位，优先保证可弹完；可再点「换一组」尝试全弦覆盖。",
            ]
        )
        return ScaleTrainingExercise(
            id: "ST-L3-\(UUID().uuidString.prefix(8))",
            difficulty: .高级,
            keyName: key,
            scaleKind: scale,
            pattern: pattern,
            direction: direction,
            rhythm: .十六分音符,
            bpmMin: bpmLo,
            bpmMax: bpmHi,
            allowsSequenceShift: true,
            allowsDegreeLeap: true,
            usesAllStrings: usesAll,
            retrogradeApplied: retro,
            promptZh: prompt,
            goalsZh: advancedGoals(),
            steps: steps
        )
    }

    // MARK: - 音高与音阶表

    private enum LeapKind {
        case none
        case skipOneScaleDegreeOnce
        case skipTwoScaleDegreesOnce
    }

    private static func pitchClass(forKeyName name: String) -> Int {
        switch name.uppercased() {
        case "C": return 0
        case "G": return 7
        case "D": return 2
        case "F": return 5
        case "A": return 9
        case "E": return 4
        case "BB", "A#": return 10
        default:
            preconditionFailure("unsupported key \(name)")
        }
    }

    /// 在指定指型的**根音弦**上，取 `[1,12]` 内最小品位使 `(open+f)%12 == keyPc`。
    private static func anchorFretForKey(pattern: ScaleTrainingFingerPattern, keyPc: Int) -> Int {
        let s = pattern.anchorStringIndexFromBass
        let open = openMidi[s]
        for f in 1 ... 12 {
            if (open + f) % 12 == keyPc { return f }
        }
        return 1
    }

    /// 根音 MIDI：锚品位 + 空弦 MIDI，落在 `[E2, B3]` 附近舒适区（约 MIDI 40–71），否则 +12。
    private static func anchorRootMidi(keyPc: Int, pattern: ScaleTrainingFingerPattern) -> Int {
        let s = pattern.anchorStringIndexFromBass
        let f = anchorFretForKey(pattern: pattern, keyPc: keyPc)
        var m = openMidi[s] + f
        while m < 45 { m += 12 }
        while m > 71 { m -= 12 }
        return m
    }

    private static func intervalsTwoOctaves(scale: ScaleTrainingScaleKind) -> [Int] {
        let one = scale.intervalsOneOctaveInclusive()
        let high = one.dropFirst().map { $0 + 12 }
        return Array(one) + Array(high)
    }

    /// `degreeIndices` 下标对应 `intervals` 数组（含八度终点）。
    private static func midisFromDegrees(
        rootMidi: Int,
        intervals: [Int],
        degreeIndices: [Int]
    ) -> [Int] {
        degreeIndices.map { rootMidi + intervals[$0] }
    }

    private static func degreeSpineOneOctave(
        degreeCount: Int,
        direction: ScaleTrainingPlayDirection,
        leap: LeapKind,
        using rng: inout some RandomNumberGenerator
    ) -> [Int] {
        let n = max(2, degreeCount)
        var idx = Array(0 ..< n)
        let cutUpper = max(3, n - 1)
        switch leap {
        case .none:
            break
        case .skipOneScaleDegreeOnce:
            guard n > 4 else { break }
            let cut = Int.random(in: 2 ..< min(6, cutUpper), using: &rng)
            idx.remove(at: cut)
        case .skipTwoScaleDegreesOnce:
            guard n > 5 else { break }
            let a = Int.random(in: 2 ..< min(6, n - 2), using: &rng)
            var b = Int.random(in: 2 ..< min(6, n - 2), using: &rng)
            if b == a { b = min(n - 3, a + 1) }
            let hi = max(a, b)
            let lo = min(a, b)
            idx.remove(at: hi)
            idx.remove(at: lo)
        }
        return applyDirection(indices: idx, direction: direction)
    }

    private static func degreeSpineTwoOctaves(
        direction: ScaleTrainingPlayDirection,
        leap: LeapKind,
        intervals: [Int],
        using rng: inout some RandomNumberGenerator
    ) -> [Int] {
        let maxI = intervals.count - 1
        var idx = Array(0 ... maxI)
        switch leap {
        case .none:
            break
        case .skipOneScaleDegreeOnce:
            let cut = Int.random(in: 3 ..< min(10, maxI - 1), using: &rng)
            idx.remove(at: cut)
        case .skipTwoScaleDegreesOnce:
            let a = Int.random(in: 3 ..< min(10, maxI - 1), using: &rng)
            var b = Int.random(in: 3 ..< min(10, maxI - 1), using: &rng)
            if b == a { b = min(maxI - 2, a + 1) }
            let hi = max(a, b)
            let lo = min(a, b)
            idx.remove(at: hi)
            idx.remove(at: lo)
        }
        return applyDirection(indices: idx, direction: direction)
    }

    private static func applyDirection(
        indices: [Int],
        direction: ScaleTrainingPlayDirection
    ) -> [Int] {
        switch direction {
        case .上行:
            return indices
        case .下行:
            return indices.reversed()
        case .上下行:
            let up = indices
            let down = up.reversed().dropFirst()
            return up + Array(down)
        }
    }

    /// 1213 模进：级数序列 (1,2,1,3) 平移，重复 `cycles` 组。
    private static func motif1213Midis(
        rootMidi: Int,
        intervals: [Int],
        cycles: Int
    ) -> [Int] {
        let maxDeg = intervals.count - 2
        var out: [Int] = []
        var shift = 0
        for _ in 0 ..< cycles {
            let patternIdx = [0 + shift, 1 + shift, 0 + shift, 2 + shift]
            for p in patternIdx where p >= 0 && p < intervals.count {
                out.append(rootMidi + intervals[p])
            }
            shift += 1
            if shift + 2 > maxDeg { shift = 0 }
        }
        return out
    }

    private static func motif1213MidisAdvanced(
        rootMidi: Int,
        intervals: [Int],
        cycles: Int
    ) -> [Int] {
        motif1213Midis(rootMidi: rootMidi, intervals: intervals, cycles: cycles)
    }

    // MARK: - 指板落点

    private static func placeOnFretboard(
        midis: [Int],
        pattern _: ScaleTrainingFingerPattern,
        anchorFret: Int,
        span: Int,
        widenOnFailure: Bool
    ) -> [(Int, Int)]? {
        var spanVar = span
        for _ in 0 ..< (widenOnFailure ? 6 : 1) {
            if let r = placeGreedy(midis: midis, anchorFret: anchorFret, span: spanVar, preferCoverage: false) {
                return r
            }
            spanVar += 1
        }
        return nil
    }

    private static func placeGreedy(
        midis: [Int],
        anchorFret: Int,
        span: Int,
        preferCoverage: Bool
    ) -> [(Int, Int)]? {
        let boxLow = max(1, anchorFret - 1)
        let boxHigh = min(15, anchorFret + span)
        var prev: (Int, Int)?
        var usedStrings = Set<Int>()
        var out: [(Int, Int)] = []
        for m in midis {
            let cand = candidates(midi: m, boxLow: boxLow, boxHigh: boxHigh)
            guard !cand.isEmpty else { return nil }
            let best = cand.min(by: { a, b in
                var sa = score(a, prev: prev)
                var sb = score(b, prev: prev)
                if preferCoverage, !usedStrings.contains(a.0) { sa -= 45 }
                if preferCoverage, !usedStrings.contains(b.0) { sb -= 45 }
                return sa < sb
            })!
            usedStrings.insert(best.0)
            out.append(best)
            prev = best
        }
        return out
    }

    private static func candidates(midi: Int, boxLow: Int, boxHigh: Int) -> [(Int, Int)] {
        var r: [(Int, Int)] = []
        for s in 0 ..< 6 {
            for f in 1 ... 15 {
                guard openMidi[s] + f == midi else { continue }
                if f >= boxLow - 2, f <= boxHigh + 3 {
                    r.append((s, f))
                }
            }
        }
        return r
    }

    private static func score(_ p: (Int, Int), prev: (Int, Int)?) -> Int {
        guard let prev else { return p.0 * 3 + p.1 }
        return abs(p.0 - prev.0) * 10 + abs(p.1 - prev.1)
    }

    /// 高级：随机加宽指型窗并多次尝试；`requireSixStrings` 为真时仅接受六根弦均出现的落点方案。
    private static func placeAllStrings(
        midis: [Int],
        anchorFret: Int,
        using rng: inout some RandomNumberGenerator,
        requireSixStrings: Bool
    ) -> [(Int, Int)]? {
        for _ in 0 ..< 96 {
            let span = Int.random(in: 5 ... 11, using: &rng)
            if let placed = placeGreedy(
                midis: midis,
                anchorFret: anchorFret,
                span: span,
                preferCoverage: true
            ) {
                let used = Set(placed.map(\.0))
                if !requireSixStrings || used.count == 6 { return placed }
            }
        }
        return nil
    }

    private static func makeSteps(placed: [(Int, Int)]) -> [ScaleTrainingStep] {
        placed.enumerated().map { i, p in
            let midi = openMidi[p.0] + p.1
            let label = PitchMath.midiToPitchLabel(midi)
            return ScaleTrainingStep(
                id: i,
                stringIndexFromBass: p.0,
                fret: p.1,
                midi: midi,
                pitchLabelZh: label,
                degreeLabelZh: "\(i + 1)"
            )
        }
    }

    // MARK: - 文案

    private static func keyDisplayName(key: String, scale: ScaleTrainingScaleKind) -> String {
        switch scale {
        case .自然大调, .五声音阶大调:
            return "\(key)大调"
        case .自然小调, .五声音阶小调:
            return "\(key)小调"
        }
    }

    private static func promptText(
        difficulty: ScaleTrainingDifficulty,
        keyDisplay: String,
        scale: ScaleTrainingScaleKind,
        pattern: ScaleTrainingFingerPattern,
        direction: ScaleTrainingPlayDirection,
        rhythm: ScaleTrainingRhythmGrid,
        bpmMin: Int,
        bpmMax: Int,
        extras: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("【\(difficulty.rawValue)】\(keyDisplay) · \(scale.rawValue) · \(pattern.titleZh)")
        lines.append("弹奏方向：\(direction.rawValue)。节奏：\(rhythm.userLabelZh)。节拍器 \(bpmMin)–\(bpmMax) BPM。")
        for e in extras { lines.append(e) }
        return lines.joined(separator: "\n")
    }

    private static func beginnerGoals() -> [String] {
        [
            "熟悉 Mi 指型在一个八度内的上行/下行/简单上下行。",
            "固定 C 大调自然音，建立稳定节拍与左手触弦。",
            "不使用模进与跳进，专注指序与音色均匀。",
        ]
    }

    private static func intermediateGoals() -> [String] {
        [
            "在四个常用调之间切换读谱反应。",
            "体验 Mi/Sol/La 三种根弦位置带来的把位差异。",
            "在仍可控的范围内加入模进与一次级进跳进。",
        ]
    }

    private static func advancedGoals() -> [String] {
        [
            "两八度耐力与跨把稳定。",
            "十六分音符下保持松弛与颗粒清晰。",
            "全弦落点覆盖，避免只练熟悉弦区。",
        ]
    }
}
