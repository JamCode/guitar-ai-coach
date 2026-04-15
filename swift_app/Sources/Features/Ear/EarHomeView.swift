import SwiftUI

public struct EarHomeView: View {
    public init() {}

    public var body: some View {
        List {
            Section("自由练习") {
                NavigationLink {
                    IntervalEarView()
                } label: {
                    earRow(
                        title: "音程识别",
                        subtitle: "两音上行、四选一",
                        systemImage: "play.circle"
                    )
                }
                NavigationLink {
                    EarMcqSessionView(title: "和弦听辨", bank: "A", totalQuestions: 10)
                } label: {
                    earRow(
                        title: "和弦听辨",
                        subtitle: "大三 / 小三 / 属七 · 题库离线 · 吉他采样合成",
                        systemImage: "pianokeys"
                    )
                }
                NavigationLink {
                    EarMcqSessionView(title: "和弦进行", bank: "B", totalQuestions: 10)
                } label: {
                    earRow(
                        title: "和弦进行",
                        subtitle: "常见流行进行 · 四选一",
                        systemImage: "music.note.list"
                    )
                }
                NavigationLink {
                    SightSingingSetupView()
                } label: {
                    earRow(
                        title: "视唱训练",
                        subtitle: "单音视唱 · 可选音域 · 麦克风实时判定",
                        systemImage: "mic"
                    )
                }
            }
        }
        .navigationTitle("练耳")
    }

    private func earRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
