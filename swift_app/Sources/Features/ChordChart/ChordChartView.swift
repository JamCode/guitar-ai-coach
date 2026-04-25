import SwiftUI
import Core
import Chords

private final class ChordChartAudioHolder: ObservableObject {
    let tonePlayer = ChordVoicingTonePlayer()
}

public struct ChordChartView: View {
    @State private var expandedSections: Set<String> = []
    @StateObject private var chartAudio = ChordChartAudioHolder()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringResource("chord_chart_about_title", bundle: .main)).appSectionTitle()
                    Text(LocalizedStringResource("chord_chart_about_body", bundle: .main))
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
                                        chartAudio.tonePlayer.playChordFrets(entry.frets)
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
                                                Text(String(format: AppL10n.t("chord_chart_fret_line_format"), entry.frets.map { $0 < 0 ? "x" : String($0) }.joined(separator: " ")))
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(SwiftAppTheme.muted)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 10)
                                            .contentShape(Rectangle())

                                            chordDiagramCard(entry: entry)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(SwiftAppTheme.surfaceSoft)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(String(format: AppL10n.t("chord_chart_a11y_label_format"), entry.symbol))
                                    .accessibilityHint(AppL10n.t("chord_chart_a11y_hint"))
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
        .navigationTitle(Text(LocalizedStringResource("tools_chord_chart_title", bundle: .main)))
        .appPageBackground()
        .onAppear {
            chartAudio.tonePlayer.prepare()
        }
    }

    private func chordDiagramCard(entry: ChordChartEntry) -> some View {
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
}
