import 'chord_models.dart';
import 'chord_spelling.dart';
import 'chord_symbol.dart';

/// 解析和弦符号（与下拉拼出的 `buildChordSymbol` 形式一致，如 `Am`、`G/B`）。
class ParsedChordSymbol {
  const ParsedChordSymbol({
    required this.root,
    required this.qualId,
    this.slashBassName,
  });

  final String root;
  final String qualId;
  final String? slashBassName;

  /// [symbol] 不含变调，一般为 C 调记谱拼出的结果。
  static ParsedChordSymbol? parse(String symbol) {
    var s = symbol.trim();
    if (s.isEmpty) return null;
    String? slash;
    if (s.contains('/')) {
      final i = s.indexOf('/');
      final bassPart = s.substring(i + 1).trim();
      s = s.substring(0, i).trim();
      slash = bassPart;
    }
    const roots = [
      'C#', 'Db', 'D#', 'Eb', 'F#', 'Gb', 'G#', 'Ab', 'A#', 'Bb',
      'C', 'D', 'E', 'F', 'G', 'A', 'B',
    ];
    for (final r in roots) {
      if (s.startsWith(r)) {
        final qualSuffix = s.substring(r.length);
        final qid = _normalizeQualId(qualSuffix);
        return ParsedChordSymbol(
          root: r,
          qualId: qid,
          slashBassName: slash,
        );
      }
    }
    return null;
  }

  static String _normalizeQualId(String q) {
    if (q.isEmpty) return '';
    // 和弦切换练习里会出现扩展和弦符号，映射到离线拼字/按法可用的性质。
    if (q == 'm7b5') return 'm7b5';
    if (q == 'maj9') return 'maj7';
    if (q == 'm9') return 'm7';
    if (q == '9') return '7';
    const order = ['maj7', 'm7', 'sus2', 'sus4', 'add9', 'dim', 'aug', 'm', '7'];
    for (final o in order) {
      if (q == o) return o;
    }
    return '';
  }

  /// 用于覆盖表查找（无 slash）。
  String get lookupKey => buildChordSymbol(root: root, qualId: qualId, bassId: '');
}

/// 开放/常用把位覆盖（6→1 弦）；无网络。
const Map<String, List<List<int>>> kOfflineChordFretOverrides = {
  'C': [
    [-1, 3, 2, 0, 1, 0],
    [-1, 3, 5, 5, 5, 3],
  ],
  'Cm': [
    [-1, 3, 5, 5, 4, 3],
    [3, 3, 5, 5, 4, 3],
  ],
  'C7': [
    [-1, 3, 2, 3, 1, 0],
    [ -1, 3, 5, 3, 5, 3],
  ],
  'Cmaj7': [
    [-1, 3, 2, 0, 0, 0],
    [3, 3, 5, 4, 5, 3],
  ],
  'G': [
    [3, 2, 0, 0, 0, 3],
    [3, 2, 0, 0, 3, 3],
  ],
  'Gm': [
    [3, 5, 5, 3, 3, 3],
    [ -1, 10, 10, 8, 8, 8],
  ],
  'D': [
    [-1, -1, 0, 2, 3, 2],
    [-1, -1, 0, 7, 7, 5],
  ],
  'Dm': [
    [-1, -1, 0, 2, 3, 1],
    [-1, -1, 0, 5, 7, 5],
  ],
  'A': [
    [-1, 0, 2, 2, 2, 0],
    [5, 5, 7, 7, 7, 5],
  ],
  'Am': [
    [-1, 0, 2, 2, 1, 0],
    [5, 7, 7, 5, 5, 5],
  ],
  'E': [
    [0, 2, 2, 1, 0, 0],
    [0, 7, 6, 7, 7, 0],
  ],
  'Em': [
    [0, 2, 2, 0, 0, 0],
    [0, 7, 7, 5, 5, 0],
  ],
  'F': [
    [1, 3, 3, 2, 1, 1],
    [-1, -1, 3, 2, 1, 1],
  ],
  'Fm': [
    [1, 3, 3, 1, 1, 1],
    [1, 3, 3, 1, 4, 1],
  ],
  'B': [
    [2, 2, 4, 4, 4, 2],
    [7, 7, 9, 9, 9, 7],
  ],
  'Bm': [
    [2, 2, 4, 4, 3, 2],
    [7, 7, 7, 9, 9, 7],
  ],
};

