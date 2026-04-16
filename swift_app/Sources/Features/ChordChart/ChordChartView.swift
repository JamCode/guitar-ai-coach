import SwiftUI
import Core

public struct ChordChartView: View {
    @State private var selectedEntry: ChordChartEntry?
    @State private var expandedSections: Set<String> = [ChordChartData.sections.first?.id ?? ""]

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
        .navigationTitle("和弦表")
        .appPageBackground()
        .sheet(item: $selectedEntry) { entry in
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.symbol).font(.largeTitle.bold())
                Text(entry.theory)
                if let voicing = entry.voicing {
                    Text(voicing).foregroundStyle(SwiftAppTheme.brand)
                }
                Text("6→1 弦：\(entry.frets.map { $0 < 0 ? "x" : String($0) }.joined(separator: " "))")
                    .font(.body.monospaced())
                Spacer()
            }
            .padding(20)
        }
    }
}

