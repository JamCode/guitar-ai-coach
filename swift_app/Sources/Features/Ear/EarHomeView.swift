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
                        subtitle: "两音上行、四选一 · 不限题量 · 累计正确率",
                        systemImage: "play.circle"
                    ) { IntervalEarView() }
                    navCard(
                        title: "和弦听辨",
                        subtitle: "大三 / 小三 / 属七 / 七和弦 · 不限题量 · 即时判分 · 吉他采样",
                        systemImage: "pianokeys"
                    ) { EarMcqSessionView(title: "和弦听辨", bank: "A", chordDifficulty: .初级) }
                    navCard(
                        title: "和弦进行",
                        subtitle: "常见流行进行 · 四选一 · 不限题量 · 揭示后指法图",
                        systemImage: "music.note.list"
                    ) { EarMcqSessionView(title: "和弦进行", bank: "B") }
                    navCard(
                        title: "视唱训练",
                        subtitle: "模唱单音 / 模唱音程 · 可选音域 · 麦克风实时判定",
                        systemImage: "mic"
                    ) {
                        TabBarHiddenContainer {
                            SightSingingSessionView(
                                repository: LocalSightSingingRepository(),
                                pitchRange: "mid",
                                includeAccidental: false,
                                questionCount: 10,
                                pitchTracker: DefaultSightSingingPitchTracker(),
                                intervalPreview: IntervalTonePlayer(),
                                exerciseKind: .singleNoteMimic
                            )
                        }
                    }
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
