import Core
import SwiftUI

/// 音阶训练推荐：调用 `ScaleTrainingGenerator` 生成初/中/高题目与步骤列表。
public struct ScaleTrainingPracticeView: View {
    @State private var exercises: [ScaleTrainingExercise] = []

    public init() {}

    public var body: some View {
        List {
            Section {
                Text(
                    "每条题目包含：调与音阶类型、Mi/Sol/La 指型（根音在六/五/四弦）、弹奏方向、"
                        + "节奏网格与 BPM 区间；下列为自动生成的练习序列（按步落指）。"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("推荐题目") {
                ForEach(exercises) { item in
                    NavigationLink {
                        ScaleTrainingExerciseDetailView(exercise: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.difficulty.rawValue) · \(item.keyName) · \(item.scaleKind.rawValue)")
                                .font(.headline)
                            Text(item.pattern.titleZh)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Button("换一组题目") { reload() }
            }
        }
        .navigationTitle("音阶训练")
        .appNavigationBarChrome()
        .onAppear { reload() }
    }

    private func reload() {
        var rng = SystemRandomNumberGenerator()
        exercises = ScaleTrainingGenerator.recommendedExercises(using: &rng)
    }
}

private struct ScaleTrainingExerciseDetailView: View {
    let exercise: ScaleTrainingExercise

    var body: some View {
        List {
            Section {
                Text(exercise.promptZh)
                    .font(.body)
                Text(exercise.bpmHintZh)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if exercise.retrogradeApplied {
                    Text("本组已应用整段反向演奏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !exercise.goalsZh.isEmpty {
                Section("训练目标") {
                    ForEach(Array(exercise.goalsZh.enumerated()), id: \.offset) { _, line in
                        Text("· \(line)")
                    }
                }
            }

            Section("规则标记") {
                Text("模进：\(exercise.allowsSequenceShift ? "允许" : "不允许")")
                Text("跳进：\(exercise.allowsDegreeLeap ? "允许" : "不允许")")
                Text("全弦覆盖：\(exercise.usesAllStrings ? "是" : "否")")
            }

            Section("步骤（\(exercise.steps.count) 音）") {
                ForEach(exercise.steps) { step in
                    Text(step.lineSummaryZh)
                        .font(.body.monospacedDigit())
                }
            }
        }
        .navigationTitle(exercise.difficulty.rawValue)
        .appNavigationBarChrome()
    }
}
