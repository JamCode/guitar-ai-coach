import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/practice/chord_progression_library.dart';

void main() {
  group('ChordProgressionEngine.resolveChordNames', () {
    test('I-V-vi-IV in C basic → C G Am F', () {
      final names = ChordProgressionEngine.resolveChordNames(
        romanNumerals: 'I-V-vi-IV',
        key: 'C',
        complexity: ChordComplexity.basic,
      );
      expect(names, ['C', 'G', 'Am', 'F']);
    });

    test('I-V-vi-IV in G basic → G D Em C', () {
      final names = ChordProgressionEngine.resolveChordNames(
        romanNumerals: 'I-V-vi-IV',
        key: 'G',
        complexity: ChordComplexity.basic,
      );
      expect(names, ['G', 'D', 'Em', 'C']);
    });

    test('I-V-vi-IV in D basic → D A Bm G', () {
      final names = ChordProgressionEngine.resolveChordNames(
        romanNumerals: 'I-V-vi-IV',
        key: 'D',
        complexity: ChordComplexity.basic,
      );
      expect(names, ['D', 'A', 'Bm', 'G']);
    });

    test('I-V-vi-IV in F basic → F C Dm Bb', () {
      final names = ChordProgressionEngine.resolveChordNames(
        romanNumerals: 'I-V-vi-IV',
        key: 'F',
        complexity: ChordComplexity.basic,
      );
      expect(names, ['F', 'C', 'Dm', 'Bb']);
    });

    test('ii-V-I in C intermediate → Dm7 G7 Cmaj7', () {
      final names = ChordProgressionEngine.resolveChordNames(
        romanNumerals: 'ii-V-I',
        key: 'C',
        complexity: ChordComplexity.intermediate,
      );
      expect(names, ['Dm7', 'G7', 'Cmaj7']);
    });

    test('ii-V-I in Bb intermediate → Cm7 F7 Bbmaj7', () {
      final names = ChordProgressionEngine.resolveChordNames(
        romanNumerals: 'ii-V-I',
        key: 'Bb',
        complexity: ChordComplexity.intermediate,
      );
      expect(names, ['Cm7', 'F7', 'Bbmaj7']);
    });

    test('I-V-vi-IV in C advanced → Cmaj9 G9 Am9 Fmaj9', () {
      final names = ChordProgressionEngine.resolveChordNames(
        romanNumerals: 'I-V-vi-IV',
        key: 'C',
        complexity: ChordComplexity.advanced,
      );
      expect(names, ['Cmaj9', 'G9', 'Am9', 'Fmaj9']);
    });

    test('borrowed bVII uses flat name even in sharp keys', () {
      final names = ChordProgressionEngine.resolveChordNames(
        romanNumerals: 'I-bVII-IV-I',
        key: 'G',
        complexity: ChordComplexity.basic,
      );
      expect(names, ['G', 'F', 'C', 'G']);
    });

    test('borrowed bVI uses flat name in D (Bb not A#)', () {
      final names = ChordProgressionEngine.resolveChordNames(
        romanNumerals: 'I-bVII-bVI-V',
        key: 'D',
        complexity: ChordComplexity.basic,
      );
      expect(names, ['D', 'C', 'Bb', 'A']);
    });

    test('borrowed bVI uses flat name in G (Eb not D#)', () {
      final names = ChordProgressionEngine.resolveChordNames(
        romanNumerals: 'I-bVII-bVI-V',
        key: 'G',
        complexity: ChordComplexity.basic,
      );
      expect(names, ['G', 'F', 'Eb', 'D']);
    });

    test('12-bar blues resolves to 12 chords', () {
      final names = ChordProgressionEngine.resolveChordNames(
        romanNumerals: 'I-I-I-I-IV-IV-I-I-V-IV-I-V',
        key: 'A',
        complexity: ChordComplexity.basic,
      );
      expect(names.length, 12);
      expect(names[0], 'A');
      expect(names[4], 'D');
      expect(names[8], 'E');
    });

    test('all 12 keys produce non-empty result', () {
      for (final key in kMusicKeys) {
        final names = ChordProgressionEngine.resolveChordNames(
          romanNumerals: 'I-V-vi-IV',
          key: key,
          complexity: ChordComplexity.basic,
        );
        expect(names.length, 4, reason: 'key=$key should produce 4 chords');
        for (final name in names) {
          expect(name.isNotEmpty, isTrue, reason: 'key=$key has empty chord');
        }
      }
    });
  });

  group('kChordProgressions', () {
    test('contains at least 12 progressions', () {
      expect(kChordProgressions.length, greaterThanOrEqualTo(12));
    });

    test('every progression has unique id', () {
      final ids = kChordProgressions.map((p) => p.id).toSet();
      expect(ids.length, kChordProgressions.length);
    });

    test('every progression resolves without error in all keys', () {
      for (final prog in kChordProgressions) {
        for (final key in kMusicKeys) {
          for (final c in ChordComplexity.values) {
            final names = ChordProgressionEngine.resolveChordNames(
              romanNumerals: prog.romanNumerals,
              key: key,
              complexity: c,
            );
            expect(
              names.isNotEmpty,
              isTrue,
              reason: '${prog.id} in $key $c should resolve',
            );
          }
        }
      }
    });
  });

  group('ChordComplexity', () {
    test('label returns non-empty string', () {
      for (final c in ChordComplexity.values) {
        expect(c.label.isNotEmpty, isTrue);
        expect(c.fullLabel.isNotEmpty, isTrue);
      }
    });
  });
}
