import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'practice_models.dart';
import 'practice_session_store.dart';

/// 练习记录本地仓库：所有数据仅保存到本机 SharedPreferences。
class PracticeLocalStore implements PracticeSessionStore {
  PracticeLocalStore({SharedPreferencesAsync? prefs, Uuid? uuid})
      : _prefs = prefs ?? SharedPreferencesAsync(),
        _uuid = uuid ?? const Uuid();

  static const _sessionsKey = 'practice_sessions_v1';

  final SharedPreferencesAsync _prefs;
  final Uuid _uuid;

  @override
  Future<List<PracticeSession>> loadSessions() async {
    final raw = await _prefs.getString(_sessionsKey);
    if (raw == null || raw.isEmpty) {
      return <PracticeSession>[];
    }
    final list = decodeSessions(raw);
    list.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    return list;
  }

  @override
  Future<void> saveSession({
    required PracticeTask task,
    required DateTime startedAt,
    required DateTime endedAt,
    required int durationSeconds,
    required bool completed,
    required int difficulty,
    String? note,
    String? progressionId,
    String? musicKey,
    String? complexity,
    String? rhythmPatternId,
  }) async {
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
        progressionId: progressionId,
        musicKey: musicKey,
        complexity: complexity,
        rhythmPatternId: rhythmPatternId,
      ),
    );
    await _prefs.setString(_sessionsKey, encodeSessions(sessions));
  }

  @override
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
