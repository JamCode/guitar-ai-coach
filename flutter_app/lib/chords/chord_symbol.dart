/// 与 Web 和弦字典页一致的下拉选项与符号拼接（C 调记谱）。
abstract final class ChordSelectCatalog {
  static const List<String> keys = [
    'C',
    'Db',
    'D',
    'Eb',
    'E',
    'F',
    'Gb',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];

  static const List<String> levels = ['初级', '中级', '高级'];

  /// 和弦字典使用的参考调（记谱基准），与 [frontend/src/session.ts] 中 `referenceKey` 一致。
  static const String referenceKey = 'C';

  static const List<({String id, String label})> qualOptions = [
    (id: '', label: '大三（无后缀）'),
    (id: 'm', label: '小三 (m)'),
    (id: '7', label: '属七 (7)'),
    (id: 'maj7', label: '大七 (maj7)'),
    (id: 'm7', label: '小七 (m7)'),
    (id: 'sus2', label: 'sus2'),
    (id: 'sus4', label: 'sus4'),
    (id: 'add9', label: 'add9'),
    (id: 'dim', label: 'dim'),
    (id: 'aug', label: 'aug'),
  ];

  static const List<({String id, String label})> bassOptions = [
    (id: '', label: '无转位'),
    (id: '/C', label: '低音 C'),
    (id: '/Db', label: '低音 Db'),
    (id: '/D', label: '低音 D'),
    (id: '/Eb', label: '低音 Eb'),
    (id: '/E', label: '低音 E'),
    (id: '/F', label: '低音 F'),
    (id: '/Gb', label: '低音 Gb'),
    (id: '/G', label: '低音 G'),
    (id: '/Ab', label: '低音 Ab'),
    (id: '/A', label: '低音 A'),
    (id: '/Bb', label: '低音 Bb'),
    (id: '/B', label: '低音 B'),
  ];
}

/// 由根音、性质后缀、slash 低音拼出 C 调记谱下的和弦符号（如 `Am7`、`G/B`）。
String buildChordSymbol({
  required String root,
  required String qualId,
  required String bassId,
}) {
  final r = root.trim();
  if (r.isEmpty) return '';
  return '$r$qualId$bassId';
}
