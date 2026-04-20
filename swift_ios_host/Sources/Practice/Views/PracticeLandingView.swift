import SwiftUI
import Core
import Ear
import Practice

/// 练习模块首页：突出「今日训练」题单，并保留专项快速入口。
struct PracticeLandingView: View {
    @StateObject private var vm = PracticeLandingViewModel()

    var body: some View {
        Group {
            if vm.loading {
                ProgressView()
            } else if let error = vm.loadError {
                VStack(spacing: 12) {
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SwiftAppTheme.text)
                    Button("重试") { Task { await vm.refresh(blockingUI: true) } }
                        .appPrimaryButton()
                }
                .padding(24)
            } else {
                content
            }
        }
        .background(SwiftAppTheme.bg.ignoresSafeArea())
        .navigationTitle("练习")
        .appNavigationBarChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TabBarHiddenContainer {
                        PracticeCalendarScreen(sessions: vm.sessions)
                    }
                } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(SwiftAppTheme.text)
                }
                .accessibilityLabel("训练日历")
            }
        }
        .task { await vm.refresh() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                todayTrainingCard

                Text("快速开始")
                    .appSectionTitle()

                HStack(spacing: 10) {
                    quickStartCard(
                        title: "视唱练耳",
                        subtitle: "初级"
                    ) {
                        EarPracticeHubScreen()
                    }
                    quickStartCard(
                        title: "练琴",
                        subtitle: "初级"
                    ) {
                        GuitarPracticeHubScreen()
                    }
                }

                NavigationLink {
                    TabBarHiddenContainer {
                        PracticeTrainingCatalogView()
                    }
                } label: {
                    HStack {
                        Text("全部训练项目")
                            .font(.subheadline)
                            .foregroundStyle(SwiftAppTheme.muted)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .practiceScrollPageBackground()
        .refreshable { await vm.refresh(blockingUI: false) }
    }

    private var todayTrainingCard: some View {
        let outerRadius: CGFloat = 20
        let innerRadius: CGFloat = 16

        return VStack(alignment: .leading, spacing: 14) {
            Text("今日推荐训练")
                .font(.title3.weight(.bold))
                .foregroundStyle(SwiftAppTheme.text)

            if vm.recommendationItems.isEmpty {
                Text("暂无推荐，点击开始训练后将自动生成。")
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(SwiftAppTheme.surfaceSoft)
                    .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                            .stroke(SwiftAppTheme.line, lineWidth: 1)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.recommendationItems.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Image(systemName: item.module.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(SwiftAppTheme.brand)
                                .frame(width: 26, alignment: .center)

                            Text(item.module.title)
                                .font(.headline)
                                .foregroundStyle(SwiftAppTheme.text)
                                .lineLimit(1)

                            Spacer(minLength: 8)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 12)
                        .allowsHitTesting(false)

                        if index < vm.recommendationItems.count - 1 {
                            Divider()
                                .overlay(SwiftAppTheme.line)
                                .padding(.leading, 50) // 对齐图标列，避免分割线顶到左边缘
                        }
                    }
                }
                .background(SwiftAppTheme.surfaceSoft)
                .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                        .stroke(SwiftAppTheme.line, lineWidth: 1)
                )
            }

            NavigationLink {
                TabBarHiddenContainer {
                    TodayRecommendationListView(
                        sessions: vm.sessions,
                        referenceDate: vm.recommendationDay,
                        initialIndex: 0
                    )
                }
            } label: {
                Text("开始训练")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SwiftAppTheme.brand)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(SwiftAppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: outerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 10)
    }

    private func quickStartCard<Destination: View>(
        title: String,
        subtitle: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: TabBarHiddenContainer { destination() }) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: title == "练琴" ? "guitars" : "music.quarternote.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.brand)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(SwiftAppTheme.text)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        }
        .buttonStyle(.plain)
    }
}

/// Keep old symbol name to avoid touching existing call sites.
struct PracticeHomeView: View {
    var body: some View {
        PracticeLandingView()
    }
}

