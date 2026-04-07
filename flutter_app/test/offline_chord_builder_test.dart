import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/chords/chord_transpose_local.dart';
import 'package:guitar_helper/chords/offline_chord_builder.dart';

void main() {
  test('buildOfflineChordPayload C 大三', () {
    final p = buildOfflineChordPayload(displaySymbol: 'C');
    expect(p, isNotNull);
    expect(p!.chordSummary.notesLetters, contains('C'));
    expect(p.voicings.length, greaterThanOrEqualTo(2));
  });

  test('变调 Am -> Bm', () {
    expect(
      ChordTransposeLocal.transposeChordSymbol('Am', 'C', 'D'),
      'Bm',
    );
  });

  test('slash G/B 可解析', () {
    final p = buildOfflineChordPayload(displaySymbol: 'G/B');
    expect(p, isNotNull);
    expect(p!.chordSummary.notesExplainZh, contains('Slash'));
  });
}
