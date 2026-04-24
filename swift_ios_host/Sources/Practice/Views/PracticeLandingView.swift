import SwiftUI
import Core
import Ear
import Practice

/// 练习首页模块：产品要求暂时隐藏，恢复时改为 `true`。
private enum PracticeLandingVisibility {
    static let showTodayRecommendedTraining = false
    static let showAllTrainingItemsLink = false
}

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
                    Button(AppL10n.t("practice_retry")) { Task { await vm.refresh(blockingUI: true) } }
                        .appPrimaryButton()
                }
                .padding(24)
            } else {
                content
            }
        }
        .background(SwiftAppTheme.bg.ignoresSafeArea())
        .navigationTitle(AppL10n.t("practice_screen_title"))
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
                .accessibilityLabel(AppL10n.t("practice_a11y_training_calendar"))
            }
        }
        .task { await vm.refresh() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if PracticeLandingVisibility.showTodayRecommendedTraining {
                    todayTrainingCard
                }

                PracticeRecentSummaryCard(sessions: vm.sessions)

                Text(AppL10n.t("practice_section_ear"))
                    .appSectionTitle()

                PracticeLinkCard(
                    title: AppL10n.t("task_interval_ear_name"),
                    subtitle: AppL10n.t("practice_link_interval_sub"),
                    icon: "play.circle"
                ) {
                    ForegroundPracticeSessionTracker(task: kIntervalEarPracticeTask, note: nil) {
                        IntervalEarView()
                    }
                }
                PracticeLinkCard(
                    title: AppL10n.t("task_ear_chord_mcq_name"),
                    subtitle: AppL10n.t("practice_link_ear_chord_sub"),
                    icon: "pianokeys"
                ) {
                    ForegroundPracticeSessionTracker(task: kEarChordMcqPracticeTask, note: nil) {
                        EarMcqSessionView(title: AppL10n.t("task_ear_chord_mcq_name"), bank: "A")
                    }
                }
                PracticeLinkCard(
                    title: AppL10n.t("task_ear_progression_mcq_name"),
                    subtitle: AppL10n.t("practice_link_ear_prog_sub"),
                    icon: "music.note.list"
                ) {
                    ForegroundPracticeSessionTracker(task: kEarProgressionMcqPracticeTask, note: nil) {
                        EarMcqSessionView(title: AppL10n.t("task_ear_progression_mcq_name"), bank: "B")
                    }
                }
                if EarPracticeHubVisibility.showSightSingingTraining {
                    PracticeLinkCard(
                        title: AppL10n.t("task_sight_singing_name"),
                        subtitle: AppL10n.t("task_ear_mcq_sight_subtitle"),
                        icon: "mic"
                    ) {
                        ForegroundPracticeSessionTracker(task: kSightSingingPracticeTask, note: nil) {
                            SightSingingSessionView()
                        }
                    }
                }

                Text(AppL10n.t("practice_section_guitar"))
                    .appSectionTitle()

                ForEach(kDefaultPracticeTasks) { task in
                    PracticeLinkCard(
                        title: task.localizedName,
                        subtitle: task.localizedDescription,
                        icon: practiceHomeIcon(for: task.id)
                    ) {
                        PracticeTaskRouterScreen(task: task)
                    }
                }

                if PracticeLandingVisibility.showAllTrainingItemsLink {
                    NavigationLink {
                        TabBarHiddenContainer {
                            PracticeTrainingCatalogView()
                        }
                    } label: {
                        HStack {
                            Text(AppL10n.t("practice_all_training"))
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
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .practiceScrollPageBackground()
        .refreshable { await vm.refresh(blockingUI: false) }
    }

    private func practiceHomeIcon(for taskId: String) -> String {
        switch taskId {
        case "chord-switch": return "guitars"
        case "rhythm-strum": return "waveform"
        case "scale-walk": return "hand.raised.fingers.spread"
        default: return "music.note.list"
        }
    }

    private var todayTrainingCard: some View {
        let outerRadius: CGFloat = 20
        let innerRadius: CGFloat = 16

        return VStack(alignment: .leading, spacing: 14) {
            Text(AppL10n.t("practice_today_recommend"))
                .font(.title3.weight(.bold))
                .foregroundStyle(SwiftAppTheme.text)

            if vm.recommendationItems.isEmpty {
                Text(AppL10n.t("practice_today_recommend_empty"))
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

                            Text(item.module.localizedTitle)
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
                Text(AppL10n.t("practice_start_training"))
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
}

private enum PracticeHomeCopy {
    static func rollingSummaryLine(sessionCount: Int, totalSeconds: Int) -> String {
        let totalMinutes = max(0, totalSeconds) / 60
        let durationText: String = {
            let m = totalMinutes
            let h = m / 60
            let rem = m % 60
            if h > 0 {
                if rem > 0 {
                    return String(format: AppL10n.t("time_hours_minutes"), h, rem)
                }
                return String(format: AppL10n.t("time_hours_only"), h)
            }
            return String(format: AppL10n.t("time_minutes"), m)
        }()
        return String(format: AppL10n.t("practice_rolling_format"), sessionCount, durationText)
    }

    static func lastPracticeLine(endedAt: Date?, now: Date = Date()) -> String {
        guard let endedAt else { return AppL10n.t("practice_last_never") }
        let cal = Calendar(identifier: .gregorian)
        let timeOnly = DateFormatter()
        timeOnly.locale = .current
        timeOnly.timeStyle = .short
        timeOnly.dateStyle = .none
        if cal.isDate(endedAt, inSameDayAs: now) {
            return String(format: AppL10n.t("practice_last_today"), timeOnly.string(from: endedAt))
        }
        let dateTime = DateFormatter()
        dateTime.locale = .current
        dateTime.dateStyle = .medium
        dateTime.timeStyle = .short
        return String(format: AppL10n.t("practice_last_past"), dateTime.string(from: endedAt))
    }
}

private struct PracticeRecentSummaryCard: View {
    let sessions: [PracticeSession]

    var body: some View {
        let now = Date()
        let stats = computeRollingSevenDayPracticeStats(sessions, now: now)
        let last = latestCompletedPracticeEndedAt(sessions)
        VStack(alignment: .leading, spacing: 6) {
            Text(PracticeHomeCopy.rollingSummaryLine(sessionCount: stats.sessionCount, totalSeconds: stats.totalDurationSeconds))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.text)
            Text(PracticeHomeCopy.lastPracticeLine(endedAt: last, now: now))
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SwiftAppTheme.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }
}

/// Keep old symbol name to avoid touching existing call sites.
struct PracticeHomeView: View {
    var body: some View {
        PracticeLandingView()
    }
}

/// 视唱训练入口：产品要求暂时从练耳列表与目录中隐藏，恢复时改为 `true`。
private enum EarPracticeHubVisibility {
    static let showSightSingingTraining = false
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
                Text(AppL10n.t("practice_nav_ear_full"))
                    .font(.headline)
                    .foregroundStyle(SwiftAppTheme.text)
                Text(AppL10n.t("practice_ear_hub_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .padding(.bottom, 4)

                PracticeLinkCard(
                    title: AppL10n.t("task_interval_ear_name"),
                    subtitle: AppL10n.t("practice_link_interval_sub"),
                    icon: "play.circle"
                ) {
                    ForegroundPracticeSessionTracker(task: kIntervalEarPracticeTask, note: nil) {
                        IntervalEarView()
                    }
                }
                PracticeLinkCard(
                    title: AppL10n.t("task_ear_chord_mcq_name"),
                    subtitle: AppL10n.t("practice_link_ear_chord_sub"),
                    icon: "pianokeys"
                ) {
                    ForegroundPracticeSessionTracker(task: kEarChordMcqPracticeTask, note: nil) {
                        EarMcqSessionView(title: AppL10n.t("task_ear_chord_mcq_name"), bank: "A")
                    }
                }
                PracticeLinkCard(
                    title: AppL10n.t("task_ear_progression_mcq_name"),
                    subtitle: AppL10n.t("practice_link_ear_prog_sub"),
                    icon: "music.note.list"
                ) {
                    ForegroundPracticeSessionTracker(task: kEarProgressionMcqPracticeTask, note: nil) {
                        EarMcqSessionView(title: AppL10n.t("task_ear_progression_mcq_name"), bank: "B")
                    }
                }
                if EarPracticeHubVisibility.showSightSingingTraining {
                    PracticeLinkCard(
                        title: AppL10n.t("task_sight_singing_name"),
                        subtitle: AppL10n.t("task_ear_mcq_sight_subtitle"),
                        icon: "mic"
                    ) {
                        ForegroundPracticeSessionTracker(task: kSightSingingPracticeTask, note: nil) {
                            SightSingingSessionView()
                        }
                    }
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(AppL10n.t("practice_nav_ear_full"))
        .appPageBackground()
    }
}

private struct GuitarPracticeHubScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppL10n.t("practice_nav_guitar_hub"))
                    .font(.headline)
                    .foregroundStyle(SwiftAppTheme.text)
                Text(AppL10n.t("practice_guitar_hub_subtitle"))
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
                                Text(task.localizedName)
                                    .font(.headline)
                                    .foregroundStyle(SwiftAppTheme.text)
                                Text(String(format: AppL10n.t("practice_task_line"), Int64(task.targetMinutes), task.localizedDescription))
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
        .navigationTitle(AppL10n.t("practice_nav_guitar_hub"))
        .appPageBackground()
    }
}

private struct PracticeTrainingCatalogView: View {
    var body: some View {
        List {
            Section(AppL10n.t("practice_catalog_ear")) {
                NavigationLink(AppL10n.t("task_interval_ear_name")) {
                    TabBarHiddenContainer {
                        ForegroundPracticeSessionTracker(task: kIntervalEarPracticeTask, note: nil) {
                            IntervalEarView()
                        }
                    }
                }
                NavigationLink(AppL10n.t("task_ear_chord_mcq_name")) {
                    TabBarHiddenContainer {
                        ForegroundPracticeSessionTracker(task: kEarChordMcqPracticeTask, note: nil) {
                            EarMcqSessionView(title: AppL10n.t("task_ear_chord_mcq_name"), bank: "A")
                        }
                    }
                }
                NavigationLink(AppL10n.t("task_ear_progression_mcq_name")) {
                    TabBarHiddenContainer {
                        ForegroundPracticeSessionTracker(task: kEarProgressionMcqPracticeTask, note: nil) {
                            EarMcqSessionView(title: AppL10n.t("task_ear_progression_mcq_name"), bank: "B")
                        }
                    }
                }
                if EarPracticeHubVisibility.showSightSingingTraining {
                    NavigationLink(AppL10n.t("task_sight_singing_name")) {
                        TabBarHiddenContainer {
                            ForegroundPracticeSessionTracker(task: kSightSingingPracticeTask, note: nil) {
                                SightSingingSessionView()
                            }
                        }
                    }
                }
            }

            Section(AppL10n.t("practice_catalog_guitar")) {
                ForEach(kDefaultPracticeTasks) { task in
                    NavigationLink(task.localizedName) {
                        TabBarHiddenContainer {
                            PracticeTaskRouterScreen(task: task)
                        }
                    }
                }
            }
        }
        .navigationTitle(AppL10n.t("practice_catalog_title"))
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
                    AppL10n.t("practice_pick_date"),
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(SwiftAppTheme.brand)
                .appCard()

                Text(String(format: AppL10n.t("practice_month_stats"), monthPracticedDays))
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .appCard()

                Text(AppL10n.t("practice_today_log"))
                    .appSectionTitle()
                    .padding(.top, 4)

                if selectedDaySessions.isEmpty {
                    Text(AppL10n.t("practice_no_sessions_day"))
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
                                Text(String(format: AppL10n.t("practice_row_time_diff"), time, session.difficulty))
                                    .foregroundStyle(SwiftAppTheme.muted)
                            }
                            Text(String(format: AppL10n.t("practice_row_duration"), PracticeSessionDisplay.duration(session.durationSeconds)))
                                .font(.subheadline)
                                .foregroundStyle(SwiftAppTheme.muted)
                        }
                        .appCard()
                    }
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(AppL10n.t("practice_calendar_title"))
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
            loadError = String(format: AppL10n.t("practice_error_load"), String(describing: error))
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
            if let chordTask = kDefaultPracticeTasks.first(where: { $0.id == "chord-switch" }) {
                ForegroundPracticeSessionTracker(task: chordTask, note: nil) {
                    ChordPracticeSessionView()
                }
            } else {
                ChordPracticeSessionView()
            }
        case "rhythm-strum":
            RhythmStrummingView(task: task, store: store)
        case "scale-walk":
            ScaleWarmupSessionView(task: task, store: store)
        default:
            VStack(spacing: 12) {
                Image(systemName: "hammer.circle")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                Text(task.localizedName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.text)
                Text(String(format: AppL10n.t("practice_task_migrating"), task.id))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationTitle(task.localizedName)
            .appPageBackground()
        }
    }
}
