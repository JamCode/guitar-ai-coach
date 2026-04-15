import 'package:flutter/foundation.dart';

import '../chords/chord_models.dart';

/// 和弦表难度档（与和弦字典联网参数文案一致，便于用户理解进阶路径）。
enum ChordChartTier {
  /// 开放把位与少量简化按法，流行伴奏入门。
  beginner,

  /// 横按、常见七和弦与挂留，覆盖大部分歌曲进行。
  intermediate,

  /// 色彩和弦、转位与可移动型，丰富编配与爵士/融合入门。
  advanced,
}

/// 单条和弦：C 调记谱符号 + 乐理提示 + 主用指法（6→1 弦，-1 闷音、0 空弦）。
@immutable
class ChordChartEntry {
  const ChordChartEntry({
    required this.tier,
    required this.symbol,
    required this.theoryZh,
    required this.frets,
    this.voicingZh,
    this.fingers,
    this.barre,
  });

  final ChordChartTier tier;
  final String symbol;
  final String theoryZh;
  final List<int> frets;
  final String? voicingZh;
  final List<int?>? fingers;
  final ChordBarre? barre;
}

/// 分段标题与和弦条目（全部前端静态，不请求后端）。
@immutable
class ChordChartSection {
  const ChordChartSection({
    required this.tier,
    required this.titleZh,
    required this.introZh,
    required this.entries,
  });

  final ChordChartTier tier;
  final String titleZh;
  final String introZh;
  final List<ChordChartEntry> entries;
}

