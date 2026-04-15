import SwiftUI

public struct IntervalEarView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: IntervalEarSessionViewModel
    @State private var showSummary = false

    public init(totalQuestions: Int = 5) {
        _viewModel = StateObject(wrappedValue: IntervalEarSessionViewModel(totalQuestions: totalQuestions))
    }

    public var body: some View {
        List {
            Section {
                Text("音程 · 第 \(viewModel.pageIndex + 1) / \(viewModel.totalQuestions) 题")
                ProgressView(value: Double(viewModel.pageIndex + 1), total: Double(viewModel.totalQuestions))
            }
            Section("说明") {
                Text("听两个音，选择它们之间的音程。")
                Text("先播较低音，再播较高音；可多次点击再听一遍。")
                    .foregroundStyle(.secondary)
                if let playError = viewModel.playError {
                    Text(playError).foregroundStyle(.red)
                }
                HStack {
                    Button("播放") { Task { await viewModel.playPair() } }
                    Button("再听一遍") { Task { await viewModel.playPair() } }
                }
            }
            if let q = viewModel.question {
                Section("四选一") {
                    ForEach(Array(q.choices.enumerated()), id: \.offset) { idx, choice in
                        Button {
                            if !viewModel.revealed {
                                viewModel.selectedChoiceIndex = idx
                            }
                        } label: {
                            HStack {
                                Text(choice.nameZh)
                                Spacer()
                                if viewModel.selectedChoiceIndex == idx {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    if viewModel.revealed, let picked = viewModel.selectedChoiceIndex {
                        let ok = q.choices[picked].semitones == q.answer.semitones
                        Text(ok ? "回答正确：\(q.answer.nameZh)。" : "回答错误：正确答案是 \(q.answer.nameZh)。")
                            .foregroundStyle(ok ? .green : .red)
                    }
                }
            }
            Section {
                Button(viewModel.revealed ? (viewModel.pageIndex >= viewModel.totalQuestions - 1 ? "查看结果" : "下一题") : "提交答案") {
                    if viewModel.revealed {
                        viewModel.nextOrFinish()
                        if viewModel.finished {
                            showSummary = true
                        }
                    } else {
                        viewModel.submit()
                    }
                }
                .disabled(!viewModel.revealed && viewModel.selectedChoiceIndex == nil)
            }
        }
        .navigationTitle("音程识别")
        .alert("本轮完成", isPresented: $showSummary) {
            Button("确定") { dismiss() }
        } message: {
            Text(viewModel.summaryText)
        }
    }
}
