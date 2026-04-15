import '../tuner/note_math.dart';

/// 标准调弦（E A D G B E）六根空弦 MIDI，自左向右 **6 弦→1 弦**。
const kStandardOpenMidiStrings = <int>[40, 45, 50, 55, 59, 64];

/// 展示用弦名（6→1）。
const kStringNoteNames = <String>['E', 'A', 'D', 'G', 'B', 'E'];

/// [stringIndex] 0～5 为 6 弦→1 弦；[fret] 0 为空弦；[capo] 为变调夹品数（0 表示无）。
int midiAtFret({
  required int stringIndex,
  required int fret,
  required int capo,
  required List<int> openMidi,
}) {
  return openMidi[stringIndex] + capo + fret;
}

/// 是否自然音（无升降号的音级类）。
bool isNaturalPitchClass(int midi) {
  final pc = (midi % 12 + 12) % 12;
  const naturals = <int>{0, 2, 4, 5, 7, 9, 11};
  return naturals.contains(pc);
}

/// 格内展示文案：带「仅自然音」时非自然音返回 null。
String? labelForCell({
  required int stringIndex,
  required int fret,
  required int capo,
  required List<int> openMidi,
  required bool naturalOnly,
}) {
  final m = midiAtFret(
    stringIndex: stringIndex,
    fret: fret,
    capo: capo,
    openMidi: openMidi,
  );
  if (naturalOnly && !isNaturalPitchClass(m)) {
    return null;
  }
  return midiToNoteName(m.toDouble());
}
