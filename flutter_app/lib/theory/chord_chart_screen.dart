import 'package:flutter/material.dart';

import '../chords/chord_diagram_widget.dart';
import '../chords/chord_models.dart';
import 'common_chord_chart_data.dart';

/// 常用和弦指法表：初 / 中 / 高分段，**数据全部打包在前端**，不请求后端。
///
/// 布局为「分段折叠 + 紧凑行」：一屏可扫更多和弦；点行打开底部详情看完整说明与大图。
class ChordChartScreen extends StatelessWidget {
  const ChordChartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('和弦表')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              title: Text(
                '关于本表',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '按乐理难度分段：初级开放三和弦为主，中级横按与七和弦、挂留，'
                  '高级色彩与 slash。记谱为 C 调示例，把型可平移到其他调。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (var si = 0; si < kChordChartSections.length; si++)
            _SectionExpansion(
              section: kChordChartSections[si],
              initiallyExpanded: si == 0,
            ),
          const SizedBox(height: 8),
          Text(
            '点某一和弦可查看大图与品位数字；构成音与第二套把位见「和弦字典」。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionExpansion extends StatelessWidget {
  const _SectionExpansion({
    required this.section,
    required this.initiallyExpanded,
  });

  final ChordChartSection section;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = section.entries.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('chord_section_${section.titleZh}'),
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          title: Text(
            section.titleZh,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            '$n 个 · ${section.introZh}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: [
            for (final e in section.entries) _ChordCompactRow(entry: e),
          ],
        ),
      ),
    );
  }
}

/// 紧凑行：小图 + 符号 + 摘要；点击展开底部详情。
class _ChordCompactRow extends StatelessWidget {
  const _ChordCompactRow({required this.entry});

  final ChordChartEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = _baseFret(entry.frets);
    const diagramW = 92.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openChordDetail(context, entry, base),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ChordDiagramWidget(
                frets: entry.frets,
                fingers: entry.fingers,
                baseFret: base,
                barre: entry.barre,
                width: diagramW,
                color: scheme.onSurface,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.symbol,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.theoryZh,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface,
                        height: 1.25,
                      ),
                    ),
                    if (entry.voicingZh != null &&
                        entry.voicingZh!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        entry.voicingZh!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _openChordDetail(
  BuildContext context,
  ChordChartEntry entry,
  int base,
) {
  final scheme = Theme.of(context).colorScheme;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              entry.symbol,
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            Center(
              child: ChordDiagramWidget(
                frets: entry.frets,
                fingers: entry.fingers,
                baseFret: base,
                barre: entry.barre,
                width: 168,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              entry.theoryZh,
              style: Theme.of(ctx).textTheme.bodyLarge,
            ),
            if (entry.voicingZh != null && entry.voicingZh!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                entry.voicingZh!,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            SelectableText(
              '起算品格：$base · 6→1 弦：${formatFretsLine(entry.frets)}',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    },
  );
}

/// 与离线字典一致：用于指法图左侧「fr」标注与 [ChordDiagramWidget.baseFret]。
int _baseFret(List<int> frets) {
  final positive = frets.where((f) => f > 0);
  if (positive.isEmpty) return 1;
  return positive.reduce((a, b) => a < b ? a : b);
}
