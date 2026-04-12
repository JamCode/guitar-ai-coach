import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/practice/practice_models.dart';

void main() {
  test('decodeSessions 损坏 JSON 返回空列表', () {
    expect(decodeSessions('not json'), isEmpty);
    expect(decodeSessions('{}'), isEmpty);
  });

  test('PracticeSession.fromJson 接受 durationSeconds 为 double', () {
    final s = PracticeSession.fromJson({
      'id': '550e8400-e29b-41d4-a716-446655440000',
      'taskId': 'a',
      'taskName': 'A',
      'startedAt': '2026-04-09T10:00:00.000',
      'endedAt': '2026-04-09T10:01:00.000',
      'durationSeconds': 60.0,
      'completed': true,
      'difficulty': 4.0,
    });
    expect(s.durationSeconds, 60);
    expect(s.difficulty, 4);
  });

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
    expect(computeTodaySessions(sessions, now), 1);
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
