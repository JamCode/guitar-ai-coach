/// 单题判分输出。
class SightSingingScore {
  const SightSingingScore({
    required this.score,
    required this.avgCentsAbs,
    required this.stableHitMs,
    required this.isCorrect,
  });

  final double score;
  final double avgCentsAbs;
  final int stableHitMs;
  final bool isCorrect;
}

/// 依据 cent 偏差序列计算单题分数（0~10）。
SightSingingScore computeSightSingingScore({
  required List<double> absCentsSamples,
  required int sampleStepMs,
}) {
  if (absCentsSamples.isEmpty) {
    return const SightSingingScore(
      score: 0,
      avgCentsAbs: 99,
      stableHitMs: 0,
      isCorrect: false,
    );
  }
  var totalWeight = 0.0;
  var totalCents = 0.0;
  var currentStableMs = 0;
  var bestStableMs = 0;

  for (final cents in absCentsSamples) {
    totalCents += cents;
    if (cents <= 15) {
      totalWeight += 1.0;
    } else if (cents <= 30) {
      totalWeight += 0.7;
    } else if (cents <= 50) {
      totalWeight += 0.3;
    }
    if (cents <= 30) {
      currentStableMs += sampleStepMs;
      if (currentStableMs > bestStableMs) {
        bestStableMs = currentStableMs;
      }
    } else {
      currentStableMs = 0;
    }
  }
  final avgWeight = totalWeight / absCentsSamples.length;
  var score = avgWeight * 10;
  if (bestStableMs < 500 && score > 6) {
    score = 6;
  }
  final avgCents = totalCents / absCentsSamples.length;
  return SightSingingScore(
    score: score.clamp(0, 10),
    avgCentsAbs: avgCents,
    stableHitMs: bestStableMs,
    isCorrect: score >= 6,
  );
}
