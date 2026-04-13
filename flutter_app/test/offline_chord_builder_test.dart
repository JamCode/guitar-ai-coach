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

  test('进阶 Am9 映射为小七构成并生成按法', () {
    final p = buildOfflineChordPayload(displaySymbol: 'Am9');
    expect(p, isNotNull);
    expect(p!.chordSummary.symbol, 'Am9');
    expect(p.chordSummary.notesLetters, contains('G'));
  });

  test('高阶 G9 映射为属七构成', () {
    final p = buildOfflineChordPayload(displaySymbol: 'G9');
    expect(p, isNotNull);
    expect(p!.chordSummary.notesLetters.length, 4);
  });

  test('Bm7b5 可解析', () {
    final p = buildOfflineChordPayload(displaySymbol: 'Bm7b5');
    expect(p, isNotNull);
    expect(p!.chordSummary.notesLetters, contains('A'));
  });
}
