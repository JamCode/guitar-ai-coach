import 'package:uuid/uuid.dart';

import 'practice_models.dart';
import 'practice_session_store.dart';

/// 非持久化的练习会话仓库，专供自动化测试在隔离环境中注入。
///
/// 数据仅存于进程内 [List]，不读写磁盘，也不发起网络请求。与
/// [PracticeRemoteStore] 相对，后者以服务端为唯一数据源。
class PracticeFakeStore implements PracticeSessionStore {
  /// 创建空仓库；[uuid] 可注入以便断言生成的会话 id。
  PracticeFakeStore({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  /// 进程内持有的会话，按插入顺序追加；读取时再排序。
  final List<PracticeSession> _buffer = <PracticeSession>[];

  @override
  Future<List<PracticeSession>> loadSessions() async {
    final snapshot = List<PracticeSession>.from(_buffer);
    snapshot.sort((PracticeSession a, PracticeSession b) {
      return b.endedAt.compareTo(a.endedAt);
    });
    return snapshot;
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
    _buffer.add(
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
  }

  @override
  Future<PracticeSummary> loadSummary({DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final sessions = await loadSessions();
    return PracticeSummary(
      todayMinutes: computeTodayMinutes(sessions, clock),
      todaySessions: computeTodaySessions(sessions, clock),
      streakDays: computeStreakDays(sessions, clock),
    );
  }
}
