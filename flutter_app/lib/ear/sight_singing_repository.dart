import 'dart:math';
import 'package:uuid/uuid.dart';

import 'sight_singing_models.dart';

/// 视唱会话数据源。
abstract class SightSingingRepository {
  Future<SightSingingSessionStart> startSession({
    required String pitchRange,
    required bool includeAccidental,
    required int questionCount,
  });

  Future<void> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> answers,
    required double avgCentsAbs,
    required int stableHitMs,
    required int durationMs,
  });

  Future<SightSingingQuestion?> nextQuestion(String sessionId);
  Future<SightSingingResult> fetchResult(String sessionId);
}

/// 本地离线版视唱仓库：在内存中维护单次训练会话与结果。
class LocalSightSingingRepository implements SightSingingRepository {
  LocalSightSingingRepository({Uuid? uuid, Random? random})
      : _uuid = uuid ?? const Uuid(),
        _random = random ?? Random();

  final Uuid _uuid;
  final Random _random;
  final Map<String, _LocalSession> _sessions = <String, _LocalSession>{};

  @override
  Future<SightSingingSessionStart> startSession({
    required String pitchRange,
    required bool includeAccidental,
    required int questionCount,
  }) async {
    final range = _noteRangeFor(pitchRange);
    final config = SightSingingConfig(
      minNote: range.minNote,
      maxNote: range.maxNote,
      questionCount: questionCount,
      includeAccidental: includeAccidental,
    );
    final sessionId = _uuid.v4();
    final notes = _buildQuestionNotes(
      config: config,
      includeAccidental: includeAccidental,
      questionCount: questionCount,
    );
    final session = _LocalSession(config: config, questionNotes: notes);
    _sessions[sessionId] = session;
    return SightSingingSessionStart(
      sessionId: sessionId,
      config: config,
      question: _questionFor(session, 0),
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
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw SightSingingApiException('训练会话不存在，请重新开始');
    }
    if (questionId != 'q-${session.currentIndex + 1}') {
      throw SightSingingApiException('题目状态已变化，请重新开始本题');
    }
    final isCorrect = avgCentsAbs <= 30 && stableHitMs >= 700;
    session.answered += 1;
    if (isCorrect) {
      session.correct += 1;
    }
  }

  @override
  Future<SightSingingQuestion?> nextQuestion(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw SightSingingApiException('训练会话不存在，请重新开始');
    }
    session.currentIndex += 1;
    if (session.currentIndex >= session.questionNotes.length) {
      return null;
    }
    return _questionFor(session, session.currentIndex);
  }

  @override
  Future<SightSingingResult> fetchResult(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session == null) {
      throw SightSingingApiException('训练会话不存在，请重新开始');
    }
    final total = session.questionNotes.length;
    final answered = session.answered.clamp(0, total);
    final correct = session.correct.clamp(0, answered);
    final accuracy = answered == 0 ? 0.0 : correct / answered;
    return SightSingingResult(
      answered: answered,
      correct: correct,
      total: total,
      accuracy: accuracy,
    );
  }

  SightSingingQuestion _questionFor(_LocalSession session, int index) {
    return SightSingingQuestion(
      id: 'q-${index + 1}',
      index: index + 1,
      totalQuestions: session.questionNotes.length,
      targetNotes: <String>[session.questionNotes[index]],
    );
  }

  List<String> _buildQuestionNotes({
    required SightSingingConfig config,
    required bool includeAccidental,
    required int questionCount,
  }) {
    final candidates = _candidateNotes(
      minNote: config.minNote,
      maxNote: config.maxNote,
      includeAccidental: includeAccidental,
    );
    if (candidates.isEmpty) {
      return List<String>.filled(questionCount, 'C4');
    }
    return List<String>.generate(
      questionCount,
      (_) => candidates[_random.nextInt(candidates.length)],
    );
  }

  List<String> _candidateNotes({
    required String minNote,
    required String maxNote,
    required bool includeAccidental,
  }) {
    final min = _noteNameToMidi(minNote);
    final max = _noteNameToMidi(maxNote);
    final start = min <= max ? min : max;
    final end = min <= max ? max : min;
    final out = <String>[];
    for (var midi = start; midi <= end; midi++) {
      final note = _midiToNoteName(midi);
      if (!includeAccidental && note.contains('#')) {
        continue;
      }
      out.add(note);
    }
    return out;
  }

  _LocalRange _noteRangeFor(String range) {
    switch (range) {
      case 'low':
        return const _LocalRange(minNote: 'C3', maxNote: 'B3');
      case 'wide':
        return const _LocalRange(minNote: 'C3', maxNote: 'B4');
      case 'mid':
      default:
        return const _LocalRange(minNote: 'C4', maxNote: 'B4');
    }
  }
}

class SightSingingApiException implements Exception {
  SightSingingApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _LocalSession {
  _LocalSession({required this.config, required this.questionNotes});

  final SightSingingConfig config;
  final List<String> questionNotes;
  int currentIndex = 0;
  int answered = 0;
  int correct = 0;
}

class _LocalRange {
  const _LocalRange({required this.minNote, required this.maxNote});

  final String minNote;
  final String maxNote;
}

int _noteNameToMidi(String note) {
  final n = note.trim().toUpperCase();
  final m = RegExp(r'^([A-G])(#?)(\d)$').firstMatch(n);
  if (m == null) return 60;
  final name = '${m.group(1)}${m.group(2) ?? ''}';
  final octave = int.tryParse(m.group(3) ?? '4') ?? 4;
  const names = <String>[
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
  return (octave + 1) * 12 + (idx < 0 ? 0 : idx);
}

String _midiToNoteName(int midi) {
  const names = <String>[
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
  final note = names[midi % 12];
  final octave = midi ~/ 12 - 1;
  return '$note$octave';
}
