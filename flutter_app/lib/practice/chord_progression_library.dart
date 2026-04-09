/// 和弦进行库：预置进行数据 + 级数×调×复杂度 → 和弦符号解析引擎。
library;

/// 和弦复杂度：影响每个级数生成的和弦后缀。
enum ChordComplexity {
  basic,
  intermediate,
  advanced;

  String get label {
    switch (this) {
      case ChordComplexity.basic:
        return '基础';
      case ChordComplexity.intermediate:
        return '进阶';
      case ChordComplexity.advanced:
        return '高级';
    }
  }

  String get fullLabel {
    switch (this) {
      case ChordComplexity.basic:
        return '基础（三和弦）';
      case ChordComplexity.intermediate:
        return '进阶（七和弦）';
      case ChordComplexity.advanced:
        return '高级（九和弦+）';
    }
  }
}

/// 一条和弦进行：以罗马级数形式存储，可在任意调与复杂度下解析为实际和弦名。
class ChordProgression {
  const ChordProgression({
    required this.id,
    required this.name,
    required this.romanNumerals,
    required this.style,
    this.description,
  });

  final String id;
  final String name;

  /// 连字符分隔的罗马级数，如 `I-V-vi-IV`。
  final String romanNumerals;

  /// 风格标签，用于列表分组。
  final String style;
  final String? description;
}

// ---------------------------------------------------------------------------
// 预置和弦进行
// ---------------------------------------------------------------------------

const List<ChordProgression> kChordProgressions = <ChordProgression>[
  // Pop
  ChordProgression(
    id: 'pop-classic',
    name: '流行经典',
    romanNumerals: 'I-V-vi-IV',
    style: 'Pop',
    description: '全球最常见的流行和弦走向',
  ),
  ChordProgression(
    id: 'pop-50s',
    name: '50 年代',
    romanNumerals: 'I-vi-IV-V',
    style: 'Pop',
  ),
  ChordProgression(
    id: 'pop-minor',
    name: '小调流行',
    romanNumerals: 'vi-IV-I-V',
    style: 'Pop',
  ),
  ChordProgression(
    id: 'pop-canon',
    name: '卡农进行',
    romanNumerals: 'I-V-vi-iii-IV-I-IV-V',
    style: 'Pop',
    description: '帕赫贝尔卡农经典 8 和弦',
  ),
  ChordProgression(
    id: 'pop-emotional',
    name: '催泪进行',
    romanNumerals: 'IV-V-iii-vi',
    style: 'Pop',
  ),
  ChordProgression(
    id: 'pop-axis',
    name: '轴心进行',
    romanNumerals: 'I-V-vi-iii',
    style: 'Pop',
  ),

  // Rock
  ChordProgression(
    id: 'rock-classic',
    name: '经典三和弦',
    romanNumerals: 'I-IV-V-I',
    style: 'Rock',
  ),
  ChordProgression(
    id: 'rock-mixo',
    name: '混合利底亚',
    romanNumerals: 'I-bVII-IV-I',
    style: 'Rock',
  ),
  ChordProgression(
    id: 'rock-power',
    name: '力量进行',
    romanNumerals: 'I-bVII-bVI-V',
    style: 'Rock',
    description: '安达卢西亚终止变体',
  ),

  // Blues
  ChordProgression(
    id: 'blues-12bar',
    name: '12 小节布鲁斯',
    romanNumerals: 'I-I-I-I-IV-IV-I-I-V-IV-I-V',
    style: 'Blues',
  ),
  ChordProgression(
    id: 'blues-quick4',
    name: '快四布鲁斯',
    romanNumerals: 'I-IV-I-I-IV-IV-I-I-V-IV-I-V',
    style: 'Blues',
    description: '第 2 小节提前到 IV 级',
  ),

  // Jazz
  ChordProgression(
    id: 'jazz-251',
    name: '二五一',
    romanNumerals: 'ii-V-I',
    style: 'Jazz',
    description: '爵士最核心的终止进行',
  ),
  ChordProgression(
    id: 'jazz-turnaround',
    name: '回转进行',
    romanNumerals: 'I-vi-ii-V',
    style: 'Jazz',
  ),
  ChordProgression(
    id: 'jazz-rhythm',
    name: '节奏变化',
    romanNumerals: 'ii-V-I-vi',
    style: 'Jazz',
  ),

  // Folk
  ChordProgression(
    id: 'folk-basic',
    name: '民谣三和弦',
    romanNumerals: 'I-IV-V-IV',
    style: 'Folk',
  ),
  ChordProgression(
    id: 'folk-vi',
    name: '民谣四和弦',
    romanNumerals: 'I-vi-IV-V',
    style: 'Folk',
  ),
];

/// 按 style 分组后的顺序（UI 用）。
const List<String> kProgressionStyles = [
  'Pop',
  'Rock',
  'Blues',
  'Jazz',
  'Folk',
];

/// 风格显示名映射。
const Map<String, String> kStyleLabels = {
  'Pop': '流行',
  'Rock': '摇滚',
  'Blues': '布鲁斯',
  'Jazz': '爵士',
  'Folk': '民谣',
};

// ---------------------------------------------------------------------------
// 12 调列表（与 ChordSelectCatalog.keys 一致）
// ---------------------------------------------------------------------------

const List<String> kMusicKeys = [
  'C', 'Db', 'D', 'Eb', 'E', 'F',
  'Gb', 'G', 'Ab', 'A', 'Bb', 'B',
];

// ---------------------------------------------------------------------------
// 转调引擎
// ---------------------------------------------------------------------------

