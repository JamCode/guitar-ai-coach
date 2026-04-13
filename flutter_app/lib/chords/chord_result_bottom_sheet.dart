import 'dart:async';

import 'package:flutter/material.dart';

import '../ear/ear_chord_player.dart';
import 'chord_diagram_widget.dart';
import 'chord_models.dart';
import 'chord_voicing_midi.dart';

/// 从底部弹出展示和弦结果：指法图、文字说明、分解/齐奏试听。
///
/// 依赖 [initGuitarAudio] 已初始化 SoLoud；试听失败时仅在控制台打印。
Future<void> showChordResultBottomSheet({
  required BuildContext context,
  required ChordExplainMultiPayload payload,
  String? disclaimer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      return _ChordResultSheetBody(
        key: const Key('chord_result_sheet'),
        payload: payload,
        disclaimer: disclaimer,
      );
    },
  );
}

class _ChordResultSheetBody extends StatefulWidget {
  const _ChordResultSheetBody({
    super.key,
    required this.payload,
    this.disclaimer,
  });

  final ChordExplainMultiPayload payload;
  final String? disclaimer;

  @override
  State<_ChordResultSheetBody> createState() => _ChordResultSheetBodyState();
}

class _ChordResultSheetBodyState extends State<_ChordResultSheetBody> {
  late final PageController _pageController;
  late final EarChordPlayer _player;
  var _pageIndex = 0;
  var _audioBusy = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _player = EarChordPlayer();
  }

  @override
  void dispose() {
    _pageController.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _playArpeggioFor(int voicingIndex) async {
    final ex = widget.payload.voicings[voicingIndex].explain;
    final midis = guitarVoicingMidis(ex);
    if (midis.isEmpty) return;
    setState(() => _audioBusy = true);
    try {
      await _player.playMidisArpeggio(midis);
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  Future<void> _playTogetherFor(int voicingIndex) async {
    final ex = widget.payload.voicings[voicingIndex].explain;
    final midis = guitarVoicingMidis(ex);
    if (midis.isEmpty) return;
    setState(() => _audioBusy = true);
    try {
      await _player.playMidisSimultaneous(midis);
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    final s = widget.payload.chordSummary;

    return AnimatedPadding(
      duration: Duration.zero,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.symbol.isEmpty ? '和弦' : s.symbol,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (s.notesLetters.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '构成音：${s.notesLetters.join(' · ')}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if (s.notesExplainZh.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      s.notesExplainZh,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.payload.voicings.length,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                itemBuilder: (context, i) {
                  final v = widget.payload.voicings[i];
                  final ex = v.explain;
                  final midis = guitarVoicingMidis(ex);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      Text(
                        v.labelZh,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: ChordDiagramWidget(
                          frets: ex.frets,
                          fingers: ex.fingers,
                          baseFret: ex.baseFret,
                          barre: ex.barre,
                          width: 220,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '6→1 弦：${formatFretsLine(ex.frets)} · 起算品格：${ex.baseFret}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (ex.barre != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '横按：${ex.barre!.fret} 品 '
                          '（弦 ${ex.barre!.fromString}–${ex.barre!.toString_}）',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: Key('chord_result_arpeggio_$i'),
                              onPressed: (_audioBusy || midis.isEmpty)
                                  ? null
                                  : () => unawaited(_playArpeggioFor(i)),
                              icon: const Icon(Icons.graphic_eq_rounded, size: 20),
                              label: const Text('分解试听'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              key: Key('chord_result_full_$i'),
                              onPressed: (_audioBusy || midis.isEmpty)
                                  ? null
                                  : () => unawaited(_playTogetherFor(i)),
                              icon: const Icon(Icons.surround_sound_rounded, size: 20),
                              label: const Text('齐奏试听'),
                            ),
                          ),
                        ],
                      ),
                      if (ex.voicingExplainZh.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          ex.voicingExplainZh,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            if (widget.payload.voicings.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.payload.voicings.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _pageIndex
                                ? scheme.primary
                                : scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (widget.disclaimer != null && widget.disclaimer!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  widget.disclaimer!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
