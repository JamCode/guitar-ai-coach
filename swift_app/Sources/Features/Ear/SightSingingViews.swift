import SwiftUI
import Core

/// 主反馈：目标音 vs 当前拾音的柱状对比（弱化时间–音分曲线，见 `docs/cursor/6c75954f/ui-ux.md`）。
private struct SightSingingPitchBarCompareView: View {
    let targetNotes: [String]
    let targetMidis: [Double]
    let userMidi: Double?

    private var midiRange: ClosedRange<Double> {
        guard !targetMidis.isEmpty else { return 58...74 }
        let tLo = targetMidis.min()!
        let tHi = targetMidis.max()!
        let u = userMidi
        var lo = min(tLo, u ?? tLo)
        var hi = max(tHi, u ?? tHi)
        lo -= 3
        hi += 3
        if hi - lo < 8 {
            let mid = (hi + lo) / 2
            lo = mid - 4
            hi = mid + 4
        }
        return lo...hi
    }

    private var lo: Double { midiRange.lowerBound }
    private var hi: Double { midiRange.upperBound }

    private var userCaption: String {
        guard let m = userMidi else { return "未拾音" }
        return PitchMath.midiToPitchLabel(Int(m.rounded()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("音高对比").appSectionTitle()
            Text("柱高为相对 MIDI（纵轴为音名刻度）；「你唱」随麦克风更新。")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)

            HStack(alignment: .bottom, spacing: 0) {
                yAxisStrip
                    .frame(width: 36)

                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(0..<targetNotes.count, id: \.self) { i in
                        barColumn(
                            headline: targetNotes.count > 1 ? "目标 \(i + 1)" : "目标",
                            caption: targetNotes[i],
                            midi: i < targetMidis.count ? targetMidis[i] : lo,
                            fill: SwiftAppTheme.muted.opacity(0.5),
                            isPlaceholder: false
                        )
                    }
                    barColumn(
                        headline: "你唱",
                        caption: userCaption,
                        midi: userMidi ?? lo,
                        fill: userMidi == nil ? SwiftAppTheme.line : SwiftAppTheme.brand,
                        isPlaceholder: userMidi == nil
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 190)

            legendRow
        }
    }

    private var yAxisStrip: some View {
        VStack {
            Text(PitchMath.midiToPitchLabel(Int(round(hi))))
                .font(.caption2)
            Spacer()
            Text(PitchMath.midiToPitchLabel(Int(round((hi + lo) / 2))))
                .font(.caption2)
            Spacer()
            Text(PitchMath.midiToPitchLabel(Int(round(lo))))
                .font(.caption2)
        }
        .foregroundStyle(SwiftAppTheme.muted)
        .frame(maxHeight: .infinity)
    }

    private var legendRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(SwiftAppTheme.brand)
                    .frame(width: 10, height: 10)
                Text("你唱")
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(SwiftAppTheme.muted.opacity(0.5))
                    .frame(width: 10, height: 10)
                Text("目标")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(SwiftAppTheme.muted)
    }

