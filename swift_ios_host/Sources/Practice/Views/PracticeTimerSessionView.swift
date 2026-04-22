import SwiftUI
import Core
import Practice

struct PracticeTimerSessionView: View {
    let task: PracticeTask
    let store: PracticeSessionStore

    @Environment(\.dismiss) private var dismiss

    @State private var startedAt: Date?
    @State private var elapsedSeconds: Int = 0
    @State private var running: Bool = false

    @State private var showFinishSheet: Bool = false
    @State private var noteText: String = ""

    @State private var showNeedStartHint: Bool = false
    @State private var showMinDurationHint: Bool = false
    @State private var savingError: String?
    @State private var savedToast: Bool = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Text(task.description)
                .foregroundStyle(SwiftAppTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Text(formatDuration(elapsedSeconds))
                .font(.system(size: 54, weight: .semibold, design: .rounded))
                .foregroundStyle(SwiftAppTheme.text)
                .monospacedDigit()

            HStack(spacing: 12) {
                Button("开始") { start() }
                    .appPrimaryButton()
                    .disabled(running)

                Button("暂停") { pause() }
                    .appSecondaryButton()
                    .disabled(!running)

                Button("结束") { finishTapped() }
                    .buttonStyle(.bordered)
                    .tint(SwiftAppTheme.brandSoft)
            }

            Spacer()
        }
        .padding(SwiftAppTheme.pagePadding)
        .navigationTitle(task.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("返回")
            }
        }
        .onReceive(ticker) { _ in
            guard running else { return }
            elapsedSeconds += 1
        }
        .alert("先开始练习再结束哦", isPresented: $showNeedStartHint) {
            Button("知道了", role: .cancel) {}
        }
        .alert(
            "至少练习 \(PracticeRecordingPolicy.minForegroundSecondsToPersist) 秒才会记入练习统计",
            isPresented: $showMinDurationHint
        ) {
            Button("知道了", role: .cancel) {}
        }
        .alert("保存失败", isPresented: Binding(get: { savingError != nil }, set: { if !$0 { savingError = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(savingError ?? "")
        }
        .alert("记录已保存", isPresented: $savedToast) {
            Button("返回", role: .cancel) { dismiss() }
        }
        .sheet(isPresented: $showFinishSheet) {
            PracticeFinishDialog(
                title: "本次练习完成",
                showCompletedGoal: true,
                noteText: $noteText,
                onCancel: { showFinishSheet = false },
                onSave: { result in
                    showFinishSheet = false
                    Task { await save(result: result) }
                }
            )
        }
        .appPageBackground()
    }

    private func start() {
        guard !running else { return }
        startedAt = startedAt ?? Date()
        running = true
    }

    private func pause() {
        running = false
    }

    private func finishTapped() {
        guard elapsedSeconds > 0 else {
            showNeedStartHint = true
            return
        }
        guard elapsedSeconds >= PracticeRecordingPolicy.minForegroundSecondsToPersist else {
            showMinDurationHint = true
            return
        }
        pause()
        showFinishSheet = true
    }

    @MainActor
    private func save(result: PracticeFinishResult) async {
        guard let startedAt else { return }
        guard elapsedSeconds >= PracticeRecordingPolicy.minForegroundSecondsToPersist else { return }
        do {
            try await store.saveSession(
                task: task,
                startedAt: startedAt,
                endedAt: Date(),
                durationSeconds: elapsedSeconds,
                completed: result.completed,
                difficulty: result.difficulty,
                note: result.note,
                progressionId: nil,
                musicKey: nil,
                complexity: nil,
                rhythmPatternId: nil,
                scaleWarmupDrillId: nil
            )
            savedToast = true
        } catch {
            savingError = String(describing: error)
        }
    }
}

private func formatDuration(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let m = String(format: "%02d", s / 60)
    let r = String(format: "%02d", s % 60)
    return "\(m):\(r)"
}

