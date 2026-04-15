import 'live_chord_models.dart';

/// 页面侧稳定器：候选高频更新，主和弦延迟确认后再切换。
class LiveChordStateMachine {
  LiveChordStateMachine({
    this.minConfidence = 0.6,
    this.maxTimelineLength = 8,
    this.fastModeStableHits = 1,
    this.stableModeStableHits = 2,
  });

  final double minConfidence;
  final int maxTimelineLength;
  final int fastModeStableHits;
  final int stableModeStableHits;

  String _stableCandidate = 'Unknown';
  int _stableHits = 0;

  LiveChordUiState applyFrame(
    LiveChordUiState current,
    LiveChordFrame frame,
  ) {
    final best = frame.best.trim().isEmpty ? 'Unknown' : frame.best.trim();
    final accepted = frame.confidence >= minConfidence ? best : 'Unknown';
    final requiredStableHits = current.mode == LiveChordMode.fast
        ? fastModeStableHits
        : stableModeStableHits;

    if (accepted == _stableCandidate) {
      _stableHits += 1;
    } else {
      _stableCandidate = accepted;
      _stableHits = 1;
    }

    var nextStableChord = current.stableChord;
    var nextTimeline = current.timeline;
    if (_stableHits >= requiredStableHits && accepted != current.stableChord) {
      nextStableChord = accepted;
      if (accepted != 'Unknown') {
        nextTimeline = _appendTimeline(current.timeline, accepted);
      }
    }

    return current.copyWith(
      status: frame.status,
      stableChord: nextStableChord,
      topK: frame.topK,
      confidence: frame.confidence,
      timeline: nextTimeline,
      clearError: true,
    );
  }

  void reset() {
    _stableCandidate = 'Unknown';
    _stableHits = 0;
  }

  List<String> _appendTimeline(List<String> timeline, String chord) {
    final out = List<String>.from(timeline);
    if (out.isNotEmpty && out.last == chord) return out;
    out.add(chord);
    if (out.length > maxTimelineLength) {
      out.removeRange(0, out.length - maxTimelineLength);
    }
    return out;
  }
}
