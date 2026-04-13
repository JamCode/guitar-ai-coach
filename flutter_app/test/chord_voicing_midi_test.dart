import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/chords/chord_models.dart';
import 'package:guitar_helper/chords/chord_voicing_midi.dart';

void main() {
  test('guitarVoicingMidis 跳过闷音并按 6→1 弦顺序', () {
    const ex = ChordVoicingExplain(
      frets: [-1, 3, 2, 0, 1, 0],
      fingers: [null, null, null, null, null, null],
      baseFret: 1,
      barre: null,
      voicingExplainZh: '',
    );
    final m = guitarVoicingMidis(ex);
    expect(m, [48, 52, 55, 60, 64]);
  });

  test('guitarVoicingMidis 将过高品位钳到采样上限', () {
    const ex = ChordVoicingExplain(
      frets: [0, 0, 0, 0, 0, 20],
      fingers: [null, null, null, null, null, null],
      baseFret: 1,
      barre: null,
      voicingExplainZh: '',
    );
    final m = guitarVoicingMidis(ex);
    expect(m.last, guitarChromaticMaxMidi);
  });
}
