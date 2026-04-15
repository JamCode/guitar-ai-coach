import 'dart:math';

import 'interval_kind.dart';

/// 一道音程题：低音 → 高音，半音差为 [answer]；选项为 4 个 [IntervalKind]（已洗牌）。
class IntervalQuestion {
  IntervalQuestion({
    required this.lowMidi,
    required this.highMidi,
    required this.answer,
    required this.choices,
  }) : assert(choices.length == 4),
       assert(choices.contains(answer));

  final int lowMidi;
  final int highMidi;
  final IntervalKind answer;
  final List<IntervalKind> choices;
}

abstract final class IntervalQuestionGen {
  static const int _rootLo = 48;
  static const int _rootHi = 72;

  /// 规则随机：从 [IntervalKind.trainingPool] 抽正确答案，再抽 3 个干扰项。
  static IntervalQuestion next(Random rng) {
    final pool = IntervalKind.trainingPool;
    final answer = pool[rng.nextInt(pool.length)];
    final maxRoot = _rootHi - answer.semitones;
    if (maxRoot < _rootLo) {
      throw StateError('音域与音程池不兼容');
    }
    final root = _rootLo + rng.nextInt(maxRoot - _rootLo + 1);
    final low = root;
    final high = root + answer.semitones;

    final wrong = <IntervalKind>[
      for (final k in pool)
        if (k.semitones != answer.semitones) k,
    ]..shuffle(rng);
    final picks = wrong.take(3).toList();
    final choices = <IntervalKind>[answer, ...picks]..shuffle(rng);

    return IntervalQuestion(
      lowMidi: low,
      highMidi: high,
      answer: answer,
      choices: choices,
    );
  }
}
