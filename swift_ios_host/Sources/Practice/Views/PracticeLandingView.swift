import SwiftUI
import Core
import Ear

/// 练习模块首页：首屏仅保留「视唱练耳 / 练琴」两条主路径。
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
                    Button("重试") { Task { await vm.refresh() } }
                        .appPrimaryButton()
                }
                .padding(24)
            } else {
                content
            }
        }
        .navigationTitle("练习")
        .appNavigationBarChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PracticeCalendarScreen(sessions: vm.sessions)
                } label: {
                    Label("训练日历", systemImage: "calendar")
                }
            }
        }
        .task { await vm.refresh() }
    }

    private var content: some View {
        let dailyGoalMinutes = 20
        let progress = min(1.0, max(0.0, Double(vm.summary.todayMinutes) / Double(dailyGoalMinutes)))

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("今日目标：\(dailyGoalMinutes) 分钟")
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("已完成：\(vm.summary.todayMinutes) 分钟").foregroundStyle(SwiftAppTheme.text)
                        Text("已练习：\(vm.summary.todaySessions) 次").foregroundStyle(SwiftAppTheme.text)
                        Text("连续打卡：\(vm.summary.streakDays) 天").foregroundStyle(SwiftAppTheme.text)
                    }
                    ProgressView(value: progress)
                        .tint(SwiftAppTheme.brand)
                }
                .appCard()

                Text("选择训练方向")
                    .appSectionTitle()
                    .padding(.top, 6)

                landingEntryCard(
                    title: "视唱练耳",
                    subtitle: "音程、和弦听辨、和弦进行、视唱训练",
                    icon: "ear"
                ) {
                    EarPracticeHubScreen()
                }

                landingEntryCard(
                    title: "练琴",
                    subtitle: "和弦切换、节奏扫弦、音阶爬格子",
                    icon: "music.note"
                ) {
                    GuitarPracticeHubScreen()
                }

                HStack {
                    Text("最近训练").appSectionTitle()
                    Spacer()
                    NavigationLink("查看训练日历") {
                        PracticeCalendarScreen(sessions: vm.sessions)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                }
                .padding(.top, 6)

                if let latest = vm.latestSession {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(latest.taskName)
                                .font(.headline)
                                .foregroundStyle(SwiftAppTheme.text)
                            Spacer()
                            Text("难度 \(latest.difficulty)/5")
                                .font(.subheadline)
                                .foregroundStyle(SwiftAppTheme.muted)
                        }
                        Text(PracticeSessionDisplay.subtitle(latest))
                            .font(.subheadline)
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    .appCard()
                } else {
                    Text("还没有练习记录，先开始第一次练习吧。")
                        .foregroundStyle(SwiftAppTheme.muted)
                        .appCard()
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .appPageBackground()
        .refreshable { await vm.refresh() }
    }

    private func landingEntryCard<Destination: View>(
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
        .buttonStyle(.plain)
    }
}

/// Keep old symbol name to avoid touching existing call sites.
struct PracticeHomeView: View {
    var body: some View {
        PracticeLandingView()
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
                    EarMcqSessionView(title: "和弦听辨", bank: "A", totalQuestions: 10)
                }
                PracticeLinkCard(title: "和弦进行", subtitle: "常见流行进行 · 四选一", icon: "music.note.list") {
                    EarMcqSessionView(title: "和弦进行", bank: "B", totalQuestions: 10)
                }
                PracticeLinkCard(
                    title: "视唱训练",
                    subtitle: "单音视唱 · 可选音域 · 麦克风实时判定",
                    icon: "mic"
                ) {
                    SightSingingSetupView()
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
                        PracticeTaskRouterScreen(task: task)
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
        .buttonStyle(.plain)
    }
}

@MainActor
private final class PracticeLandingViewModel: ObservableObject {
    @Published var loading: Bool = true
    @Published var loadError: String?
    @Published var summary: PracticeSummary = .init(todayMinutes: 0, todaySessions: 0, streakDays: 0)
    @Published var sessions: [PracticeSession] = []

    private let store: PracticeSessionStore

    init(store: PracticeSessionStore = PracticeLocalStore()) {
        self.store = store
    }

    var latestSession: PracticeSession? { sessions.first }

    func refresh() async {
        loading = true
        loadError = nil
        do {
            async let summary = store.loadSummary(now: nil)
            async let sessions = store.loadSessions()
            let (s, list) = try await (summary, sessions)
            self.summary = s
            self.sessions = list
            loading = false
        } catch {
            loadError = "读取本地练习记录失败：\(error)"
            summary = .init(todayMinutes: 0, todaySessions: 0, streakDays: 0)
            sessions = []
            loading = false
        }
    }
}

private enum PracticeSessionDisplay {
    static func subtitle(_ session: PracticeSession) -> String {
        let timePart = "\(formatDate(session.endedAt)) · \(formatDuration(session.durationSeconds))"
        if let id = session.rhythmPatternId, let name = strummingPatternNameForId(id) {
            return "\(name) · \(timePart)"
        }
        return timePart
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

    private static func formatDate(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.month, .day], from: date)
        let month = String(format: "%02d", comps.month ?? 0)
        let day = String(format: "%02d", comps.day ?? 0)
        return "\(month)/\(day)"
    }
}

/// 任务入口路由：后续会逐个替换为真实页面。
private struct PracticeTaskRouterScreen: View {
    let task: PracticeTask
    private let store: PracticeSessionStore = PracticeLocalStore()

    var body: some View {
        switch task.id {
        case "chord-switch":
            ChordPracticeSelectionView(task: task, store: store)
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
