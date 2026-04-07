import 'package:shared_preferences/shared_preferences.dart';

/// 持久化保存后端 API 基址（与 Web 的 `VITE_API_BASE_URL` 同语义，通常含 `/api` 后缀）。
///
/// 副作用：读写 [SharedPreferences]。
class ApiBaseUrlStore {
  ApiBaseUrlStore();

  static const _key = 'guitar_api_base_url';

  /// 编译期注入的默认基址（`--dart-define=GUITAR_API_BASE_URL=...`），仅在用户未保存过配置时使用。
  static const String kCompileTimeDefault = String.fromEnvironment(
    'GUITAR_API_BASE_URL',
    defaultValue: '',
  );

  /// 返回去掉末尾 `/` 的基址；若从未配置且编译期也未定义，返回空字符串。
  Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.trim().isNotEmpty) {
      return _stripTrailingSlash(saved.trim());
    }
    return _stripTrailingSlash(kCompileTimeDefault.trim());
  }

  /// 将 [url] 规范化后写入本地；传空字符串表示清除保存项（回退到编译期默认）。
  Future<void> save(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final t = url.trim();
    if (t.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(_key, _stripTrailingSlash(t));
  }

  static String _stripTrailingSlash(String s) {
    if (s.isEmpty) return s;
    return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
  }
}
