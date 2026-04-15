import SwiftUI
import Ear
import Tuner
import Fretboard
import Chords
import ChordsLive
import Theory
import ChordChart
import Profile
import Core

@main
struct SwiftEarHostApp: App {
    init() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(SwiftAppTheme.bg)
        nav.titleTextAttributes = [.foregroundColor: UIColor(SwiftAppTheme.text)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(SwiftAppTheme.text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(SwiftAppTheme.bg)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        UITableView.appearance().backgroundColor = .clear
    }

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
                ProfileHomeView()
            }
            .tabItem {
                Label("我的", systemImage: "person")
            }
        }
    }
}

private struct ToolsTabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 8) {
                    navCard(title: "实时和弦建议（Beta）", subtitle: "监听音乐并实时显示主和弦与候选", icon: "waveform.path.ecg") { LiveChordView() }
                    navCard(title: "调音器", subtitle: "麦克风拾音与标准空弦目标", icon: "waveform") { TunerView() }
                    navCard(title: "吉他指板", subtitle: "竖向指板 · 音名 · 变调夹", icon: "square.grid.3x3") { FretboardView() }
                    navCard(title: "和弦字典", subtitle: "离线可查构成音与常见把位", icon: "pianokeys") { ChordLookupView() }
                    navCard(title: "初级乐理", subtitle: "音程、调式等入门提要", icon: "book") { TheoryView() }
                    navCard(title: "和弦表", subtitle: "初/中/高分段 · 本地指法图速查", icon: "tablecells") { ChordChartView() }
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("工具")
        .appPageBackground()
    }

    private func navCard<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(SwiftAppTheme.brand)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            .appCard()
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
