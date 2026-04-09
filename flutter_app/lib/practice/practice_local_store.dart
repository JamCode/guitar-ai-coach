import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'practice_models.dart';

/// 本地练习存储：一期仅依赖 SharedPreferences，无后端交互。
class PracticeLocalStore {
  PracticeLocalStore({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const _sessionsKey = 'practice_sessions_v1';
  final Uuid _uuid;

  /// 读取所有练习会话（按结束时间倒序）。
  Future<List<PracticeSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey);
    if (raw == null || raw.isEmpty) {
      return <PracticeSession>[];
    }
    final sessions = decodeSessions(raw);
    sessions.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    return sessions;
  }

  /// 新增会话并持久化。
  Future<void> saveSession({
    required PracticeTask task,
    required DateTime startedAt,
    required DateTime endedAt,
    required int durationSeconds,
    required bool completed,
    required int difficulty,
    String? note,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await loadSessions();
    sessions.add(
      PracticeSession(
        id: _uuid.v4(),
        taskId: task.id,
        taskName: task.name,
        startedAt: startedAt,
        endedAt: endedAt,
        durationSeconds: durationSeconds,
        completed: completed,
        difficulty: difficulty,
        note: note,
      ),
    );
    sessions.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    await prefs.setString(_sessionsKey, encodeSessions(sessions));
  }

  /// 读取首页统计数据。
  Future<PracticeSummary> loadSummary({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final sessions = await loadSessions();
    return PracticeSummary(
      todayMinutes: computeTodayMinutes(sessions, current),
      todaySessions: computeTodaySessions(sessions, current),
      streakDays: computeStreakDays(sessions, current),
    );
  }
}
