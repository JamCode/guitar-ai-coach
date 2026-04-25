import SwiftUI
import Core
import Tuner
import Fretboard
import Chords
import ChordChart
import Ear
import Practice

public struct ToolsHomeView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    EarHomeView()
                } label: {
                    toolsRow(
                        title: AppL10n.t("tools_ear_title"),
                        subtitle: AppL10n.t("tools_ear_subtitle"),
                        systemImage: "ear"
                    )
                }
                NavigationLink {
                    TunerView()
                } label: {
                    toolsRow(
                        title: AppL10n.t("tools_tuner_title"),
                        subtitle: AppL10n.t("tools_tuner_subtitle"),
                        systemImage: "waveform"
                    )
                }
                NavigationLink {
                    FretboardView()
                } label: {
                    toolsRow(
                        title: AppL10n.t("tools_fretboard_title"),
                        subtitle: AppL10n.t("tools_fretboard_subtitle"),
                        systemImage: "square.grid.3x3"
                    )
                }
                NavigationLink {
                    TraditionalCrawlPracticeView()
                } label: {
                    toolsRow(
                        title: AppL10n.t("tools_crawl_title"),
                        subtitle: AppL10n.t("tools_crawl_subtitle"),
                        systemImage: "hand.raised.fingers.spread"
                    )
                }
                NavigationLink {
                    ScaleTrainingPracticeView()
                } label: {
                    toolsRow(
                        title: AppL10n.t("tools_scale_training_title"),
                        subtitle: AppL10n.t("tools_scale_training_subtitle"),
                        systemImage: "music.note.list"
                    )
                }
                NavigationLink {
                    ChordSwitchTrainingPracticeView()
                } label: {
                    toolsRow(
                        title: AppL10n.t("tools_chord_switch_title"),
                        subtitle: AppL10n.t("tools_chord_switch_subtitle"),
                        systemImage: "guitars"
                    )
                }
                NavigationLink {
                    ChordLookupView()
                } label: {
                    toolsRow(
                        title: AppL10n.t("tools_chord_lookup_title"),
                        subtitle: AppL10n.t("tools_chord_lookup_subtitle"),
                        systemImage: "pianokeys"
                    )
                }
                NavigationLink {
                    ChordChartView()
                } label: {
                    toolsRow(
                        title: AppL10n.t("tools_chord_chart_title"),
                        subtitle: AppL10n.t("tools_chord_chart_subtitle"),
                        systemImage: "tablecells"
                    )
                }
            }
            .navigationTitle(AppL10n.t("tools_nav_title"))
            .appNavigationBarChrome()
        }
    }

    private func toolsRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
    }
}