    @ViewBuilder
    private func barColumn(
        headline: String,
        caption: String,
        midi: Double,
        fill: Color,
        isPlaceholder: Bool
    ) -> some View {
        let span = max(hi - lo, 0.000_001)
        let barH: CGFloat = {
            if isPlaceholder {
                return 10
            }
            let t = (midi - lo) / span
            let u = CGFloat(min(1, max(0, t)))
            return max(14, 146 * u)
        }()

        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SwiftAppTheme.surfaceSoft)
                    .frame(width: 44, height: 150)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
                    .frame(width: 36, height: barH)
                    .opacity(isPlaceholder ? 0.45 : 1)
            }
            .frame(height: 150)

            Text(headline)
                .font(.caption2)
                .foregroundStyle(SwiftAppTheme.muted)

            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline)，\(caption)")
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

                    SightSingingPitchBarCompareView(
                        targetNotes: q.targetNotes,
                        targetMidis: viewModel.targetMidiDoubles(for: q),
                        userMidi: viewModel.currentHz.map { Double(PitchMath.frequencyToMidi($0)) }
                    )
                    .appCard()
                    .animation(.easeOut(duration: 0.12), value: viewModel.currentHz)

                    Group {
                        if let cents = viewModel.livePitchCents {
                            Text(String(format: "实时偏差（相对最近目标）：%+.0f ¢　·　100¢ ≈ 1 个半音", cents))
                        } else if viewModel.evaluating {
                            Text("判定收音中… 请持续发声，「你唱」柱高会随麦克风更新。")
                        } else {
                            Text("开唱后「你唱」柱会升高；与灰色目标柱越接近越好。")
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
                        Text("提示：音柱高度对应当前 MIDI；纵轴刻度为音名，便于对齐目标。")
                            .font(.caption)
                            .foregroundStyle(SwiftAppTheme.muted)
                        if viewModel.evaluating {
                            ProgressView().tint(SwiftAppTheme.brand)
                        }
                    }
                    .appCard()

                    // 底栏：示范（播完自动判）与下一题并列（见 docs/cursor/6c75954f/ui-ux.md §6）。
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 10) {
                            Button {
                                Task { await viewModel.playPreviewAndEvaluate() }
                            } label: {
                                VStack(spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                        Text(viewModel.evaluating ? "判定中…" : (viewModel.previewing ? "示范中…" : "示范"))
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    Text(viewModel.evaluating ? "请持续发声" : "播完约 \(evaluateSeconds) 秒自动判")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SwiftAppTheme.brand)
                            .disabled(viewModel.evaluating || viewModel.previewing)

                            Button {
                                Task {
                                    if await viewModel.nextOrFinish() { showResult = true }
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "forward.end.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text(
                                        infinite
                                            ? "下一题"
                                            : (q.index >= q.totalQuestions ? "结果" : "下一题")
                                    )
                                    .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text("换题")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.bordered)
                            .tint(SwiftAppTheme.brand)
                            .disabled(viewModel.evaluating || viewModel.previewing)
                        }
                        if let hint = viewModel.evaluateUserHint {
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(
                            infinite || q.index < q.totalQuestions
                                ? "点「示范」听示范后将自动判定；「下一题」可跳过本题不计分。"
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()

                        VStack(alignment: .leading, spacing: 0) {
                            Text("训练模式").appSectionTitle()
                                .padding(.bottom, 6)
                            ForEach(Array(SightSingingExerciseKind.allCases.enumerated()), id: \.element) { index, kind in
                                if index > 0 {
                                    Divider()
                                }
                                SightSingingSettingsChoiceRow(
                                    title: kind.titleZh,
                                    selected: settingsDraft.exerciseKind == kind
                                ) {
                                    settingsDraft.exerciseKind = kind
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()

                        VStack(alignment: .leading, spacing: 0) {
                            Text("音域").appSectionTitle()
                                .padding(.bottom, 6)
                            ForEach(Array(SightSingingPitchRangeOption.allCases.enumerated()), id: \.element) { index, option in
                                if index > 0 {
                                    Divider()
                                }
                                SightSingingSettingsChoiceRow(
                                    title: option.titleZh,
                                    selected: settingsDraft.pitchRange == option.rawValue
                                ) {
                                    settingsDraft.pitchRange = option.rawValue
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()

                        Text("保存后从下一题起按新设置随机出题；并写入本机，下次打开自动沿用。")
                            .font(.footnote)
                            .foregroundStyle(SwiftAppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(SwiftAppTheme.pagePadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .appPageBackground()
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

// MARK: - 出题设置：卡片内全宽单选行（方案 C，无弹出菜单）

private enum SightSingingPitchRangeOption: String, CaseIterable {
    case low
    case mid
    case wide

    fileprivate var titleZh: String {
        switch self {
        case .low:
            return "低音区 C3-B3"
        case .mid:
            return "中音区 C4-B4"
        case .wide:
            return "宽范围 C3-B4"
        }
    }
}

private struct SightSingingSettingsChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? SwiftAppTheme.brand : SwiftAppTheme.muted)
                Text(title)
                    .font(.body)
                    .foregroundStyle(SwiftAppTheme.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
