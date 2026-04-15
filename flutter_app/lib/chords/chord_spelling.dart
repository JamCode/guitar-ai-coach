/// 从根音名与性质后缀（与下拉 `qualId` 一致）推算构成音名（无 slash 低音叠加）。
List<String> spellTriadOrSeventhLetters({
  required String rootName,
  required String qualId,
}) {
  final rootPc = _rootNameToPc(rootName);
  if (rootPc == null) return [];
  final intervals = _intervalsForQual(qualId);
  return intervals.map((i) => _pcToLetterSharp((rootPc + i) % 12)).toList();
}

/// slash 低音音名（仅音名，不含八度）。
String? slashBassLetter(String bassId) {
  if (bassId.isEmpty || !bassId.startsWith('/')) return null;
  final note = bassId.substring(1);
  final pc = _rootNameToPc(note);
  if (pc == null) return null;
  return _pcToLetterSharp(pc);
}

int? _rootNameToPc(String name) {
  switch (name.trim()) {
    case 'C':
      return 0;
    case 'Db':
    case 'C#':
      return 1;
    case 'D':
      return 2;
    case 'Eb':
    case 'D#':
      return 3;
    case 'E':
      return 4;
    case 'F':
      return 5;
    case 'Gb':
    case 'F#':
      return 6;
    case 'G':
      return 7;
    case 'Ab':
    case 'G#':
      return 8;
    case 'A':
      return 9;
    case 'Bb':
    case 'A#':
      return 10;
    case 'B':
      return 11;
    default:
      return null;
  }
}

String _pcToLetterSharp(int pc) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  return names[pc % 12];
}

List<int> _intervalsForQual(String qualId) {
  switch (qualId) {
    case '':
      return [0, 4, 7];
    case 'm':
      return [0, 3, 7];
    case '7':
      return [0, 4, 7, 10];
    case 'maj7':
      return [0, 4, 7, 11];
    case 'm7':
      return [0, 3, 7, 10];
    case 'm7b5':
      return [0, 3, 6, 10];
    case 'sus2':
      return [0, 2, 7];
    case 'sus4':
      return [0, 5, 7];
    case 'add9':
      return [0, 2, 4, 7];
    case 'dim':
      return [0, 3, 6];
    case 'aug':
      return [0, 4, 8];
    default:
      return [0, 4, 7];
  }
}

/// 一句中文性质说明（离线字典用）。
String chordQualityExplainZh(String qualId) {
  switch (qualId) {
    case '':
      return '大三和弦：根音、大三度、纯五度。';
    case 'm':
      return '小三和弦：根音、小三度、纯五度。';
    case '7':
      return '属七和弦：大三和弦上加小七度，有解决倾向。';
    case 'maj7':
      return '大七和弦：大三和弦上大七度，色彩更亮、更爵士。';
    case 'm7':
      return '小七和弦：小三和弦上加小七度。';
    case 'm7b5':
      return '半减七和弦（小七减五）：减三和弦上加小七度。';
    case 'sus2':
      return '挂二和弦：用二度替代三度，色彩空灵。';
    case 'sus4':
      return '挂四和弦：用四度替代三度。';
    case 'add9':
      return '加九和弦：大三和弦上加大二度（九音）。';
    case 'dim':
      return '减三和弦：根音、小三度、减五度。';
    case 'aug':
      return '增三和弦：根音、大三度、增五度。';
    default:
      return '和弦构成音见上表；指法为常见吉他型，可按需移动把位。';
  }
}
