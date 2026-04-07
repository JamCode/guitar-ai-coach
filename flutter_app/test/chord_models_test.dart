import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/chords/chord_models.dart';

void main() {
  test('ChordExplainMultiPayload 解析示例 JSON', () {
    const json = '''
{
  "chord_summary": {
    "symbol": "C",
    "notes_letters": ["C", "E", "G"],
    "notes_explain_zh": "大三和弦。"
  },
  "voicings": [
    {
      "label_zh": "开放",
      "explain": {
        "frets": [-1, 3, 2, 0, 1, 0],
        "fingers": [null, 3, 2, null, 1, null],
        "base_fret": 1,
        "barre": null,
        "voicing_explain_zh": "常用开放把位。"
      }
    },
    {
      "label_zh": "横按",
      "explain": {
        "frets": [3, 3, 5, 5, 5, 3],
        "fingers": [1, 1, 3, 4, 4, 1],
        "base_fret": 3,
        "barre": {"fret": 3, "from_string": 6, "to_string": 1},
        "voicing_explain_zh": "可移动形。"
      }
    }
  ],
  "disclaimer": "仅供参考。"
}
''';
    final p = ChordExplainMultiPayload.tryParseJsonString(json);
    expect(p, isNotNull);
    expect(p!.chordSummary.symbol, 'C');
    expect(p.voicings.length, 2);
    expect(formatFretsLine(p.voicings.first.explain.frets), 'x 3 2 0 1 0');
    expect(p.voicings[1].explain.barre?.fret, 3);
  });

  test('formatFretsLine 闷音为 x', () {
    expect(formatFretsLine(const [-1, 0, 2, 2, 2, 0]), 'x 0 2 2 2 0');
  });
}
