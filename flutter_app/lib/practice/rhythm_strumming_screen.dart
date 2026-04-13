import 'package:flutter/material.dart';

import 'practice_api_repository.dart';
import 'practice_finish_dialog.dart';
import 'practice_models.dart';
import 'practice_session_store.dart';
import 'strumming_pattern.dart';

/// 节奏扫弦练习：按内置常用扫弦型展示 4/4 八分网格图示，无计时器；可选保存记录。
class RhythmStrummingScreen extends StatefulWidget {
  const RhythmStrummingScreen({
    super.key,
    required this.task,
    required this.store,
  });

  final PracticeTask task;
  final PracticeSessionStore store;

  @override
  State<RhythmStrummingScreen> createState() => _RhythmStrummingScreenState();
}

class _RhythmStrummingScreenState extends State<RhythmStrummingScreen> {
  final _noteController = TextEditingController();
  late StrummingPattern _pattern;
  late final DateTime _openedAt;

  static const _beatLabels = <String>['1', '&', '2', '&', '3', '&', '4', '&'];

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    _pattern = kStrummingPatterns.first;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _onFinish() async {
    final result = await showPracticeFinishDialog(
      context: context,
      noteController: _noteController,
      title: '本次练习',
      showCompletedGoal: false,
    );
    if (result == null || !context.mounted) {
      return;
    }
    try {
      await widget.store.saveSession(
        task: widget.task,
        startedAt: _openedAt,
        endedAt: DateTime.now(),
        durationSeconds: 0,
        completed: result.completed,
        difficulty: result.difficulty,
        note: result.note,
        rhythmPatternId: _pattern.id,
      );
    } on PracticeApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('记录已保存')));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('离开练习？'),
            content: const Text('确定要返回吗？未保存的记录将丢失。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('继续练习'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('返回'),
              ),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.task.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: '图示说明',
              onPressed: () => _showHelp(context),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.task.description, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 20),
              Text('当前节奏', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '扫弦节奏型',
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<StrummingPattern>(
                    key: const Key('rhythm_pattern_dropdown'),
                    value: _pattern,
                    isExpanded: true,
                    items: kStrummingPatterns
                        .map(
                          (p) => DropdownMenuItem<StrummingPattern>(
                            value: p,
                            child: Text('${p.name} · ${p.subtitle}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _pattern = value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '一小节（4/4，八分音符网格）',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              _StrummingGrid(
                key: const Key('strumming_pattern_grid'),
                cells: _pattern.cells,
                beatLabels: _beatLabels,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _pattern.tip,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('rhythm_finish_practice'),
                onPressed: _onFinish,
                icon: const Icon(Icons.check_rounded),
                label: const Text('完成练习'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('图示说明'),
        content: const SingleChildScrollView(
          child: Text(
            '每一格对应一拍里的两个八分位置之一，顺序为「1 & 2 & 3 & 4 &」。\n\n'
            '「下」「上」表示扫弦方向；「休」表示该位置不扫弦，可做空拍或制音准备。\n\n'
            '本页为 4/4 常用型，可与节拍器或歌曲一起练习；本期不含内置节拍器与音频。',
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
}

class _StrummingGrid extends StatelessWidget {
  const _StrummingGrid({
    super.key,
    required this.cells,
    required this.beatLabels,
  });

  final List<StrumCellKind> cells;
  final List<String> beatLabels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: List.generate(8, (i) {
            return Expanded(
              child: Center(
                child: Text(
                  beatLabels[i],
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(8, (i) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _StrumCellChip(kind: cells[i]),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _StrumCellChip extends StatelessWidget {
  const _StrumCellChip({required this.kind});

  final StrumCellKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    late final String label;
    late final Color bg;
    late final Color fg;
    switch (kind) {
      case StrumCellKind.down:
        label = '下';
        bg = scheme.primaryContainer;
        fg = scheme.onPrimaryContainer;
        break;
      case StrumCellKind.up:
        label = '上';
        bg = scheme.secondaryContainer;
        fg = scheme.onSecondaryContainer;
        break;
      case StrumCellKind.rest:
        label = '休';
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        break;
    }
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
