import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/chords_live/live_chord_models.dart';
import 'package:guitar_helper/chords_live/live_chord_state_machine.dart';

LiveChordFrame _frame({
  required String best,
  required double confidence,
}) {
  return LiveChordFrame(
    best: best,
    confidence: confidence,
    status: '🎵 Listening…',
    timestampMs: 1,
    topK: [
      LiveChordCandidate(label: best, score: confidence),
      const LiveChordCandidate(label: 'C', score: 0.2),
    ],
  );
}

void main() {
  test('stable 模式需要连续 2 帧确认', () {
    final machine = LiveChordStateMachine(minConfidence: 0.5);
    var state = LiveChordUiState.initial().copyWith(mode: LiveChordMode.stable);

    state = machine.applyFrame(state, _frame(best: 'Am', confidence: 0.8));
    expect(state.stableChord, 'Unknown');

    state = machine.applyFrame(state, _frame(best: 'Am', confidence: 0.8));
    expect(state.stableChord, 'Am');
    expect(state.timeline.last, 'Am');
  });

  test('fast 模式首帧即可切换', () {
    final machine = LiveChordStateMachine(minConfidence: 0.5);
    var state = LiveChordUiState.initial().copyWith(mode: LiveChordMode.fast);

    state = machine.applyFrame(state, _frame(best: 'F', confidence: 0.8));
    expect(state.stableChord, 'F');
  });

  test('低置信度输出 Unknown 并不写入时间线', () {
    final machine = LiveChordStateMachine(minConfidence: 0.6);
    var state = LiveChordUiState.initial().copyWith(mode: LiveChordMode.fast);
    final originalTimeline = state.timeline;

    state = machine.applyFrame(state, _frame(best: 'G', confidence: 0.2));
    expect(state.stableChord, 'Unknown');
    expect(state.timeline, originalTimeline);
  });
}
