import SwiftUI


struct FocusedEarHubView: View {
    @State private var state: AdaptiveEarAbilityState = .initial
    @State private var loaded = false
    private let store: AdaptiveEarTrainingStoring = UserDefaultsAdaptiveEarTrainingStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("选择要强化的题型")
                    .font(.headline)
                    .foregroundStyle(SwiftAppTheme.text)
                Text("每道题的结果都会计入你的听力值")
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .padding(.bottom, 4)

                typeCard(
                    kind: .interval,
                    icon: "play.circle",
                    color: Color(red: 0.26, green: 0.57, blue: 0.98),
                    description: "听两音选音程"
                )
                typeCard(
                    kind: .chord,
                    icon: "pianokeys",
                    color: Color(red: 0.92, green: 0.27, blue: 0.21),
                    description: "大三 / 小三 / 属七 / 大七 / 小七"
                )
                typeCard(
                    kind: .progression,
                    icon: "music.note.list",
                    color: Color(red: 0.20, green: 0.65, blue: 0.33),
                    description: "常见流行进行，四选一"
                )
                typeCard(
                    kind: .singleNote,
                    icon: "speaker.wave.2",
                    color: Color(red: 0.98, green: 0.74, blue: 0.02),
                    description: "标准音 A4 参考，四选一"
                )
                typeCard(
                    kind: .rhythm,
                    icon: "metronome",
                    color: Color(red: 0.85, green: 0.35, blue: 0.75),
                    description: "4/4 拍一小节，听节奏选谱例"
                )
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("专项训练")
        .appPageBackground()
        .task {
            state = await store.loadState()
            loaded = true
        }
    }

    private func typeCard(kind: AdaptiveEarQuestionKind, icon: String, color: Color, description: String) -> some View {
        NavigationLink {
            TabBarHiddenContainer {
                FocusedEarTrainingSessionView(kind: kind)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(state.rating(for: kind).rounded()))")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(SwiftAppTheme.brand)
                        .monospacedDigit()
                    Text("听力值")
                        .font(.caption2)
                        .foregroundStyle(SwiftAppTheme.muted)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            .appCard()
        }
        .buttonStyle(.plain)
    }
}
