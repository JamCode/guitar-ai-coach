import SwiftUI

/// 练习模块首页：当前产品聚焦自适应练耳，吉他专项入口暂时隐藏但保留旧实现。
struct PracticeLandingView: View {
    @StateObject private var vm = PracticeLandingViewModel()
    @State private var showingEarStats = false

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
                Menu {
                    NavigationLink {
                        TabBarHiddenContainer {
                            FocusedEarHubView()
                        }
                    } label: {
                        Label("专项训练", systemImage: "target")
                    }

                    Button {
                        showingEarStats = true
                    } label: {
                        Label("训练统计", systemImage: "chart.bar.fill")
                    }

                    NavigationLink {
                        TabBarHiddenContainer {
                            PracticeCalendarScreen(sessions: vm.sessions)
                        }
                    } label: {
                        Label("练习日历", systemImage: "calendar")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(SwiftAppTheme.text)
                }
                .accessibilityLabel("更多")
            }
        }
        .sheet(isPresented: $showingEarStats) {
            NavigationStack {
                EarStatsOverviewView()
            }
        }
        .task { await vm.refresh() }
    }

    private var content: some View {
        AdaptiveEarTrainingView(sessions: vm.sessions)
        .refreshable { await vm.refresh(blockingUI: false) }
    }
}

/// Keep old symbol name to avoid touching existing call sites.
struct PracticeHomeView: View {
    var body: some View {
        ForegroundPracticeSessionTracker(task: kAdaptiveEarTrainingPracticeTask, note: nil) {
            PracticeLandingView()
        }
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
                            if let earLine = PracticeSessionDisplay.earAccuracyLine(session) {
                                Text(earLine)
                                    .font(.subheadline)
                                    .foregroundStyle(SwiftAppTheme.text)
                            }
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

@MainActor
private final class PracticeLandingViewModel: ObservableObject {
    @Published var loading: Bool = true
    @Published var loadError: String?
    @Published var sessions: [PracticeSession] = []

    /// 已成功加载过至少一次；再次进入 Tab 时 `.task` 会重跑，但不应再全屏 `ProgressView` 闪一下。
    private var hasShownInitialContent = false

    private let store: PracticeSessionStore

    init(
        store: PracticeSessionStore = PracticeLocalStore()
    ) {
        self.store = store
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
            sessions = loadedSessions
            hasShownInitialContent = true
            loading = false
        } catch {
            hasShownInitialContent = false
            loadError = String(format: AppL10n.t("practice_error_load"), String(describing: error))
            sessions = []
            loading = false
        }
    }
}

private enum PracticeSessionDisplay {
    /// 练耳任务：展示本次停留期间判题正确率（依赖 `ForegroundPracticeSessionTracker` 写入的计数）。
    static func earAccuracyLine(_ session: PracticeSession) -> String? {
        guard let answered = session.earAnsweredCount, let correct = session.earCorrectCount else { return nil }
        guard answered > 0 else { return nil }
        let pct = Int((Double(correct) / Double(answered) * 100).rounded())
        return "练耳作答 \(answered) 题 · 答对 \(correct) · 正确率 \(pct)%"
    }

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

/// 练耳统计概览（从本地存储加载，与自适应练耳共享数据）
private struct EarStatsOverviewView: View {
    @State private var state: AdaptiveEarAbilityState = .initial
    @State private var records: [AdaptiveEarAttemptRecord] = []
    @State private var loaded = false
    private let store: AdaptiveEarTrainingStoring = UserDefaultsAdaptiveEarTrainingStore()

    var body: some View {
        List {
            if !loaded {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else {
                Section("听力能力") {
                    statsRow("总听力值", "\(state.roundedOverallRating) · \(state.levelTitle)")
                    statsRow("音程", "\(Int(state.intervalRating.rounded()))")
                    statsRow("和弦", "\(Int(state.chordRating.rounded()))")
                    statsRow("和弦进行", "\(Int(state.progressionRating.rounded()))")
                    statsRow("单音", "\(Int(state.singleNoteRating.rounded()))")
                    statsRow("节奏", "\(Int(state.rhythmRating.rounded()))")
                }
                Section("近期表现") {
                    statsRow("总题数", "\(records.count)")
                    statsRow("近 20 题正确率", recentAccuracyText)
                    statsRow("连续答对", "\(state.consecutiveCorrect)")
                    statsRow("连续答错", "\(state.consecutiveWrong)")
                    statsRow("今日题数", "\(todayCount)")
                }
            }
        }
        .navigationTitle("训练统计")
        .task {
            state = await store.loadState()
            records = await store.loadAttempts()
            loaded = true
        }
    }

    private var recentAccuracyText: String {
        guard let accuracy = AdaptiveEarTrainingEngine.recentAccuracy(records: records) else { return "--" }
        return "\(Int((accuracy * 100).rounded()))%"
    }

    private var todayCount: Int {
        let calendar = Calendar(identifier: .gregorian)
        return records.filter { calendar.isDateInToday($0.answeredAt) }.count
    }

    private func statsRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
