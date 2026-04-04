import 'dart:math' as math;

const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// A4 = 440Hz 下的 MIDI 音符频率。
double midiToHz(double midi) =>
    (440 * math.pow(2, (midi - 69) / 12)).toDouble();

/// A4 = 440Hz 下的 MIDI 音高（可带小数）。
double frequencyToMidi(double hz) {
  if (hz <= 0) return 0;
  return 69 + 12 * math.log(hz / 440) / math.ln2;
}

String midiToNoteName(double midi) {
  final pitchClass = (midi.round() % 12 + 12) % 12;
  return _noteNames[pitchClass];
}

/// 相对 [targetHz] 的音分偏差。
double centsBetween(double hz, double targetHz) {
  if (hz <= 0 || targetHz <= 0) return 0;
  return 1200 * math.log(hz / targetHz) / math.ln2;
}

/// 标准调弦空弦频率（Hz），顺序 6..1 弦。
const guitarOpenStringsHz = <double>[
  82.40688926529948, // E2
  110.0, // A2
  146.8323839587038, // D3
  195.99771799087463, // G3
  246.94165062806206, // B3
  329.6275569128699, // E4
];
