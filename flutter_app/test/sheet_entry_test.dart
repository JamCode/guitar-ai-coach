import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/sheets/sheet_entry.dart';

void main() {
  test('SheetEntry.fromJson 兼容旧版单文件 storedFileName', () {
    final e = SheetEntry.fromJson({
      'id': 'a',
      'displayName': 'x',
      'storedFileName': 'a.pdf',
      'addedAtMs': 1,
    });
    expect(e, isNotNull);
    expect(e!.storedFileNames, ['a.pdf']);
    expect(e.pageCount, 1);
  });

  test('SheetEntry.fromJson 新版 storedFileNames', () {
    final e = SheetEntry.fromJson({
      'id': 'b',
      'displayName': 'y',
      'storedFileNames': ['b_0.jpg', 'b_1.jpg'],
      'addedAtMs': 2,
    });
    expect(e, isNotNull);
    expect(e!.pageCount, 2);
    expect(e.toJson()['storedFileNames'], ['b_0.jpg', 'b_1.jpg']);
  });

  test('SheetEntry.fromJson 拒绝空页列表', () {
    expect(
      SheetEntry.fromJson({
        'id': 'c',
        'displayName': 'z',
        'storedFileNames': <String>[],
        'addedAtMs': 3,
      }),
      isNull,
    );
  });
}
