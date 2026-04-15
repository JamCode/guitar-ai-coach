import 'package:flutter/material.dart';

import 'live_chord_controller.dart';
import 'live_chord_models.dart';

/// 实时和弦识别页：展示主和弦、候选、置信度与时间线。
class LiveChordScreen extends StatefulWidget {
  const LiveChordScreen({
    super.key,
    this.controller,
  });

  /// 测试可注入控制器；生产默认自建。
  final LiveChordController? controller;

  @override
  State<LiveChordScreen> createState() => _LiveChordScreenState();
}

class _LiveChordScreenState extends State<LiveChordScreen> {
  late final LiveChordController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? LiveChordController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _controller.state;
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('实时和弦建议（Beta）'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusCard(
                  status: s.status,
                  isListening: s.isListening,
                  confidence: s.confidence,
                ),
                const SizedBox(height: 12),
                _MainChordCard(state: s),
                const SizedBox(height: 12),
                _TimelineCard(timeline: s.timeline, stableChord: s.stableChord),
                if (s.error != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: c.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(s.error!),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _BottomControls(
            state: s,
            onToggleListening: () async {
              if (s.isListening) {
                await _controller.stop();
              } else {
                await _controller.start();
              }
            },
            onChangeMode: (mode) async => _controller.setMode(mode),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.isListening,
    required this.confidence,
  });

  final String status;
  final bool isListening;
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isListening ? c.secondary : c.outline,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Confidence ${(confidence * 100).round()}%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: confidence.clamp(0.0, 1.0),
                backgroundColor: c.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MainChordCard extends StatelessWidget {
  const _MainChordCard({required this.state});

  final LiveChordUiState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                state.stableChord,
                key: ValueKey<String>(state.stableChord),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              minHeight: 2,
              value: state.isListening ? null : 0,
              backgroundColor: Colors.transparent,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: state.topK.take(3).map((cand) {
                final isMain = cand.label == state.stableChord;
                return Chip(
                  label: Text('${cand.label}  ${cand.score.toStringAsFixed(2)}'),
                  backgroundColor: isMain
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  side: BorderSide(
                    color: isMain
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.timeline,
    required this.stableChord,
  });

  final List<String> timeline;
  final String stableChord;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '最近和弦进行',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: timeline.map((chord) {
                  final isCurrent = chord == stableChord;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: Border.all(
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        chord,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.state,
    required this.onToggleListening,
    required this.onChangeMode,
  });

  final LiveChordUiState state;
  final Future<void> Function() onToggleListening;
  final Future<void> Function(LiveChordMode mode) onChangeMode;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: onToggleListening,
              child: Text(state.isListening ? '暂停' : '开始'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onChangeMode(LiveChordMode.fast),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: state.mode == LiveChordMode.fast
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                    ),
                    child: const Text('快速识别'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onChangeMode(LiveChordMode.stable),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: state.mode == LiveChordMode.stable
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                    ),
                    child: const Text('稳定识别'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
