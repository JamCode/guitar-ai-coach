/// 大调调内三和弦：罗马数字 → 和弦内音 MIDI（相对根音偏移后落在吉他采样范围内）。
abstract final class DiatonicRoman {
  /// 根音名（如 `C`、`Bb`、`F`）到半音级（C=0）。
  static int pitchClassSemitones(String name) {
    final n = name.trim();
    switch (n) {
      case 'C':
        return 0;
      case 'Db':
      case 'C#':
        return 1;
      case 'D':
        return 2;
      case 'Eb':
      case 'D#':
        return 3;
      case 'E':
        return 4;
      case 'F':
        return 5;
      case 'Gb':
      case 'F#':
        return 6;
      case 'G':
        return 7;
      case 'Ab':
      case 'G#':
        return 8;
      case 'A':
        return 9;
      case 'Bb':
      case 'A#':
        return 10;
      case 'B':
        return 11;
      default:
        throw ArgumentError.value(name, 'name', 'unsupported note');
    }
  }

  /// MIDI：C4 = 60，公式 `(octave + 1) * 12 + pitchClass`。
  static int noteNameToMidi(String name, int octave) {
    return (octave + 1) * 12 + pitchClassSemitones(name);
  }

  /// 自然大调第 n 级根音相对调式主音的半音偏移（1-based）。
  static int majorScaleOffsetFromTonic(int degree1to7) {
    const steps = [0, 2, 4, 5, 7, 9, 11];
    if (degree1to7 < 1 || degree1to7 > 7) {
      throw ArgumentError.value(degree1to7, 'degree1to7');
    }
    return steps[degree1to7 - 1];
  }

  static ({int degree, bool minor}) _parseRomanTriad(String roman) {
    switch (roman) {
      case 'I':
        return (degree: 1, minor: false);
      case 'ii':
        return (degree: 2, minor: true);
      case 'iii':
        return (degree: 3, minor: true);
      case 'IV':
        return (degree: 4, minor: false);
      case 'V':
        return (degree: 5, minor: false);
      case 'vi':
        return (degree: 6, minor: true);
      default:
        throw ArgumentError.value(roman, 'roman', 'unsupported roman numeral');
    }
  }

  /// 解析 `I-V-vi-IV` 形式（连字符分隔）。
  static List<String> splitProgression(String progressionRoman) {
    return progressionRoman.split('-').where((s) => s.isNotEmpty).toList();
  }

  /// 某一罗马数字在和弦根音 [chordRootMidi] 上的三和弦三个音（大/小由调式决定）。
  static List<int> triadMidiAtRoot(int chordRootMidi, bool minor) {
    if (minor) {
      return [chordRootMidi, chordRootMidi + 3, chordRootMidi + 7];
    }
    return [chordRootMidi, chordRootMidi + 4, chordRootMidi + 7];
  }

  /// 调性主音 + 级数 → 和弦根音 MIDI（先按 [baseOctave] 起算再整体移八度落入 [clampMin,clampMax]）。
  static int chordRootMidiInMajorKey({
    required String keyName,
    required String roman,
    int baseOctave = 3,
    int clampMin = 38,
    int clampMax = 74,
  }) {
    final parsed = _parseRomanTriad(roman);
    final tonic = noteNameToMidi(keyName, baseOctave);
    var root = tonic + majorScaleOffsetFromTonic(parsed.degree);
    root = _clampChordSetCenter(root, clampMin, clampMax);
    return root;
  }

  static int _clampChordSetCenter(int rootMidi, int min, int max) {
    var r = rootMidi;
    for (var i = 0; i < 6; i++) {
      final top = r + 7;
      if (r >= min && top <= max) return r;
      if (top > max) {
        r -= 12;
      } else {
        r += 12;
      }
    }
    return rootMidi.clamp(min, max - 7);
  }

  /// 大调上进行 [progressionRoman] 的每个三和弦 MIDI 列表（用于依次播放）。
  static List<List<int>> progressionTriadsMidi({
    required String musicKey,
    required String progressionRoman,
  }) {
    final romans = splitProgression(progressionRoman);
    final out = <List<int>>[];
    for (final roman in romans) {
      final parsed = _parseRomanTriad(roman);
      final root = chordRootMidiInMajorKey(keyName: musicKey, roman: roman);
      out.add(triadMidiAtRoot(root, parsed.minor));
    }
    return out;
  }

  /// 单和弦：根音名 + `major` / `minor` / `dominant7`（与种子 `target_quality` 一致）。
  static List<int> singleChordMidis({
    required String rootName,
    required String targetQuality,
    int baseOctave = 3,
    int clampMin = 38,
    int clampMax = 74,
  }) {
    var root = noteNameToMidi(rootName, baseOctave);
    root = _clampChordSetCenter(root, clampMin, clampMax);
    switch (targetQuality) {
      case 'major':
        return [root, root + 4, root + 7];
      case 'minor':
        return [root, root + 3, root + 7];
      case 'dominant7':
        return [root, root + 4, root + 7, root + 10];
      default:
        throw ArgumentError.value(targetQuality, 'targetQuality');
    }
  }

  /// 将每个 MIDI 限制在采样可用范围内（单音平移）。
  static List<int> clampMidis(List<int> midis, {int min = 38, int max = 74}) {
    return midis
        .map((m) {
          var x = m;
          while (x < min) {
            x += 12;
          }
          while (x > max) {
            x -= 12;
          }
          return x;
        })
        .toList(growable: false);
  }
}
