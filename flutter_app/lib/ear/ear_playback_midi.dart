import 'diatonic_roman.dart';
import 'ear_seed_models.dart';

/// 由题目字段推导用于 [EarChordPlayer] 的 MIDI（不依赖种子里的 `audio_ref` 文件）。
abstract final class EarPlaybackMidi {
  static List<int> forSingleChord(EarBankItem q) {
    final r = q.root;
    final t = q.targetQuality;
    if (r == null || t == null) {
      throw StateError('A 题缺少 root/target_quality: ${q.id}');
    }
    return DiatonicRoman.clampMidis(
      DiatonicRoman.singleChordMidis(rootName: r, targetQuality: t),
    );
  }

  static List<List<int>> forProgression(EarBankItem q) {
    final k = q.musicKey;
    final p = q.progressionRoman;
    if (k == null || p == null) {
      throw StateError('B 题缺少 music_key/progression_roman: ${q.id}');
    }
    final raw = DiatonicRoman.progressionTriadsMidi(
      musicKey: k,
      progressionRoman: p,
    );
    return raw.map(DiatonicRoman.clampMidis).toList(growable: false);
  }
}