/// 初级：开放和弦家族（CAGED 中的 C/G/D/E/A 型开放位）与自然小调常用 ii。
///
/// 中级：大横按、属七/小七/大七、挂留、Gmaj7 等歌曲高频型。
///
/// 高级：增、减、加九、常用 slash、Bm7 等色彩与低音线常用型。
const List<ChordChartSection> kChordChartSections = [
  ChordChartSection(
    tier: ChordChartTier.beginner,
    titleZh: '初级 · 开放把位',
    introZh: '以空弦与低把位为主，先稳定换和弦与右手节奏；下列均为 C 调记谱，可把型整体平移变调。',
    entries: [
      ChordChartEntry(
        tier: ChordChartTier.beginner,
        symbol: 'C',
        theoryZh: '大三和弦（根-大三度-纯五度），大调 I 级色彩明亮。',
        frets: [-1, 3, 2, 0, 1, 0],
        voicingZh: '开放 C，5 弦起根音。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.beginner,
        symbol: 'G',
        theoryZh: '大三和弦；与 C、D 等组成 I–V–vi–IV 等流行进行。',
        frets: [3, 2, 0, 0, 0, 3],
        voicingZh: '开放 G，6 弦与 1 弦双根音。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.beginner,
        symbol: 'D',
        theoryZh: '大三和弦；大调 II 或属功能准备时常用。',
        frets: [-1, -1, 0, 2, 3, 2],
        voicingZh: '开放 D，4 弦起根音。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.beginner,
        symbol: 'A',
        theoryZh: '大三和弦；大调 IV 或属前属等位置常见。',
        frets: [-1, 0, 2, 2, 2, 0],
        voicingZh: '开放 A，5 弦根音。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.beginner,
        symbol: 'E',
        theoryZh: '大三和弦；布鲁斯/摇滚 I 级常用开放位。',
        frets: [0, 2, 2, 1, 0, 0],
        voicingZh: '开放 E，6 弦根音。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.beginner,
        symbol: 'Am',
        theoryZh: '小三和弦；与 C 大调共享音阶，常作 vi 级。',
        frets: [-1, 0, 2, 2, 1, 0],
        voicingZh: '开放 Am。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.beginner,
        symbol: 'Em',
        theoryZh: '小三和弦；自然小调 i 或关系大调 vi 的平行色彩。',
        frets: [0, 2, 2, 0, 0, 0],
        voicingZh: '开放 Em。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.beginner,
        symbol: 'Dm',
        theoryZh: '小三和弦；自然小调 ii 或小调下属色彩。',
        frets: [-1, -1, 0, 2, 3, 1],
        voicingZh: '开放 Dm。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.beginner,
        symbol: 'F',
        theoryZh: '大三和弦；入门常用「小横按」省略 6 弦大横按。',
        frets: [-1, -1, 3, 2, 1, 1],
        voicingZh: '简化 F（4～1 弦），熟练后再练全横按。',
      ),
    ],
  ),
  ChordChartSection(
    tier: ChordChartTier.intermediate,
    titleZh: '中级 · 横按与七和弦、挂留',
    introZh: '掌握 E 型/A 型可移动后，同一手型可弹 12 个调；七和弦与 sus 解决大量流行与布鲁斯语汇。',
    entries: [
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'F',
        theoryZh: '大三和弦；E 型大横按模板，6 弦根音。',
        frets: [1, 3, 3, 2, 1, 1],
        voicingZh: '全横按 F，可整体上下移调。',
        barre: ChordBarre(fret: 1, fromString: 6, toString_: 1),
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'Bm',
        theoryZh: '小三和弦；A 型小横按，5 弦根音可移动。',
        frets: [-1, 2, 4, 4, 3, 2],
        voicingZh: 'A 型小横按（此处为 Bm）。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'C7',
        theoryZh: '属七（大三+小七度），解决到 F 的倾向强。',
        frets: [-1, 3, 2, 3, 1, 0],
        voicingZh: '开放 C7。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'G7',
        theoryZh: '属七；终止式 V7→I 的核心色彩。',
        frets: [3, 2, 0, 0, 0, 1],
        voicingZh: '开放 G7。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'D7',
        theoryZh: '属七；二级属或布鲁斯 I7–IV7–V7 链中常见。',
        frets: [-1, -1, 0, 2, 1, 2],
        voicingZh: '开放 D7。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'E7',
        theoryZh: '属七；开放 E 把位上的布鲁斯/摇滚语汇。',
        frets: [0, 2, 0, 1, 0, 0],
        voicingZh: '开放 E7。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'A7',
        theoryZh: '属七；与 D、E 等调式搭配作 V7。',
        frets: [-1, 0, 2, 0, 2, 0],
        voicingZh: '开放 A7。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'Am7',
        theoryZh: '小七（小三+小七度），柔和、爵士与流行抒情常用。',
        frets: [-1, 0, 2, 0, 1, 0],
        voicingZh: '开放 Am7。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'Dm7',
        theoryZh: '小七；ii7–V7–I 中的 ii7 开放示例。',
        frets: [-1, -1, 0, 2, 1, 1],
        voicingZh: '开放 Dm7。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'Em7',
        theoryZh: '小七；与 G 大调共享音，伴奏铺底干净。',
        frets: [0, 2, 2, 0, 3, 0],
        voicingZh: '开放 Em7。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'Cmaj7',
        theoryZh: '大七（大三+大七度），明亮、爵士/流行色彩。',
        frets: [-1, 3, 2, 0, 0, 0],
        voicingZh: '开放 Cmaj7。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'Gmaj7',
        theoryZh: '大七；Imaj7 色彩，抒情与 R&B 常见。',
        frets: [3, 2, 0, 0, 0, 2],
        voicingZh: '开放 Gmaj7。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'Asus4',
        theoryZh: '挂四（无三度），悬而未决，常解决回 A 大三。',
        frets: [-1, 0, 2, 2, 3, 0],
        voicingZh: '开放 Asus4。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.intermediate,
        symbol: 'Dsus4',
        theoryZh: '挂四；D 与 Dsus4–D 装饰在摇滚/英伦流行极常见。',
        frets: [-1, -1, 0, 2, 3, 3],
        voicingZh: '开放 Dsus4。',
      ),
    ],
  ),
  ChordChartSection(
    tier: ChordChartTier.advanced,
    titleZh: '高级 · 色彩、转位与扩展',
    introZh: '增、减、加九与 slash 低音改变低音线走向；Bm7 等为 ii7 小横按模板，可平移。',
    entries: [
      ChordChartEntry(
        tier: ChordChartTier.advanced,
        symbol: 'B7',
        theoryZh: '属七；E 大调 / 小调中的 V7，爵士 ii–V–I 右侧常用。',
        frets: [-1, 2, 1, 2, 0, 2],
        voicingZh: '开放 B7（A 型指法变体）。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.advanced,
        symbol: 'Bm7',
        theoryZh: '小七；ii7 可移动型（此处为 Bm7）。',
        frets: [-1, 2, 4, 2, 3, 2],
        voicingZh: 'A 弦根的小七型，可上下移调。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.advanced,
        symbol: 'Cadd9',
        theoryZh: '大三加九度，比 sus2 更「厚」，流行抒情常用。',
        frets: [-1, 3, 2, 0, 3, 0],
        voicingZh: '开放 Cadd9。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.advanced,
        symbol: 'Edim',
        theoryZh: '减三和弦（根-小三度-减五度），可沿品丝每 3 品重复型。',
        frets: [0, 1, 2, 1, 2, 1],
        voicingZh: '开放 Edim（可整体上移小三度循环）。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.advanced,
        symbol: 'Eaug',
        theoryZh: '增三和弦（大三+增五度），对称、色彩强烈。',
        frets: [0, 3, 2, 1, 1, 0],
        voicingZh: '开放 Eaug。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.advanced,
        symbol: 'G/B',
        theoryZh: 'Slash：低音为 B，第一转位色彩；低音线 G–B–D 等进行常用。',
        frets: [-1, 2, 0, 0, 0, 3],
        voicingZh: 'G 第一转位（5 弦 B 低音）。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.advanced,
        symbol: 'D/F#',
        theoryZh: 'Slash：低音 #F，_walking bass_ 与卡农式进行常见。',
        frets: [2, -1, 0, 2, 3, 2],
        voicingZh: 'D 第一转位（6 弦 #F）。',
      ),
      ChordChartEntry(
        tier: ChordChartTier.advanced,
        symbol: 'C/G',
        theoryZh: 'Slash：低音 G，属准备或踏板低音上的 C。',
        frets: [3, 3, 2, 0, 1, 0],
        voicingZh: 'C 第二转位（6 弦 G 低音）。',
      ),
    ],
  ),
];
