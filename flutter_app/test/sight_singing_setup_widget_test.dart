import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/app_theme.dart';
import 'package:guitar_helper/ear/sight_singing_models.dart';
import 'package:guitar_helper/ear/sight_singing_repository.dart';
import 'package:guitar_helper/ear/sight_singing_session_screen.dart';
import 'package:guitar_helper/ear/sight_singing_setup_screen.dart';

void main() {
  testWidgets('视唱设置页可修改选项并进入会话页', (tester) async {
    final repo = _FakeSightSingingRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SightSingingSetupScreen(
          repository: repo,
          pitchTrackerBuilder: _FakePitchTracker.new,
        ),
      ),
    );

    expect(find.text('视唱训练'), findsOneWidget);
    await tester.tap(find.text('宽范围 C3-B4'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始训练'));
    await tester.pumpAndSettle();

    expect(find.text('开始判定（2秒）'), findsOneWidget);
  });
}

class _FakeSightSingingRepository implements SightSingingRepository {
  @override
  Future<SightSingingResult> fetchResult(String sessionId) async {
    return const SightSingingResult(
      answered: 1,
      correct: 1,
      total: 1,
      accuracy: 1,
    );
  }

  @override
  Future<SightSingingQuestion?> nextQuestion(String sessionId) async {
    return null;
  }

  @override
  Future<SightSingingSessionStart> startSession({
    required String pitchRange,
    required bool includeAccidental,
    required int questionCount,
  }) async {
    return const SightSingingSessionStart(
      sessionId: 'test_session',
      config: SightSingingConfig(
        minNote: 'C3',
        maxNote: 'B4',
        questionCount: 10,
        includeAccidental: false,
      ),
      question: SightSingingQuestion(
        id: 'q1',
        index: 1,
        totalQuestions: 1,
        targetNotes: ['C4'],
      ),
    );
  }

  @override
  Future<void> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> answers,
    required double avgCentsAbs,
    required int stableHitMs,
    required int durationMs,
  }) async {}
}

class _FakePitchTracker implements SightSingingPitchTracker {
  @override
  double? get currentHz => 261.63;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
