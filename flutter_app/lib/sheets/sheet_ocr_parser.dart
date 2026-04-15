import 'sheet_parsed_models.dart';

/// OCR 一行文本及其垂直中心坐标。
class OcrLineCandidate {
  const OcrLineCandidate({required this.text, required this.centerY});

  final String text;
  final double centerY;
}

/// 纯文本规则解析器：将 OCR 行分拣为和弦、旋律、歌词。
abstract final class SheetOcrParser {
  static final RegExp _chordToken = RegExp(
    r'^[A-G](?:#|b)?(?:m|maj|min|sus|dim|aug|add)?\d*(?:/[A-G](?:#|b)?)?$',
  );
  static final RegExp _melodyChars = RegExp(r'^[0-7\-\.\|\(\)\s]+$');
  static final RegExp _containsCjk = RegExp(r'[\u4e00-\u9fff]');

  static List<SheetSegment> parseCandidates(List<OcrLineCandidate> lines) {
    if (lines.isEmpty) return const [];
    final sorted = [...lines]..sort((a, b) => a.centerY.compareTo(b.centerY));
    final chordLines = <String>[];
    final melodyLines = <String>[];
    final lyricLines = <String>[];

    for (final line in sorted) {
      final text = _normalize(line.text);
      if (text.isEmpty) continue;
      if (_isChordLine(text)) {
        chordLines.add(text);
        continue;
      }
      if (_isMelodyLine(text)) {
        melodyLines.add(text);
        continue;
      }
      if (_containsCjk.hasMatch(text)) {
        lyricLines.add(text);
      }
    }

    final size = _max3(
      chordLines.length,
      melodyLines.length,
      lyricLines.length,
    );
    if (size == 0) return const [];
    final out = <SheetSegment>[];
    for (var i = 0; i < size; i++) {
      out.add(
        SheetSegment(
          chords: i < chordLines.length
              ? _splitChordLine(chordLines[i])
              : const [],
          melody: i < melodyLines.length ? melodyLines[i] : '',
          lyrics: i < lyricLines.length ? lyricLines[i] : '',
        ),
      );
    }
    return out;
  }

  static String _normalize(String text) {
    return text
        .replaceAll('｜', '|')
        .replaceAll('–', '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isChordLine(String text) {
    final tokens = text
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return false;
    var chordCount = 0;
    for (final token in tokens) {
      if (_chordToken.hasMatch(token)) chordCount++;
    }
    return chordCount >= 2 && chordCount * 2 >= tokens.length;
  }

  static bool _isMelodyLine(String text) {
    if (!_melodyChars.hasMatch(text)) return false;
    final digitCount = RegExp(r'[0-7]').allMatches(text).length;
    return digitCount >= 4;
  }

  static List<String> _splitChordLine(String text) {
    return text
        .split(RegExp(r'\s+'))
        .where((t) => _chordToken.hasMatch(t))
        .toList(growable: false);
  }

  static int _max3(int a, int b, int c) =>
      (a > b ? (a > c ? a : c) : (b > c ? b : c));
}
