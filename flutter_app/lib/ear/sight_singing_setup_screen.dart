import 'package:flutter/material.dart';

import 'sight_singing_models.dart';
import 'sight_singing_repository.dart';
import 'sight_singing_session_screen.dart';

typedef SightSingingPitchTrackerBuilder = SightSingingPitchTracker Function();

/// 视唱设置页：选择音域与题量后开始训练。
class SightSingingSetupScreen extends StatefulWidget {
  const SightSingingSetupScreen({
    super.key,
    SightSingingRepository? repository,
    SightSingingPitchTrackerBuilder? pitchTrackerBuilder,
  }) : repository = repository ?? const _DefaultSightSingingRepository(),
       pitchTrackerBuilder = pitchTrackerBuilder ?? _defaultPitchTrackerBuilder;

  final SightSingingRepository repository;
  final SightSingingPitchTrackerBuilder pitchTrackerBuilder;

  @override
  State<SightSingingSetupScreen> createState() =>
      _SightSingingSetupScreenState();
}

class _SightSingingSetupScreenState extends State<SightSingingSetupScreen> {
  String _pitchRange = 'mid';
  bool _includeAccidental = false;
  int _questionCount = 10;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('视唱训练')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '音域选择',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'low', label: Text('低音区 C3-B3')),
                      ButtonSegment(value: 'mid', label: Text('中音区 C4-B4')),
                      ButtonSegment(value: 'wide', label: Text('宽范围 C3-B4')),
                    ],
                    selected: {_pitchRange},
                    onSelectionChanged: (set) {
                      setState(() => _pitchRange = set.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _includeAccidental,
                    onChanged: (v) => setState(() => _includeAccidental = v),
                    title: const Text('包含升降号'),
                    subtitle: const Text('关闭后仅出 C D E F G A B 自然音'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '题量：$_questionCount 题',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Slider(
                    value: _questionCount.toDouble(),
                    min: 5,
                    max: 20,
                    divisions: 3,
                    label: '$_questionCount',
                    onChanged: (v) =>
                        setState(() => _questionCount = v.round()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => SightSingingSessionScreen(
                    repository: widget.repository,
                    pitchRange: _pitchRange,
                    includeAccidental: _includeAccidental,
                    questionCount: _questionCount,
                    pitchTracker: widget.pitchTrackerBuilder(),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.music_note),
            label: const Text('开始训练'),
          ),
        ],
      ),
    );
  }
}

SightSingingPitchTracker _defaultPitchTrackerBuilder() =>
    const DefaultSightSingingPitchTracker();

class _DefaultSightSingingRepository implements SightSingingRepository {
  const _DefaultSightSingingRepository();

  @override
  Future<SightSingingResult> fetchResult(String sessionId) {
    return HttpSightSingingRepository().fetchResult(sessionId);
  }

  @override
  Future<SightSingingQuestion?> nextQuestion(String sessionId) {
    return HttpSightSingingRepository().nextQuestion(sessionId);
  }

  @override
  Future<SightSingingSessionStart> startSession({
    required String pitchRange,
    required bool includeAccidental,
    required int questionCount,
  }) {
    return HttpSightSingingRepository().startSession(
      pitchRange: pitchRange,
      includeAccidental: includeAccidental,
      questionCount: questionCount,
    );
  }

  @override
  Future<void> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> answers,
    required double avgCentsAbs,
    required int stableHitMs,
    required int durationMs,
  }) {
    return HttpSightSingingRepository().submitAnswer(
      sessionId: sessionId,
      questionId: questionId,
      answers: answers,
      avgCentsAbs: avgCentsAbs,
      stableHitMs: stableHitMs,
      durationMs: durationMs,
    );
  }
}
