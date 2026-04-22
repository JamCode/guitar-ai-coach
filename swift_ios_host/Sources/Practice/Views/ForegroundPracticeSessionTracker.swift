import SwiftUI
import Core
import Practice

private enum ForegroundPracticeSessionMinimum {
    static let secondsToRecord: TimeInterval = 3
}

/// 包裹子页面：在用户停留期间按 **前台** 时间累加，离开时写入 `PracticeLocalStore`（与「我的谱」详情一致语义）。
struct ForegroundPracticeSessionTracker<Content: View>: View {
    let task: PracticeTask
    let note: String?
    @ViewBuilder var content: () -> Content

    @Environment(\.scenePhase) private var scenePhase

    @State private var didAppear = false
    @State private var foregroundSegmentStartedAt: Date?
    @State private var accumulatedForegroundSeconds: TimeInterval = 0

    private let store: PracticeSessionStore = PracticeLocalStore()

    var body: some View {
        content()
            .onAppear {
                didAppear = true
                if scenePhase == .active {
                    resumeForegroundClockIfEligible()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    resumeForegroundClockIfEligible()
                case .inactive, .background:
                    pauseForegroundClock()
                @unknown default:
                    pauseForegroundClock()
                }
            }
            .onDisappear {
                pauseForegroundClock()
                guard didAppear else { return }
                let durationSeconds = Int(accumulatedForegroundSeconds.rounded(.down))
                guard durationSeconds >= Int(ForegroundPracticeSessionMinimum.secondsToRecord) else { return }
                Task {
                    let endedAt = Date()
                    let startedAt = endedAt.addingTimeInterval(-Double(durationSeconds))
                    try? await store.saveSession(
                        task: task,
                        startedAt: startedAt,
                        endedAt: endedAt,
                        durationSeconds: durationSeconds,
                        completed: true,
                        difficulty: 3,
                        note: note,
                        progressionId: nil,
                        musicKey: nil,
                        complexity: nil,
                        rhythmPatternId: nil,
                        scaleWarmupDrillId: nil
                    )
                }
            }
    }

    private func pauseForegroundClock() {
        guard let start = foregroundSegmentStartedAt else { return }
        accumulatedForegroundSeconds += Date().timeIntervalSince(start)
        foregroundSegmentStartedAt = nil
    }

    private func resumeForegroundClockIfEligible() {
        guard foregroundSegmentStartedAt == nil else { return }
        foregroundSegmentStartedAt = Date()
    }
}
