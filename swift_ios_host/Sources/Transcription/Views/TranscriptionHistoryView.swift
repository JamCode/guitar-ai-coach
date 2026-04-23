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
                        Text(entry.displayName)
                            .foregroundStyle(SwiftAppTheme.text)
                        Text("原调：\(entry.originalKey) · \(formatDate(entry.createdAtMs))")
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
        .navigationTitle("扒歌历史")
        .appPageBackground()
    }

    private func formatDate(_ ms: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}