private extension View {
    /// 练习首页滚动区：与全站 `SwiftAppTheme.bg` 一致，随系统亮/暗色变化（不再强制纯白）。
    func practiceScrollPageBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(SwiftAppTheme.bg.ignoresSafeArea())
            .tint(SwiftAppTheme.brand)
    }
}

private struct EarPracticeHubScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("视唱练耳")
                    .font(.headline)
                    .foregroundStyle(SwiftAppTheme.text)
                Text("选择一个训练开始，建议每次 10 分钟。")
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .padding(.bottom, 4)

                PracticeLinkCard(title: "音程识别", subtitle: "两音上行、四选一", icon: "play.circle") {
                    IntervalEarView()
                }
                PracticeLinkCard(
                    title: "和弦听辨",
                    subtitle: "大三 / 小三 / 属七 · 题库离线 · 吉他采样合成",
                    icon: "pianokeys"
                ) {
                    EarMcqSessionView(title: "和弦听辨", bank: "A")
                }
                PracticeLinkCard(title: "和弦进行", subtitle: "常见流行进行 · 不限题量 · 指法揭示", icon: "music.note.list") {
                    EarMcqSessionView(title: "和弦进行", bank: "B")
                }
                PracticeLinkCard(
                    title: "视唱训练",
                    subtitle: "立刻出题 · 齿轮内调音域与模式 · 设置自动保存",
                    icon: "mic"
                ) {
                    SightSingingSessionView()
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("视唱练耳")
        .appPageBackground()
    }
}

private struct GuitarPracticeHubScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("练琴")
                    .font(.headline)
                    .foregroundStyle(SwiftAppTheme.text)
                Text("从基础练习开始，优先保持节拍稳定。")
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .padding(.bottom, 4)

                ForEach(kDefaultPracticeTasks) { task in
                    NavigationLink {
                        TabBarHiddenContainer {
                            PracticeTaskRouterScreen(task: task)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.name)
                                    .font(.headline)
                                    .foregroundStyle(SwiftAppTheme.text)
                                Text("\(task.targetMinutes) 分钟 · \(task.description)")
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
                    .buttonStyle(.plain)
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("练琴")
        .appPageBackground()
    }
}

private struct PracticeTrainingCatalogView: View {
    var body: some View {
        List {
            Section("视唱练耳") {
                NavigationLink("音程识别") { TabBarHiddenContainer { IntervalEarView() } }
                NavigationLink("和弦听辨") {
                    TabBarHiddenContainer { EarMcqSessionView(title: "和弦听辨", bank: "A") }
                }
                NavigationLink("和弦进行") {
                    TabBarHiddenContainer { EarMcqSessionView(title: "和弦进行", bank: "B") }
                }
                NavigationLink("视唱训练") {
                    TabBarHiddenContainer {
                        SightSingingSessionView()
                    }
                }
            }

            Section("练琴") {
                ForEach(kDefaultPracticeTasks) { task in
                    NavigationLink(task.name) {
                        TabBarHiddenContainer {
                            PracticeTaskRouterScreen(task: task)
                        }
                    }
                }
            }
        }
        .navigationTitle("全部训练项目")
        .appPageBackground()
    }
}

private struct PracticeCalendarScreen: View {
    let sessions: [PracticeSession]
    @State private var selectedDate: Date = Date()

    private var selectedDaySessions: [PracticeSession] {
        let day = calendar.startOfDay(for: selectedDate)
        return sessions.filter { calendar.isDate($0.endedAt, inSameDayAs: day) }
    }

