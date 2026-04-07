/// 将 MIDI 映射到 `assets/audio/guitar_chromatic/` 下文件名（与 [IntervalTonePlayer] 一致）。
String guitarChromaticAssetPath(int midi) {
  const noteNames = [
    'C', 'Cs', 'D', 'Ds', 'E', 'F', 'Fs', 'G', 'Gs', 'A', 'As', 'B',
  ];
  final pitchClass = midi % 12;
  final octave = midi ~/ 12 - 1;
  return 'assets/audio/guitar_chromatic/${noteNames[pitchClass]}$octave.mp3';
}
