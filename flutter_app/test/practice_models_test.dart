import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/practice/practice_models.dart';

void main() {
  test('computeTodayMinutes 仅统计今日且已完成会话', () {
    final now = DateTime(2026, 4, 9, 20);
    final sessions = <PracticeSession>[
      PracticeSession(
        id: '1',
        taskId: 'a',
        taskName: '任务A',
        startedAt: DateTime(2026, 4, 9, 10),
        endedAt: DateTime(2026, 4, 9, 10, 5),
        durationSeconds: 300,
        completed: true,
        difficulty: 3,
      ),
      PracticeSession(
        id: '2',
        taskId: 'a',
        taskName: '任务A',
        startedAt: DateTime(2026, 4, 9, 11),
        endedAt: DateTime(2026, 4, 9, 11, 2),
        durationSeconds: 120,
        completed: false,
        difficulty: 2,
      ),
      PracticeSession(
        id: '3',
        taskId: 'a',
        taskName: '任务A',
        startedAt: DateTime(2026, 4, 8, 12),
        endedAt: DateTime(2026, 4, 8, 12, 10),
        durationSeconds: 600,
        completed: true,
        difficulty: 4,
      ),
    ];

    expect(computeTodayMinutes(sessions, now), 5);
  });

  test('computeStreakDays 正确计算连续打卡', () {
    final now = DateTime(2026, 4, 9, 20);
    final sessions = <PracticeSession>[
      PracticeSession(
        id: '1',
        taskId: 'a',
        taskName: '任务A',
        startedAt: DateTime(2026, 4, 9, 10),
        endedAt: DateTime(2026, 4, 9, 10, 5),
        durationSeconds: 300,
        completed: true,
        difficulty: 3,
      ),
      PracticeSession(
        id: '2',
        taskId: 'a',
        taskName: '任务A',
        startedAt: DateTime(2026, 4, 8, 11),
        endedAt: DateTime(2026, 4, 8, 11, 5),
        durationSeconds: 300,
        completed: true,
        difficulty: 3,
      ),
      PracticeSession(
        id: '3',
        taskId: 'a',
        taskName: '任务A',
        startedAt: DateTime(2026, 4, 6, 11),
        endedAt: DateTime(2026, 4, 6, 11, 5),
        durationSeconds: 300,
        completed: true,
        difficulty: 3,
      ),
    ];

    expect(computeStreakDays(sessions, now), 2);
  });
}
