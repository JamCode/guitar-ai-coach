import SwiftUI
import Ear
import Tuner
import Fretboard
import Chords
import ChordsLive
import Theory
import ChordChart

@main
struct SwiftEarHostApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

private struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ToolsTabView()
            }
            .tabItem {
                Label("工具", systemImage: "wrench.and.screwdriver")
            }

            NavigationStack {
                EarHomeView()
            }
            .tabItem {
                Label("练耳", systemImage: "ear")
            }

            NavigationStack {
                PlaceholderView(
                    title: "练习",
                    detail: "该 Tab 还未在 Swift 版本迁移。当前可先体验工具与练耳。"
                )
            }
            .tabItem {
                Label("练习", systemImage: "figure.strengthtraining.traditional")
            }

            NavigationStack {
                PlaceholderView(
                    title: "我的",
                    detail: "该 Tab 还未在 Swift 版本迁移。"
                )
            }
            .tabItem {
                Label("我的", systemImage: "person")
            }
        }
    }
}

private struct ToolsTabView: View {
    var body: some View {
        List {
            NavigationLink {
                LiveChordView()
            } label: {
                row(title: "实时和弦建议（Beta）", subtitle: "监听音乐并实时显示主和弦与候选", icon: "waveform.path.ecg")
            }
            NavigationLink {
                TunerView()
            } label: {
                row(title: "调音器", subtitle: "麦克风拾音与标准空弦目标", icon: "waveform")
            }
            NavigationLink {
                FretboardView()
            } label: {
                row(title: "吉他指板", subtitle: "竖向指板 · 音名 · 变调夹", icon: "square.grid.3x3")
            }
            NavigationLink {
                ChordLookupView()
            } label: {
                row(title: "和弦字典", subtitle: "离线可查构成音与常见把位", icon: "pianokeys")
            }
            NavigationLink {
                TheoryView()
            } label: {
                row(title: "初级乐理", subtitle: "音程、调式等入门提要", icon: "book")
            }
            NavigationLink {
                ChordChartView()
            } label: {
                row(title: "和弦表", subtitle: "初/中/高分段 · 本地指法图速查", icon: "tablecells")
            }
        }
        .navigationTitle("工具")
    }

    private func row(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.circle").font(.system(size: 40))
            Text(detail).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(24)
        .navigationTitle(title)
    }
}
