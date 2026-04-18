import SwiftUI
import Core

private struct SightSingingPitchGraphView: View {
    let user: [SightSingingPitchGraphPoint]
    let targetLow: [SightSingingPitchGraphPoint]
    let targetHigh: [SightSingingPitchGraphPoint]
    /// When false, only the first target pitch is meaningful (single-note mimic).
    let showsTwoTargetPitches: Bool

    private let yRange: ClosedRange<Double> = -50 ... 50

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("音准曲线（相对目标音）")
                .appSectionTitle()

            Canvas { context, size in
                let w = size.width
                let h = size.height
                let padL: CGFloat = 34
                let padR: CGFloat = 10
                let padT: CGFloat = 10
                let padB: CGFloat = 18
                let plotW = w - padL - padR
                let plotH = h - padT - padB

                func y(forCents cents: Double) -> CGFloat {
                    let t = (cents - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)
                    return padT + plotH * (1 - CGFloat(t))
                }

                // Background
                context.fill(
                    Path(
                        CGRect(x: padL, y: padT, width: plotW, height: plotH)
                    ),
                    with: .color(SwiftAppTheme.surfaceSoft)
                )

                // Grid: 0 line + +/-25
                for cents in [-25.0, 0.0, 25.0] {
                    var p = Path()
                    p.move(to: CGPoint(x: padL, y: y(forCents: cents)))
                    p.addLine(to: CGPoint(x: padL + plotW, y: y(forCents: cents)))
                    context.stroke(
                        p,
                        with: .color(cents == 0 ? SwiftAppTheme.line : SwiftAppTheme.line.opacity(0.55)),
                        lineWidth: cents == 0 ? 1.2 : 0.8
                    )
                }

                let nowT = max(
                    user.last?.t ?? 0,
                    targetLow.last?.t ?? 0,
                    targetHigh.last?.t ?? 0,
                    0.000_001
                )
                let t0 = max(0, nowT - 6)

                func x(forT t: Double) -> CGFloat {
                    let u = (t - t0) / max(0.000_001, (nowT - t0))
                    return padL + plotW * CGFloat(u)
                }

                func strokeSeries(_ pts: [SightSingingPitchGraphPoint], color: Color, lineWidth: CGFloat) {
                    guard pts.count >= 2 else { return }
                    var p = Path()
                    let sorted = pts.sorted { $0.t < $1.t }
                    p.move(to: CGPoint(x: x(forT: sorted[0].t), y: y(forCents: sorted[0].cents)))
                    for pt in sorted.dropFirst() {
                        p.addLine(to: CGPoint(x: x(forT: pt.t), y: y(forCents: pt.cents)))
                    }
                    context.stroke(p, with: .color(color), lineWidth: lineWidth)
                }

                strokeSeries(targetLow, color: SwiftAppTheme.muted.opacity(0.85), lineWidth: 2)
                if showsTwoTargetPitches {
                    strokeSeries(targetHigh, color: SwiftAppTheme.muted.opacity(0.55), lineWidth: 2)
                }
                strokeSeries(user, color: SwiftAppTheme.brand, lineWidth: 3)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 12) {
                legendDot(color: SwiftAppTheme.brand, text: "你唱的音高")
                if showsTwoTargetPitches {
                    legendDot(color: SwiftAppTheme.muted.opacity(0.85), text: "目标第 1 个音")
                    legendDot(color: SwiftAppTheme.muted.opacity(0.55), text: "目标第 2 个音")
                } else {
                    legendDot(color: SwiftAppTheme.muted.opacity(0.85), text: "目标音（0¢ 参考线）")
                }
            }
            .font(.caption)
            .foregroundStyle(SwiftAppTheme.muted)
        }
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
        }
    }
}

public struct SightSingingSetupView: View {
    @State private var pitchRange = "mid"
    @State private var includeAccidental = false
    @State private var questionCount = 0.0
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

                    Text(questionCount <= 0 ? "题量：不限（无限刷题）" : "题量：\(Int(questionCount)) 题")
                        .foregroundStyle(SwiftAppTheme.text)
                    Slider(value: $questionCount, in: 0...20, step: 5)
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
    @State private var showEndConfirm = false
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
                    let isIntervalQuestion = q.targetNotes.count >= 2
                    let segments = max(1, q.targetNotes.count)
                    let evaluateSeconds = segments * 2
                    let infinite = q.totalQuestions <= 0

                    SightSingingPitchGraphView(
                        user: viewModel.userPitchGraph,
                        targetLow: viewModel.targetLowGraph,
                        targetHigh: viewModel.targetHighGraph,
                        showsTwoTargetPitches: isIntervalQuestion
                    )
                    .appCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isIntervalQuestion ? "目标音程（上行）" : "目标音").appSectionTitle()
                        if isIntervalQuestion {
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
                        Text("提示：曲线纵轴为音分偏差（±50¢），横轴为最近 6 秒。")
                            .font(.caption)
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
                            Text("本题结果").appSectionTitle()
                            HStack(spacing: 12) {
                                Text("得分 \(score.score.formatted(.number.precision(.fractionLength(1)))) / 10")
                                    .foregroundStyle(SwiftAppTheme.text)
                                Text("偏差 \(score.avgCentsAbs.formatted(.number.precision(.fractionLength(1))))¢")
                                    .foregroundStyle(SwiftAppTheme.muted)
                                Text("稳定 \(score.stableHitMs) ms")
                                    .foregroundStyle(SwiftAppTheme.muted)
                            }
                            .font(.subheadline)

                            Button(infinite ? "下一题" : (q.index >= q.totalQuestions ? "查看结果" : "下一题")) {
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
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button("结束") {
                    showEndConfirm = true
                }
                .disabled(viewModel.loading || viewModel.evaluating)
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                Button("结束") {
                    showEndConfirm = true
                }
                .disabled(viewModel.loading || viewModel.evaluating)
            }
            #endif
        }
        .task {
            if viewModel.loading {
                await viewModel.bootstrap()
            }
        }
        .onDisappear {
            // Leaving the screen should not keep mic sampling / preview graph tasks alive.
            viewModel.cancelActiveWork(stopPitchTracker: !viewModel.loading)
        }
        .confirmationDialog("结束训练？", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("结束并查看统计", role: .destructive) {
                Task {
                    if await viewModel.endTraining() {
                        showResult = true
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("点右上角「结束」会统计本轮已判定题目；不限题量时不会自动收尾。")
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
