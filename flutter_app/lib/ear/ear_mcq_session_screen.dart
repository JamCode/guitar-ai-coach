import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'ear_chord_player.dart';
import 'ear_playback_midi.dart';
import 'ear_seed_loader.dart';
import 'ear_seed_models.dart';

/// 练耳 MCQ 会话：模式 A（单和弦性质）或 B（和弦进行），题目来自种子 JSON。
class EarMcqSessionScreen extends StatefulWidget {
  const EarMcqSessionScreen({
    super.key,
    required this.title,
    required this.bank,
    this.totalQuestions = 10,
    this.overrideItems,
  });

  final String title;

  /// `A` 或 `B`，对应种子 `banks`。
  final String bank;

  final int totalQuestions;

  /// 测试注入；非空时不读 Asset。
  final List<EarBankItem>? overrideItems;

  @override
  State<EarMcqSessionScreen> createState() => _EarMcqSessionScreenState();
}

class _EarMcqSessionScreenState extends State<EarMcqSessionScreen> {
  final _rng = Random();
  late final EarChordPlayer _player;

  var _loading = true;
  String? _loadError;
  List<EarBankItem> _session = [];

  int _pageIndex = 0;
  int _correctCount = 0;
  EarBankItem? _question;
  int? _selectedChoiceIndex;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _player = EarChordPlayer();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final override = widget.overrideItems;
      final List<EarBankItem> pool;
      if (override != null) {
        pool = List.of(override);
      } else {
        final doc = await EarSeedLoader.instance.load();
        pool = widget.bank == 'B' ? doc.bankB : doc.bankA;
      }
      if (pool.isEmpty) {
        setState(() {
          _loading = false;
          _loadError = '题库为空（bank ${widget.bank}）';
        });
        return;
      }
      pool.shuffle(_rng);
      final n = min(widget.totalQuestions, pool.length);
      setState(() {
        _session = pool.take(n).toList();
        _loading = false;
        _question = _session.isNotEmpty ? _session.first : null;
      });
    } on Object catch (e) {
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _playCurrent() async {
    final q = _question;
    if (q == null) return;
    try {
      if (q.mode == 'B' || q.questionType == 'progression_recognition') {
        await _player.playChordSequence(EarPlaybackMidi.forProgression(q));
      } else {
        await _player.playChordMidis(EarPlaybackMidi.forSingleChord(q));
      }
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播放失败：$e')),
      );
    }
  }

  void _rollQuestion() {
    setState(() {
      _question = _session[_pageIndex];
      _selectedChoiceIndex = null;
      _revealed = false;
    });
  }

  void _onSelectOption(int index) {
    if (_revealed) return;
    setState(() => _selectedChoiceIndex = index);
  }

  void _submit() {
    final q = _question;
    final idx = _selectedChoiceIndex;
    if (q == null || idx == null || _revealed) return;
    final picked = q.options[idx].key;
    final ok = picked == q.correctOptionKey;
    if (ok) _correctCount++;
    setState(() => _revealed = true);
  }

  void _nextOrFinish() {
    final last = _pageIndex >= _session.length - 1;
    if (last) {
      unawaited(_showSummary());
      return;
    }
    setState(() => _pageIndex++);
    _rollQuestion();
  }

  Future<void> _showSummary() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('本轮完成'),
        content: Text('共 ${_session.length} 题 · 答对 $_correctCount 题'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_loadError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final q = _question;
    if (q == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: Text('无题目')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _ProgressRow(index: _pageIndex, total: _session.length),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.promptZh,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (q.hintZh != null && q.hintZh!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      q.hintZh!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '使用吉他采样合成，与预录音色可能略有差异。',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => unawaited(_playCurrent()),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('播放'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () => unawaited(_playCurrent()),
                        child: const Text('再听一遍'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '四选一',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          _OptionGrid(
            options: q.options,
            selectedIndex: _selectedChoiceIndex,
            revealed: _revealed,
            correctKey: q.correctOptionKey,
            onSelect: _onSelectOption,
          ),
          if (_revealed) ...[
            const SizedBox(height: 16),
            _FeedbackBanner(
              correct: q.options[_selectedChoiceIndex!].key == q.correctOptionKey,
              answerLabel: q.options
                  .firstWhere((o) => o.key == q.correctOptionKey)
                  .label,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _revealed
                ? _nextOrFinish
                : (_selectedChoiceIndex != null ? _submit : null),
            child: Text(_revealed ? _nextLabel() : '提交答案'),
          ),
        ],
      ),
    );
  }

  String _nextLabel() {
    if (_pageIndex >= _session.length - 1) {
      return '查看结果';
    }
    return '下一题';
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '第 ${index + 1} / $total 题',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (index + 1) / total,
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _OptionGrid extends StatelessWidget {
  const _OptionGrid({
    required this.options,
    required this.selectedIndex,
    required this.revealed,
    required this.correctKey,
    required this.onSelect,
  });

  final List<EarMcqOption> options;
  final int? selectedIndex;
  final bool revealed;
  final String correctKey;
  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [
        for (var i = 0; i < options.length; i++)
          _OptionTile(
            label: options[i].label,
            selected: selectedIndex == i,
            revealed: revealed,
            isCorrect: options[i].key == correctKey,
            isWrongPick:
                revealed && selectedIndex == i && options[i].key != correctKey,
            enabled: !revealed,
            onTap: () => onSelect(i),
          ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.revealed,
    required this.isCorrect,
    required this.isWrongPick,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool revealed;
  final bool isCorrect;
  final bool isWrongPick;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var border = scheme.outlineVariant;
    var bg = scheme.surfaceContainerHighest;
    var fg = scheme.onSurface;

    if (revealed && isCorrect) {
      border = scheme.secondary;
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
    } else if (isWrongPick) {
      border = scheme.error;
      bg = scheme.errorContainer.withValues(alpha: 0.55);
      fg = scheme.onErrorContainer;
    } else if (selected && !revealed) {
      border = scheme.primary;
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({
    required this.correct,
    required this.answerLabel,
  });

  final bool correct;
  final String answerLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = correct ? scheme.secondaryContainer : scheme.errorContainer;
    final fg =
        correct ? scheme.onSecondaryContainer : scheme.onErrorContainer;
    final msg =
        correct ? '回答正确：$answerLabel' : '回答错误：正确答案是 $answerLabel';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: correct ? scheme.secondary : scheme.error,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          msg,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
