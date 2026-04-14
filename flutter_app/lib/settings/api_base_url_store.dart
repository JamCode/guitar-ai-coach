import '../config/app_env.dart';

/// 返回应用内固定后端 API 基址（不允许运行时改写）。
class ApiBaseUrlStore {
  ApiBaseUrlStore();

  /// 返回去掉末尾 `/` 的固定基址。
  Future<String> load() async {
    return _stripTrailingSlash(AppEnv.apiBaseUrl.trim());
  }

  /// 兼容历史调用；线上不再允许运行时覆盖 API 地址。
  Future<void> save(String url) async {
    return;
  }

  static String _stripTrailingSlash(String s) {
    if (s.isEmpty) return s;
    return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
  }
}
