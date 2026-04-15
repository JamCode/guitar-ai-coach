import SwiftUI

public struct TheoryView: View {
    public init() {}

    public var body: some View {
        List {
            section("音名与十二平均律", "吉他上每一品约等于半音。空弦标准调弦从粗到细为 E、A、D、G、B、E。熟悉自然音阶内各音的相对位置，是读谱与扒歌的基础。")
            section("音程（扒歌核心）", "两个音之间的距离称为音程。先练会：纯四度、纯五度、大三度、小三度、大七度、小七度等。")
            section("大调与小调色彩", "大三和弦明亮，小三和弦暗淡；属七和弦有要解决的张力。")
            section("节拍与分层聆听", "先分段循环，低速听低音与根音运动，再确认上层和声。")
        }
        .navigationTitle("初级乐理")
    }

    private func section(_ title: String, _ body: String) -> some View {
        Section(title) {
            Text(body)
        }
    }
}

