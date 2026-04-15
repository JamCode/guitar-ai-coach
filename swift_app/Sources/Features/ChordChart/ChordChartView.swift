import SwiftUI

public struct ChordChartView: View {
    @State private var selectedEntry: ChordChartEntry?
    @State private var expandedSections: Set<String> = [ChordChartData.sections.first?.id ?? ""]

    public init() {}

    public var body: some View {
        List {
            Section("关于本表") {
                Text("按乐理难度分段：初级开放三和弦为主，中级横按与七和弦，高级色彩与 slash。")
                    .foregroundStyle(.secondary)
            }
            ForEach(ChordChartData.sections) { section in
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedSections.contains(section.id) },
                            set: { expanded in
                                if expanded { expandedSections.insert(section.id) }
                                else { expandedSections.remove(section.id) }
                            }
                        )
                    ) {
                        ForEach(section.entries) { entry in
                            Button {
                                selectedEntry = entry
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.symbol).font(.headline)
                                    Text(entry.theory).font(.subheadline).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if let voicing = entry.voicing, !voicing.isEmpty {
                                        Text(voicing).font(.caption).foregroundStyle(.blue)
                                    }
                                    Text("6→1 弦：\(entry.frets.map { $0 < 0 ? "x" : String($0) }.joined(separator: " "))")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title).font(.headline)
                            Text("\(section.entries.count) 个 · \(section.intro)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                }
        }
        .navigationTitle("和弦表")
        .sheet(item: $selectedEntry) { entry in
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.symbol).font(.largeTitle.bold())
                Text(entry.theory)
                if let voicing = entry.voicing {
                    Text(voicing).foregroundStyle(.blue)
                }
                Text("6→1 弦：\(entry.frets.map { $0 < 0 ? "x" : String($0) }.joined(separator: " "))")
                    .font(.body.monospaced())
                Spacer()
            }
            .padding(20)
        }
    }
}

