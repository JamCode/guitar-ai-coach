import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/sheets/sheet_ocr_parser.dart';

void main() {
  test('SheetOcrParser 将行文本分拣为和弦/旋律/歌词', () {
    final segments = SheetOcrParser.parseCandidates(const [
      OcrLineCandidate(text: 'C D7 G7 C', centerY: 10),
      OcrLineCandidate(text: '033551 17 | 76366-', centerY: 20),
      OcrLineCandidate(text: '我听见雨滴落在 青青草地', centerY: 30),
    ]);

    expect(segments, hasLength(1));
    expect(segments.first.chords, ['C', 'D7', 'G7', 'C']);
    expect(segments.first.melody, '033551 17 | 76366-');
    expect(segments.first.lyrics, '我听见雨滴落在 青青草地');
  });
}
