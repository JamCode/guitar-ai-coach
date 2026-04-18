import SwiftUI
import Ear
import Core

struct TodayRecommendationListView: View {
    let sessions: [PracticeSession]
    let referenceDate: Date
    let initialIndex: Int
    private let historyStore: any RecommendationHistoryStore = UserDefaultsRecommendationHistoryStore()

    @State private var loading = true
    @State private var errorText: String?
    @State private var items: [TodayRecommendationItem] = []
    @State private var currentIndex: Int = 0

    init(sessions: [PracticeSession], referenceDate: Date = Date(), initialIndex: Int = 0) {
        self.sessions = sessions
        self.referenceDate = referenceDate
        self.initialIndex = max(0, initialIndex)
    }

    var body: some View {
        Group {
            if loading {
                ProgressView("生成今日推荐中…")
            } else if let errorText {
                VStack(spacing: 12) {
                    Text(errorText)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SwiftAppTheme.text)
                    Button("重试") { Task { await loadRecommendations() } }
                        .appPrimaryButton()
                }
                .padding(24)
            } else {
                recommendationFlow
            }
        }
        .navigationTitle(items.isEmpty ? "今日训练" : "今日训练 \(currentIndex + 1)/\(items.count)")
        .appPageBackground()
        .task { await loadRecommendations() }
    }

    @ViewBuilder
    private var recommendationFlow: some View {
        if items.isEmpty {
            VStack(spacing: 12) {
                Text("暂无推荐内容")
                    .foregroundStyle(SwiftAppTheme.muted)
                Button("重新生成") { Task { await loadRecommendations() } }
                    .appPrimaryButton()
            }
            .padding(24)
        } else {
            VStack(spacing: 0) {
                currentModuleBanner(item: items[currentIndex])
                destinationView(for: items[currentIndex])
                    .id("\(items[currentIndex].id)-\(currentIndex)")
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button("上一项") { moveToPrevious() }
                        .appSecondaryButton()
                        .disabled(currentIndex == 0)

                    Button("下一项") { moveToNext() }
                        .appPrimaryButton()
                        .disabled(currentIndex >= items.count - 1)
                }
                .padding(.horizontal, SwiftAppTheme.pagePadding)
                .padding(.vertical, 10)
                .background(SwiftAppTheme.bg)
            }
        }
    }

    @ViewBuilder
    private func destinationView(for item: TodayRecommendationItem) -> some View {
        switch item.payload {
        case .intervalQuestion:
            IntervalEarView(
                maxQuestions: 5,
                difficulty: mappedIntervalDifficulty(from: item.difficulty),
                onSessionComplete: { correct, answered in
                    Task {
                        await appendRecord(
                            module: .intervalEar,
                            successRate: answered == 0 ? 0 : Double(correct) / Double(answered),
                            durationSeconds: 300
                        )
                        await MainActor.run { moveToNext() }
                    }
                },
                autoDismissOnComplete: false
            )
        case let .chordQuestion(question):
            EarMcqSessionView(
                title: "和弦听辨",
                bank: question.mode,
                maxQuestions: 10,
                chordDifficulty: mappedChordDifficulty(from: item.difficulty),
                onSessionComplete: { correct, total in
                    Task {
                        await appendRecord(
                            module: .chordEar,
                            successRate: total == 0 ? 0 : Double(correct) / Double(total),
                            durationSeconds: 360
                        )
                        await MainActor.run { moveToNext() }
                    }
                },
                autoDismissOnComplete: false
            )
        case let .sightSingingConfig(pitchRange, includeAccidental, questionCount, exerciseKind):
            SightSingingSessionView(
                repository: LocalSightSingingRepository(),
                pitchRange: pitchRange,
                includeAccidental: includeAccidental,
                questionCount: questionCount,
                pitchTracker: DefaultSightSingingPitchTracker(),
                exerciseKind: exerciseKind,
                onSessionComplete: { result in
                    Task {
                        await appendRecord(
                            module: .sightSinging,
                            successRate: result.accuracy,
                            durationSeconds: max(300, result.total * 45)
                        )
                        await MainActor.run { moveToNext() }
                    }
                },
                autoDismissOnComplete: false
            )
        case let .chordSwitch(exercise):
            GeneratedPracticeDetailView(
                title: item.module.title,
                summary: item.summary,
                module: item.module,
                lines: [
                    "建议和弦序列：\(exercise.chords.joined(separator: " → "))",
                    "建议速度：\(exercise.bpm) BPM",
                    "保持每拍稳定换和弦。"
                ],
                onComplete: { duration in
                    Task {
                        await appendRecord(module: .chordSwitch, successRate: 1, durationSeconds: duration)
                        await MainActor.run { moveToNext() }
                    }
                }
            )
        case let .scaleTraining(exercise):
            GeneratedPracticeDetailView(
                title: item.module.title,
                summary: item.summary,
                module: item.module,
                lines: [
                    "调性：\(exercise.keyName)",
                    "音阶：\(exercise.modeName)",
                    "指型：\(exercise.patternName)",
                    "建议速度：\(exercise.bpm) BPM"
                ],
                onComplete: { duration in
                    Task {
                        await appendRecord(module: .scaleTraining, successRate: 1, durationSeconds: duration)
                        await MainActor.run { moveToNext() }
                    }
                }
            )
        case let .traditionalCrawl(exercise):
            GeneratedPracticeDetailView(
                title: item.module.title,
                summary: item.summary,
                module: item.module,
                lines: [
                    "起始把位：\(exercise.startFret) 品",
                    "推荐轮次：\(exercise.rounds) 轮",
                    "建议速度：\(exercise.bpm) BPM",
                    "按 1-2-3-4 指序完成每根弦。"
                ],
                onComplete: { duration in
                    Task {
                        await appendRecord(module: .traditionalCrawl, successRate: 1, durationSeconds: duration)
                        await MainActor.run { moveToNext() }
                    }
                }
            )
        }
    }

    private func mappedIntervalDifficulty(from level: RecommendationDifficultyLevel) -> IntervalEarDifficulty {
        switch level {
        case .beginner: return .初级
        case .intermediate: return .中级
        case .advanced: return .高级
        }
    }

    private func mappedChordDifficulty(from level: RecommendationDifficultyLevel) -> EarChordMcqDifficulty {
        switch level {
        case .beginner: return .初级
        case .intermediate: return .中级
        case .advanced: return .高级
        }
    }

    @MainActor
    private func loadRecommendations() async {
        loading = true
        errorText = nil
        let history = await historyStore.loadRecent(now: referenceDate, days: 7)
        let merged = RecommendationHistoryMerging.mergeLegacyPracticeRecords(stored: history, sessions: sessions)
        var planner = TodayRecommendationPlanner(referenceDate: referenceDate)
        items = await planner.buildRecommendations(historyRecords: merged)
        currentIndex = min(max(0, initialIndex), max(0, items.count - 1))
        loading = false
    }

    @MainActor
    private func moveToNext() {
        guard !items.isEmpty else { return }
        currentIndex = min(items.count - 1, currentIndex + 1)
    }

    @MainActor
    private func moveToPrevious() {
        guard !items.isEmpty else { return }
        currentIndex = max(0, currentIndex - 1)
    }

    private func appendRecord(module: RecommendationModuleType, successRate: Double, durationSeconds: Int) async {
        await historyStore.append(
            RecommendationHistoryRecord(
                module: module,
                completed: true,
                successRate: max(0, min(1, successRate)),
                durationSeconds: max(30, durationSeconds),
                occurredAt: Date()
            )
        )
    }

    @ViewBuilder
    private func currentModuleBanner(item: TodayRecommendationItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.module.icon)
                .foregroundStyle(SwiftAppTheme.brand)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.module.title)
                    .font(.headline)
                    .foregroundStyle(SwiftAppTheme.text)
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            Spacer()
        }
        .appCard()
        .padding(.horizontal, SwiftAppTheme.pagePadding)
        .padding(.top, 8)
    }
}

private struct GeneratedPracticeDetailView: View {
    let title: String
    let summary: String
    let module: RecommendationModuleType
    let lines: [String]
    let onComplete: (Int) -> Void
    @State private var appearedAt: Date = Date()
    @State private var recorded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .appCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("训练内容")
                        .appSectionTitle()
                    ForEach(lines, id: \.self) { line in
                        Text("• \(line)")
                            .foregroundStyle(SwiftAppTheme.text)
                    }
                }
                .appCard()

                Button(recorded ? "已记录完成" : "完成并记录到历史") {
                    let duration = max(60, Int(Date().timeIntervalSince(appearedAt)))
                    onComplete(duration)
                    recorded = true
                }
                .appPrimaryButton()
                .disabled(recorded)
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .onAppear { appearedAt = Date() }
        .navigationTitle(title)
        .appPageBackground()
    }
}
