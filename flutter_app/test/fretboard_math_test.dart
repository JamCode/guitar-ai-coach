import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/tools/fretboard_math.dart';

void main() {
  test('标准调弦空弦 MIDI 与品上音高', () {
    const open = kStandardOpenMidiStrings;
    expect(open, <int>[40, 45, 50, 55, 59, 64]);
    expect(
      midiAtFret(
        stringIndex: 0,
        fret: 0,
        capo: 0,
        openMidi: open,
      ),
      40,
    );
    expect(
      midiAtFret(
        stringIndex: 0,
        fret: 5,
        capo: 0,
        openMidi: open,
      ),
      45,
    );
  });

  test('变调夹升高半音数', () {
    const open = kStandardOpenMidiStrings;
    expect(
      midiAtFret(
        stringIndex: 5,
        fret: 0,
        capo: 2,
        openMidi: open,
      ),
      66,
    );
  });

  test('仅自然音时过滤变音', () {
    const open = kStandardOpenMidiStrings;
    expect(
      labelForCell(
        stringIndex: 0,
        fret: 2,
        capo: 0,
        openMidi: open,
        naturalOnly: true,
      ),
      isNull,
    );
    expect(
      labelForCell(
        stringIndex: 0,
        fret: 2,
        capo: 0,
        openMidi: open,
        naturalOnly: false,
      ),
      'F#',
    );
  });
}
