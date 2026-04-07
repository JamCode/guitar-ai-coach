import 'chord_symbol.dart';

/// 与后端 `chord_transpose.py` 对齐的本地变调（和弦符号级，不调用网络）。
abstract final class ChordTransposeLocal {
  static const _sharpNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  static const _flatNames = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];

  static const _preferFlats = {
    'Db': true,
    'Eb': true,
    'F': true,
    'Gb': true,
    'Ab': true,
    'Bb': true,
  };

  static int _keyPc(String key) => ChordSelectCatalog.keys.contains(key)
      ? const {
          'C': 0,
          'Db': 1,
          'D': 2,
          'Eb': 3,
          'E': 4,
          'F': 5,
          'Gb': 6,
          'G': 7,
          'Ab': 8,
          'A': 9,
          'Bb': 10,
          'B': 11,
        }[key]!
      : 0;

  static int semitoneDelta(String fromKey, String toKey) =>
      (_keyPc(toKey) - _keyPc(fromKey) + 12) % 12;

  static int? _noteToPc(String note) {
    final n = note.trim();
    if (n.isEmpty) return null;
    const map = {
      'C': 0,
      'B#': 0,
      'C#': 1,
      'Db': 1,
      'D': 2,
      'D#': 3,
      'Eb': 3,
      'E': 4,
      'Fb': 4,
      'F': 5,
      'E#': 5,
      'F#': 6,
      'Gb': 6,
      'G': 7,
      'G#': 8,
      'Ab': 8,
      'A': 9,
      'A#': 10,
      'Bb': 10,
      'B': 11,
      'Cb': 11,
    };
    return map[n];
  }

  static String _pcToNote(int pc, bool preferFlats) {
    final names = preferFlats ? _flatNames : _sharpNames;
    return names[pc % 12];
  }

  static String _transposeNote(String note, int semitones, bool preferFlats) {
    final pc = _noteToPc(note);
    if (pc == null) return note;
    return _pcToNote(pc + semitones, preferFlats);
  }

  /// 将 [chord] 从 [fromKey] 变调到 [toKey]（仅移根音与 slash 低音，性质后缀保留）。
  static String transposeChordSymbol(
    String chord,
    String fromKey,
    String toKey,
  ) {
    var c = chord.trim();
    if (c.isEmpty) return c;
    final delta = semitoneDelta(fromKey, toKey);
    if (delta == 0) return c;
    final preferFlats = _preferFlats[toKey] ?? false;

    String? bass;
    if (c.contains('/')) {
      final i = c.indexOf('/');
      bass = c.substring(i + 1).trim();
      c = c.substring(0, i).trim();
    }

    final head = RegExp(r'^([A-G])([#b]?)(.*)$');
    final m = head.firstMatch(c);
    if (m == null) return chord;
    final root = '${m.group(1)}${m.group(2) ?? ''}';
    final quality = m.group(3) ?? '';
    final newRoot = _transposeNote(root, delta, preferFlats);
    var out = '$newRoot$quality';
    if (bass != null && bass.isNotEmpty) {
      final mb = head.firstMatch(bass);
      if (mb != null) {
        final br = '${mb.group(1)}${mb.group(2) ?? ''}';
        out += '/${_transposeNote(br, delta, preferFlats)}';
      } else {
        out += '/$bass';
      }
    }
    return out;
  }
}
