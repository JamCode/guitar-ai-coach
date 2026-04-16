import SwiftUI
import Ear
import Tuner
import Fretboard
import Chords
import ChordsLive
import ChordChart
import Profile
import Core

@main
struct SwiftEarHostApp: App {
    init() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(SwiftAppTheme.bg)
        // 使用系统标签色，避免 SwiftUI 动态 Color 桥接为 UIColor 时在导航栏上下文中解析异常导致标题「看不见」。
        nav.titleTextAttributes = [.foregroundColor: UIColor.label]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().compactScrollEdgeAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(SwiftAppTheme.bg)
        tab.stackedLayoutAppearance.selected.iconColor = UIColor(SwiftAppTheme.brand)
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(SwiftAppTheme.brand)
        ]
        tab.stackedLayoutAppearance.normal.iconColor = UIColor(SwiftAppTheme.muted)
        tab.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(SwiftAppTheme.muted)
        ]
        tab.inlineLayoutAppearance = tab.stackedLayoutAppearance
        tab.compactInlineLayoutAppearance = tab.stackedLayoutAppearance
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = UIColor(SwiftAppTheme.brand)
        UITabBar.appearance().unselectedItemTintColor = UIColor(SwiftAppTheme.muted)

        UITableView.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

private struct RootTabView: View {
    @State private var selectedTab: Int = 0
    @State private var practiceTabMounted: Bool = false
    
    /// 自定义 Tab 选择绑定：切到「练习」时在同一事务内先完成挂载，
    /// 避免先显示占位页再切到真实页面造成导航标题闪动。
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == 2 {
                    practiceTabMounted = true
                }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack {
                ToolsTabView()
            }
            .tabItem {
                Label("工具", systemImage: "wrench.and.screwdriver")
            }
            .tag(0)

            NavigationStack {
                EarHomeView()
            }
            .tabItem {
                Label("练耳", systemImage: "ear")
            }
            .tag(1)

            NavigationStack {
                if practiceTabMounted {
                    PracticeHomeView()
                } else {
                    PlaceholderView(
                        title: "练习",
                        detail: "首次进入该 Tab 后才会加载练习数据。"
                    )
                }
            }
            .tabItem {
                Label("练习", systemImage: "figure.strengthtraining.traditional")
            }
            .tag(2)

            NavigationStack {
                ProfileHomeView()
            }
            .tabItem {
                Label("我的", systemImage: "person")
            }
            .tag(3)
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
                    navCard(title: "吉他指板", subtitle: "竖向指板 · 音高标注 · 拨弦试听 · 变调夹", icon: "square.grid.3x3") { FretboardView() }
                    navCard(title: "和弦字典", subtitle: "离线可查构成音与常见把位", icon: "pianokeys") { ChordLookupView() }
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
        .appNavigationBarChrome()
    }
}
