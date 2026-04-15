import 'package:uuid/uuid.dart';

import 'practice_api_repository.dart';
import 'practice_models.dart';
import 'practice_session_store.dart';

/// 练习记录以服务端为唯一数据源（须已登录，且请求固定后端地址）。
///
/// 副作用：通过 [PracticeApiRepository] 发起 HTTP 请求。
class PracticeRemoteStore implements PracticeSessionStore {
  PracticeRemoteStore({
    PracticeApiRepository? api,
    Uuid? uuid,
  })  : _api = api ?? PracticeApiRepository(),
        _uuid = uuid ?? const Uuid();

  final PracticeApiRepository _api;
  final Uuid _uuid;

  @override
  Future<List<PracticeSession>> loadSessions() async {
    final list = await _api.listSessions();
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
    final session = PracticeSession(
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
    );
    await _api.createSession(session);
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
