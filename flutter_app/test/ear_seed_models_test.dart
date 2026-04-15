import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/ear/ear_seed_models.dart';

void main() {
  test('EarBankItem.tryParse 解析 A 题片段', () {
    const raw = '''
{
  "id": "EA0001",
  "mode": "A",
  "question_type": "single_chord_quality",
  "prompt_zh": "听音后判断和弦性质：C ?",
  "correct_option_key": "C",
  "root": "C",
  "target_quality": "major",
  "options": [
    {"key": "A", "label": "小三", "is_correct": false},
    {"key": "B", "label": "属七", "is_correct": false},
    {"key": "C", "label": "大三", "is_correct": true},
    {"key": "D", "label": "maj7", "is_correct": false}
  ]
}
''';
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final q = EarBankItem.tryParse(map);
    expect(q, isNotNull);
    expect(q!.correctOptionKey, 'C');
    expect(q.root, 'C');
    expect(q.targetQuality, 'major');
    expect(q.options.length, 4);
  });

  test('EarSeedDocument 解析最小 banks', () {
    final doc = EarSeedDocument.tryParseMap({
      'banks': {
        'A': [
          {
            'id': 'x1',
            'mode': 'A',
            'question_type': 'single_chord_quality',
            'prompt_zh': 'p',
            'correct_option_key': 'A',
            'root': 'C',
            'target_quality': 'major',
            'options': [
              {'key': 'A', 'label': '大三', 'is_correct': true},
              {'key': 'B', 'label': '小三', 'is_correct': false},
            ],
          },
        ],
        'B': <Map<String, Object>>[],
      },
    });
    expect(doc, isNotNull);
    expect(doc!.bankA.length, 1);
    expect(doc.bankB, isEmpty);
  });
}
