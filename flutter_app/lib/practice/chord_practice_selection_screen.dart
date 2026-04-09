import 'dart:async';

import 'package:flutter/material.dart';

import 'chord_progression_library.dart';
import 'practice_local_store.dart';
import 'practice_models.dart';

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
class ChordPracticeSelectionScreen extends StatefulWidget {
  const ChordPracticeSelectionScreen({
    super.key,
    required this.task,
    required this.store,
  });

  final PracticeTask task;
  final PracticeLocalStore store;

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
                          children: chords
                              .map((c) => Chip(
                                    label: Text(
                                      c,
                                      key: Key('preview_chord_$c'),
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_selectedProgression.name} · $_selectedKey 调 · ${_selectedComplexity.label}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ---- 调性选择 ----
                Text('调性', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kMusicKeys.map((k) {
                    final selected = k == _selectedKey;
                    return ChoiceChip(
                      key: Key('key_chip_$k'),
                      label: Text(k),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedKey = k),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

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

                const SizedBox(height: 16),

                // ---- 进行列表 ----
                Text('和弦进行', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...kProgressionStyles.expand((style) {
                  final progs = kChordProgressions
                      .where((p) => p.style == style)
                      .toList();
                  if (progs.isEmpty) return <Widget>[];
                  return [
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Text(
                        kStyleLabels[style] ?? style,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    ...progs.map((prog) {
                      final isSelected =
                          prog.id == _selectedProgression.id;
                      return Card(
                        elevation: isSelected ? 2 : 0,
                        color: isSelected
                            ? theme.colorScheme.secondaryContainer
                            : null,
                        child: ListTile(
                          key: Key('progression_${prog.id}'),
                          title: Text(prog.name),
                          subtitle: Text(prog.romanNumerals),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          onTap: () => setState(
                              () => _selectedProgression = prog),
                        ),
                      );
                    }),
                  ];
                }),
                const SizedBox(height: 80),
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
  final PracticeLocalStore store;
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
    final result = await showDialog<_FinishResult>(
      context: context,
      builder: (_) => _FinishDialog(noteController: _noteController),
    );
    if (result == null || _startedAt == null) return;
    final cfg = widget.config;
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
                    children: cfg.resolvedChords.map((c) {
                      return Text(
                        c,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList(),
                  ),
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

// ---------------------------------------------------------------------------
// 结束弹窗（复用逻辑，独立 StatefulWidget 避免依赖泄漏）
// ---------------------------------------------------------------------------

class _FinishDialog extends StatefulWidget {
  const _FinishDialog({required this.noteController});

  final TextEditingController noteController;

  @override
  State<_FinishDialog> createState() => _FinishDialogState();
}

class _FinishDialogState extends State<_FinishDialog> {
  var _completed = true;
  var _difficulty = 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('本次练习完成'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('完成目标'),
              value: _completed,
              onChanged: (v) => setState(() => _completed = v),
            ),
            Row(
              children: [
                const Text('主观难度'),
                Expanded(
                  child: Slider(
                    key: const Key('chord_difficulty_slider'),
                    value: _difficulty.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$_difficulty',
                    onChanged: (v) =>
                        setState(() => _difficulty = v.round()),
                  ),
                ),
                Text('$_difficulty'),
              ],
            ),
            TextField(
              key: const Key('chord_note_input'),
              controller: widget.noteController,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('chord_save_session'),
          onPressed: () {
            Navigator.of(context).pop(
              _FinishResult(
                completed: _completed,
                difficulty: _difficulty,
                note: widget.noteController.text.trim().isEmpty
                    ? null
                    : widget.noteController.text.trim(),
              ),
            );
          },
          child: const Text('保存记录'),
        ),
      ],
    );
  }
}

class _FinishResult {
  const _FinishResult({
    required this.completed,
    required this.difficulty,
    required this.note,
  });

  final bool completed;
  final int difficulty;
  final String? note;
}

String _formatDuration(int seconds) {
  final minute = (seconds ~/ 60).toString().padLeft(2, '0');
  final second = (seconds % 60).toString().padLeft(2, '0');
  return '$minute:$second';
}
