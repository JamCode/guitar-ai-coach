import 'practice_models.dart';

/// 练习会话的读写抽象：生产环境走服务端，测试可注入内存实现。
abstract class PracticeSessionStore {
  /// 拉取当前用户的练习记录（按结束时间倒序，由实现决定数据源）。
  Future<List<PracticeSession>> loadSessions();

  /// 持久化一条新的练习会话（实现侧负责生成 [PracticeSession.id] 等字段）。
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
  });

  /// 基于 [loadSessions] 的结果计算首页统计（今日分钟数、次数、连续天数）。
  Future<PracticeSummary> loadSummary({DateTime? now});
}
