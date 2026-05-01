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

/// 外部页面链接统一配置。
/// 发布前请将占位地址替换为真实 HTTPS 域名。
private enum AppLinks {
    static let privacyURL = "https://wanghanai.xyz/privacy.html"
    static let supportURL = "https://wanghanai.xyz/support.html"
}

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
        #if os(iOS)
        try? AppAudioSession.configureSharedForPlaybackAndRecording()
        #endif
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
            HostRootView()
                .environmentObject(PurchaseManager.shared)
        }
    }
}

/// 设为 `true` 时恢复首次启动全屏导览；暂时关闭时直接进入主界面。
private let kFirstLaunchTourEnabled = false

/// 根容器：首次启动展示导览，完成后不再出现（受 `kFirstLaunchTourEnabled` 控制）。
private struct HostRootView: View {
    var body: some View {
        if kFirstLaunchTourEnabled {
            HostRootWithFirstLaunchTour()
        } else {
            RootTabView()
        }
    }
}

private struct HostRootWithFirstLaunchTour: View {
    @AppStorage(FirstLaunchTourStorage.completedKey) private var tourCompleted = false

    var body: some View {
        RootTabView()
            .fullScreenCover(
                isPresented: Binding(
                    get: { !tourCompleted },
                    set: { presented in
                        if !presented { tourCompleted = true }
                    }
                )
            ) {
                FirstLaunchTourView()
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
                        title: AppL10n.t("tab_practice"),
                        detail: AppL10n.t("placeholder_practice_detail")
                    )
                }
            }
            .tabItem {
                Label(LocalizedStringResource("tab_practice", bundle: .main), systemImage: "figure.strengthtraining.traditional")
                    .accessibilityIdentifier("tab.practice")
            }
            .tag(0)
            .accessibilityIdentifier("screen.practice")

            NavigationStack {
                SheetLibraryView(vm: sheetLibraryVM)
            }
            .tabItem {
                Label(LocalizedStringResource("tab_mine_sheets", bundle: .main), systemImage: "music.note.list")
                    .accessibilityIdentifier("tab.sheets")
            }
            .tag(1)
            .accessibilityIdentifier("screen.sheets")

            NavigationStack {
                TranscriptionHomeView()
            }
            .tabItem {
                Label(LocalizedStringResource("tab_transcribe", bundle: .main), systemImage: "waveform.path.ecg")
                    .accessibilityIdentifier("tab.transcription")
            }
            .tag(2)
            .accessibilityIdentifier("screen.transcription")

            NavigationStack {
                ToolsTabView()
            }
            .tabItem {
                Label(LocalizedStringResource("tab_tools", bundle: .main), systemImage: "wrench.and.screwdriver")
                    .accessibilityIdentifier("tab.tools")
            }
            .tag(3)
            .accessibilityIdentifier("screen.tools")
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
    @State private var showSupportOpenFailed = false
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
                        title: AppL10n.t("tools_metronome_title"),
                        subtitle: AppL10n.t("tools_metronome_subtitle"),
                        icon: "metronome",
                        accessibilityIdentifier: "tools.metronome"
                    ) { MetronomeView() }
                    gridTile(
                        title: AppL10n.t("tools_tuner_title"),
                        subtitle: AppL10n.t("tools_tuner_subtitle"),
                        icon: "waveform",
                        accessibilityIdentifier: "tools.tuner"
                    ) { TunerView() }
                    gridTile(
                        title: AppL10n.t("tools_fretboard_title"),
                        subtitle: AppL10n.t("tools_fretboard_subtitle"),
                        icon: "square.grid.3x3",
                        accessibilityIdentifier: "tools.fretboard"
                    ) { FretboardView() }
                    gridTile(
                        title: AppL10n.t("tools_chord_lookup_title"),
                        subtitle: AppL10n.t("tools_chord_lookup_subtitle"),
                        icon: "pianokeys",
                        accessibilityIdentifier: "tools.chordLookup"
                    ) { ChordLookupMergedHostView() }
                }

                Text(LocalizedStringResource("section_app_support", bundle: .main))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    toolsSupportFeedbackMailRow()
                    Divider()
                        .overlay(SwiftAppTheme.line)
                        .padding(.leading, 52)
                    toolsSupportExternalSupportRow()
                    Divider()
                        .overlay(SwiftAppTheme.line)
                        .padding(.leading, 52)
                    toolsSupportPrivacyPolicyRow()
                    Divider()
                        .overlay(SwiftAppTheme.line)
                        .padding(.leading, 52)
                    toolsSupportRow(
                        icon: "info.circle",
                        title: AppL10n.t("about_version_title"),
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
        .navigationTitle(LocalizedStringResource("tools_nav_title", bundle: .main))
        .appPageBackground()
        .task {
            aboutVersionText = AppVersionInfoLoader.load().displayVersion
        }
        .alert(LocalizedStringResource("alert_cannot_open_mail_title", bundle: .main), isPresented: $showMailOpenFailed) {
            Button(LocalizedStringResource("button_ok", bundle: .main), role: .cancel) {}
        } message: {
            Text(LocalizedStringResource("alert_cannot_open_mail_message", bundle: .main))
        }
        .alert("无法打开技术支持页面", isPresented: $showSupportOpenFailed) {
            Button(LocalizedStringResource("button_ok", bundle: .main), role: .cancel) {}
        } message: {
            Text("请稍后重试，或在浏览器中手动访问。")
        }
        .alert(LocalizedStringResource("alert_cannot_open_privacy_title", bundle: .main), isPresented: $showPrivacyPolicyOpenFailed) {
            Button(LocalizedStringResource("button_ok", bundle: .main), role: .cancel) {}
        } message: {
            Text(LocalizedStringResource("alert_cannot_open_privacy_message", bundle: .main))
        }
    }

    private struct ChordLookupMergedHostView: View {
        private enum Mode: String, CaseIterable, Identifiable {
            case quick
            case custom
            var id: String { rawValue }
            var title: String {
                switch self {
                case .quick: return "常用和弦"
                case .custom: return "自定义速查"
                }
            }
        }

        @State private var mode: Mode = .quick

        var body: some View {
            VStack(spacing: 0) {
                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, SwiftAppTheme.pagePadding)
                .padding(.top, 8)

                if mode == .quick {
                    ChordChartView()
                } else {
                    ChordLookupView()
                }
            }
            .navigationTitle(AppL10n.t("tools_chord_lookup_title"))
            .appPageBackground()
        }
    }

    private func makeFeedbackMailURL() -> URL? {
        let addr = resolvedFeedbackRecipient().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addr.isEmpty else { return nil }
        let info = AppVersionInfoLoader.load()
        let subject = String(format: AppL10n.t("feedback_mail_subject"), info.displayVersion)
        let body = AppL10n.t("feedback_mail_body")
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
                    Text(LocalizedStringResource("support_feedback_title", bundle: .main))
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(LocalizedStringResource("support_feedback_subtitle", bundle: .main))
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

    private func makeSupportURL() -> URL? {
        URL(string: AppLinks.supportURL)
    }

    private func toolsSupportExternalSupportRow() -> some View {
        Button {
            guard let url = makeSupportURL() else {
                showSupportOpenFailed = true
                return
            }
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    Task { @MainActor in
                        showSupportOpenFailed = true
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lifepreserver")
                    .frame(width: 24)
                    .foregroundStyle(SwiftAppTheme.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("技术支持")
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text("查看常见问题与云端处理说明")
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

    private func makePrivacyPolicyURL() -> URL? {
        URL(string: AppLinks.privacyURL)
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
                    Text(LocalizedStringResource("support_privacy_title", bundle: .main))
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(LocalizedStringResource("support_privacy_subtitle", bundle: .main))
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
        accessibilityIdentifier: String,
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
        .accessibilityIdentifier(accessibilityIdentifier)
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
