import Foundation

/// 与节奏扫弦一致的三档中文难度（rawValue 用于 Picker 展示）。
enum ScaleWarmupDifficulty: String, CaseIterable, Identifiable {
    case 初级, 中级, 高级

    var id: String { rawValue }
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

    var titleLine: String { "\(stringsLabel) · \(fretLabel)" }
    var detailLine: String { "\(patternLabel) · 建议 \(suggestedBpm) BPM · \(roundsHint)" }
}

enum ScaleWarmupGenerator {
    /// 暴露给测试：各难度静态池（至少 2 条/档，便于去重测试）。
    static func drills(for difficulty: ScaleWarmupDifficulty) -> [ScaleWarmupDrill] {
        switch difficulty {
        case .初级:
            return [
                ScaleWarmupDrill(
                    id: "crawl_b_6_4_68",
                    stringsLabel: "⑥–④弦",
                    fretLabel: "1–4 品",
                    patternLabel: "半音四品型（上行）",
                    suggestedBpm: 68,
                    roundsHint: "建议 4 轮",
                    tip: "力度均匀，换品时贴弦减少杂音。"
                ),
                ScaleWarmupDrill(
                    id: "crawl_b_5_3_64",
                    stringsLabel: "⑤–③弦",
                    fretLabel: "1–3 品",
                    patternLabel: "半音三品型（上行）",
                    suggestedBpm: 64,
                    roundsHint: "建议 3 轮",
                    tip: "左手保留指能留则留，减少跳指。"
                ),
            ]
        case .中级:
            return [
                ScaleWarmupDrill(
                    id: "crawl_m_6_6_80",
                    stringsLabel: "⑥–③弦",
                    fretLabel: "1–6 品",
                    patternLabel: "半音四品型（跨弦）",
                    suggestedBpm: 80,
                    roundsHint: "建议 5 轮",
                    tip: "换弦时拇指在琴颈后方稳定支撑。"
                ),
                ScaleWarmupDrill(
                    id: "crawl_m_6_8_84",
                    stringsLabel: "⑥–③弦",
                    fretLabel: "3–8 品",
                    patternLabel: "半音四品型（往返）",
                    suggestedBpm: 84,
                    roundsHint: "建议 4 轮",
                    tip: "下行同样控制音量，避免「砸」弦。"
                ),
            ]
        case .高级:
            return [
                ScaleWarmupDrill(
                    id: "crawl_a_6_12_96",
                    stringsLabel: "⑥–②弦",
                    fretLabel: "1–12 品",
                    patternLabel: "半音四品型（全弦跨度）",
                    suggestedBpm: 96,
                    roundsHint: "建议 6 轮",
                    tip: "高把位注意指尖立起，避免蹭相邻弦。"
                ),
                ScaleWarmupDrill(
                    id: "crawl_a_6_12_100",
                    stringsLabel: "⑥–②弦",
                    fretLabel: "5–12 品",
                    patternLabel: "半音四品型（把位平移）",
                    suggestedBpm: 100,
                    roundsHint: "建议 5 轮",
                    tip: "换把时先慢后快，优先干净再提速。"
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
}
