import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/diagnostics/crash_log_store.dart';

void main() {
  test('formatEntry 包含 UTC 时间戳与标题', () {
    final at = DateTime.utc(2026, 4, 10, 12, 0);
    final s = CrashLogStore.formatEntry(
      header: 'test',
      body: 'line1\nline2',
      at: at,
    );
    expect(s, contains('2026-04-10T12:00:00.000Z'));
    expect(s, contains('[test]'));
    expect(s, contains('line1'));
    expect(s, contains('line2'));
  });
}
