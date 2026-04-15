import 'dart:async';

import 'package:flutter/material.dart';

import '../tuner/note_math.dart';
import '../tuner/tuner_controller.dart';
import 'sight_singing_models.dart';
import 'sight_singing_repository.dart';
import 'sight_singing_score.dart';

/// 视唱会话页：显示目标音，采样用户音高并判分。
class SightSingingSessionScreen extends StatefulWidget {
  const SightSingingSessionScreen({
    super.key,
    required this.repository,
    required this.pitchRange,
    required this.includeAccidental,
    required this.questionCount,
    SightSingingPitchTracker? pitchTracker,
  }) : pitchTracker = pitchTracker ?? const DefaultSightSingingPitchTracker();

  final SightSingingRepository repository;
  final SightSingingPitchTracker pitchTracker;
  final String pitchRange;
  final bool includeAccidental;
  final int questionCount;

  @override
  State<SightSingingSessionScreen> createState() =>
      _SightSingingSessionScreenState();
}

class _SightSingingSessionScreenState extends State<SightSingingSessionScreen> {
  String? _sessionId;
  SightSingingQuestion? _question;
  String? _error;
  bool _loading = true;
  bool _evaluating = false;
  double? _currentHz;
  SightSingingScore? _lastScore;
  Timer? _timer;
  final _samples = <double>[];

  static const _sampleStepMs = 120;
  static const _warmupMs = 800;
  static const _evalMs = 2000;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(widget.pitchTracker.stop());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await widget.pitchTracker.start();
      final start = await widget.repository.startSession(
        pitchRange: widget.pitchRange,
        includeAccidental: widget.includeAccidental,
        questionCount: widget.questionCount,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = start.sessionId;
        _question = start.question;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _evaluate() async {
    final question = _question;
    final sessionId = _sessionId;
    if (question == null || sessionId == null || _evaluating) return;
    setState(() {
      _evaluating = true;
      _lastScore = null;
      _samples.clear();
    });
    final target = question.targetNotes.isNotEmpty
        ? question.targetNotes.first
        : 'C4';
    final targetMidi = _noteNameToMidi(target);

    var elapsed = 0;
    _timer?.cancel();
    final c = Completer<void>();
    _timer = Timer.periodic(const Duration(milliseconds: _sampleStepMs), (
      timer,
    ) {
      elapsed += _sampleStepMs;
      final hz = widget.pitchTracker.currentHz;
      _currentHz = hz;
      if (elapsed > _warmupMs && hz != null) {
        final midi = frequencyToMidi(hz);
        final cents = ((midi - targetMidi) * 100).abs();
        _samples.add(cents);
      }
      if (elapsed >= _warmupMs + _evalMs) {
        timer.cancel();
        c.complete();
      }
      if (mounted) setState(() {});
    });
    await c.future;
    final score = computeSightSingingScore(
      absCentsSamples: List.of(_samples),
      sampleStepMs: _sampleStepMs,
    );
    final detected = _currentHz == null
        ? <String>[]
        : [midiToNoteName(frequencyToMidi(_currentHz!))];
    await widget.repository.submitAnswer(
      sessionId: sessionId,
      questionId: question.id,
      answers: detected,
      avgCentsAbs: score.avgCentsAbs,
      stableHitMs: score.stableHitMs,
      durationMs: _evalMs,
    );
    if (!mounted) return;
    setState(() {
      _evaluating = false;
      _lastScore = score;
    });
  }

  Future<void> _nextOrFinish() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final next = await widget.repository.nextQuestion(sessionId);
    if (!mounted) return;
    if (next == null) {
      final result = await widget.repository.fetchResult(sessionId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('本轮完成'),
          content: Text(
            '共 ${result.total} 题，答对 ${result.correct} 题，准确率 ${(result.accuracy * 100).toStringAsFixed(0)}%',
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
      return;
    }
    setState(() {
      _question = next;
      _lastScore = null;
      _samples.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('视唱训练')),
        body: Center(child: Text(_error!)),
      );
    }
    final q = _question;
    if (q == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('视唱训练')),
        body: const Center(child: Text('题目为空')),
      );
    }
    final target = q.targetNotes.isNotEmpty ? q.targetNotes.first : '--';
    final currentNote = _currentHz == null
        ? '--'
        : midiToNoteName(frequencyToMidi(_currentHz!));
    return Scaffold(
      appBar: AppBar(title: const Text('视唱训练')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('第 ${q.index} / ${q.totalQuestions} 题'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('目标音', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Text(
                    target,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('当前检测：$currentNote'),
                  if (_evaluating) const SizedBox(height: 8),
                  if (_evaluating) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _evaluating ? null : _evaluate,
            icon: const Icon(Icons.mic),
            label: Text(_evaluating ? '判定中…' : '开始判定（2秒）'),
          ),
          if (_lastScore != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  '单题得分 ${_lastScore!.score.toStringAsFixed(1)} / 10\n'
                  '平均偏差 ${_lastScore!.avgCentsAbs.toStringAsFixed(1)} cent\n'
                  '稳定命中 ${_lastScore!.stableHitMs} ms',
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _nextOrFinish,
              child: Text(q.index >= q.totalQuestions ? '查看结果' : '下一题'),
            ),
          ],
        ],
      ),
    );
  }
}

double _noteNameToMidi(String note) {
  final n = note.trim().toUpperCase();
  final m = RegExp(r'^([A-G])(#?)(\d)?$').firstMatch(n);
  if (m == null) return 60;
  final name = '${m.group(1)}${m.group(2) ?? ''}';
  final octave = int.tryParse(m.group(3) ?? '') ?? 4;
  const names = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];
  final idx = names.indexOf(name);
  final fixedIdx = idx >= 0 ? idx : 0;
  return ((octave + 1) * 12 + fixedIdx).toDouble();
}

/// 视唱采样器：抽象出音高来源，便于测试注入。
abstract class SightSingingPitchTracker {
  double? get currentHz;
  Future<void> start();
  Future<void> stop();
}

class DefaultSightSingingPitchTracker implements SightSingingPitchTracker {
  const DefaultSightSingingPitchTracker();

  @override
  double? get currentHz => _impl.smoothedHz ?? _impl.frequencyHz;

  static final TunerController _impl = TunerController();

  @override
  Future<void> start() => _impl.start();

  @override
  Future<void> stop() => _impl.stop();
}
