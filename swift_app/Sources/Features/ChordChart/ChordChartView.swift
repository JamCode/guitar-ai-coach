import SwiftUI
import Core
import Chords

public struct ChordChartView: View {
    @State private var selectedEntry: ChordChartEntry?
    @State private var expandedSections: Set<String> = []

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("关于本表").appSectionTitle()
                    Text("按和弦类型分组：基础三和弦、七和弦、挂留、加音、延伸与变化和弦。")
                        .foregroundStyle(SwiftAppTheme.muted)
                }
                .appCard()

                ForEach(ChordChartData.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedSections.contains(section.id) },
                                set: { expanded in
                                    if expanded { expandedSections.insert(section.id) }
                                    else { expandedSections.remove(section.id) }
                                }
                            )
                        ) {
                            VStack(spacing: 8) {
                                ForEach(section.entries) { entry in
                                    Button {
                                        selectedEntry = entry
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(entry.symbol)
                                                    .font(.headline)
                                                    .foregroundStyle(SwiftAppTheme.text)
                                                Text(entry.theory)
                                                    .font(.subheadline)
                                                    .foregroundStyle(SwiftAppTheme.muted)
                                                    .lineLimit(2)
                                                if let voicing = entry.voicing, !voicing.isEmpty {
                                                    Text(voicing)
                                                        .font(.caption)
                                                        .foregroundStyle(SwiftAppTheme.brand)
                                                }
                                                Text("6→1 弦：\(entry.frets.map { $0 < 0 ? "x" : String($0) }.joined(separator: " "))")
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(SwiftAppTheme.muted)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                            ChordDiagramView(frets: entry.frets)
                                                .frame(width: 76, height: 98)
                                                .padding(6)
                                                .background(SwiftAppTheme.surface)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .stroke(SwiftAppTheme.line.opacity(0.85), lineWidth: 1)
                                                )
                                                .accessibilityHidden(true)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .background(SwiftAppTheme.surfaceSoft)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title).font(.headline).foregroundStyle(SwiftAppTheme.text)
                                Text("\(section.entries.count) 个 · \(section.intro)")
                                    .font(.caption)
                                    .foregroundStyle(SwiftAppTheme.muted)
                            }
                        }
                        .tint(SwiftAppTheme.text)
                    }
                    .appCard()
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("常用和弦")
        .appPageBackground()
        .sheet(item: $selectedEntry) { entry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(entry.symbol).font(.largeTitle.bold())
                    Text(entry.theory)
                    if let voicing = entry.voicing {
                        Text(voicing).foregroundStyle(SwiftAppTheme.brand)
                    }
                    ChordDiagramView(frets: entry.frets)
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .padding(12)
                        .background(SwiftAppTheme.surfaceSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("指法图（6→1 弦）")
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                    Text("6→1 弦：\(entry.frets.map { $0 < 0 ? "x" : String($0) }.joined(separator: " "))")
                        .font(.body.monospaced())
                }
                .padding(20)
            }
        }
    }
}

