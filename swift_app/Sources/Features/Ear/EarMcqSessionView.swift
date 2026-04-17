import SwiftUI
import Core

public struct EarMcqSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EarMcqSessionViewModel
    @State private var showSummary = false
    private let onSessionComplete: ((Int, Int) -> Void)?
    private let autoDismissOnComplete: Bool

    public init(
        title: String,
        bank: String,
        totalQuestions: Int = 10,
        chordDifficulty: EarChordMcqDifficulty = .初级,
        onSessionComplete: ((Int, Int) -> Void)? = nil,
        autoDismissOnComplete: Bool = true
    ) {
        _viewModel = StateObject(
            wrappedValue: EarMcqSessionViewModel(
                title: title,
                bank: bank,
                totalQuestions: totalQuestions,
                chordDifficulty: chordDifficulty
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
                } else if let err = viewModel.loadError {
                    Text(err).foregroundStyle(.red).appCard()
                } else if let q = viewModel.question {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("第 \(viewModel.pageIndex + 1) / \(max(1, viewModel.session.count)) 题")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SwiftAppTheme.text)
                        ProgressView(
                            value: Double(viewModel.pageIndex + 1),
                            total: Double(max(1, viewModel.session.count))
                        )
                        .tint(SwiftAppTheme.brand)
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("题目").appSectionTitle()
                        Text(q.promptZh).foregroundStyle(SwiftAppTheme.text)
                        if let hint = q.hintZh, !hint.isEmpty {
                            Text(hint).foregroundStyle(SwiftAppTheme.muted)
                        }
                        Text("使用吉他采样合成，与预录音色可能略有差异。")
                            .font(.caption)
                            .foregroundStyle(SwiftAppTheme.muted)
                        if let playError = viewModel.playError {
                            Text(playError).foregroundStyle(.red)
                        }
                        HStack(spacing: 10) {
                            Button("播放") { Task { await viewModel.playCurrent() } }
                                .appPrimaryButton()
                            Button("再听一遍") { Task { await viewModel.playCurrent() } }
                                .appSecondaryButton()
                        }
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("四选一").appSectionTitle()
                        ForEach(Array(q.options.enumerated()), id: \.offset) { idx, opt in
                            Button {
                                if !viewModel.revealed {
                                    viewModel.selectedChoiceIndex = idx
                                }
                            } label: {
                                HStack {
                                    Text(opt.label).foregroundStyle(SwiftAppTheme.text)
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
                        if viewModel.revealed, let selected = viewModel.selectedChoiceIndex {
                            let ok = q.options[selected].key == q.correctOptionKey
                            let answer = q.options.first(where: { $0.key == q.correctOptionKey })?.label ?? "--"
                            Text(ok ? "回答正确：\(answer)" : "回答错误：正确答案是 \(answer)")
                                .foregroundStyle(ok ? SwiftAppTheme.dynamic(.green, .green) : .red)
                        }
                    }
                    .appCard()

                    Button(viewModel.revealed ? (viewModel.pageIndex >= viewModel.session.count - 1 ? "查看结果" : "下一题") : "提交答案") {
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
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(viewModel.title)
        .appPageBackground()
        .task {
            if viewModel.loading {
                await viewModel.bootstrap()
            }
        }
        .alert("本轮完成", isPresented: $showSummary) {
            Button("确定") {
                onSessionComplete?(viewModel.correctCount, max(1, viewModel.session.count))
                if autoDismissOnComplete {
                    dismiss()
                }
            }
        } message: {
            Text(viewModel.summaryText)
        }
    }
}
