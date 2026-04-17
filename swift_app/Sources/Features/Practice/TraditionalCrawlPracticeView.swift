import SwiftUI
import Core

/// 工具页入口：展示「传统爬格子」推荐内容（调用 `TraditionalCrawlGenerator`）。
public struct TraditionalCrawlPracticeView: View {
    @State private var exercises: [TraditionalCrawlExercise] = []

    public init() {}

    public var body: some View {
        List {
            Section {
                Text(
                    "以下为经典「四指一格」半音型：每弦 1-2-3-4 指对应连续四品，弦序六弦→一弦；"
                        + "每走完一轮六根弦，把位整体上移一品再重复。"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section("推荐练习") {
                ForEach(exercises) { item in
                    NavigationLink {
                        TraditionalCrawlExerciseDetailView(exercise: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.titleZh).font(.headline)
                            Text(item.difficulty.subtitleZh)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Button("换一组把位建议") {
                    reload()
                }
            }
        }
        .navigationTitle("爬格子")
        .appNavigationBarChrome()
        .onAppear { reload() }
    }

    private func reload() {
        var rng = SystemRandomNumberGenerator()
        exercises = TraditionalCrawlGenerator.recommendedExercises(using: &rng)
    }
}

private struct TraditionalCrawlExerciseDetailView: View {
    let exercise: TraditionalCrawlExercise

    var body: some View {
        List {
            Section {
                Text(exercise.summaryZh).font(.body)
                Text(exercise.bpmHintZh)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !exercise.tipsZh.isEmpty {
                Section("练习要点") {
                    ForEach(Array(exercise.tipsZh.enumerated()), id: \.offset) { _, line in
                        Text("· \(line)")
                    }
                }
            }

            Section("步骤列表（\(exercise.steps.count) 步）") {
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
