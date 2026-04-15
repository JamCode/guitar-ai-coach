import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/practice/strumming_pattern.dart';

void main() {
  test('内置节奏型均为 8 格且 id 可解析名称', () {
    for (final p in kStrummingPatterns) {
      expect(p.cells, hasLength(8));
      expect(strummingPatternNameForId(p.id), p.name);
    }
  });

  test('未知 id 返回 null', () {
    expect(strummingPatternNameForId('no-such'), isNull);
    expect(strummingPatternNameForId(null), isNull);
  });
}
