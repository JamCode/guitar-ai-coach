import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/auth/auth_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('损坏的 token 字符串降级为未登录', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'guitar_auth_access_token': '   ',
    });
    final store = AuthSessionStore();
    expect(await store.isLoggedIn(), isFalse);
    expect(await store.loadAccessToken(), isNull);
  });

  test('有效 token 可读写', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = AuthSessionStore();
    await store.saveAccessToken('abc.def.ghi');
    expect(await store.isLoggedIn(), isTrue);
    expect(await store.loadAccessToken(), 'abc.def.ghi');
    await store.clear();
    expect(await store.isLoggedIn(), isFalse);
  });
}
