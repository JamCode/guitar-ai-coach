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

                func clampCents(_ cents: Double) -> Double {
                    min(max(cents, yRange.lowerBound), yRange.upperBound)
                }

                func strokeSeries(_ pts: [SightSingingPitchGraphPoint], color: Color, lineWidth: CGFloat) {
                    guard pts.count >= 2 else { return }
                    var p = Path()
                    let sorted = pts.sorted { $0.t < $1.t }
                    p.move(to: CGPoint(x: x(forT: sorted[0].t), y: y(forCents: clampCents(sorted[0].cents))))
                    for pt in sorted.dropFirst() {
                        p.addLine(to: CGPoint(x: x(forT: pt.t), y: y(forCents: clampCents(pt.cents))))
                    }
                    context.stroke(p, with: .color(color), lineWidth: lineWidth)
                }

                strokeSeries(targetLow, color: SwiftAppTheme.muted.opacity(0.85), lineWidth: 2)
                if showsTwoTargetPitches {
                    strokeSeries(targetHigh, color: SwiftAppTheme.muted.opacity(0.55), lineWidth: 2)
                }
                strokeSeries(user, color: SwiftAppTheme.brand, lineWidth: 3)

                // 单点或最新采样：画「船头」圆点，方便一眼看到当前偏差位置。
                let sortedUser = user.sorted { $0.t < $1.t }
                if let pt = sortedUser.last {
                    let cx = x(forT: pt.t)
                    let cy = y(forCents: clampCents(pt.cents))
                    let r: CGFloat = 5
                    let dot = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                    context.fill(dot, with: .color(SwiftAppTheme.brand))
                    context.stroke(dot, with: .color(Color.white.opacity(0.35)), lineWidth: 1)
                }
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
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("进入后立刻出题；点右上角齿轮可设置音域、升降号、训练模式与题量。设置会保存，下次自动沿用。")
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)

                NavigationLink {
                    SightSingingSessionView()
                } label: {
                    HStack {
                        Image(systemName: "music.note")
                        Text("开始视唱训练")
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
    @State private var showSettings = false
    @State private var settingsDraft = SightSingingStoredPreferences.defaultPreferences

    private let onSessionComplete: ((SightSingingResult) -> Void)?
    private let autoDismissOnComplete: Bool

    public init(
        repository: SightSingingRepository = LocalSightSingingRepository(),
        pitchRange: String? = nil,
        includeAccidental: Bool? = nil,
        questionCount: Int? = nil,
        pitchTracker: SightSingingPitchTracking = DefaultSightSingingPitchTracker(),
        intervalPreview: IntervalTonePlaying? = IntervalTonePlayer(),
        exerciseKind: SightSingingExerciseKind? = nil,
        onSessionComplete: ((SightSingingResult) -> Void)? = nil,
        autoDismissOnComplete: Bool = true
    ) {
        let stored = SightSingingPreferencesStore.load()
        let merged = SightSingingStoredPreferences(
            pitchRange: pitchRange ?? stored.pitchRange,
            includeAccidental: includeAccidental ?? stored.includeAccidental,
            questionCount: questionCount ?? stored.questionCount,
            exerciseKind: exerciseKind ?? stored.exerciseKind
        )
        _settingsDraft = State(initialValue: merged)
        self.onSessionComplete = onSessionComplete
        self.autoDismissOnComplete = autoDismissOnComplete
        _viewModel = StateObject(
            wrappedValue: SightSingingSessionViewModel(
                repository: repository,
                pitchTracker: pitchTracker,
                intervalPreview: intervalPreview,
                pitchRange: merged.pitchRange,
                includeAccidental: merged.includeAccidental,
                questionCount: max(0, merged.questionCount),
                exerciseKind: merged.exerciseKind
            )
        )
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
                    .animation(.easeOut(duration: 0.12), value: viewModel.userPitchGraph.count)

                    Group {
                        if let cents = viewModel.livePitchCents {
                            Text(String(format: "实时偏差（相对目标）：%+.0f ¢　·　100¢ ≈ 1 个半音", cents))
                        } else if viewModel.evaluating {
                            Text("判定收音中… 请持续发声，曲线会随麦克风更新。")
                        } else {
                            Text("开唱后橙色曲线会动态延伸；越接近 0¢ 参考线越准。")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)

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

                    // 方案 B：底栏三栏（示范 | 判定 | 下一题），中间为主 CTA、两侧图标+短标签。
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 8) {
                            Button {
                                Task { await viewModel.playPreview() }
                            } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                    Text("示范")
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.bordered)
                            .tint(SwiftAppTheme.brand)
                            .disabled(viewModel.evaluating || viewModel.previewing)
                            .frame(width: 76)

                            Button {
                                Task { await viewModel.evaluate() }
                            } label: {
                                VStack(spacing: 3) {
                                    Text(viewModel.evaluating ? "判定中…" : "开始判定")
                                        .font(.subheadline.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.85)
                                    if !viewModel.evaluating {
                                        Text("\(evaluateSeconds) 秒")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SwiftAppTheme.brand)
                            .disabled(viewModel.evaluating || viewModel.previewing)
                            .layoutPriority(1)

                            Button {
                                Task {
                                    if await viewModel.nextOrFinish() { showResult = true }
                                }
                            } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: "forward.end.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                    Text(
                                        infinite
                                            ? "下一题"
                                            : (q.index >= q.totalQuestions ? "结果" : "下一题")
                                    )
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.bordered)
                            .tint(SwiftAppTheme.brand)
                            .disabled(viewModel.evaluating || viewModel.previewing)
                            .frame(width: 76)
                        }
                        Text(
                            infinite || q.index < q.totalQuestions
                                ? "「下一题」可跳过本题，不计入得分。"
                                : "末题点「结果」查看本轮统计。"
                        )
                            .font(.caption2)
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous)
                            .fill(SwiftAppTheme.surfaceSoft)
                    )

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
            // 保留系统返回按钮与边缘右滑 pop（勿 `navigationBarBackButtonHidden`，否则会禁用 interactive pop）。
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    settingsDraft = viewModel.currentPreferences()
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(viewModel.loading || viewModel.evaluating)
            }
            #else
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    Task {
                        await viewModel.discardSessionSilently()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(viewModel.loading || viewModel.evaluating)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    settingsDraft = viewModel.currentPreferences()
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(viewModel.loading || viewModel.evaluating)
            }
            #endif
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    // Toggle/Slider 置顶，两个 Picker 分节置底，减轻菜单浮层压住下方可点控件。
                    Section {
                        Toggle("包含升降号", isOn: $settingsDraft.includeAccidental)
                        Text(settingsDraft.questionCount <= 0 ? "题量：不限（无限刷题）" : "题量：\(settingsDraft.questionCount) 题")
                            .foregroundStyle(SwiftAppTheme.text)
                        Slider(
                            value: Binding(
                                get: { Double(settingsDraft.questionCount) },
                                set: { settingsDraft.questionCount = Int($0) }
                            ),
                            in: 0...20,
                            step: 5
                        )
                        .tint(SwiftAppTheme.brand)
                    }

                    // 与 `ChordLookupView` 一致：标题在 Picker 外 + `.pickerStyle(.menu)` + 横向拉满，避免 Form 内默认 Picker 命中区偏窄。
                    Section {
                        settingsMenuPickerRow(title: "训练模式") {
                            Picker("训练模式", selection: $settingsDraft.exerciseKind) {
                                ForEach(SightSingingExerciseKind.allCases) { kind in
                                    Text(kind.titleZh).tag(kind)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Section {
                        settingsMenuPickerRow(title: "音域") {
                            Picker("音域", selection: $settingsDraft.pitchRange) {
                                Text("低音区 C3-B3").tag("low")
                                Text("中音区 C4-B4").tag("mid")
                                Text("宽范围 C3-B4").tag("wide")
                            }
                            .pickerStyle(.menu)
                        }
                    } footer: {
                        Text("保存后从下一题起按新设置随机出题；并写入本机，下次打开自动沿用。")
                            .font(.footnote)
                    }
                }
                .navigationTitle("出题设置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            showSettings = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            Task {
                                await viewModel.persistAndApplyPreferences(settingsDraft)
                                showSettings = false
                            }
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.bootstrapIfNeeded()
        }
        .onDisappear {
            viewModel.cancelActiveWork(stopPitchTracker: true)
            Task {
                await viewModel.discardSessionSilently()
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

// MARK: - 出题设置 menu 行（对齐 `ChordLookupView.chordMenuRow`）

private extension SightSingingSessionView {
    @ViewBuilder
    func settingsMenuPickerRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
