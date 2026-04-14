import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/ear/sight_singing_score.dart';

void main() {
  test('computeSightSingingScore 高命中得到高分', () {
    final score = computeSightSingingScore(
      absCentsSamples: List<double>.filled(20, 12),
      sampleStepMs: 120,
    );
    expect(score.score, greaterThan(9));
    expect(score.stableHitMs, greaterThanOrEqualTo(500));
    expect(score.isCorrect, isTrue);
  });

  test('computeSightSingingScore 无稳定命中会限分', () {
    final score = computeSightSingingScore(
      absCentsSamples: const [12, 80, 13, 85, 12, 70],
      sampleStepMs: 120,
    );
    expect(score.stableHitMs, lessThan(500));
    expect(score.score, lessThanOrEqualTo(6));
  });
}
