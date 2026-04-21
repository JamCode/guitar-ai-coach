import Foundation

/// 与节奏扫弦一致的三档中文难度（rawValue 用于 Picker 展示）。
enum ScaleWarmupDifficulty: String, CaseIterable, Identifiable {
    case 初级, 中级, 高级

    var id: String { rawValue }
}

/// 指板上的一个弹奏步（TAB：弦号 1=① 在最上行 … 6=⑥ 在最下行）。
struct ScaleWarmupStep: Equatable, Sendable {
    /// 1…6，对应 ①…⑥。
    let stringNumber: Int
    let fret: Int
    /// 格内显示顺序，从 1 递增。
    let order: Int
}

/// 单次随机题卡（可持久化 `id` 到练习记录）。
struct ScaleWarmupDrill: Equatable, Sendable {
    let id: String
    let stringsLabel: String
    let fretLabel: String
    let patternLabel: String
    let suggestedBpm: Int
    let roundsHint: String
    let tip: String

    /// 参与高亮的弦号集合（1=① … 6=⑥），升序。
    let stringsIncluded: [Int]
    let fretStart: Int
    let fretEnd: Int

    /// 格内编号顺序（方案 3）。「往返」题型仅标上行半段，下行见 `sequenceBullets`。
    let orderedSteps: [ScaleWarmupStep]

    /// 「练习顺序」列表文案（方案 1）。
    let sequenceBullets: [String]

    var titleLine: String { "\(stringsLabel) · \(fretLabel)" }
    var detailLine: String { "\(patternLabel) · 建议 \(suggestedBpm) BPM · \(roundsHint)" }
}

enum ScaleWarmupGenerator {
    /// 暴露给测试：各难度静态池（至少 2 条/档，便于去重测试）。
    static func drills(for difficulty: ScaleWarmupDifficulty) -> [ScaleWarmupDrill] {
        switch difficulty {
        case .初级:
            return [
                makeDrill(
                    id: "crawl_b_6_4_68",
                    stringsLabel: "⑥–④弦",
                    fretLabel: "1–4 品",
                    stringsPlayLowToHigh: [6, 5, 4],
                    fretRange: 1 ... 4,
                    patternLabel: "半音四品型（上行）",
                    suggestedBpm: 68,
                    roundsHint: "建议 4 轮",
                    tip: "力度均匀，换品时贴弦减少杂音。",
                    isRoundTrip: false
                ),
                makeDrill(
                    id: "crawl_b_5_3_64",
                    stringsLabel: "⑤–③弦",
                    fretLabel: "1–3 品",
                    stringsPlayLowToHigh: [5, 4, 3],
                    fretRange: 1 ... 3,
                    patternLabel: "半音三品型（上行）",
                    suggestedBpm: 64,
                    roundsHint: "建议 3 轮",
                    tip: "左手保留指能留则留，减少跳指。",
                    isRoundTrip: false
                ),
            ]
        case .中级:
            return [
                makeDrill(
                    id: "crawl_m_6_6_80",
                    stringsLabel: "⑥–③弦",
                    fretLabel: "1–6 品",
                    stringsPlayLowToHigh: [6, 5, 4, 3],
                    fretRange: 1 ... 6,
                    patternLabel: "半音四品型（跨弦）",
                    suggestedBpm: 80,
                    roundsHint: "建议 5 轮",
                    tip: "换弦时拇指在琴颈后方稳定支撑。",
                    isRoundTrip: false
                ),
                makeDrill(
                    id: "crawl_m_6_8_84",
                    stringsLabel: "⑥–③弦",
                    fretLabel: "3–8 品",
                    stringsPlayLowToHigh: [6, 5, 4, 3],
                    fretRange: 3 ... 8,
                    patternLabel: "半音四品型（往返）",
                    suggestedBpm: 84,
                    roundsHint: "建议 4 轮",
                    tip: "下行同样控制音量，避免「砸」弦。",
                    isRoundTrip: true
                ),
            ]
        case .高级:
            return [
                makeDrill(
                    id: "crawl_a_6_12_96",
                    stringsLabel: "⑥–②弦",
                    fretLabel: "1–12 品",
                    stringsPlayLowToHigh: [6, 5, 4, 3, 2],
                    fretRange: 1 ... 12,
                    patternLabel: "半音四品型（全弦跨度）",
                    suggestedBpm: 96,
                    roundsHint: "建议 6 轮",
                    tip: "高把位注意指尖立起，避免蹭相邻弦。",
                    isRoundTrip: false
                ),
                makeDrill(
                    id: "crawl_a_6_12_100",
                    stringsLabel: "⑥–②弦",
                    fretLabel: "5–12 品",
                    stringsPlayLowToHigh: [6, 5, 4, 3, 2],
                    fretRange: 5 ... 12,
                    patternLabel: "半音四品型（把位平移）",
                    suggestedBpm: 100,
                    roundsHint: "建议 5 轮",
                    tip: "换把时先慢后快，优先干净再提速。",
                    isRoundTrip: false
                ),
            ]
        }
    }

