/// 单个和弦候选（按分数从高到低）。
class LiveChordCandidate {
  const LiveChordCandidate({
    required this.label,
    required this.score,
  });

  final String label;
  final double score;
}

/// 原始帧结果：来自 iOS NNLS‑Chroma 引擎（高频更新）。
class LiveChordFrame {
  const LiveChordFrame({
    required this.best,
    required this.topK,
    required this.confidence,
    required this.status,
    required this.timestampMs,
  });

  final String best;
  final List<LiveChordCandidate> topK;
  final double confidence;
  final String status;
  final int timestampMs;
}

enum LiveChordMode {
  fast,
  stable,
}

/// 页面展示态：主和弦、候选、时间线、监听状态。
class LiveChordUiState {
  const LiveChordUiState({
    required this.isListening,
    required this.mode,
    required this.status,
    required this.stableChord,
    required this.topK,
    required this.confidence,
    required this.timeline,
    required this.error,
  });

  factory LiveChordUiState.initial() {
    return const LiveChordUiState(
      isListening: false,
      mode: LiveChordMode.stable,
      status: '未开始监听',
      stableChord: 'Unknown',
      topK: <LiveChordCandidate>[
        LiveChordCandidate(label: 'Am', score: 0.0),
        LiveChordCandidate(label: 'F', score: 0.0),
        LiveChordCandidate(label: 'G', score: 0.0),
      ],
      confidence: 0,
      timeline: <String>['C', 'G', 'Am', 'F'],
      error: null,
    );
  }

  final bool isListening;
  final LiveChordMode mode;
  final String status;
  final String stableChord;
  final List<LiveChordCandidate> topK;
  final double confidence;
  final List<String> timeline;
  final String? error;

  LiveChordUiState copyWith({
    bool? isListening,
    LiveChordMode? mode,
    String? status,
    String? stableChord,
    List<LiveChordCandidate>? topK,
    double? confidence,
    List<String>? timeline,
    String? error,
    bool clearError = false,
  }) {
    return LiveChordUiState(
      isListening: isListening ?? this.isListening,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      stableChord: stableChord ?? this.stableChord,
      topK: topK ?? this.topK,
      confidence: confidence ?? this.confidence,
      timeline: timeline ?? this.timeline,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
