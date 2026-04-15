import SwiftUI
import Core

public struct SightSingingSetupView: View {
    @State private var pitchRange = "mid"
    @State private var includeAccidental = false
    @State private var questionCount = 10.0

    public init() {}

    public var body: some View {
        List {
            Section("音域选择") {
                Picker("音域", selection: $pitchRange) {
                    Text("低音区 C3-B3").tag("low")
                    Text("中音区 C4-B4").tag("mid")
                    Text("宽范围 C3-B4").tag("wide")
                }
                Toggle("包含升降号", isOn: $includeAccidental)
                Text("题量：\(Int(questionCount)) 题")
                Slider(value: $questionCount, in: 5...20, step: 5)
            }
            Section {
                NavigationLink {
                    SightSingingSessionView(
                        repository: LocalSightSingingRepository(),
                        pitchRange: pitchRange,
                        includeAccidental: includeAccidental,
                        questionCount: Int(questionCount),
                        pitchTracker: DefaultSightSingingPitchTracker()
                    )
                } label: {
                    Label("开始训练", systemImage: "music.note")
                }
            }
        }
        .navigationTitle("视唱训练")
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
        List {
            if viewModel.loading {
                ProgressView("加载中…")
            } else if let error = viewModel.errorText {
                Text(error).foregroundStyle(.red)
            } else if let q = viewModel.question {
                Section {
                    Text("第 \(q.index) / \(q.totalQuestions) 题")
                }
                Section("目标音") {
                    Text(q.targetNotes.first ?? "--")
                        .font(.system(size: 44, weight: .bold))
                    let current = viewModel.currentHz.map {
                        PitchMath.midiToNoteName(PitchMath.frequencyToMidi($0))
                    } ?? "--"
                    Text("当前检测：\(current)")
                    if viewModel.evaluating {
                        ProgressView()
                    }
                }
                Section {
                    Button(viewModel.evaluating ? "判定中…" : "开始判定（2秒）") {
                        Task { await viewModel.evaluate() }
                    }
                    .disabled(viewModel.evaluating)
                }
                if let score = viewModel.lastScore {
                    Section("结果") {
                        Text("单题得分 \(score.score.formatted(.number.precision(.fractionLength(1)))) / 10")
                        Text("平均偏差 \(score.avgCentsAbs.formatted(.number.precision(.fractionLength(1)))) cent")
                        Text("稳定命中 \(score.stableHitMs) ms")
                        Button(q.index >= q.totalQuestions ? "查看结果" : "下一题") {
                            Task {
                                if await viewModel.nextOrFinish() {
                                    showResult = true
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("视唱训练")
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
