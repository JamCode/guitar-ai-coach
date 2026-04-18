import SwiftUI
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
    @StateObject private var sheetLibraryVM = SheetLibraryViewModel()
    
    /// 自定义 Tab 选择绑定：切到「练习」时在同一事务内先完成挂载，
    /// 避免先显示占位页再切到真实页面造成导航标题闪动。
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                // Tab 切换使用无动画事务，减少视觉干扰与注意力跳转。
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if newValue == 1 {
                        practiceTabMounted = true
                    }
                    selectedTab = newValue
                }
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
            .tag(1)

            NavigationStack {
                SheetLibraryView(vm: sheetLibraryVM)
            }
            .tabItem {
                Label("我的谱", systemImage: "music.note.list")
            }
            .tag(2)

            NavigationStack {
                LiveChordView()
            }
            .tabItem {
                Label("扒歌", systemImage: "waveform.path.ecg")
            }
            .tag(3)

            NavigationStack {
                ProfileHomeView()
            }
            .tabItem {
                Label("我的", systemImage: "person")
            }
            .tag(4)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct ToolsTabView: View {
    /// 比全站 `pagePadding` 略紧，减少工具宫格外圈留白。
    private let gridEdgePadding: CGFloat = 12
    private let gridGap: CGFloat = 8
    private let cardAspectRatio: CGFloat = 0.92

    var body: some View {
        let pad = gridEdgePadding
        VStack(spacing: 0) {
            VStack(spacing: gridGap) {
                HStack(spacing: gridGap) {
                    gridTile(
                        title: "调音器",
                        subtitle: "麦克风拾音与标准空弦目标",
                        icon: "waveform"
                    ) { TunerView() }
                    gridTile(
                        title: "吉他指板",
                        subtitle: "竖向指板·音高标注·拨弦试听·变调夹",
                        icon: "square.grid.3x3"
                    ) { FretboardView() }
                }

                HStack(spacing: gridGap) {
                    gridTile(
                        title: "和弦速查",
                        subtitle: "离线可查构成音与常见把位",
                        icon: "pianokeys"
                    ) { ChordLookupView() }
                    gridTile(
                        title: "常用和弦",
                        subtitle: "初/中/高分段·本地指法图速查",
                        icon: "tablecells"
                    ) { ChordChartView() }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(pad)
        .navigationTitle("工具")
        .appPageBackground()
    }

    private func gridTile<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            TabBarHiddenContainer { destination() }
        } label: {
            VStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                    .imageScale(.large)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(SwiftAppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous)
                    .stroke(SwiftAppTheme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .aspectRatio(cardAspectRatio, contentMode: .fit)
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
