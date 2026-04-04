import 'dart:async';

import 'package:flutter/material.dart';

import '../ear/interval_ear_screen.dart';
import 'note_math.dart';
import 'tuner_controller.dart';

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  late final TunerController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TunerController();
    _ctrl.addListener(_onTick);
  }

  void _onTick() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_onTick);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = _ctrl.smoothedHz ?? _ctrl.frequencyHz;
    final target = _ctrl.targetHz;
    final cents = hz != null ? centsBetween(hz, target) : 0.0;
    final note = hz != null ? midiToNoteName(frequencyToMidi(hz)) : '--';

    return Scaffold(
      appBar: AppBar(
        title: const Text('调音器'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '音程练耳',
            icon: const Icon(Icons.hearing_rounded),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const IntervalEarScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_ctrl.error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_ctrl.error!),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ctrl.statusMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        note,
                        style: theme.textTheme.displayLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hz != null
                                  ? '${hz.toStringAsFixed(1)} Hz'
                                  : '-- Hz',
                            ),
                            Text(
                              '目标：第 ${6 - _ctrl.selectedStringIndex} 弦 · ${target.toStringAsFixed(2)} Hz',
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              hz != null
                                  ? '${cents >= 0 ? '+' : ''}${cents.toStringAsFixed(0)} cent'
                                  : '',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _MeterBar(cents: cents, active: hz != null),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('选择弦', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < 6; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: _StringChip(
                            label: ['6\nE', '5\nA', '4\nD', '3\nG', '2\nB', '1\ne'][i],
                            selected: _ctrl.selectedStringIndex == i,
                            onTap: () => unawaited(_ctrl.setSelectedString(i)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _ctrl.isListening
                ? () => _ctrl.stop()
                : () => _ctrl.start(),
            icon: Icon(_ctrl.isListening ? Icons.stop : Icons.mic),
            label: Text(_ctrl.isListening ? '停止监听' : '开始监听'),
          ),
        ],
      ),
    );
  }
}

/// 单行六格等分，避免 [Wrap] 在窄屏把最后一枚挤到下一行。
class _StringChip extends StatelessWidget {
  const _StringChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    final bg = selected ? scheme.secondaryContainer : scheme.surfaceContainerHighest;
    final border = selected ? scheme.secondary : scheme.outlineVariant;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
          ),
        ),
      ),
    );
  }
}

/// -50 ~ +50 cent 的简易横向指示（MVP）。
class _MeterBar extends StatelessWidget {
  const _MeterBar({required this.cents, required this.active});

  final double cents;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    // 映射到 0..1，中心 0.5
    const maxC = 50.0;
    final t = (cents + maxC) / (2 * maxC);
    final x = t.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('-50', style: TextStyle(fontSize: 11, color: c.outline)),
            Text('准', style: TextStyle(fontSize: 11, color: c.outline)),
            Text('+50', style: TextStyle(fontSize: 11, color: c.outline)),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: c.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.outlineVariant),
                  ),
                ),
                Positioned(
                  left: w / 2 - 1,
                  top: -4,
                  child: Container(
                    width: 2,
                    height: 20,
                    color: c.outline,
                  ),
                ),
                if (active)
                  Positioned(
                    left: w * x - 7,
                    top: -6,
                    child: Container(
                      width: 14,
                      height: 24,
                      decoration: BoxDecoration(
                        color: c.primary,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: c.surface, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: c.primary.withValues(alpha: 0.35),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
