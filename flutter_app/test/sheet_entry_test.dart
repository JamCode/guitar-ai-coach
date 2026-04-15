import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/sheets/sheet_entry.dart';

void main() {
  test('SheetEntry 云端仅 page_count 可解析', () {
    final e = SheetEntry.fromJson({
      'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      'displayName': '测试',
      'addedAtMs': 1000,
      'serverPageCount': 3,
    });
    expect(e, isNotNull);
    expect(e!.pageCount, 3);
    expect(e.storedFileNames, isEmpty);
  });
}
