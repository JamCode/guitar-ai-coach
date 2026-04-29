import SwiftUI
import Core

struct TranscriptionHistoryView: View {
    let entries: [TranscriptionHistoryEntry]
    let onDelete: (TranscriptionHistoryEntry) -> Void
    let onRename: (TranscriptionHistoryEntry, String) -> Void

    @State private var renamingEntry: TranscriptionHistoryEntry?
    @State private var renamingText = ""

    var body: some View {
        List {
            Section {
                ForEach(entries, id: \.id) { entry in
                    NavigationLink {
                        TranscriptionResultView(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.displayName)
                                .foregroundStyle(SwiftAppTheme.text)
                            Text(String(format: AppL10n.t("transcribe_history_row_format"), entry.originalKey, formatDate(entry.createdAtMs)))
                                .font(.caption)
                                .foregroundStyle(SwiftAppTheme.muted)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            renamingEntry = entry
                            renamingText = entry.displayName
                        } label: {
                            Label("改名", systemImage: "pencil")
                        }
                        .tint(SwiftAppTheme.brand)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        onDelete(entries[index])
                    }
                }
            } footer: {
                Text(LocalizedStringResource("transcribe_privacy_notice", bundle: .main))
                    .font(.caption2)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .navigationTitle(LocalizedStringResource("transcribe_history_title", bundle: .main))
        .appPageBackground()
        .alert("修改记录名称", isPresented: renameAlertBinding) {
            TextField("例如：周杰伦-晴天", text: $renamingText)
            Button("取消", role: .cancel) {
                renamingEntry = nil
            }
            Button("保存") {
                guard let entry = renamingEntry else { return }
                onRename(entry, renamingText)
                renamingEntry = nil
            }
        } message: {
            Text("修改后会在历史列表和结果页显示新名称。")
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingEntry != nil },
            set: { isPresented in
                if !isPresented {
                    renamingEntry = nil
                }
            }
        )
    }

    private func formatDate(_ ms: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}
