/// 单格扫弦方向：对应一小节内 8 个八分音符位置之一（`1 & 2 & 3 & 4 &`）。
enum StrumCellKind {
  /// 下扫
  down,

  /// 上扫
  up,

  /// 休止（不扫）
  rest,
}

/// 一条内置扫弦节奏型（4/4，八分音符网格）。
class StrummingPattern {
  const StrummingPattern({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.tip,
    required this.cells,
  });

  /// 稳定 id，用于本地会话记录。
  final String id;

  /// 列表与选择器展示名。
  final String name;

  /// 副标题（简短说明难度或风格）。
  final String subtitle;

  /// 练习提示（主界面展示）。
  final String tip;

  /// 长度 8：`[1, &, 2, &, 3, &, 4, &]`。
  final List<StrumCellKind> cells;
}

/// 内置常用扫弦节奏目录（4/4 八分网格，可随教学补充）。
const List<StrummingPattern> kStrummingPatterns = <StrummingPattern>[
  StrummingPattern(
    id: 'all-down-eighths',
    name: '八分全下',
    subtitle: '入门 · 稳拍',
    tip: '每一拍均匀下扫，先求稳再求力度变化。',
    cells: <StrumCellKind>[
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.down,
    ],
  ),
  StrummingPattern(
    id: 'all-up-eighths',
    name: '八分全上',
    subtitle: '上扫均匀',
    tip: '全部用上扫练手腕回程，音量通常比下扫轻，注意与弦接触角度。',
    cells: <StrumCellKind>[
      StrumCellKind.up,
      StrumCellKind.up,
      StrumCellKind.up,
      StrumCellKind.up,
      StrumCellKind.up,
      StrumCellKind.up,
      StrumCellKind.up,
      StrumCellKind.up,
    ],
  ),
  StrummingPattern(
    id: 'alternate-eighths',
    name: '八分交替',
    subtitle: '上下均匀',
    tip: '下上交替，注意小臂摆动幅度一致。',
    cells: <StrumCellKind>[
      StrumCellKind.down,
      StrumCellKind.up,
      StrumCellKind.down,
      StrumCellKind.up,
      StrumCellKind.down,
      StrumCellKind.up,
      StrumCellKind.down,
      StrumCellKind.up,
    ],
  ),
  StrummingPattern(
    id: 'folk-dduudu',
    name: '民谣常用',
    subtitle: '下下上 上下上',
    tip: '经典型：前两拍「下下」，后两拍「上上下上」的变体，先慢速跟拍。',
    cells: <StrumCellKind>[
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.up,
      StrumCellKind.up,
      StrumCellKind.down,
      StrumCellKind.up,
      StrumCellKind.rest,
      StrumCellKind.rest,
    ],
  ),
  StrummingPattern(
    id: 'chunk-double',
    name: '双 Chunk',
    subtitle: '下下上 下下上',
    tip: '两拍一组「下下上」连做两次，流行歌常用，注意第二组不要抢拍。',
    cells: <StrumCellKind>[
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.up,
      StrumCellKind.up,
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.up,
      StrumCellKind.up,
    ],
  ),
  StrummingPattern(
    id: 'driving-triplets-feel',
    name: '行进感',
    subtitle: '三下接一上',
    tip: '连续三个下扫后接一个上扫，有推进感；先慢速再加速。',
    cells: <StrumCellKind>[
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.up,
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.down,
      StrumCellKind.up,
    ],
  ),
  StrummingPattern(
    id: 'quarter-downs',
    name: '每拍一下',
    subtitle: '四分音符 · 稳',
    tip: '只在正拍下扫，& 位置休息，适合慢歌或强调重音。',
    cells: <StrumCellKind>[
      StrumCellKind.down,
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.rest,
    ],
  ),
  StrummingPattern(
    id: 'half-note-downs',
    name: '两拍一下',
    subtitle: '二分音符 · 慢曲',
    tip: '只在第 1、3 拍正点下扫，其余空拍，适合很慢的抒情或数拍。',
    cells: <StrumCellKind>[
      StrumCellKind.down,
      StrumCellKind.rest,
      StrumCellKind.rest,
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.rest,
      StrumCellKind.rest,
      StrumCellKind.rest,
    ],
  ),
  StrummingPattern(
    id: 'offbeat-downs',
    name: '反拍八分',
    subtitle: '弱拍下扫',
    tip: '正拍不扫、弱拍扫，先小声找「反拍」位置，再加重。',
    cells: <StrumCellKind>[
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.rest,
      StrumCellKind.down,
    ],
  ),
  StrummingPattern(
    id: 'ska-ups',
    name: 'Ska 上扫',
    subtitle: '弱拍上扫',
    tip: '正拍休止、弱拍上扫，手腕略抬高；可与反拍下扫对照练。',
    cells: <StrumCellKind>[
      StrumCellKind.rest,
      StrumCellKind.up,
      StrumCellKind.rest,
      StrumCellKind.up,
      StrumCellKind.rest,
      StrumCellKind.up,
      StrumCellKind.rest,
      StrumCellKind.up,
    ],
  ),
  StrummingPattern(
    id: 'reggae-backbeat',
    name: '雷鬼反拍',
    subtitle: '2、4 拍',
    tip: '只在第 2、4 拍正点下扫，其余不扫，适合雷鬼/慢摇滚律动。',
    cells: <StrumCellKind>[
      StrumCellKind.rest,
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.rest,
      StrumCellKind.rest,
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.rest,
    ],
  ),
  StrummingPattern(
    id: 'percussive-du-gap',
    name: '下切上',
    subtitle: '带空隙',
    tip: '下—空—上循环，空拍可做护弦或制音，偏节奏吉他。',
    cells: <StrumCellKind>[
      StrumCellKind.down,
      StrumCellKind.rest,
      StrumCellKind.up,
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.rest,
      StrumCellKind.up,
      StrumCellKind.rest,
    ],
  ),
  StrummingPattern(
    id: 'shuffle-eighths',
    name: 'Shuffle 感',
    subtitle: '长短短',
    tip: '近似三连音长短短：长音用下扫，短音用上扫，慢速对齐摇摆感。',
    cells: <StrumCellKind>[
      StrumCellKind.down,
      StrumCellKind.up,
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.up,
      StrumCellKind.rest,
      StrumCellKind.down,
      StrumCellKind.up,
    ],
  ),
];

/// 按 [id] 解析展示名；未知时返回 null。
String? strummingPatternNameForId(String? id) {
  if (id == null || id.isEmpty) {
    return null;
  }
  for (final p in kStrummingPatterns) {
    if (p.id == id) {
      return p.name;
    }
  }
  return null;
}
