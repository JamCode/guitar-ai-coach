import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'interval_kind.dart';
import 'interval_question_gen.dart';
import 'interval_tone_player.dart';

/// 音程识别练耳（对齐 HTML 原型：两音 · 四选一 · 播放/重听 · 选题后提交 · 即时反馈）。
class IntervalEarScreen extends StatefulWidget {
  const IntervalEarScreen({super.key, this.totalQuestions = 5});

  final int totalQuestions;

  @override
  State<IntervalEarScreen> createState() => _IntervalEarScreenState();
}

class _IntervalEarScreenState extends State<IntervalEarScreen> {
  late final Random _rng;
  late final IntervalTonePlayer _player;

  int _pageIndex = 0;
  int _correctCount = 0;

  IntervalQuestion? _question;
  int? _selectedChoiceIndex;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _rng = Random();
    _player = IntervalTonePlayer();
    _rollQuestion();
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  void _rollQuestion() {
    setState(() {
      _question = IntervalQuestionGen.next(_rng);
      _selectedChoiceIndex = null;
      _revealed = false;
    });
  }

  Future<void> _playPair() async {
    final q = _question;
    if (q == null) return;
    await _player.playAscendingPair(q.lowMidi, q.highMidi);
  }

  void _onSelectOption(int index) {
    if (_revealed) return;
    setState(() => _selectedChoiceIndex = index);
  }

  void _submit() {
    final q = _question;
    final idx = _selectedChoiceIndex;
    if (q == null || idx == null || _revealed) return;

    final ok = q.choices[idx] == q.answer;
    if (ok) _correctCount++;

    setState(() => _revealed = true);
  }

  void _nextOrFinish() {
    final last = _pageIndex >= widget.totalQuestions - 1;
    if (last) {
      _showSummary();
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
        content: Text(
          '音程 ${widget.totalQuestions} 题 · 答对 $_correctCount 题',
        ),
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
    final scheme = theme.colorScheme;
    final q = _question;

    return Scaffold(
      appBar: AppBar(
        title: const Text('音程识别'),
      ),
      body: q == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _ProgressRow(
                  index: _pageIndex,
                  total: widget.totalQuestions,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '听两个音，选择它们之间的音程。',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '先播较低音，再播较高音；可多次点击「再听一遍」。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => unawaited(_playPair()),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('播放'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: () => unawaited(_playPair()),
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
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                _OptionGrid(
                  choices: q.choices,
                  selectedIndex: _selectedChoiceIndex,
                  revealed: _revealed,
                  answer: q.answer,
                  onSelect: _onSelectOption,
                ),
                if (_revealed) ...[
                  const SizedBox(height: 16),
                  _FeedbackBanner(
                    correct: q.choices[_selectedChoiceIndex!] == q.answer,
                    answerName: q.answer.nameZh,
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
    if (_pageIndex >= widget.totalQuestions - 1) {
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
        Row(
          children: [
            Text(
              '音程 · 第 ${index + 1} / $total 题',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
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
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            total,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= index
                      ? scheme.primary.withValues(alpha: 0.9)
                      : scheme.outlineVariant,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionGrid extends StatelessWidget {
  const _OptionGrid({
    required this.choices,
    required this.selectedIndex,
    required this.revealed,
    required this.answer,
    required this.onSelect,
  });

  final List<IntervalKind> choices;
  final int? selectedIndex;
  final bool revealed;
  final IntervalKind answer;
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
        for (var i = 0; i < choices.length; i++)
          _OptionTile(
            label: choices[i].nameZh,
            selected: selectedIndex == i,
            revealed: revealed,
            isCorrect: choices[i] == answer,
            isWrongPick: revealed &&
                selectedIndex == i &&
                choices[i] != answer,
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

    Color border = scheme.outlineVariant;
    Color bg = scheme.surfaceContainerHighest;
    Color fg = scheme.onSurface;

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
    required this.answerName,
  });

  final bool correct;
  final String answerName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = correct ? scheme.secondaryContainer : scheme.errorContainer;
    final fg =
        correct ? scheme.onSecondaryContainer : scheme.onErrorContainer;
    final msg = correct
        ? '回答正确：$answerName。'
        : '回答错误：正确答案是 $answerName。';

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
