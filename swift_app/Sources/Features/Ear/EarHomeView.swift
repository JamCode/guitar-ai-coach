import SwiftUI
import Core

public struct EarHomeView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("自由练习")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                VStack(spacing: 8) {
                    navCard(
                        title: "音程识别",
                        subtitle: "两音上行、四选一",
                        systemImage: "play.circle"
                    ) { IntervalEarView() }
                    navCard(
                        title: "和弦听辨",
                        subtitle: "大三 / 小三 / 属七 / 七和弦 · 按难度程序化出题 · 吉他采样合成",
                        systemImage: "pianokeys"
                    ) { EarMcqSessionView(title: "和弦听辨", bank: "A", totalQuestions: 10, chordDifficulty: .初级) }
                    navCard(
                        title: "和弦进行",
                        subtitle: "常见流行进行 · 四选一",
                        systemImage: "music.note.list"
                    ) { EarMcqSessionView(title: "和弦进行", bank: "B", totalQuestions: 10) }
                    navCard(
                        title: "视唱训练",
                        subtitle: "单音视唱 · 可选音域 · 麦克风实时判定",
                        systemImage: "mic"
                    ) { SightSingingSetupView() }
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("练耳")
        .appPageBackground()
    }

    private func navCard<Destination: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(SwiftAppTheme.brand)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            .appCard()
        }
    }
}
