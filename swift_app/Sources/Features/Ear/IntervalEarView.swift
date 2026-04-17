import SwiftUI
import Core

public struct IntervalEarView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: IntervalEarSessionViewModel
    @State private var showSummary = false
    private let onSessionComplete: ((Int, Int) -> Void)?
    private let autoDismissOnComplete: Bool

    public init(
        totalQuestions: Int = 5,
        difficulty: IntervalEarDifficulty = .初级,
        onSessionComplete: ((Int, Int) -> Void)? = nil,
        autoDismissOnComplete: Bool = true
    ) {
        _viewModel = StateObject(
            wrappedValue: IntervalEarSessionViewModel(totalQuestions: totalQuestions, difficulty: difficulty)
        )
        self.onSessionComplete = onSessionComplete
        self.autoDismissOnComplete = autoDismissOnComplete
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("音程 · 第 \(viewModel.pageIndex + 1) / \(viewModel.totalQuestions) 题")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                    ProgressView(
                        value: Double(viewModel.pageIndex + 1),
                        total: Double(viewModel.totalQuestions)
                    )
                    .tint(SwiftAppTheme.brand)
                }
                .appCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("说明").appSectionTitle()
                    Text("听两个音，选择它们之间的音程。")
                        .foregroundStyle(SwiftAppTheme.text)
                    Text("先播较低音，再播较高音；可多次点击再听一遍。")
                        .foregroundStyle(SwiftAppTheme.muted)
                    if let playError = viewModel.playError {
                        Text(playError).foregroundStyle(.red)
                    }
                    HStack(spacing: 10) {
                        Button("播放") { Task { await viewModel.playPair() } }
                            .appPrimaryButton()
                        Button("再听一遍") { Task { await viewModel.playPair() } }
                            .appSecondaryButton()
                    }
                }
                .appCard()

                if let q = viewModel.question {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("四选一").appSectionTitle()
                        ForEach(Array(q.choices.enumerated()), id: \.offset) { idx, choice in
                            Button {
                                if !viewModel.revealed {
                                    viewModel.selectedChoiceIndex = idx
                                }
                            } label: {
                                HStack {
                                    Text(choice.nameZh).foregroundStyle(SwiftAppTheme.text)
                                    Spacer()
                                    if viewModel.selectedChoiceIndex == idx {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(SwiftAppTheme.brand)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(SwiftAppTheme.surfaceSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        viewModel.selectedChoiceIndex == idx ? SwiftAppTheme.brand : SwiftAppTheme.line,
                                        lineWidth: viewModel.selectedChoiceIndex == idx ? 1.5 : 1
                                    )
                            )
                        }
                        if viewModel.revealed, let picked = viewModel.selectedChoiceIndex {
                            let ok = q.choices[picked].semitones == q.answer.semitones
                            Text(ok ? "回答正确：\(q.answer.nameZh)。" : "回答错误：正确答案是 \(q.answer.nameZh)。")
                                .foregroundStyle(ok ? SwiftAppTheme.dynamic(.green, .green) : .red)
                        }
                    }
                    .appCard()
                }

                Button(viewModel.revealed ? (viewModel.pageIndex >= viewModel.totalQuestions - 1 ? "查看结果" : "下一题") : "提交答案") {
                    if viewModel.revealed {
                        viewModel.nextOrFinish()
                        if viewModel.finished { showSummary = true }
                    } else {
                        viewModel.submit()
                    }
                }
                .appPrimaryButton()
                .disabled(!viewModel.revealed && viewModel.selectedChoiceIndex == nil)
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("音程识别")
        .appPageBackground()
        .alert("本轮完成", isPresented: $showSummary) {
            Button("确定") {
                onSessionComplete?(viewModel.correctCount, viewModel.totalQuestions)
                if autoDismissOnComplete {
                    dismiss()
                }
            }
        } message: {
            Text(viewModel.summaryText)
        }
    }
}
