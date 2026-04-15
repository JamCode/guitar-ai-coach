import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/profile/profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('首启会生成非空随机昵称', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = ProfileStore();

    final profile = await store.loadOrCreate();

    expect(profile.nickname, isNotEmpty);
  });

  test('保存昵称后再次读取应保持一致', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = ProfileStore();

    await store.saveNickname('我的新昵称');
    final profile = await store.loadOrCreate();

    expect(profile.nickname, '我的新昵称');
  });
}
