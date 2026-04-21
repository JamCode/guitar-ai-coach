import SwiftUI
import Core

/// 爬格子热身：随机题卡；难度在齿轮内选择（与节奏扫弦一致）。不含页面内计时器。
struct ScaleWarmupSessionView: View {
    let task: PracticeTask
    let store: PracticeSessionStore

    @Environment(\.dismiss) private var dismiss

    @AppStorage("practice.scaleWarmup.difficultyRaw") private var difficultyRaw: String = ScaleWarmupDifficulty.初级.rawValue

    @State private var drill: ScaleWarmupDrill = ScaleWarmupGenerator.drills(for: .初级)[0]
    @State private var openedAt: Date = Date()

    @State private var showSettings: Bool = false
    @State private var showFinishSheet: Bool = false
    @State private var noteText: String = ""

    @State private var savingError: String?
    @State private var savedToast: Bool = false

    private var selectedDifficulty: ScaleWarmupDifficulty {
        ScaleWarmupDifficulty(rawValue: difficultyRaw) ?? .初级
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(task.description)
                    .foregroundStyle(SwiftAppTheme.text)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("本组练习")
                            .appSectionTitle()
                        Spacer()
                        Text(selectedDifficulty.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SwiftAppTheme.brand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(SwiftAppTheme.brandSoft)
                            .clipShape(Capsule())
                    }
                    Text(drill.titleLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(drill.detailLine)
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.text)
                        .lineLimit(3)
                    Text(drill.tip)
                        .font(.footnote)
                        .foregroundStyle(SwiftAppTheme.muted)
                    Text("每次进入或点「下一组」会按当前难度随机抽题卡；可与外置节拍器同练，本页不含音频节拍器。")
                        .font(.footnote)
                        .foregroundStyle(SwiftAppTheme.muted)
                }
                .appCard()

                Button("下一组") { nextDrill() }
                    .appSecondaryButton()
                    .frame(maxWidth: .infinity)

                Button("保存记录") { showFinishSheet = true }
                    .appPrimaryButton()
                    .frame(maxWidth: .infinity)
            }
            .padding(SwiftAppTheme.pagePadding)
        }
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("练习设置")
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("难度") {
                        Picker("难度", selection: Binding(
                            get: { ScaleWarmupDifficulty(rawValue: difficultyRaw) ?? .初级 },
                            set: { difficultyRaw = $0.rawValue }
                        )) {
                            ForEach(ScaleWarmupDifficulty.allCases) { lv in
                                Text(lv.rawValue).tag(lv)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("选择后会立即按该难度抽取新的题卡。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("说明") {
                        Text(
                            """
                            题卡为常见爬格子热身示意（弦范围、品位、建议速度与轮数），请按自身手型微调。

                            本页不包含内置节拍器或音频，建议配合外置节拍器或慢速曲目练习。
                            """
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("练习设置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { showSettings = false }
                    }
                }
            }
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
                title: "本次练习",
                showCompletedGoal: false,
                noteText: $noteText,
                onCancel: { showFinishSheet = false },
                onSave: { result in
                    showFinishSheet = false
                    Task { await save(result: result) }
                }
            )
        }
        .appPageBackground()
        .onAppear {
            openedAt = Date()
            reshuffleDrill(excluding: nil)
        }
        .onChange(of: difficultyRaw) { _, _ in
            reshuffleDrill(excluding: nil)
        }
    }

    private func nextDrill() {
        reshuffleDrill(excluding: drill.id)
    }

    private func reshuffleDrill(excluding: String?) {
        var rng = SystemRandomNumberGenerator()
        drill = ScaleWarmupGenerator.nextDrill(
            difficulty: selectedDifficulty,
            excluding: excluding,
            using: &rng
        )
    }

    @MainActor
    private func save(result: PracticeFinishResult) async {
        do {
            try await store.saveSession(
                task: task,
                startedAt: openedAt,
                endedAt: Date(),
                durationSeconds: 0,
                completed: result.completed,
                difficulty: result.difficulty,
                note: result.note,
                progressionId: nil,
                musicKey: nil,
                complexity: nil,
                rhythmPatternId: nil,
                scaleWarmupDrillId: drill.id
            )
            savedToast = true
        } catch {
            savingError = String(describing: error)
        }
    }
}
