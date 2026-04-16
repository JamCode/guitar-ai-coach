import SwiftUI
import Core

struct PracticeFinishResult: Equatable {
    let completed: Bool
    let difficulty: Int
    let note: String?
}

struct PracticeFinishDialog: View {
    let title: String
    let showCompletedGoal: Bool

    @Binding var noteText: String
    let onCancel: () -> Void
    let onSave: (PracticeFinishResult) -> Void

    @State private var completed: Bool = true
    @State private var difficulty: Double = 3

    var body: some View {
        NavigationStack {
            Form {
                if showCompletedGoal {
                    Toggle("完成目标", isOn: $completed)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("主观难度")
                        Spacer()
                        Text("\(Int(difficulty))")
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    Slider(value: $difficulty, in: 1...5, step: 1)
                }

                Section("备注（可选）") {
                    TextField("写点本次练习感受…", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存记录") {
                        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(
                            PracticeFinishResult(
                                completed: showCompletedGoal ? completed : true,
                                difficulty: min(5, max(1, Int(difficulty))),
                                note: trimmed.isEmpty ? nil : trimmed
                            )
                        )
                    }
                    .appPrimaryButton()
                }
            }
        }
    }
}

