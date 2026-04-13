import 'chord_models.dart';

/// 标准调弦下各弦空弦 MIDI（6 弦→1 弦，E2–E4）。
const guitarOpenStringMidis = <int>[40, 45, 50, 55, 59, 64];

/// `assets/audio/guitar_chromatic/` 采样覆盖范围（与工程内 mp3 一致）。
const guitarChromaticMinMidi = 38;
const guitarChromaticMaxMidi = 74;

/// 将一条按法（6→1 弦，`-1` 闷音、`0` 空弦、`>0` 品位）转为可采样的 MIDI 列表（低音弦→高音弦，跳过闷音）。
///
/// 超出采样范围的音高会被钳制到可用区间，避免加载失败。
List<int> guitarVoicingMidis(ChordVoicingExplain voicing) {
  final frets = voicing.frets;
  if (frets.length != 6) return const [];
  final out = <int>[];
  for (var i = 0; i < 6; i++) {
    final f = frets[i];
    if (f < 0) continue;
    final m = guitarOpenStringMidis[i] + f;
    out.add(m.clamp(guitarChromaticMinMidi, guitarChromaticMaxMidi));
  }
  return out;
}
