import 'package:shared_preferences/shared_preferences.dart';

/// 持久化保存登录态（后端签发的 access token）。
///
/// 副作用：读写 [SharedPreferences]；解析失败时清除损坏项并视为未登录。
class AuthSessionStore {
  AuthSessionStore();

  static const _keyAccessToken = 'guitar_auth_access_token';

  /// 是否已有非空 access token。
  Future<bool> isLoggedIn() async {
    final t = await loadAccessToken();
    return t != null && t.isNotEmpty;
  }

  /// 返回已保存的 Bearer token；无或损坏时返回 null。
  Future<String?> loadAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyAccessToken);
      if (raw == null) {
        return null;
      }
      final t = raw.trim();
      if (t.isEmpty) {
        await prefs.remove(_keyAccessToken);
        return null;
      }
      return t;
    } catch (_) {
      return null;
    }
  }

  /// 写入登录令牌；传空字符串则清除。
  Future<void> saveAccessToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final t = token.trim();
    if (t.isEmpty) {
      await prefs.remove(_keyAccessToken);
      return;
    }
    await prefs.setString(_keyAccessToken, t);
  }

  /// 登出：清除本地 token。
  Future<void> clear() async {
    await saveAccessToken('');
  }
}
