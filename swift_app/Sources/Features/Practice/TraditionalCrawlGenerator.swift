import Foundation
import Fretboard

// MARK: - 传统爬格子生成（供 SwiftUI 调用）

/// 经典「四指一格」：
/// - 在**同一根弦**上依次按 `b…b+3` 四品，对应手指 `1-2-3-4`（弦内半音）。
/// - **弦序**从粗到细：**六弦 → 一弦**（`stringIndexFromBass` 0→5）。
/// - 六根弦走完一轮后，把位起点 **`b` 整体 +1**，再自六弦重复（把位整体上移）。
public enum TraditionalCrawlGenerator {
    public static let maxFretInclusive = 15

    /// 工具页「推荐练习」卡片：固定返回初 / 中 / 高各一条（稳定文案 + 随机把位种子）。
    public static func recommendedExercises(
        capo: Int = 0,
        using rng: inout some RandomNumberGenerator
    ) -> [TraditionalCrawlExercise] {
        [
            buildExercise(difficulty: .初级, capo: capo, using: &rng),
            buildExercise(difficulty: .中级, capo: capo, using: &rng),
            buildExercise(difficulty: .高级, capo: capo, using: &rng),
        ]
    }

    public static func buildExercise(
        difficulty: TraditionalCrawlDifficulty,
        capo: Int = 0,
        using rng: inout some RandomNumberGenerator
    ) -> TraditionalCrawlExercise {
        switch difficulty {
        case .初级:
            return buildBeginner(capo: capo, using: &rng)
        case .中级:
            return buildIntermediate(capo: capo, using: &rng)
        case .高级:
            return buildAdvanced(capo: capo, using: &rng)
        }
    }

    // MARK: - 初级：仅六弦，低把位，少量轮次

    private static func buildBeginner(
        capo: Int,
        using rng: inout some RandomNumberGenerator
    ) -> TraditionalCrawlExercise {
        let b0 = Int.random(in: 1 ... 3, using: &rng)
        let globalRounds = 3
        let steps = makeVerticalSpider(
            stringIndices: [0],
            startingBlockFret: b0,
            globalRounds: globalRounds,
            capo: capo,
            includeDescentPerBlock: false
        )
        let id = "TC-L1-\(UUID().uuidString.prefix(8))"
        return TraditionalCrawlExercise(
            id: id,
            difficulty: .初级,
            titleZh: "初级 · 单弦爬格子（六弦）",
            summaryZh: "仅在六弦上完成 \(globalRounds) 次「四指一格」上移；把位自 \(b0) 品附近开始，每步弦内半音。",
            bpmRange: 50 ... 65,
            steps: steps,
            tipsZh: [
                "保留指：按下 2 指时尽量暂不抬 1 指，依此类推。",
                "力度轻而实，先求干净再求速度。",
                "节拍器一拍一步；若吃力，取下限 BPM。",
            ]
        )
    }

    // MARK: - 中级：全弦顺向，多轮上移

    private static func buildIntermediate(
        capo: Int,
        using rng: inout some RandomNumberGenerator
    ) -> TraditionalCrawlExercise {
        let b0 = Int.random(in: 1 ... 7, using: &rng)
        let globalRounds = 2
        let steps = makeVerticalSpider(
            stringIndices: Array(0 ..< 6),
            startingBlockFret: b0,
            globalRounds: globalRounds,
            capo: capo,
            includeDescentPerBlock: false
        )
        let id = "TC-L2-\(UUID().uuidString.prefix(8))"
        return TraditionalCrawlExercise(
            id: id,
            difficulty: .中级,
            titleZh: "中级 · 全弦顺向爬格子",
            summaryZh: "六弦→一弦，每弦 \(globalRounds) 轮把位整体上移；起点约 \(b0) 品，共 \(steps.count) 步。",
            bpmRange: 65 ... 88,
            steps: steps,
            tipsZh: [
                "换弦时保持四品「手型框」整体平移，不要单指够远品。",
                "右手可用交替拨弦（i m）或经济拨弦，选一种坚持。",
                "每根弦四音后再换弦，避免提前跳弦。",
            ]
        )
    }

