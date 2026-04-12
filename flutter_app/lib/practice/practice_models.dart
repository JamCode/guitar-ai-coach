import 'dart:convert';

/// 预置练习任务模型：用于首页展示与进入练习会话。
class PracticeTask {
  const PracticeTask({
    required this.id,
    required this.name,
    required this.targetMinutes,
    required this.description,
  });

  final String id;
  final String name;
  final int targetMinutes;
  final String description;
}

/// 单次练习会话：由用户结束练习后落库。
class PracticeSession {
  PracticeSession({
    required this.id,
    required this.taskId,
    required this.taskName,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.completed,
    required this.difficulty,
    this.note,
    this.progressionId,
    this.musicKey,
    this.complexity,
  });

  final String id;
  final String taskId;
  final String taskName;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;
  final bool completed;
  final int difficulty;
  final String? note;

  /// 和弦进行练习专属字段（可空，兼容旧数据）。
  final String? progressionId;
  final String? musicKey;
  final String? complexity;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'taskId': taskId,
      'taskName': taskName,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
      'durationSeconds': durationSeconds,
      'completed': completed,
      'difficulty': difficulty,
      'note': note,
      if (progressionId != null) 'progressionId': progressionId,
      if (musicKey != null) 'musicKey': musicKey,
      if (complexity != null) 'complexity': complexity,
    };
  }

  /// 从 JSON 恢复会话（兼容服务端与本地历史字段）。
  static PracticeSession fromJson(Map<String, dynamic> json) {
    return PracticeSession(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      taskName: json['taskName'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: DateTime.parse(json['endedAt'] as String),
      durationSeconds: _asInt(json['durationSeconds'], 0),
      completed: json['completed'] as bool? ?? false,
      difficulty: _asInt(json['difficulty'], 3).clamp(1, 5),
      note: json['note'] as String?,
      progressionId: json['progressionId'] as String?,
      musicKey: json['musicKey'] as String?,
      complexity: json['complexity'] as String?,
    );
  }
}

int _asInt(dynamic v, int fallback) {
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  return fallback;
}

/// 练习首页展示统计数据。
class PracticeSummary {
  const PracticeSummary({
    required this.todayMinutes,
    required this.todaySessions,
    required this.streakDays,
  });

  final int todayMinutes;
  final int todaySessions;
  final int streakDays;
}

/// 统一维护一期内置任务，避免散落常量。
const List<PracticeTask> kDefaultPracticeTasks = <PracticeTask>[
  PracticeTask(
    id: 'chord-switch',
    name: '和弦切换',
    targetMinutes: 5,
    description: '多种进行 · 12 调 · 3 档复杂度',
  ),
  PracticeTask(
    id: 'rhythm-strum',
    name: '节奏扫弦',
    targetMinutes: 10,
    description: '目标：稳定 4/4 节拍，下上扫衔接均匀。',
  ),
  PracticeTask(
    id: 'scale-walk',
    name: '音阶爬格子',
    targetMinutes: 5,
    description: '目标：保持力度均匀，减少杂音。',
  ),
];

/// 将会话列表编码为字符串，便于存储到 SharedPreferences。
String encodeSessions(List<PracticeSession> sessions) {
  return jsonEncode(sessions.map((e) => e.toJson()).toList());
}

/// 从字符串反序列化会话列表。
List<PracticeSession> decodeSessions(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <PracticeSession>[];
    }
    final out = <PracticeSession>[];
    for (final e in decoded) {
      if (e is! Map<String, dynamic>) {
        continue;
      }
      try {
        out.add(PracticeSession.fromJson(e));
      } catch (_) {
        // 跳过损坏元素
      }
    }
    return out;
  } catch (_) {
    return <PracticeSession>[];
  }
}

/// 计算今日已练习分钟数（向下取整）。
int computeTodayMinutes(List<PracticeSession> sessions, DateTime now) {
  var seconds = 0;
  for (final session in sessions) {
    if (_isSameDay(session.endedAt, now) && session.completed) {
      seconds += session.durationSeconds;
    }
  }
  return seconds ~/ 60;
}

/// 计算今日完成练习的次数。
int computeTodaySessions(List<PracticeSession> sessions, DateTime now) {
  var count = 0;
  for (final session in sessions) {
    if (_isSameDay(session.endedAt, now) && session.completed) {
      count += 1;
    }
  }
  return count;
}

/// 计算连续打卡天数：自然日内有至少一次 completed 即记 1 天。
int computeStreakDays(List<PracticeSession> sessions, DateTime now) {
  final completedDates = sessions
      .where((s) => s.completed)
      .map((s) => DateTime(s.endedAt.year, s.endedAt.month, s.endedAt.day))
      .toSet();
  if (completedDates.isEmpty) {
    return 0;
  }
  var cursor = DateTime(now.year, now.month, now.day);
  var streak = 0;
  while (completedDates.contains(cursor)) {
    streak += 1;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
