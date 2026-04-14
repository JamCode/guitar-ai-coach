/// 视唱会话配置。
class SightSingingConfig {
  const SightSingingConfig({
    required this.minNote,
    required this.maxNote,
    required this.questionCount,
    required this.includeAccidental,
  });

  final String minNote;
  final String maxNote;
  final int questionCount;
  final bool includeAccidental;
}

/// 视唱单题。
class SightSingingQuestion {
  const SightSingingQuestion({
    required this.id,
    required this.index,
    required this.totalQuestions,
    required this.targetNotes,
  });

  final String id;
  final int index;
  final int totalQuestions;
  final List<String> targetNotes;
}

/// 视唱会话结果汇总。
class SightSingingResult {
  const SightSingingResult({
    required this.answered,
    required this.correct,
    required this.total,
    required this.accuracy,
  });

  final int answered;
  final int correct;
  final int total;
  final double accuracy;
}

/// 视唱会话启动响应。
class SightSingingSessionStart {
  const SightSingingSessionStart({
    required this.sessionId,
    required this.config,
    required this.question,
  });

  final String sessionId;
  final SightSingingConfig config;
  final SightSingingQuestion? question;
}
