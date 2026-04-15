import SwiftUI
import Core

struct ChordPracticeSessionView: View {
    let task: PracticeTask
    let store: PracticeSessionStore
    let config: ChordPracticeConfig

    @Environment(\.dismiss) private var dismiss

    @State private var startedAt: Date?
    @State private var elapsedSeconds: Int = 0
    @State private var running: Bool = false

    @State private var showFinishSheet: Bool = false
    @State private var noteText: String = ""

    @State private var showLeaveConfirm: Bool = false
    @State private var showNeedStartHint: Bool = false
    @State private var savingError: String?
    @State private var savedToast: Bool = false

    @State private var chordSymbolToPresent: String?

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                FlowLayout(spacing: 8, runSpacing: 6) {
                    ForEach(Array(config.resolvedChords.enumerated()), id: \.offset) { idx, chord in
                        chordButton(chord: chord, index: idx)
                    }
                }
                Text("点击和弦名查看指法")
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                Text(config.complexity.fullLabel)
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            .appCard()

            Spacer()

            Text(formatDurationLocal(elapsedSeconds))
                .font(.system(size: 54, weight: .semibold, design: .rounded))
                .foregroundStyle(SwiftAppTheme.text)
                .monospacedDigit()

            HStack(spacing: 12) {
                if !running {
                    Button("开始") { start() }
                        .appPrimaryButton()
                } else {
                    Button("暂停") { pause() }
                        .appSecondaryButton()
                }

                Button("结束") { finishTapped() }
                    .buttonStyle(.bordered)
                    .tint(SwiftAppTheme.brandSoft)
            }

            Spacer()
        }
        .padding(SwiftAppTheme.pagePadding)
        .navigationTitle("\(config.progression.name) · \(config.key) 调")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showLeaveConfirm = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .onReceive(ticker) { _ in
            guard running else { return }
            elapsedSeconds += 1
        }
        .alert("离开练习？", isPresented: $showLeaveConfirm) {
            Button("继续练习", role: .cancel) {}
            Button("放弃返回", role: .destructive) { dismiss() }
        } message: {
            Text("当前练习尚未保存，确定要返回吗？")
        }
        .alert("先开始练习再结束哦", isPresented: $showNeedStartHint) {
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
        .chordQuickReferenceSheet(chordSymbolToPresent: $chordSymbolToPresent)
        .appPageBackground()
    }

    private func chordButton(chord: String, index: Int) -> some View {
        Button {
            chordSymbolToPresent = chord
        } label: {
            Text(chord)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.brand)
                .underline(true, color: SwiftAppTheme.brand.opacity(0.35))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("会话和弦 \(chord) \(index + 1)")
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
        pause()
        showFinishSheet = true
    }

    @MainActor
    private func save(result: PracticeFinishResult) async {
        guard let startedAt else { return }
        do {
            try await store.saveSession(
                task: task,
                startedAt: startedAt,
                endedAt: Date(),
                durationSeconds: elapsedSeconds,
                completed: result.completed,
                difficulty: result.difficulty,
                note: result.note,
                progressionId: config.progression.id,
                musicKey: config.key,
                complexity: config.complexity.rawValue,
                rhythmPatternId: nil
            )
            savedToast = true
        } catch {
            savingError = String(describing: error)
        }
    }
}

private func formatDurationLocal(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let m = String(format: "%02d", s / 60)
    let r = String(format: "%02d", s % 60)
    return "\(m):\(r)"
}

