import ChordChart
import Chords
import Core
import Practice
import SwiftUI

struct ChordPracticeConfig: Equatable {
    /// 宿主练琴「和弦切换」唯一出题来源：`swift_app` 的 `ChordSwitchGenerator`。
    let exercise: ChordSwitchExercise
}

/// 和弦切换：与 Tools 一致，使用 `ChordSwitchGenerator` 自动组卷（初 / 中 / 高各一条）。
struct ChordPracticeSelectionView: View {
    let task: PracticeTask
    let store: PracticeSessionStore

    @State private var exercises: [ChordSwitchExercise] = []

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text(
                        "按难度自动组卷：每组内从左到右切换；BPM 与每和弦拍数为固定区间随机。"
                            + "题目由 `ChordSwitchGenerator` 生成，与工具箱「和弦切换」一致。"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Section("推荐练习") {
                    ForEach(exercises) { item in
                        NavigationLink {
                            TabBarHiddenContainer {
                                ChordPracticeSessionView(
                                    task: task,
                                    store: store,
                                    config: ChordPracticeConfig(exercise: item)
                                )
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(item.segments.count) 组")
                                        .font(.headline)
                                    Text(item.bpmHintZh)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(item.difficulty.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SwiftAppTheme.brand)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(SwiftAppTheme.brandSoft)
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    Button("换一组") { reload() }
                }
            }
        }
        .navigationTitle("和弦切换练习")
        .navigationBarTitleDisplayMode(.inline)
        .appPageBackground()
        .onAppear { reload() }
    }

    private func reload() {
        var rng = SystemRandomNumberGenerator()
        exercises = ChordSwitchGenerator.recommendedExercises(using: &rng)
    }
}
