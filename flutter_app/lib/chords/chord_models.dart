import 'dart:convert';

/// 后端 `POST /chords/explain-multi` 返回中 `chord_summary` 一段。
class ChordSummary {
  const ChordSummary({
    required this.symbol,
    required this.notesLetters,
    required this.notesExplainZh,
  });

  final String symbol;
  final List<String> notesLetters;
  final String notesExplainZh;

  static ChordSummary? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final sym = raw['symbol'];
    if (sym is! String) return null;
    final notes = raw['notes_letters'];
    final letters = <String>[];
    if (notes is List) {
      for (final x in notes) {
        if (x is String && x.trim().isNotEmpty) letters.add(x.trim());
      }
    }
    final explain = raw['notes_explain_zh'];
    return ChordSummary(
      symbol: sym.trim(),
      notesLetters: letters,
      notesExplainZh: explain is String ? explain : '',
    );
  }
}

/// 单条按法中的指法数据（6 弦→1 弦）。
class ChordVoicingExplain {
  const ChordVoicingExplain({
    required this.frets,
    required this.fingers,
    required this.baseFret,
    this.barre,
    required this.voicingExplainZh,
  });

  final List<int> frets;
  final List<int?> fingers;
  final int baseFret;
  final ChordBarre? barre;
  final String voicingExplainZh;

  static ChordVoicingExplain? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final fretsRaw = raw['frets'];
    if (fretsRaw is! List || fretsRaw.length != 6) return null;
    final frets = <int>[];
    for (final x in fretsRaw) {
      if (x is int) {
        frets.add(x);
      } else if (x is num) {
        frets.add(x.toInt());
      } else {
        return null;
      }
    }
    final fingers = <int?>[];
    final fRaw = raw['fingers'];
    if (fRaw is List && fRaw.length == 6) {
      for (final x in fRaw) {
        if (x == null) {
          fingers.add(null);
        } else if (x is int) {
          fingers.add(x);
        } else if (x is num) {
          fingers.add(x.toInt());
        } else {
          fingers.add(null);
        }
      }
    } else {
      fingers.addAll(List<int?>.filled(6, null));
    }
    final base = raw['base_fret'];
    final baseFret = base is int ? base : (base is num ? base.toInt() : 1);
    final barre = ChordBarre.tryParse(raw['barre']);
    final ve = raw['voicing_explain_zh'];
    return ChordVoicingExplain(
      frets: frets,
      fingers: fingers,
      baseFret: baseFret,
      barre: barre,
      voicingExplainZh: ve is String ? ve : '',
    );
  }
}

class ChordBarre {
  const ChordBarre({
    required this.fret,
    required this.fromString,
    required this.toString_,
  });

  final int fret;
  final int fromString;
  final int toString_;

  static ChordBarre? tryParse(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) return null;
    final f = raw['fret'];
    final fs = raw['from_string'];
    final ts = raw['to_string'];
    if (f is! num || fs is! num || ts is! num) return null;
    return ChordBarre(
      fret: f.toInt(),
      fromString: fs.toInt(),
      toString_: ts.toInt(),
    );
  }
}

class ChordVoicingItem {
  const ChordVoicingItem({
    required this.labelZh,
    required this.explain,
  });

  final String labelZh;
  final ChordVoicingExplain explain;
}

/// `explain-multi` 成功体的解析结果。
class ChordExplainMultiPayload {
  const ChordExplainMultiPayload({
    required this.chordSummary,
    required this.voicings,
    required this.disclaimer,
  });

  final ChordSummary chordSummary;
  final List<ChordVoicingItem> voicings;
  final String disclaimer;

  static ChordExplainMultiPayload? tryParseMap(Map<String, dynamic> map) {
    final summary = ChordSummary.tryParse(map['chord_summary']);
    if (summary == null) return null;
    final vRaw = map['voicings'];
    if (vRaw is! List) return null;
    final voicings = <ChordVoicingItem>[];
    for (final item in vRaw) {
      if (item is! Map) continue;
      final label = item['label_zh'];
      final explainRaw = item['explain'];
      final ex = ChordVoicingExplain.tryParse(explainRaw);
      if (ex == null) continue;
      voicings.add(
        ChordVoicingItem(
          labelZh: label is String ? label.trim() : '按法',
          explain: ex,
        ),
      );
    }
    if (voicings.isEmpty) return null;
    final disc = map['disclaimer'];
    return ChordExplainMultiPayload(
      chordSummary: summary,
      voicings: voicings,
      disclaimer: disc is String ? disc : '',
    );
  }

  /// 供测试使用的 JSON 解析入口。
  static ChordExplainMultiPayload? tryParseJsonString(String json) {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) {
      return tryParseMap(decoded);
    }
    if (decoded is Map) {
      return tryParseMap(Map<String, dynamic>.from(decoded));
    }
    return null;
  }
}

/// 将 6 弦→1 弦的品格数格式化为易读文本（闷音显示为 `x`）。
String formatFretsLine(List<int> frets) {
  if (frets.length != 6) return frets.toString();
  return frets.map((f) => f < 0 ? 'x' : '$f').join(' ');
}
