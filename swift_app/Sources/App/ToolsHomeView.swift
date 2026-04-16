import SwiftUI
import Tuner
import Fretboard
import Chords
import ChordsLive
import Theory
import ChordChart
import Ear

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
                    LiveChordView()
                } label: {
                    toolsRow(
                        title: "实时和弦建议（Beta）",
                        subtitle: "监听音乐并实时显示主和弦与候选",
                        systemImage: "waveform.path.ecg"
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
                        subtitle: "竖向指板 · 音名 · 变调夹",
                        systemImage: "square.grid.3x3"
                    )
                }
                NavigationLink {
                    ChordLookupView()
                } label: {
                    toolsRow(
                        title: "和弦字典",
                        subtitle: "离线可查构成音与常见把位",
                        systemImage: "pianokeys"
                    )
                }
                NavigationLink {
                    TheoryView()
                } label: {
                    toolsRow(
                        title: "初级乐理",
                        subtitle: "音程、调式等入门提要",
                        systemImage: "book"
                    )
                }
                NavigationLink {
                    ChordChartView()
                } label: {
                    toolsRow(
                        title: "和弦表",
                        subtitle: "初/中/高分段 · 本地指法图速查",
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
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

