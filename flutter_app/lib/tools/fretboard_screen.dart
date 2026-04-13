import 'package:flutter/material.dart';

import 'fretboard_math.dart';

/// 竖向吉他指板参考：上为弦枕，向下为更高把位；横向 6 弦（左→右 6 弦→1 弦）。
class FretboardScreen extends StatefulWidget {
  const FretboardScreen({super.key});

  /// 默认展示到第几品（含）。
  static const int defaultMaxFret = 15;

  @override
  State<FretboardScreen> createState() => _FretboardScreenState();
}

class _FretboardScreenState extends State<FretboardScreen> {
  var _capo = 0;
  var _naturalOnly = false;
  var _mirror = false;

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('指板说明'),
        content: const SingleChildScrollView(
          child: Text(
            '竖向从上往下为从弦枕向高把位；最上一行为空弦（0 品）。\n\n'
            '横向从左到右为 6 弦→1 弦（粗弦→细弦），与低头看琴颈方向一致；'
            '可打开「左右镜像」以适配习惯。\n\n'
            '变调夹会整体升高音高，格内音名为实际音高（非和弦级数）。\n\n'
            '「仅自然音」时仅显示 C D E F G A B，其余格留空。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('吉他指板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: '说明',
            onPressed: () => _showHelp(context),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '标准调弦 E A D G B E',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('变调夹 $_capo 品', style: theme.textTheme.bodyMedium),
                    Expanded(
                      child: Slider(
                        value: _capo.toDouble(),
                        min: 0,
                        max: 12,
                        divisions: 12,
                        label: '$_capo',
                        onChanged: (v) => setState(() => _capo = v.round()),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('仅自然音'),
                      selected: _naturalOnly,
                      onSelected: (v) => setState(() => _naturalOnly = v),
                    ),
                    FilterChip(
                      label: const Text('左右镜像'),
                      selected: _mirror,
                      onSelected: (v) => setState(() => _mirror = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                key: const Key('fretboard_scroll'),
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StringHeaderRow(
                      mirror: _mirror,
                      scheme: scheme,
                      theme: theme,
                    ),
                    ...List<Widget>.generate(
                      FretboardScreen.defaultMaxFret + 1,
                      (i) {
                        final fret = i;
                        return _FretRow(
                          fret: fret,
                          mirror: _mirror,
                          capo: _capo,
                          openMidi: kStandardOpenMidiStrings,
                          naturalOnly: _naturalOnly,
                          scheme: scheme,
                          theme: theme,
                          isNut: fret == 0,
                          isTwelfth: fret == 12,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StringHeaderRow extends StatelessWidget {
  const _StringHeaderRow({
    required this.mirror,
    required this.scheme,
    required this.theme,
  });

  final bool mirror;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final indices = mirror
        ? List<int>.generate(6, (i) => 5 - i)
        : List<int>.generate(6, (i) => i);
    return Padding(
      padding: const EdgeInsets.only(left: 40),
      child: Row(
        children: [
          for (final si in indices)
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${6 - si}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    kStringNoteNames[si],
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FretRow extends StatelessWidget {
  const _FretRow({
    required this.fret,
    required this.mirror,
    required this.capo,
    required this.openMidi,
    required this.naturalOnly,
    required this.scheme,
    required this.theme,
    required this.isNut,
    required this.isTwelfth,
  });

  final int fret;
  final bool mirror;
  final int capo;
  final List<int> openMidi;
  final bool naturalOnly;
  final ColorScheme scheme;
  final ThemeData theme;
  final bool isNut;
  final bool isTwelfth;

  @override
  Widget build(BuildContext context) {
    final indices = mirror
        ? List<int>.generate(6, (i) => 5 - i)
        : List<int>.generate(6, (i) => i);
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isTwelfth
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: isNut
            ? Border(bottom: BorderSide(color: scheme.outline, width: 3))
            : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Center(
              child: fret == 0
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '0',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '空弦',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '$fret',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          for (final si in indices)
            Expanded(
              child: _FretCell(
                label: labelForCell(
                  stringIndex: si,
                  fret: fret,
                  capo: capo,
                  openMidi: openMidi,
                  naturalOnly: naturalOnly,
                ),
                scheme: scheme,
                theme: theme,
              ),
            ),
        ],
      ),
    );
  }
}

class _FretCell extends StatelessWidget {
  const _FretCell({
    required this.label,
    required this.scheme,
    required this.theme,
  });

  final String? label;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: SizedBox(
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Center(
            child: Text(
              label ?? '·',
              style: theme.textTheme.titleMedium?.copyWith(
                color: label != null
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant.withValues(alpha: 0.45),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