    static func nextDrill(
        difficulty: ScaleWarmupDifficulty,
        excluding: String?,
        using rng: inout some RandomNumberGenerator
    ) -> ScaleWarmupDrill {
        let pool = drills(for: difficulty)
        let candidates = pool.filter { $0.id != excluding }
        let pickFrom = candidates.isEmpty ? pool : candidates
        let idx = pickFrom.indices.randomElement(using: &rng)!
        return pickFrom[idx]
    }

    // MARK: - Builders

    private static func makeDrill(
        id: String,
        stringsLabel: String,
        fretLabel: String,
        stringsPlayLowToHigh: [Int],
        fretRange: ClosedRange<Int>,
        patternLabel: String,
        suggestedBpm: Int,
        roundsHint: String,
        tip: String,
        isRoundTrip: Bool
    ) -> ScaleWarmupDrill {
        let stringsIncluded = stringsPlayLowToHigh.sorted()
        let steps = upSteps(stringsPlayLowToHigh: stringsPlayLowToHigh, fretRange: fretRange)
        let bullets = sequenceBullets(
            stringsLabel: stringsLabel,
            fretLabel: fretLabel,
            stringsPlayLowToHigh: stringsPlayLowToHigh,
            fretRange: fretRange,
            isRoundTrip: isRoundTrip
        )
        return ScaleWarmupDrill(
            id: id,
            stringsLabel: stringsLabel,
            fretLabel: fretLabel,
            patternLabel: patternLabel,
            suggestedBpm: suggestedBpm,
            roundsHint: roundsHint,
            tip: tip,
            stringsIncluded: stringsIncluded,
            fretStart: fretRange.lowerBound,
            fretEnd: fretRange.upperBound,
            orderedSteps: steps,
            sequenceBullets: bullets
        )
    }

    /// 从低音弦 → 高音弦（⑥→⑤→④ 即数组 [6,5,4]），每根弦上品位从低到高。
    private static func upSteps(stringsPlayLowToHigh: [Int], fretRange: ClosedRange<Int>) -> [ScaleWarmupStep] {
        var out: [ScaleWarmupStep] = []
        var order = 1
        for s in stringsPlayLowToHigh {
            for f in fretRange {
                out.append(ScaleWarmupStep(stringNumber: s, fret: f, order: order))
                order += 1
            }
        }
        return out
    }

    private static func sequenceBullets(
        stringsLabel: String,
        fretLabel: String,
        stringsPlayLowToHigh: [Int],
        fretRange: ClosedRange<Int>,
        isRoundTrip: Bool
    ) -> [String] {
        let low = fretRange.lowerBound
        let high = fretRange.upperBound
        let circle = stringsPlayLowToHigh.map(circleStringName).joined(separator: " → ")
        var lines: [String] = [
            "练习区域：\(stringsLabel)，\(fretLabel)。弦弹奏顺序（先 → 后）：\(circle)。",
            "每根弦上品位从低到高：\(low) 品 → \(high) 品（上行）。",
            "四指尽量一品一指；指尖立起，换弦时手腕放松。",
        ]
        if isRoundTrip {
            lines.append(
                "本题为「往返」：格内数字只标上行半段；下行请按相反顺序原路返回（\(high) 品 → \(low) 品），再换到上一根弦重复。"
            )
        }
        return lines
    }

    private static func circleStringName(_ n: Int) -> String {
        switch n {
        case 1: return "①"
        case 2: return "②"
        case 3: return "③"
        case 4: return "④"
        case 5: return "⑤"
        case 6: return "⑥"
        default: return "\(n)"
        }
    }
}
