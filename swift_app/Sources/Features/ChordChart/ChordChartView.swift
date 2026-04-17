import SwiftUI
import Core
import Chords

private final class ChordChartAudioHolder: ObservableObject {
    let tonePlayer = ChordVoicingTonePlayer()
}

public struct ChordChartView: View {
    @State private var selectedEntry: ChordChartEntry?
    @State private var expandedSections: Set<String> = [ChordChartData.sections.first?.id ?? ""]
    @StateObject private var chartAudio = ChordChartAudioHolder()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("关于本表").appSectionTitle()
                    Text("按和弦类型分组：基础三和弦、七和弦、挂留、加音、延伸与变化和弦。点按右侧指法图试听（先分解后柱式）。")
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
                                    HStack(alignment: .top, spacing: 10) {
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
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)

                                        chordDiagramTapToPlay(entry: entry, compact: true)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(SwiftAppTheme.surfaceSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .onAppear {
            chartAudio.tonePlayer.prepare()
        }
        .sheet(item: $selectedEntry) { entry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(entry.symbol).font(.largeTitle.bold())
                    Text(entry.theory)
                    if let voicing = entry.voicing {
                        Text(voicing).foregroundStyle(SwiftAppTheme.brand)
                    }
                    chordDiagramTapToPlay(entry: entry, compact: false)
                    Text("点按指法图试听：先分解（低音→高音），再柱式和弦。")
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
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

    @ViewBuilder
    private func chordDiagramTapToPlay(entry: ChordChartEntry, compact: Bool) -> some View {
        let diagram = ChordDiagramView(frets: entry.frets)
            .frame(width: compact ? 76 : nil, height: compact ? 98 : 240)
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(compact ? 6 : 12)
            .background(SwiftAppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                    .stroke(SwiftAppTheme.line.opacity(0.85), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
            .onTapGesture {
                chartAudio.tonePlayer.playChordFrets(entry.frets)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("指法图 \(entry.symbol)，点按试听和弦")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("先依次播放各弦再同时播放柱式和弦")

        if compact {
            diagram
        } else {
            diagram
                .padding(12)
                .background(SwiftAppTheme.surfaceSoft)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
