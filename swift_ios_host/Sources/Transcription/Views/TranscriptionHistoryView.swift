import SwiftUI
import Core

struct TranscriptionHistoryView: View {
    let entries: [TranscriptionHistoryEntry]
    let onDelete: (TranscriptionHistoryEntry) -> Void

    var body: some View {
        List {
            ForEach(entries, id: \.id) { entry in
                NavigationLink {
                    TranscriptionResultView(entry: entry)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.fileName)
                            .foregroundStyle(SwiftAppTheme.text)
                        Text(String(format: AppL10n.t("transcribe_history_row_format"), entry.originalKey, formatDate(entry.createdAtMs)))
                            .font(.caption)
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    onDelete(entries[index])
                }
            }
        }
        .navigationTitle(LocalizedStringResource("transcribe_history_title", bundle: .main))
        .appPageBackground()
    }

    private func formatDate(_ ms: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}
