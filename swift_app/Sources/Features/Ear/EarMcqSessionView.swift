import SwiftUI

public struct EarMcqSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EarMcqSessionViewModel
    @State private var showSummary = false

    public init(title: String, bank: String, totalQuestions: Int = 10) {
        _viewModel = StateObject(
            wrappedValue: EarMcqSessionViewModel(
                title: title,
                bank: bank,
                totalQuestions: totalQuestions
            )
        )
    }

    public var body: some View {
        List {
            if viewModel.loading {
                ProgressView("加载中…")
            } else if let err = viewModel.loadError {
                Text(err).foregroundStyle(.red)
            } else if let q = viewModel.question {
                Section {
                    Text("第 \(viewModel.pageIndex + 1) / \(max(1, viewModel.session.count)) 题")
                    ProgressView(value: Double(viewModel.pageIndex + 1), total: Double(max(1, viewModel.session.count)))
                }
                Section("题目") {
                    Text(q.promptZh)
                    if let hint = q.hintZh, !hint.isEmpty {
                        Text(hint).foregroundStyle(.secondary)
                    }
                    if let playError = viewModel.playError {
                        Text(playError).foregroundStyle(.red)
                    }
                    HStack {
                        Button("播放") { Task { await viewModel.playCurrent() } }
                        Button("再听一遍") { Task { await viewModel.playCurrent() } }
                    }
                }
                Section("四选一") {
                    ForEach(Array(q.options.enumerated()), id: \.offset) { idx, opt in
                        Button {
                            if !viewModel.revealed {
                                viewModel.selectedChoiceIndex = idx
                            }
                        } label: {
                            HStack {
                                Text(opt.label)
                                Spacer()
                                if viewModel.selectedChoiceIndex == idx {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    if viewModel.revealed, let selected = viewModel.selectedChoiceIndex {
                        let ok = q.options[selected].key == q.correctOptionKey
                        let answer = q.options.first(where: { $0.key == q.correctOptionKey })?.label ?? "--"
                        Text(ok ? "回答正确：\(answer)" : "回答错误：正确答案是 \(answer)")
                            .foregroundStyle(ok ? .green : .red)
                    }
                }
                Section {
                    Button(viewModel.revealed ? (viewModel.pageIndex >= viewModel.session.count - 1 ? "查看结果" : "下一题") : "提交答案") {
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
        }
        .navigationTitle(viewModel.title)
        .task {
            if viewModel.loading {
                await viewModel.bootstrap()
            }
        }
        .alert("本轮完成", isPresented: $showSummary) {
            Button("确定") { dismiss() }
        } message: {
            Text(viewModel.summaryText)
        }
    }
}
