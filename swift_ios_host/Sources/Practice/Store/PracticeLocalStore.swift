import Foundation
import Practice

/// 练习记录本地仓库：所有数据仅保存到本机 UserDefaults（对齐 Flutter `PracticeLocalStore`）。
final class PracticeLocalStore: PracticeSessionStore {
    private let key = "practice_sessions_v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSessions() async throws -> [PracticeSession] {
        let raw = defaults.string(forKey: key) ?? ""
        if raw.isEmpty {
            return []
        }
        var list = decodeSessions(raw)
        list.sort { $0.endedAt > $1.endedAt }
        return list
    }

    func saveSession(
        task: PracticeTask,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        completed: Bool,
        difficulty: Int,
        note: String?,
        progressionId: String?,
        musicKey: String?,
        complexity: String?,
        rhythmPatternId: String?,
        scaleWarmupDrillId: String?,
        earAnsweredCount: Int?,
        earCorrectCount: Int?
    ) async throws {
        guard durationSeconds >= PracticeRecordingPolicy.minForegroundSecondsToPersist else { return }
        var sessions = try await loadSessions()
        let session = PracticeSession(
            id: UUID().uuidString,
            taskId: task.id,
            taskName: task.name,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            completed: completed,
            difficulty: min(5, max(1, difficulty)),
            note: note,
            progressionId: progressionId,
            musicKey: musicKey,
            complexity: complexity,
            rhythmPatternId: rhythmPatternId,
            scaleWarmupDrillId: scaleWarmupDrillId,
            earAnsweredCount: earAnsweredCount,
            earCorrectCount: earCorrectCount
        )
        sessions.append(session)
        defaults.set(encodeSessions(sessions), forKey: key)
    }

    func loadSummary(now: Date? = nil) async throws -> PracticeSummary {
        let current = now ?? Date()
        let sessions = try await loadSessions()
        return PracticeSummary(
            todayMinutes: computeTodayMinutes(sessions, now: current),
            todaySessions: computeTodaySessions(sessions, now: current),
            streakDays: computeStreakDays(sessions, now: current)
        )
    }
}

// MARK: - Encoding / decoding (tolerant, aligned with Flutter behavior)

private let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func encodeSessions(_ sessions: [PracticeSession]) -> String {
    let out: [[String: Any]] = sessions.map { s in
        var m: [String: Any] = [
            "id": s.id,
            "taskId": s.taskId,
            "taskName": s.taskName,
            "startedAt": iso8601.string(from: s.startedAt),
            "endedAt": iso8601.string(from: s.endedAt),
            "durationSeconds": s.durationSeconds,
            "completed": s.completed,
            "difficulty": s.difficulty,
        ]
        if let note = s.note { m["note"] = note }
        if let progressionId = s.progressionId { m["progressionId"] = progressionId }
        if let musicKey = s.musicKey { m["musicKey"] = musicKey }
        if let complexity = s.complexity { m["complexity"] = complexity }
        if let rhythmPatternId = s.rhythmPatternId { m["rhythmPatternId"] = rhythmPatternId }
        if let scaleWarmupDrillId = s.scaleWarmupDrillId { m["scaleWarmupDrillId"] = scaleWarmupDrillId }
        if let earAnsweredCount = s.earAnsweredCount { m["earAnsweredCount"] = earAnsweredCount }
        if let earCorrectCount = s.earCorrectCount { m["earCorrectCount"] = earCorrectCount }
        return m
    }
    guard
        let data = try? JSONSerialization.data(withJSONObject: out, options: []),
        let str = String(data: data, encoding: .utf8)
    else {
        return "[]"
    }
    return str
}

/// 从字符串反序列化会话列表；任意解析失败回落空列表，单项损坏则跳过（对齐 Flutter）。
func decodeSessions(_ raw: String) -> [PracticeSession] {
    guard let data = raw.data(using: .utf8) else { return [] }
    guard let any = try? JSONSerialization.jsonObject(with: data, options: []) else { return [] }
    guard let list = any as? [Any] else { return [] }

    var out: [PracticeSession] = []
    for item in list {
        guard let dict = item as? [String: Any] else { continue }
        guard let session = decodeSessionDict(dict) else { continue }
        out.append(session)
    }
    return out
}

private func decodeSessionDict(_ dict: [String: Any]) -> PracticeSession? {
    guard
        let id = dict["id"] as? String,
        let taskId = dict["taskId"] as? String,
        let taskName = dict["taskName"] as? String
    else { return nil }

    guard let startedAt = parseISODate(dict["startedAt"]), let endedAt = parseISODate(dict["endedAt"]) else {
        return nil
    }

    let durationSeconds = asInt(dict["durationSeconds"], fallback: 0)
    let completed = (dict["completed"] as? Bool) ?? false
    let difficulty = min(5, max(1, asInt(dict["difficulty"], fallback: 3)))
    let note = dict["note"] as? String

    let progressionId = dict["progressionId"] as? String
    let musicKey = dict["musicKey"] as? String
    let complexity = dict["complexity"] as? String
    let rhythmPatternId = dict["rhythmPatternId"] as? String
    let scaleWarmupDrillId = dict["scaleWarmupDrillId"] as? String
    let earAnsweredCount = asOptionalInt(dict["earAnsweredCount"])
    let earCorrectCount = asOptionalInt(dict["earCorrectCount"])

    return PracticeSession(
        id: id,
        taskId: taskId,
        taskName: taskName,
        startedAt: startedAt,
        endedAt: endedAt,
        durationSeconds: durationSeconds,
        completed: completed,
        difficulty: difficulty,
        note: note,
        progressionId: progressionId,
        musicKey: musicKey,
        complexity: complexity,
        rhythmPatternId: rhythmPatternId,
        scaleWarmupDrillId: scaleWarmupDrillId,
        earAnsweredCount: earAnsweredCount,
        earCorrectCount: earCorrectCount
    )
}

private func parseISODate(_ v: Any?) -> Date? {
    if let s = v as? String {
        // Try fractional first (what we write), then fallback to non-fractional.
        if let d = iso8601.date(from: s) { return d }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    return nil
}

private func asInt(_ v: Any?, fallback: Int) -> Int {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let n = v as? NSNumber { return n.intValue }
    return fallback
}

private func asOptionalInt(_ v: Any?) -> Int? {
    if v == nil { return nil }
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let n = v as? NSNumber { return n.intValue }
    return nil
}

