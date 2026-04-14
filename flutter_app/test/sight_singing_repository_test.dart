import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/ear/sight_singing_repository.dart';

void main() {
  test('local sight singing repository supports full session flow', () async {
    final repo = LocalSightSingingRepository();
    final start = await repo.startSession(
        pitchRange: 'mid',
        includeAccidental: false,
        questionCount: 10,
    );
    expect(start.sessionId, isNotEmpty);
    expect(start.question, isNotNull);

    var question = start.question!;
    for (var i = 0; i < 10; i++) {
      await repo.submitAnswer(
        sessionId: start.sessionId,
        questionId: question.id,
        answers: const <String>['C4'],
        avgCentsAbs: 15,
        stableHitMs: 900,
        durationMs: 2000,
      );
      final next = await repo.nextQuestion(start.sessionId);
      if (next == null) {
        break;
      }
      question = next;
    }

    final result = await repo.fetchResult(start.sessionId);
    expect(result.total, 10);
    expect(result.answered, greaterThan(0));
    expect(result.correct, lessThanOrEqualTo(result.answered));
    expect(result.accuracy, inInclusiveRange(0, 1));
  });
}
