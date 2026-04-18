import SwiftUI
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
                        title: "练耳",
                        subtitle: "音程/和弦/视唱训练",
                        systemImage: "ear"
                    )
                }
                NavigationLink {
                    TunerView()
                } label: {
                    toolsRow(
                        title: "调音器",
                        subtitle: "麦克风拾音与标准空弦目标",
                        systemImage: "waveform"
                    )
                }
                NavigationLink {
                    FretboardView()
                } label: {
                    toolsRow(
                        title: "吉他指板",
                        subtitle: "竖向指板·音高标注·拨弦试听·变调夹",
                        systemImage: "square.grid.3x3"
                    )
                }
                NavigationLink {
                    TraditionalCrawlPracticeView()
                } label: {
                    toolsRow(
                        title: "爬格子",
                        subtitle: "传统四指一格·推荐步骤与节拍建议",
                        systemImage: "hand.raised.fingers.spread"
                    )
                }
                NavigationLink {
                    ScaleTrainingPracticeView()
                } label: {
                    toolsRow(
                        title: "音阶训练",
                        subtitle: "大调/小调/五声·Mi/Sol/La 指型·自动出题",
                        systemImage: "music.note.list"
                    )
                }
                NavigationLink {
                    ChordSwitchTrainingPracticeView()
                } label: {
                    toolsRow(
                        title: "和弦切换",
                        subtitle: "开放/横按·分组节奏·BPM 自动组卷",
                        systemImage: "guitars"
                    )
                }
                NavigationLink {
                    ChordLookupView()
                } label: {
                    toolsRow(
                        title: "和弦速查",
                        subtitle: "离线可查构成音与常见把位",
                        systemImage: "pianokeys"
                    )
                }
                NavigationLink {
                    ChordChartView()
                } label: {
                    toolsRow(
                        title: "常用和弦",
                        subtitle: "按和弦类型分类·本地指法图速查",
                        systemImage: "tablecells"
                    )
                }
            }
            .navigationTitle("工具")
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