/// 将罗马级数进行解析为指定调与复杂度下的和弦符号列表。
abstract final class ChordProgressionEngine {
  /// 12 半音对应的降号音名（用于借用和弦与降号调）。
  static const _flatNames = [
    'C', 'Db', 'D', 'Eb', 'E', 'F',
    'Gb', 'G', 'Ab', 'A', 'Bb', 'B',
  ];

  /// 12 半音对应的升号音名（用于升号调的自然音级）。
  static const _sharpNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F',
    'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  /// 升号调集合：这些调的自然音级优先用升号命名。
  static const _sharpKeys = {'C', 'G', 'D', 'A', 'E', 'B'};

  static const _notePcMap = <String, int>{
    'C': 0, 'C#': 1, 'Db': 1,
    'D': 2, 'D#': 3, 'Eb': 3,
    'E': 4, 'F': 5, 'F#': 6,
    'Gb': 6, 'G': 7, 'G#': 8,
    'Ab': 8, 'A': 9, 'A#': 10,
    'Bb': 10, 'B': 11,
  };

  /// 每个罗马级数在 C 调下的和弦符号（三档复杂度）。
  static const _romanToChordInC =
      <String, Map<ChordComplexity, String>>{
    'I': {
      ChordComplexity.basic: 'C',
      ChordComplexity.intermediate: 'Cmaj7',
      ChordComplexity.advanced: 'Cmaj9',
    },
    'ii': {
      ChordComplexity.basic: 'Dm',
      ChordComplexity.intermediate: 'Dm7',
      ChordComplexity.advanced: 'Dm9',
    },
    'iii': {
      ChordComplexity.basic: 'Em',
      ChordComplexity.intermediate: 'Em7',
      ChordComplexity.advanced: 'Em9',
    },
    'IV': {
      ChordComplexity.basic: 'F',
      ChordComplexity.intermediate: 'Fmaj7',
      ChordComplexity.advanced: 'Fmaj9',
    },
    'V': {
      ChordComplexity.basic: 'G',
      ChordComplexity.intermediate: 'G7',
      ChordComplexity.advanced: 'G9',
    },
    'vi': {
      ChordComplexity.basic: 'Am',
      ChordComplexity.intermediate: 'Am7',
      ChordComplexity.advanced: 'Am9',
    },
    'vii': {
      ChordComplexity.basic: 'Bdim',
      ChordComplexity.intermediate: 'Bm7b5',
      ChordComplexity.advanced: 'Bm7b5',
    },
    // 借用和弦 —— 根音在 C 调下用降号表示
    'bVII': {
      ChordComplexity.basic: 'Bb',
      ChordComplexity.intermediate: 'Bb7',
      ChordComplexity.advanced: 'Bb9',
    },
    'bIII': {
      ChordComplexity.basic: 'Eb',
      ChordComplexity.intermediate: 'Ebmaj7',
      ChordComplexity.advanced: 'Ebmaj9',
    },
    'bVI': {
      ChordComplexity.basic: 'Ab',
      ChordComplexity.intermediate: 'Abmaj7',
      ChordComplexity.advanced: 'Abmaj9',
    },
    // 自然小调级数
    'i': {
      ChordComplexity.basic: 'Cm',
      ChordComplexity.intermediate: 'Cm7',
      ChordComplexity.advanced: 'Cm9',
    },
    'iv': {
      ChordComplexity.basic: 'Fm',
      ChordComplexity.intermediate: 'Fm7',
      ChordComplexity.advanced: 'Fm9',
    },
    'v': {
      ChordComplexity.basic: 'Gm',
      ChordComplexity.intermediate: 'Gm7',
      ChordComplexity.advanced: 'Gm9',
    },
  };

  /// 核心 API：把一条级数进行解析为当前调与复杂度下的和弦符号。
  ///
  /// [romanNumerals] 以连字符分隔，如 `I-V-vi-IV`。
  static List<String> resolveChordNames({
    required String romanNumerals,
    required String key,
    required ChordComplexity complexity,
  }) {
    final romans =
        romanNumerals.split('-').where((s) => s.trim().isNotEmpty).toList();
    return romans
        .map((r) => _resolveSingle(r.trim(), key, complexity))
        .toList();
  }

  static String _resolveSingle(
    String roman,
    String key,
    ChordComplexity complexity,
  ) {
    final chordMap = _romanToChordInC[roman];
    if (chordMap == null) return roman;
    final chordInC =
        chordMap[complexity] ?? chordMap[ChordComplexity.basic]!;
    if (key == 'C') return chordInC;
    final isBorrowed = roman.startsWith('b');
    return _transposeChord(chordInC, key, forceFlats: isBorrowed);
  }

  /// 将 C 调和弦符号移至目标调。
  ///
  /// [forceFlats] 为 true 时即使目标调为升号调也使用降号命名
  /// （用于 bVII / bVI / bIII 等借用和弦）。
  static String _transposeChord(
    String chordInC,
    String toKey, {
    bool forceFlats = false,
  }) {
    final delta = _notePcMap[toKey] ?? 0;
    if (delta == 0) return chordInC;
    final match = RegExp(r'^([A-G])([#b]?)(.*)$').firstMatch(chordInC);
    if (match == null) return chordInC;
    final rootNote = '${match.group(1)}${match.group(2) ?? ''}';
    final suffix = match.group(3) ?? '';
    final rootPc = _notePcMap[rootNote] ?? 0;
    final newPc = (rootPc + delta) % 12;
    final useFlats = forceFlats || !_sharpKeys.contains(toKey);
    final newRoot = useFlats ? _flatNames[newPc] : _sharpNames[newPc];
    return '$newRoot$suffix';
  }
}
