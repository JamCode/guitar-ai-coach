import SwiftUI
import Core

/// 练习模块首页（Swift 版本）：提供任务入口、今日进度与历史记录。
struct PracticeHomeView: View {
    @StateObject private var vm = PracticeHomeViewModel()

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
        .task { await vm.refresh() }
    }

    private var content: some View {
        let dailyGoalMinutes = 20
        let progress = min(1.0, max(0.0, Double(vm.summary.todayMinutes) / Double(dailyGoalMinutes)))

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // 今日进度
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

                // 今日任务
                Text("今日任务").appSectionTitle()
                    .padding(.top, 6)
                VStack(spacing: 8) {
                    ForEach(kDefaultPracticeTasks) { task in
                        NavigationLink {
                            PracticeTaskRouterView(task: task)
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
                        }
                        .buttonStyle(.plain)
                        .appCard()
                    }
                }

                // 我的谱
                NavigationLink {
                    SheetLibraryView()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("我的谱")
                                .font(.headline)
                                .foregroundStyle(SwiftAppTheme.text)
                            Text("在曲谱中练习并累计时长与次数")
                                .font(.subheadline)
                                .foregroundStyle(SwiftAppTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                }
                .buttonStyle(.plain)
                .appCard()

                // 练习历史
                HStack {
                    Text("练习历史").appSectionTitle()
                    Spacer()
                    NavigationLink("查看全部") {
                        PracticeHistoryView(sessions: vm.sessions)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                }
                .padding(.top, 6)

                if vm.recentSessions.isEmpty {
                    Text("还没有练习记录，先开始第一次练习吧。")
                        .foregroundStyle(SwiftAppTheme.muted)
                        .appCard()
                } else {
                    ForEach(vm.recentSessions) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.taskName)
                                    .font(.headline)
                                    .foregroundStyle(SwiftAppTheme.text)
                                Spacer()
                                Text("难度 \(session.difficulty)/5")
                                    .font(.subheadline)
                                    .foregroundStyle(SwiftAppTheme.muted)
                            }
                            Text(PracticeSessionPresenter.subtitle(session))
                                .font(.subheadline)
                                .foregroundStyle(SwiftAppTheme.muted)
                        }
                        .appCard()
                    }
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .appPageBackground()
        .refreshable { await vm.refresh() }
    }
}

@MainActor
final class PracticeHomeViewModel: ObservableObject {
    @Published var loading: Bool = true
    @Published var loadError: String?
    @Published var summary: PracticeSummary = .init(todayMinutes: 0, todaySessions: 0, streakDays: 0)
    @Published var sessions: [PracticeSession] = []

    private let store: PracticeSessionStore

    init(store: PracticeSessionStore = PracticeLocalStore()) {
        self.store = store
    }

    var recentSessions: [PracticeSession] { Array(sessions.prefix(3)) }

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

private enum PracticeSessionPresenter {
    static func subtitle(_ session: PracticeSession) -> String {
        let timePart = "\(formatDate(session.endedAt)) · \(formatDuration(session.durationSeconds))"
        if let id = session.rhythmPatternId, let name = strummingPatternNameForId(id) {
            return "\(name) · \(timePart)"
        }
        return timePart
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

private struct PracticeHistoryView: View {
    let sessions: [PracticeSession]

    var body: some View {
        Group {
            if sessions.isEmpty {
                Text("暂无历史记录")
                    .foregroundStyle(SwiftAppTheme.muted)
            } else {
                List(sessions) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(session.taskName).foregroundStyle(SwiftAppTheme.text)
                            Spacer()
                            Text("难度 \(session.difficulty)/5").foregroundStyle(SwiftAppTheme.muted)
                        }
                        Text(PracticeSessionPresenter.subtitle(session))
                            .font(.subheadline)
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(SwiftAppTheme.surface)
                }
                .scrollContentBackground(.hidden)
                .background(SwiftAppTheme.bg)
            }
        }
        .navigationTitle("练习历史")
        .appPageBackground()
    }
}

/// 任务入口路由：后续会逐个替换为真实页面。
private struct PracticeTaskRouterView: View {
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

