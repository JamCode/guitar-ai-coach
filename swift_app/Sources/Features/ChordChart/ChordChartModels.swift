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
            title: "1. 基础三和弦（最核心、必学）",
            intro: "3 个音构成，稳定、实用，是绝大多数歌曲的和声基础。",
            entries: [
                ChordChartEntry(symbol: "C", frets: [-1, 3, 2, 0, 1, 0], theory: "大三和弦（1-3-5）；明亮稳定。", voicing: "开放 C，5 弦根音。"),
                ChordChartEntry(symbol: "G", frets: [3, 2, 0, 0, 0, 3], theory: "大三和弦（1-3-5）；流行进行高频。", voicing: "开放 G，6/1 弦双根音。"),
                ChordChartEntry(symbol: "Am", frets: [-1, 0, 2, 2, 1, 0], theory: "小三和弦（1-b3-5）；柔和抒情。", voicing: "开放 Am。"),
                ChordChartEntry(symbol: "Em", frets: [0, 2, 2, 0, 0, 0], theory: "小三和弦（1-b3-5）；常见小调主和弦。", voicing: "开放 Em。"),
                ChordChartEntry(symbol: "Edim", frets: [0, 1, 2, 0, 2, 0], theory: "减三和弦（1-b3-b5）；紧张、导向性强。", voicing: "开放 Edim。"),
                ChordChartEntry(symbol: "Eaug", frets: [0, 3, 2, 1, 1, 0], theory: "增三和弦（1-3-#5）；梦幻且不稳定。", voicing: "开放 Eaug。")
            ]
        ),
        ChordChartSection(
            title: "2. 七和弦（流行歌灵魂）",
            intro: "在三和弦上加入第七音，情绪层次明显提升。",
            entries: [
                ChordChartEntry(symbol: "Cmaj7", frets: [-1, 3, 2, 0, 0, 0], theory: "大七（1-3-5-7）；温柔、高级。", voicing: "开放 Cmaj7。"),
                ChordChartEntry(symbol: "Gmaj7", frets: [3, 2, 0, 0, 0, 2], theory: "大七；抒情常用。", voicing: "开放 Gmaj7。"),
                ChordChartEntry(symbol: "Am7", frets: [-1, 0, 2, 0, 1, 0], theory: "小七（1-b3-5-b7）；忧郁流行。", voicing: "开放 Am7。"),
                ChordChartEntry(symbol: "Dm7", frets: [-1, -1, 0, 2, 1, 1], theory: "小七；ii-V-I 常见 ii。", voicing: "开放 Dm7。"),
                ChordChartEntry(symbol: "G7", frets: [3, 2, 0, 0, 0, 1], theory: "属七（1-3-5-b7）；强烈解决感。", voicing: "开放 G7。"),
                ChordChartEntry(symbol: "C7", frets: [-1, 3, 2, 3, 1, 0], theory: "属七；蓝调/摇滚常见。", voicing: "开放 C7。"),
                ChordChartEntry(symbol: "Bm7b5", frets: [-1, 2, 3, 2, 3, -1], theory: "半减七（1-b3-b5-b7）；悲伤爵士色彩。", voicing: "5～2 弦紧凑按法。"),
                ChordChartEntry(symbol: "Cdim7", frets: [-1, 3, 4, 2, 4, -1], theory: "减七（1-b3-b5-bb7）；紧张且常用于转调。", voicing: "5～2 弦对称按法。")
            ]
        ),
        ChordChartSection(
            title: "3. 挂留和弦（现代感最强）",
            intro: "没有三音，听感悬空、干净，现代流行编配高频使用。",
            entries: [
                ChordChartEntry(symbol: "Asus4", frets: [-1, 0, 2, 2, 3, 0], theory: "sus4（1-4-5）；常回到 A。", voicing: "开放 Asus4。"),
                ChordChartEntry(symbol: "Dsus4", frets: [-1, -1, 0, 2, 3, 3], theory: "sus4；流行扫弦常见。", voicing: "开放 Dsus4。"),
                ChordChartEntry(symbol: "Asus2", frets: [-1, 0, 2, 2, 0, 0], theory: "sus2（1-2-5）；清澈开放。", voicing: "开放 Asus2。"),
                ChordChartEntry(symbol: "Dsus2", frets: [-1, -1, 0, 2, 3, 0], theory: "sus2；木吉他编配高频。", voicing: "开放 Dsus2。")
            ]
        ),
        ChordChartSection(
            title: "4. 加音和弦（温暖、空灵）",
            intro: "在原和弦性质不变的前提下增加色彩音，适合抒情与氛围伴奏。",
            entries: [
                ChordChartEntry(symbol: "Cadd9", frets: [-1, 3, 2, 0, 3, 0], theory: "add9；最常用加音和弦之一。", voicing: "开放 Cadd9。"),
                ChordChartEntry(symbol: "Gadd9", frets: [3, 0, 0, 2, 0, 3], theory: "add9；明亮宽阔。", voicing: "开放 Gadd9。"),
                ChordChartEntry(symbol: "Cadd6", frets: [-1, 3, 2, 2, 1, 0], theory: "add6；温暖复古。", voicing: "开放 Cadd6。"),
                ChordChartEntry(symbol: "C6", frets: [-1, 3, 2, 2, 1, 0], theory: "6 和弦（1-3-5-6）；流行/爵士常用。", voicing: "开放 C6。"),
                ChordChartEntry(symbol: "Am6", frets: [-1, 0, 2, 2, 1, 2], theory: "小六和弦（1-b3-5-6）；空灵细腻。", voicing: "开放 Am6。")
            ]
        ),
        ChordChartSection(
            title: "5. 延伸和弦（九和弦以上）",
            intro: "基于七和弦继续叠加 9/11/13，常见于 Jazz、R&B、Soul 与高级流行。",
            entries: [
                ChordChartEntry(symbol: "C9", frets: [-1, 3, 2, 3, 3, -1], theory: "9 和弦；属功能上加 9 度色彩。", voicing: "5～2 弦紧凑按法。"),
                ChordChartEntry(symbol: "Cm9", frets: [3, 1, 3, 3, 3, 3], theory: "小九和弦；柔和且深邃。", voicing: "6 弦根横按。"),
                ChordChartEntry(symbol: "G9", frets: [3, -1, 3, 4, 3, -1], theory: "9 和弦；蓝调与 Funk 常见。", voicing: "6～3 弦根部按法。"),
                ChordChartEntry(symbol: "C11", frets: [-1, 3, 3, 3, 1, 1], theory: "11 和弦；开放而悬浮。", voicing: "5 弦根延伸按法。"),
                ChordChartEntry(symbol: "G13", frets: [3, -1, 3, 4, 5, -1], theory: "13 和弦；厚实且具律动感。", voicing: "6 弦根紧凑按法。")
            ]
        ),
        ChordChartSection(
            title: "6. 变化和弦（色彩强烈）",
            intro: "在属和弦上做升降变化，张力强、个性鲜明，常用于过渡与调味。",
            entries: [
                ChordChartEntry(symbol: "E7b9", frets: [0, 2, 0, 1, 0, 1], theory: "7b9；经典紧张感。", voicing: "开放 E7b9。"),
                ChordChartEntry(symbol: "E7#9", frets: [0, 2, 0, 1, 3, 3], theory: "7#9；布鲁斯/摇滚标志音色。", voicing: "Hendrix 常用按法。"),
                ChordChartEntry(symbol: "C7#11", frets: [-1, 3, 2, 3, 2, 0], theory: "7#11；Lydian dominant 味道。", voicing: "开放 C7#11。"),
                ChordChartEntry(symbol: "C7b5", frets: [-1, 3, 2, 3, 0, 1], theory: "7b5；不稳定、导向性强。", voicing: "开放 C7b5。")
            ]
        )
    ]
}

