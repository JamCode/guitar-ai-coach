import SwiftUI
import Core

public struct SightSingingSetupView: View {
    @State private var pitchRange = "mid"
    @State private var includeAccidental = false
    @State private var questionCount = 10.0
    @State private var exerciseKind: SightSingingExerciseKind = .singleNoteMimic

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("训练模式").appSectionTitle()
                    Picker("训练模式", selection: $exerciseKind) {
                        ForEach(SightSingingExerciseKind.allCases) { kind in
                            Text(kind.titleZh).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("音域选择").appSectionTitle()
                    Picker("音域", selection: $pitchRange) {
                        Text("低音区 C3-B3").tag("low")
                        Text("中音区 C4-B4").tag("mid")
                        Text("宽范围 C3-B4").tag("wide")
                    }
                    .pickerStyle(.segmented)

                    Toggle("包含升降号", isOn: $includeAccidental)

                    Text("题量：\(Int(questionCount)) 题")
                        .foregroundStyle(SwiftAppTheme.text)
                    Slider(value: $questionCount, in: 5...20, step: 5)
                        .tint(SwiftAppTheme.brand)
                }
                .appCard()

                NavigationLink {
                    SightSingingSessionView(
                        repository: LocalSightSingingRepository(),
                        pitchRange: pitchRange,
                        includeAccidental: includeAccidental,
                        questionCount: Int(questionCount),
                        pitchTracker: DefaultSightSingingPitchTracker(),
                        exerciseKind: exerciseKind
                    )
                } label: {
                    HStack {
                        Image(systemName: "music.note")
                        Text("开始训练")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    .foregroundStyle(SwiftAppTheme.text)
                    .appCard()
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("视唱训练")
        .appPageBackground()
    }
}

public struct SightSingingSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SightSingingSessionViewModel
    @State private var showResult = false
    private let onSessionComplete: ((SightSingingResult) -> Void)?
    private let autoDismissOnComplete: Bool

    public init(
        repository: SightSingingRepository,
        pitchRange: String,
        includeAccidental: Bool,
        questionCount: Int,
        pitchTracker: SightSingingPitchTracking,
        intervalPreview: IntervalTonePlaying? = IntervalTonePlayer(),
        exerciseKind: SightSingingExerciseKind,
        onSessionComplete: ((SightSingingResult) -> Void)? = nil,
        autoDismissOnComplete: Bool = true
    ) {
        _viewModel = StateObject(
            wrappedValue: SightSingingSessionViewModel(
                repository: repository,
                pitchTracker: pitchTracker,
                intervalPreview: intervalPreview,
                pitchRange: pitchRange,
                includeAccidental: includeAccidental,
                questionCount: questionCount,
                exerciseKind: exerciseKind
            )
        )
        self.onSessionComplete = onSessionComplete
        self.autoDismissOnComplete = autoDismissOnComplete
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.loading {
                    ProgressView("加载中…")
                        .tint(SwiftAppTheme.brand)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                } else if let error = viewModel.errorText {
                    Text(error).foregroundStyle(.red).appCard()
                } else if let q = viewModel.question {
                    let segments = max(1, q.targetNotes.count)
                    let evaluateSeconds = segments * 2
                    VStack(alignment: .leading, spacing: 10) {
                        Text("第 \(q.index) / \(q.totalQuestions) 题")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SwiftAppTheme.text)
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(q.targetNotes.count >= 2 ? "目标音程（上行）" : "目标音").appSectionTitle()
                        if q.targetNotes.count >= 2 {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(q.targetNotes[0])
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(SwiftAppTheme.text)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(SwiftAppTheme.muted)
                                Text(q.targetNotes[1])
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(SwiftAppTheme.text)
                            }
                            Text("请按顺序模唱：先低音，再高音（判定会自动分段采样）")
                                .font(.footnote)
                                .foregroundStyle(SwiftAppTheme.muted)
                        } else {
                            Text(q.targetNotes.first ?? "--")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(SwiftAppTheme.text)
                        }
                        let current = viewModel.currentHz.map {
                            PitchMath.midiToNoteName(PitchMath.frequencyToMidi($0))
                        } ?? "--"
                        Text("当前检测：\(current)")
                            .foregroundStyle(SwiftAppTheme.muted)
                        if viewModel.evaluating {
                            ProgressView().tint(SwiftAppTheme.brand)
                        }
                    }
                    .appCard()

                    Button {
                        Task { await viewModel.playPreview() }
                    } label: {
                        HStack {
                            Image(systemName: "speaker.wave.2")
                            Text("播放示范")
                            Spacer()
                        }
                    }
                    .appSecondaryButton()
                    .disabled(viewModel.evaluating || viewModel.previewing)

                    Button(viewModel.evaluating ? "判定中…" : "开始判定（\(evaluateSeconds) 秒）") {
                        Task { await viewModel.evaluate() }
                    }
                    .appPrimaryButton()
                    .disabled(viewModel.evaluating || viewModel.previewing)

                    if let score = viewModel.lastScore {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("结果").appSectionTitle()
                            Text("单题得分 \(score.score.formatted(.number.precision(.fractionLength(1)))) / 10")
                                .foregroundStyle(SwiftAppTheme.text)
                            Text("平均偏差 \(score.avgCentsAbs.formatted(.number.precision(.fractionLength(1)))) cent")
                                .foregroundStyle(SwiftAppTheme.muted)
                            Text("稳定命中 \(score.stableHitMs) ms")
                                .foregroundStyle(SwiftAppTheme.muted)
                            Button(q.index >= q.totalQuestions ? "查看结果" : "下一题") {
                                Task {
                                    if await viewModel.nextOrFinish() { showResult = true }
                                }
                            }
                            .appPrimaryButton()
                        }
                        .appCard()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("视唱训练")
        .appPageBackground()
        .task {
            if viewModel.loading {
                await viewModel.bootstrap()
            }
        }
        .alert("本轮完成", isPresented: $showResult) {
            Button("确定") {
                if let result = viewModel.finalResult {
                    onSessionComplete?(result)
                }
                if autoDismissOnComplete {
                    dismiss()
                }
            }
        } message: {
            Text(viewModel.resultText ?? "训练完成")
        }
    }
}
