import Core
import SwiftUI

/// 和弦切换推荐练习：由 `ChordSwitchGenerator` 生成多组序列与 BPM 说明。
public struct ChordSwitchTrainingPracticeView: View {
    @State private var exercises: [ChordSwitchExercise] = []

    public init() {}

    public var body: some View {
        List {
            Section {
                Text(
                    "按难度自动组卷：每组内从左到右切换；BPM 与每和弦拍数为固定区间随机。"
                        + "具体品位可结合「和弦速查」查看。"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("推荐练习") {
                ForEach(exercises) { item in
                    NavigationLink {
                        ChordSwitchExerciseDetailView(exercise: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.difficulty.rawValue) · \(item.segments.count) 组")
                                .font(.headline)
                            Text(item.bpmHintZh)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Button("换一组") { reload() }
            }
        }
        .navigationTitle("和弦切换")
        .appNavigationBarChrome()
        .onAppear { reload() }
    }

    private func reload() {
        var rng = SystemRandomNumberGenerator()
        exercises = ChordSwitchGenerator.recommendedExercises(using: &rng)
    }
}

private struct ChordSwitchExerciseDetailView: View {
    let exercise: ChordSwitchExercise

    var body: some View {
        List {
            Section {
                Text(exercise.promptZh).font(.body)
                Text(exercise.bpmHintZh)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !exercise.goalsZh.isEmpty {
                Section("训练目标") {
                    ForEach(Array(exercise.goalsZh.enumerated()), id: \.offset) { _, line in
                        Text("· \(line)")
                    }
                }
            }

            Section("分组") {
                ForEach(Array(exercise.segments.enumerated()), id: \.offset) { i, seg in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("第 \(i + 1) 组").font(.subheadline.weight(.semibold))
                        Text(seg.summaryZh)
                            .font(.title3.monospaced())
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(exercise.difficulty.rawValue)
        .appNavigationBarChrome()
    }
}