    // MARK: - 高级：全弦上行后接全弦下行（每轮 b 仍 +1）

    private static func buildAdvanced(
        capo: Int,
        using rng: inout some RandomNumberGenerator
    ) -> TraditionalCrawlExercise {
        let b0 = Int.random(in: 1 ... 6, using: &rng)
        let globalRounds = 2
        let steps = makeVerticalSpider(
            stringIndices: Array(0 ..< 6),
            startingBlockFret: b0,
            globalRounds: globalRounds,
            capo: capo,
            includeDescentPerBlock: true
        )
        let id = "TC-L3-\(UUID().uuidString.prefix(8))"
        return TraditionalCrawlExercise(
            id: id,
            difficulty: .高级,
            titleZh: "高级 · 全弦往返爬格子",
            summaryZh: "每轮「上行 1-2-3-4」走完全弦后，再「下行 4-3-2-1」走完全弦；把位整体上移 \(globalRounds) 轮；约 \(steps.count) 步。",
            bpmRange: 88 ... 112,
            steps: steps,
            tipsZh: [
                "下行同样保持手型框，优先让小指定位准确。",
                "上行与下行衔接处最易乱：放慢半拍确认指序。",
                "若手腕紧张，降低 BPM 或缩短单次练习时长。",
            ]
        )
    }

    // MARK: - 路径核心

    /// - `stringIndices`: 参与换弦的弦序（通常为 `[0..<6]` 或 `[0]`）。
    /// - `globalRounds`: 把位起点 `b` 递增次数（每轮结束 `b += 1`）。
    /// - `includeDescentPerBlock`: 每一固定 `b` 下，是否在六根弦走完上行后再走下行。
    private static func makeVerticalSpider(
        stringIndices: [Int],
        startingBlockFret b0: Int,
        globalRounds: Int,
        capo: Int,
        includeDescentPerBlock: Bool
    ) -> [TraditionalCrawlStep] {
        precondition(!stringIndices.isEmpty)
        var b = b0
        var out: [TraditionalCrawlStep] = []
        var seq = 0
        for _ in 0 ..< globalRounds {
            guard b + 3 <= maxFretInclusive else { break }
            appendAscendingBlock(
                strings: stringIndices,
                blockStart: b,
                capo: capo,
                seq: &seq,
                into: &out
            )
            if includeDescentPerBlock {
                appendDescendingBlock(
                    strings: stringIndices,
                    blockStart: b,
                    capo: capo,
                    seq: &seq,
                    into: &out
                )
            }
            b += 1
        }
        return out
    }

    private static func appendAscendingBlock(
        strings: [Int],
        blockStart b: Int,
        capo: Int,
        seq: inout Int,
        into out: inout [TraditionalCrawlStep]
    ) {
        for s in strings {
            for k in 0 ..< 4 {
                let f = b + k
                guard f <= maxFretInclusive else { return }
                let finger = k + 1
                let pitch = FretboardMath.labelForCell(stringIndex: s, fret: f, capo: capo)
                out.append(
                    TraditionalCrawlStep(
                        id: seq,
                        stringIndexFromBass: s,
                        fret: f,
                        finger: finger,
                        pitchLabelZh: pitch
                    )
                )
                seq += 1
            }
        }
    }

    private static func appendDescendingBlock(
        strings: [Int],
        blockStart b: Int,
        capo: Int,
        seq: inout Int,
        into out: inout [TraditionalCrawlStep]
    ) {
        for s in strings {
            for k in stride(from: 3, through: 0, by: -1) {
                let f = b + k
                guard f <= maxFretInclusive else { return }
                let finger = k + 1
                let pitch = FretboardMath.labelForCell(stringIndex: s, fret: f, capo: capo)
                out.append(
                    TraditionalCrawlStep(
                        id: seq,
                        stringIndexFromBass: s,
                        fret: f,
                        finger: finger,
                        pitchLabelZh: pitch
                    )
                )
                seq += 1
            }
        }
    }
}