/// 构建离线 [ChordExplainMultiPayload]（至少两种按法展示）。
ChordExplainMultiPayload? buildOfflineChordPayload({
  required String displaySymbol,
}) {
  final parsed = ParsedChordSymbol.parse(displaySymbol);
  if (parsed == null) return null;

  final letters = spellTriadOrSeventhLetters(
    rootName: parsed.root,
    qualId: parsed.qualId,
  );
  if (letters.isEmpty) return null;

  var explain = chordQualityExplainZh(parsed.qualId);
  if (parsed.slashBassName != null && parsed.slashBassName!.isNotEmpty) {
    explain += ' Slash 低音为 ${parsed.slashBassName}；指法需保证最低音落在对应弦上。';
  }

  final summary = ChordSummary(
    symbol: displaySymbol,
    notesLetters: letters,
    notesExplainZh: explain,
  );

  final items = <ChordVoicingItem>[];
  final key = parsed.lookupKey;
  final override = kOfflineChordFretOverrides[key];
  if (override != null && override.length >= 2) {
    items.add(
      _voicing('常用把位 ①', override[0], '离线字典收录的常见型。'),
    );
    items.add(
      _voicing('常用把位 ②', override[1], '备选按法，可择手型更顺的一种。'),
    );
  } else {
    items.addAll(_syntheticBarrePair(parsed));
  }

  if (items.length < 2) {
    return null;
  }

  return ChordExplainMultiPayload(
    chordSummary: summary,
    voicings: items,
    disclaimer:
        '本地和弦字典：指法为常见吉他型，因人而异；不构成音以乐理推算为准。'
        ' 可配置 API 使用「联网查询」获取更多 AI 按法。',
  );
}

ChordVoicingItem _voicing(String label, List<int> frets, String zh) {
  final positive = frets.where((f) => f > 0);
  final baseFret = positive.isEmpty
      ? 1
      : positive.reduce((a, b) => a < b ? a : b);
  return ChordVoicingItem(
    labelZh: label,
    explain: ChordVoicingExplain(
      frets: frets,
      fingers: List<int?>.filled(6, null),
      baseFret: baseFret,
      voicingExplainZh: zh,
    ),
  );
}

/// E 型横按模板：大三 [f,f+2,f+2,f+1,f,f]；小三 [f,f+2,f+2,f,f,f]。
List<ChordVoicingItem> _syntheticBarrePair(ParsedChordSymbol p) {
  final rootPc = _rootPc(p.root);
  if (rootPc == null) return [];
  final f = (rootPc - 4 + 12) % 12;

  final isMinor =
      p.qualId == 'm' || p.qualId == 'm7' || p.qualId == 'm7b5';
  final List<int> a;
  final List<int> b;
  if (isMinor) {
    a = [f, f + 2, f + 2, f, f, f];
    b = [f + 3, f + 5, f + 5, f + 3, f + 3, f + 3];
  } else {
    a = [f, f + 2, f + 2, f + 1, f, f];
    b = [f + 3, f + 5, f + 5, f + 4, f + 3, f + 3];
  }
  return [
    _voicing(
      'E 型横按模板（六弦根音）',
      a,
      '以 6 弦 $f 品为根音的常用可移动型；可整体上下移动把位。',
    ),
    _voicing(
      '可移动型变体',
      b,
      '另一常见把位示意；实际按法请结合手型微调，避免碰弦。',
    ),
  ];
}

int? _rootPc(String root) {
  const m = {
    'C': 0,
    'Db': 1,
    'C#': 1,
    'D': 2,
    'Eb': 3,
    'D#': 3,
    'E': 4,
    'F': 5,
    'Gb': 6,
    'F#': 6,
    'G': 7,
    'Ab': 8,
    'G#': 8,
    'A': 9,
    'Bb': 10,
    'A#': 10,
    'B': 11,
  };
  return m[root];
}
