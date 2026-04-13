import 'dart:async';

import 'package:flutter/material.dart';

import '../chords/chord_quick_reference.dart';
import 'chord_progression_library.dart';
import 'practice_api_repository.dart';
import 'practice_finish_dialog.dart';
import 'practice_models.dart';
import 'practice_session_store.dart';

/// 和弦练习配置：用户在选择页确定后传递给计时页。
class ChordPracticeConfig {
  const ChordPracticeConfig({
    required this.progression,
    required this.key,
    required this.complexity,
    required this.resolvedChords,
  });

  final ChordProgression progression;
  final String key;
  final ChordComplexity complexity;
  final List<String> resolvedChords;
}

/// 和弦进行选择页：选进行 / 调 / 复杂度，预览实际和弦名，进入练习。
///
/// 和弦进行列表在底部弹层中展示并支持搜索，避免主页面过长滚动。
class ChordPracticeSelectionScreen extends StatefulWidget {
  const ChordPracticeSelectionScreen({
    super.key,
    required this.task,
    required this.store,
  });

  final PracticeTask task;
  final PracticeSessionStore store;

  @override
  State<ChordPracticeSelectionScreen> createState() =>
      _ChordPracticeSelectionScreenState();
}

class _ChordPracticeSelectionScreenState
    extends State<ChordPracticeSelectionScreen> {
  ChordProgression _selectedProgression = kChordProgressions.first;
  String _selectedKey = 'C';
  ChordComplexity _selectedComplexity = ChordComplexity.basic;

  List<String> get _resolvedChords =>
      ChordProgressionEngine.resolveChordNames(
        romanNumerals: _selectedProgression.romanNumerals,
        key: _selectedKey,
        complexity: _selectedComplexity,
      );

  void _startPractice() {
    final config = ChordPracticeConfig(
      progression: _selectedProgression,
      key: _selectedKey,
      complexity: _selectedComplexity,
      resolvedChords: _resolvedChords,
    );
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ChordPracticeSessionScreen(
          task: widget.task,
          store: widget.store,
          config: config,
        ),
      ),
    );
  }

  /// 长列表改为底部弹层 + 搜索，主屏一屏内完成调性/复杂度/预览。
  void _openProgressionPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: _ChordProgressionPickerSheet(
            selectedId: _selectedProgression.id,
            onSelected: (p) {
              Navigator.of(ctx).pop();
              setState(() => _selectedProgression = p);
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chords = _resolvedChords;

    return Scaffold(
      appBar: AppBar(title: const Text('和弦切换练习')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // ---- 预览卡 ----
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前选择预览',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (var i = 0; i < chords.length; i++)
                              ActionChip(
                                label: Text(
                                  chords[i],
                                  key: Key('preview_chord_${chords[i]}_$i'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                tooltip: '查看指法',
                                onPressed: () {
                                  showChordQuickReferenceSheet(
                                    context,
                                    chords[i],
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_selectedProgression.name} · $_selectedKey 调 · '
                          '${_selectedComplexity.label} · 点和弦名查看指法',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ---- 调性选择（下拉，节省纵向空间）----
                Text('调性', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('practice_key_dropdown'),
                      isExpanded: true,
                      isDense: true,
                      value: _selectedKey,
                      items: [
                        for (final k in kMusicKeys)
                          DropdownMenuItem<String>(
                            key: Key('key_dropdown_item_$k'),
                            value: k,
                            child: Text(k),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _selectedKey = v);
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ---- 复杂度选择 ----
                Text('复杂度', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<ChordComplexity>(
                  key: const Key('complexity_selector'),
                  segments: ChordComplexity.values
                      .map((c) => ButtonSegment<ChordComplexity>(
                            value: c,
                            label: Text(c.label),
                          ))
                      .toList(),
                  selected: {_selectedComplexity},
                  onSelectionChanged: (s) =>
                      setState(() => _selectedComplexity = s.first),
                ),

                const SizedBox(height: 12),

                // ---- 和弦进行（底部弹层，避免主列表过长）----
                Text('和弦进行', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    key: const Key('progression_picker_tile'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    leading: Icon(
                      Icons.queue_music_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(_selectedProgression.name),
                    subtitle: Text(
                      '${kStyleLabels[_selectedProgression.style] ?? _selectedProgression.style} · '
                      '${_selectedProgression.romanNumerals}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openProgressionPicker,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            key: const Key('start_chord_practice'),
            onPressed: _startPractice,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始练习'),
          ),
        ),
      ),
    );
  }
}

/// 和弦进行列表：按风格分组，支持按名称/级数/风格关键字筛选。
class _ChordProgressionPickerSheet extends StatefulWidget {
  const _ChordProgressionPickerSheet({
    required this.selectedId,
    required this.onSelected,
  });

  final String selectedId;
  final ValueChanged<ChordProgression> onSelected;

  @override
  State<_ChordProgressionPickerSheet> createState() =>
      _ChordProgressionPickerSheetState();
}

class _ChordProgressionPickerSheetState extends State<_ChordProgressionPickerSheet> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChordProgression> _filtered() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return kChordProgressions;
    return kChordProgressions.where((p) {
      final styleZh = kStyleLabels[p.style]?.toLowerCase() ?? '';
      return p.name.toLowerCase().contains(q) ||
          p.romanNumerals.toLowerCase().contains(q) ||
          p.style.toLowerCase().contains(q) ||
          styleZh.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.82;
    final filtered = _filtered();

    return SizedBox(
      height: maxH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              '选择和弦进行',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜索名称、级数或风格',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配的进行中',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      ...kProgressionStyles.expand((style) {
                        final progs =
                            filtered.where((p) => p.style == style).toList();
                        if (progs.isEmpty) return <Widget>[];
                        return [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                            child: Text(
                              kStyleLabels[style] ?? style,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          ...progs.map((prog) {
                            final isSelected = prog.id == widget.selectedId;
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              elevation: isSelected ? 2 : 0,
                              color: isSelected
                                  ? theme.colorScheme.secondaryContainer
                                  : null,
                              child: ListTile(
                                key: Key('progression_${prog.id}'),
                                dense: true,
                                title: Text(prog.name),
                                subtitle: Text(prog.romanNumerals),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_circle,
                                        color: theme.colorScheme.primary,
                                      )
                                    : null,
                                onTap: () => widget.onSelected(prog),
                              ),
                            );
                          }),
                        ];
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 和弦练习计时页（自带计时器，顶部显示和弦序列）
// ---------------------------------------------------------------------------

class _ChordPracticeSessionScreen extends StatefulWidget {
  const _ChordPracticeSessionScreen({
    required this.task,
    required this.store,
    required this.config,
  });

  final PracticeTask task;
  final PracticeSessionStore store;
  final ChordPracticeConfig config;

  @override
  State<_ChordPracticeSessionScreen> createState() =>
      _ChordPracticeSessionScreenState();
}

class _ChordPracticeSessionScreenState
    extends State<_ChordPracticeSessionScreen> {
  final _noteController = TextEditingController();
  Timer? _ticker;
  DateTime? _startedAt;
  var _elapsed = Duration.zero;
  var _running = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  void _start() {
    if (_running) return;
    _startedAt ??= DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
    setState(() => _running = true);
  }

  void _pause() {
    _ticker?.cancel();
    setState(() => _running = false);
  }

  Future<void> _finish() async {
    if (_elapsed == Duration.zero) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先开始练习再结束哦')));
      return;
    }
    _pause();
    final result = await showPracticeFinishDialog(
      context: context,
      noteController: _noteController,
    );
    if (result == null || _startedAt == null) return;
    final cfg = widget.config;
    try {
      await widget.store.saveSession(
        task: widget.task,
        startedAt: _startedAt!,
        endedAt: DateTime.now(),
        durationSeconds: _elapsed.inSeconds,
        completed: result.completed,
        difficulty: result.difficulty,
        note: result.note,
        progressionId: cfg.progression.id,
        musicKey: cfg.key,
        complexity: cfg.complexity.name,
      );
    } on PracticeApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('记录已保存')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cfg = widget.config;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('离开练习？'),
            content: const Text('当前练习尚未保存，确定要返回吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('继续练习'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('放弃返回'),
              ),
            ],
          ),
        );
        if (leave == true && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${cfg.progression.name} · ${cfg.key} 调',
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 和弦序列展示
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var i = 0; i < cfg.resolvedChords.length; i++)
                        Tooltip(
                          message: '查看指法',
                          child: InkWell(
                            onTap: () => showChordQuickReferenceSheet(
                              context,
                              cfg.resolvedChords[i],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Text(
                                cfg.resolvedChords[i],
                                key: Key(
                                  'session_chord_${cfg.resolvedChords[i]}_$i',
                                ),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                  decorationColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '点击和弦名查看指法',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  cfg.complexity.fullLabel,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const Spacer(),
              // 计时器
              Text(
                _formatDuration(_elapsed.inSeconds),
                key: const Key('chord_practice_timer'),
                textAlign: TextAlign.center,
                style: theme.textTheme.displayMedium,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_running)
                    FilledButton(
                      key: const Key('chord_timer_start'),
                      onPressed: _start,
                      child: const Text('开始'),
                    )
                  else
                    OutlinedButton(
                      key: const Key('chord_timer_pause'),
                      onPressed: _pause,
                      child: const Text('暂停'),
                    ),
                  const SizedBox(width: 16),
                  FilledButton.tonal(
                    key: const Key('chord_timer_finish'),
                    onPressed: _finish,
                    child: const Text('结束'),
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final minute = (seconds ~/ 60).toString().padLeft(2, '0');
  final second = (seconds % 60).toString().padLeft(2, '0');
  return '$minute:$second';
}