    private var monthPracticedDays: Int {
        let selectedMonth = calendar.dateComponents([.year, .month], from: selectedDate)
        let daySet = Set(
            sessions
                .map { calendar.startOfDay(for: $0.endedAt) }
                .filter { day in
                    calendar.dateComponents([.year, .month], from: day) == selectedMonth
                }
        )
        return daySet.count
    }

    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                DatePicker(
                    "选择日期",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(SwiftAppTheme.brand)
                .appCard()

                Text("本月有 \(monthPracticedDays) 天完成了训练")
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .appCard()

                Text("当天记录")
                    .appSectionTitle()
                    .padding(.top, 4)

                if selectedDaySessions.isEmpty {
                    Text("所选日期暂无训练记录。")
                        .foregroundStyle(SwiftAppTheme.muted)
                        .appCard()
                } else {
                    ForEach(selectedDaySessions) { session in
                        let time = PracticeSessionDisplay.clock(session.endedAt)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.taskName)
                                    .foregroundStyle(SwiftAppTheme.text)
                                Spacer()
                                Text("\(time) · 难度 \(session.difficulty)/5")
                                    .foregroundStyle(SwiftAppTheme.muted)
                            }
                            Text("训练时长 \(PracticeSessionDisplay.duration(session.durationSeconds))")
                                .font(.subheadline)
                                .foregroundStyle(SwiftAppTheme.muted)
                        }
                        .appCard()
                    }
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("训练日历")
        .appPageBackground()
    }
}

private struct PracticeLinkCard<Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: TabBarHiddenContainer { destination() }) {
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
        .buttonStyle(.plain)
    }
}

@MainActor
private final class PracticeLandingViewModel: ObservableObject {
    @Published var loading: Bool = true
    @Published var loadError: String?
    @Published var sessions: [PracticeSession] = []
    @Published var recommendationItems: [TodayRecommendationItem] = []
    @Published var recommendationDay: Date = Calendar(identifier: .gregorian).startOfDay(for: Date())

    /// 已成功加载过至少一次；再次进入 Tab 时 `.task` 会重跑，但不应再全屏 `ProgressView` 闪一下。
    private var hasShownInitialContent = false

    private let store: PracticeSessionStore
    private let historyStore: any RecommendationHistoryStore

    init(
        store: PracticeSessionStore = PracticeLocalStore(),
        historyStore: any RecommendationHistoryStore = UserDefaultsRecommendationHistoryStore()
    ) {
        self.store = store
        self.historyStore = historyStore
    }

    /// - Parameter blockingUI: `nil` 表示「仅首次（或上次失败后）」显示全屏加载；`false` 用于下拉刷新；`true` 用于用户点「重试」。
    func refresh(blockingUI: Bool? = nil) async {
        let shouldShowBlockingLoader = blockingUI ?? !hasShownInitialContent
        if shouldShowBlockingLoader {
            loading = true
        }
        loadError = nil
        do {
            let loadedSessions = try await store.loadSessions()
            let calendar = Calendar(identifier: .gregorian)
            let day = calendar.startOfDay(for: Date())
            recommendationDay = day

            let history = await historyStore.loadRecent(now: day, days: 7)
            let merged = RecommendationHistoryMerging.mergeLegacyPracticeRecords(stored: history, sessions: loadedSessions)
            var planner = TodayRecommendationPlanner(referenceDate: day)

            sessions = loadedSessions
            recommendationItems = await planner.buildRecommendations(historyRecords: merged)
            hasShownInitialContent = true
            loading = false
        } catch {
            hasShownInitialContent = false
            loadError = "读取本地练习记录失败：\(error)"
            sessions = []
            recommendationItems = []
            loading = false
        }
    }
}

private enum PracticeSessionDisplay {
    static func duration(_ seconds: Int) -> String {
        formatDuration(seconds)
    }

    static func clock(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let hour = String(format: "%02d", comps.hour ?? 0)
        let minute = String(format: "%02d", comps.minute ?? 0)
        return "\(hour):\(minute)"
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let m = String(format: "%02d", s / 60)
        let r = String(format: "%02d", s % 60)
        return "\(m):\(r)"
    }
}

/// 任务入口路由：后续会逐个替换为真实页面。
private struct PracticeTaskRouterScreen: View {
    let task: PracticeTask
    private let store: PracticeSessionStore = PracticeLocalStore()

    var body: some View {
        switch task.id {
        case "chord-switch":
            ChordPracticeSessionView()
        case "rhythm-strum":
            RhythmStrummingView(task: task, store: store)
        case "scale-walk":
            PracticeTimerSessionView(task: task, store: store)
        default:
            VStack(spacing: 12) {
                Image(systemName: "hammer.circle")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                Text(task.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.text)
                Text("该任务正在迁移：\(task.id)")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationTitle(task.name)
            .appPageBackground()
        }
    }
}
