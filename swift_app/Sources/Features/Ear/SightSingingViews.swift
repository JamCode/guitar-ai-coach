import SwiftUI
import Core

public struct SightSingingSetupView: View {
    @State private var pitchRange = "mid"
    @State private var includeAccidental = false
    @State private var questionCount = 10.0

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
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
                        pitchTracker: DefaultSightSingingPitchTracker()
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

    public init(
        repository: SightSingingRepository,
        pitchRange: String,
        includeAccidental: Bool,
        questionCount: Int,
        pitchTracker: SightSingingPitchTracking
    ) {
        _viewModel = StateObject(
            wrappedValue: SightSingingSessionViewModel(
                repository: repository,
                pitchTracker: pitchTracker,
                pitchRange: pitchRange,
                includeAccidental: includeAccidental,
                questionCount: questionCount
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("第 \(q.index) / \(q.totalQuestions) 题")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SwiftAppTheme.text)
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("目标音").appSectionTitle()
                        Text(q.targetNotes.first ?? "--")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(SwiftAppTheme.text)
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

                    Button(viewModel.evaluating ? "判定中…" : "开始判定（2秒）") {
                        Task { await viewModel.evaluate() }
                    }
                    .appPrimaryButton()
                    .disabled(viewModel.evaluating)

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
            Button("确定") { dismiss() }
        } message: {
            Text(viewModel.resultText ?? "训练完成")
        }
    }
}
