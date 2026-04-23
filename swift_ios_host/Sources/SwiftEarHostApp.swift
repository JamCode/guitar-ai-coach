import SwiftUI
import UIKit
import Tuner
import Fretboard
import Chords
import ChordChart
import Profile
import Metronome
import Core

/// 「帮助与反馈」默认收件人；发版前请改为可收信地址。
/// 若 Xcode Target → Info 增加自定义键 **`AIGuitarFeedbackEmail`**（String），将优先使用该值。
private let kFeedbackMailRecipient = "23766856@qq.com"
/// 隐私政策公开页面；若链接变更，仅需修改此常量。
private let kPrivacyPolicyURLString = "https://jamcode.github.io/wanle-guitar-privacy/"

private func resolvedFeedbackRecipient() -> String {
    if let raw = Bundle.main.object(forInfoDictionaryKey: "AIGuitarFeedbackEmail") as? String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    return kFeedbackMailRecipient
}

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
    /// Tab 顺序：练习(0) → 我的谱(1) → 扒歌(2) → 工具(3)。默认落在「练习」。
    @State private var selectedTab: Int = 0
    /// 练习为首位 Tab，首屏即挂载真实页面，避免占位与标题闪动。
    @State private var practiceTabMounted: Bool = true
    @StateObject private var sheetLibraryVM = SheetLibraryViewModel()
    @State private var didScheduleAudioWarmup = false
    
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
                    if newValue == 0 {
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
            .tag(0)

            NavigationStack {
                SheetLibraryView(vm: sheetLibraryVM)
            }
            .tabItem {
                Label("我的谱", systemImage: "music.note.list")
            }
            .tag(1)

            NavigationStack {
                TranscriptionHomeView()
            }
            .tabItem {
                Label("扒歌", systemImage: "waveform.path.ecg")
            }
            .tag(2)

            NavigationStack {
                ToolsTabView()
            }
            .tabItem {
                Label("工具", systemImage: "wrench.and.screwdriver")
            }
            .tag(3)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .task {
            guard !didScheduleAudioWarmup else { return }
            didScheduleAudioWarmup = true
            AudioStartupWarmup.shared.scheduleIfNeeded()
        }
    }
}

private struct ToolsTabView: View {
    /// 比全站 `pagePadding` 略紧，减少工具宫格外圈留白。
    private let gridEdgePadding: CGFloat = 12
    private let gridGap: CGFloat = 8
    private let cardAspectRatio: CGFloat = 0.92

    @State private var aboutVersionText: String = "--"
    @State private var showMailOpenFailed = false
    @State private var showPrivacyPolicyOpenFailed = false

    var body: some View {
        let pad = gridEdgePadding
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let toolColumns = [
                    GridItem(.flexible(), spacing: gridGap),
                    GridItem(.flexible(), spacing: gridGap),
                ]
                LazyVGrid(columns: toolColumns, spacing: gridGap) {
                    gridTile(
                        title: "节拍器",
                        subtitle: "BPM·拍号·独立练习节拍",
                        icon: "metronome"
                    ) { MetronomeView() }
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
                    .gridCellColumns(2)
                }

                Text("应用与支持")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    toolsSupportFeedbackMailRow()
                    Divider()
                        .overlay(SwiftAppTheme.line)
                        .padding(.leading, 52)
                    toolsSupportPrivacyPolicyRow()
                    Divider()
                        .overlay(SwiftAppTheme.line)
                        .padding(.leading, 52)
                    toolsSupportRow(
                        icon: "info.circle",
                        title: "关于与版本",
                        subtitle: aboutVersionText
                    ) {
                        AppVersionView()
                    }
                }
                .appCard()
            }
            .padding(pad)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("工具")
        .appPageBackground()
        .task {
            aboutVersionText = AppVersionInfoLoader.load().displayVersion
        }
        .alert("无法打开邮件", isPresented: $showMailOpenFailed) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请确认本机已安装「邮件」并已登录邮箱账户；或复制反馈内容通过其他方式发送。")
        }
        .alert("无法打开隐私政策", isPresented: $showPrivacyPolicyOpenFailed) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请检查网络连接后重试。")
        }
    }

    private func makeFeedbackMailURL() -> URL? {
        let addr = resolvedFeedbackRecipient().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addr.isEmpty else { return nil }
        let info = AppVersionInfoLoader.load()
        let subject = "玩乐吉他反馈（\(info.displayVersion)）"
        let body = "请描述问题、复现步骤或建议：\n\n"
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = addr
        c.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return c.url
    }

    private func toolsSupportFeedbackMailRow() -> some View {
        Button {
            guard let url = makeFeedbackMailURL() else {
                showMailOpenFailed = true
                return
            }
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    Task { @MainActor in
                        showMailOpenFailed = true
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .frame(width: 24)
                    .foregroundStyle(SwiftAppTheme.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("帮助与反馈")
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text("发邮件反馈")
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func makePrivacyPolicyURL() -> URL? {
        URL(string: kPrivacyPolicyURLString)
    }

    private func toolsSupportPrivacyPolicyRow() -> some View {
        Button {
            guard let url = makePrivacyPolicyURL() else {
                showPrivacyPolicyOpenFailed = true
                return
            }
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    Task { @MainActor in
                        showPrivacyPolicyOpenFailed = true
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .frame(width: 24)
                    .foregroundStyle(SwiftAppTheme.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("隐私政策")
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text("查看网页版隐私说明")
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func toolsSupportRow<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            TabBarHiddenContainer { destination() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(SwiftAppTheme.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
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
