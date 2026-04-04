/// 练耳用音程（半音数 + 中文名称）。不区分增四/减五，统一为「三全音」。
class IntervalKind {
  const IntervalKind(this.semitones, this.nameZh);

  final int semitones;
  final String nameZh;

  @override
  bool operator ==(Object other) =>
      other is IntervalKind && other.semitones == semitones;

  @override
  int get hashCode => semitones;

  /// MVP 训练池：常见自然音程 + 三全音 + 八度。
  static const List<IntervalKind> trainingPool = [
    IntervalKind(1, '小二度'),
    IntervalKind(2, '大二度'),
    IntervalKind(3, '小三度'),
    IntervalKind(4, '大三度'),
    IntervalKind(5, '纯四度'),
    IntervalKind(6, '三全音'),
    IntervalKind(7, '纯五度'),
    IntervalKind(8, '小六度'),
    IntervalKind(9, '大六度'),
    IntervalKind(10, '小七度'),
    IntervalKind(11, '大七度'),
    IntervalKind(12, '纯八度'),
  ];

  static IntervalKind? fromSemitones(int s) {
    for (final k in trainingPool) {
      if (k.semitones == s) return k;
    }
    return null;
  }
}
