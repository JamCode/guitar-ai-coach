import Foundation

public struct ChordChartEntry: Identifiable, Hashable {
    public let id: String
    public let symbol: String
    public let frets: [Int]
    public let theory: String
    public let voicing: String?

    public init(symbol: String, frets: [Int], theory: String, voicing: String? = nil) {
        self.id = symbol + frets.map(String.init).joined(separator: "_")
        self.symbol = symbol
        self.frets = frets
        self.theory = theory
        self.voicing = voicing
    }
}

public struct ChordChartSection: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let intro: String
    public let entries: [ChordChartEntry]

    public init(title: String, intro: String, entries: [ChordChartEntry]) {
        self.id = title
        self.title = title
        self.intro = intro
        self.entries = entries
    }
}

public enum ChordChartData {
    public static let sections: [ChordChartSection] = [
        ChordChartSection(
            title: "初级 · 开放把位",
            intro: "以空弦与低把位为主，先稳定换和弦与右手节奏。",
            entries: [
                ChordChartEntry(symbol: "C", frets: [-1, 3, 2, 0, 1, 0], theory: "大三和弦（根-大三度-纯五度）", voicing: "开放 C，5 弦起根音。"),
                ChordChartEntry(symbol: "G", frets: [3, 2, 0, 0, 0, 3], theory: "大三和弦；与 C、D 等组成流行进行。", voicing: "开放 G，6 弦与 1 弦双根音。"),
                ChordChartEntry(symbol: "D", frets: [-1, -1, 0, 2, 3, 2], theory: "大三和弦；大调 II 或属功能准备时常用。", voicing: "开放 D，4 弦起根音。"),
                ChordChartEntry(symbol: "A", frets: [-1, 0, 2, 2, 2, 0], theory: "大三和弦；大调 IV 或属前属位置常见。", voicing: "开放 A，5 弦根音。"),
                ChordChartEntry(symbol: "E", frets: [0, 2, 2, 1, 0, 0], theory: "大三和弦；摇滚 I 级常用开放位。", voicing: "开放 E，6 弦根音。"),
                ChordChartEntry(symbol: "Am", frets: [-1, 0, 2, 2, 1, 0], theory: "小三和弦；常作 vi 级。", voicing: "开放 Am。"),
                ChordChartEntry(symbol: "Em", frets: [0, 2, 2, 0, 0, 0], theory: "小三和弦；自然小调 i。", voicing: "开放 Em。"),
                ChordChartEntry(symbol: "Dm", frets: [-1, -1, 0, 2, 3, 1], theory: "小三和弦；小调下属色彩。", voicing: "开放 Dm。"),
                ChordChartEntry(symbol: "F", frets: [-1, -1, 3, 2, 1, 1], theory: "大三和弦；入门常用简化小横按。", voicing: "简化 F（4～1 弦）。")
            ]
        ),
        ChordChartSection(
            title: "中级 · 横按与七和弦、挂留",
            intro: "掌握 E 型/A 型可移动后，同一手型可弹 12 个调。",
            entries: [
                ChordChartEntry(symbol: "F", frets: [1, 3, 3, 2, 1, 1], theory: "大三和弦；E 型大横按模板。", voicing: "全横按 F，可整体上下移调。"),
                ChordChartEntry(symbol: "Bm", frets: [-1, 2, 4, 4, 3, 2], theory: "小三和弦；A 型小横按。", voicing: "A 型小横按（Bm）。"),
                ChordChartEntry(symbol: "C7", frets: [-1, 3, 2, 3, 1, 0], theory: "属七，解决到 F 的倾向强。", voicing: "开放 C7。"),
                ChordChartEntry(symbol: "G7", frets: [3, 2, 0, 0, 0, 1], theory: "属七；终止式 V7→I 核心色彩。", voicing: "开放 G7。"),
                ChordChartEntry(symbol: "D7", frets: [-1, -1, 0, 2, 1, 2], theory: "属七；布鲁斯链中常见。", voicing: "开放 D7。"),
                ChordChartEntry(symbol: "E7", frets: [0, 2, 0, 1, 0, 0], theory: "属七；摇滚语汇。", voicing: "开放 E7。"),
                ChordChartEntry(symbol: "A7", frets: [-1, 0, 2, 0, 2, 0], theory: "属七；与 D、E 等调搭配。", voicing: "开放 A7。"),
                ChordChartEntry(symbol: "Am7", frets: [-1, 0, 2, 0, 1, 0], theory: "小七，柔和抒情色彩。", voicing: "开放 Am7。"),
                ChordChartEntry(symbol: "Dm7", frets: [-1, -1, 0, 2, 1, 1], theory: "ii7–V7–I 中常见 ii7。", voicing: "开放 Dm7。"),
                ChordChartEntry(symbol: "Em7", frets: [0, 2, 2, 0, 3, 0], theory: "小七；伴奏铺底常用。", voicing: "开放 Em7。"),
                ChordChartEntry(symbol: "Cmaj7", frets: [-1, 3, 2, 0, 0, 0], theory: "大七，明亮爵士色彩。", voicing: "开放 Cmaj7。"),
                ChordChartEntry(symbol: "Gmaj7", frets: [3, 2, 0, 0, 0, 2], theory: "大七；抒情常见。", voicing: "开放 Gmaj7。"),
                ChordChartEntry(symbol: "Asus4", frets: [-1, 0, 2, 2, 3, 0], theory: "挂四；常解决回 A 大三。", voicing: "开放 Asus4。"),
                ChordChartEntry(symbol: "Dsus4", frets: [-1, -1, 0, 2, 3, 3], theory: "挂四；英伦流行高频。", voicing: "开放 Dsus4。")
            ]
        ),
        ChordChartSection(
            title: "高级 · 色彩、转位与扩展",
            intro: "增、减、加九与 slash 低音改变低音线走向。",
            entries: [
                ChordChartEntry(symbol: "B7", frets: [-1, 2, 1, 2, 0, 2], theory: "属七；E 大调中的 V7。", voicing: "开放 B7。"),
                ChordChartEntry(symbol: "Bm7", frets: [-1, 2, 4, 2, 3, 2], theory: "小七；ii7 可移动型。", voicing: "A 弦根小七型。"),
                ChordChartEntry(symbol: "Cadd9", frets: [-1, 3, 2, 0, 3, 0], theory: "大三加九度，流行抒情常用。", voicing: "开放 Cadd9。"),
                ChordChartEntry(symbol: "Edim", frets: [0, 1, 2, 1, 2, 1], theory: "减三和弦，色彩紧张。", voicing: "开放 Edim。"),
                ChordChartEntry(symbol: "Eaug", frets: [0, 3, 2, 1, 1, 0], theory: "增三和弦，对称色彩强。", voicing: "开放 Eaug。"),
                ChordChartEntry(symbol: "G/B", frets: [-1, 2, 0, 0, 0, 3], theory: "Slash 低音为 B，第一转位。", voicing: "G 第一转位。"),
                ChordChartEntry(symbol: "D/F#", frets: [2, -1, 0, 2, 3, 2], theory: "Slash 低音 #F，walking bass 常见。", voicing: "D 第一转位。"),
                ChordChartEntry(symbol: "C/G", frets: [3, 3, 2, 0, 1, 0], theory: "Slash 低音 G，踏板低音常见。", voicing: "C 第二转位。")
            ]
        )
    ]
}

