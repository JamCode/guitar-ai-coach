import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/ear/diatonic_roman.dart';

void main() {
  test('noteNameToMidi C4 = 60', () {
    expect(DiatonicRoman.noteNameToMidi('C', 4), 60);
    expect(DiatonicRoman.noteNameToMidi('Bb', 3), 58);
  });

  test('I-V-vi-IV in C 四个和弦各 3 个音', () {
    final chords = DiatonicRoman.progressionTriadsMidi(
      musicKey: 'C',
      progressionRoman: 'I-V-vi-IV',
    );
    expect(chords.length, 4);
    for (final c in chords) {
      expect(c.length, 3);
    }
  });

  test('C major 大三和弦三个音', () {
    final m = DiatonicRoman.singleChordMidis(
      rootName: 'C',
      targetQuality: 'major',
      baseOctave: 4,
    );
    expect(m.length, 3);
    expect(m[1] - m[0], 4);
    expect(m[2] - m[0], 7);
  });

  test('dominant7 四个音', () {
    final m = DiatonicRoman.singleChordMidis(
      rootName: 'G',
      targetQuality: 'dominant7',
    );
    expect(m.length, 4);
    expect(m[3] - m[0], 10);
  });
}
