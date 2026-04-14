/// 应用级环境变量入口。
///
/// 推荐通过 `--dart-define-from-file=env/<name>.json` 注入：
/// `{"GUITAR_API_BASE_URL":"https://your-host/api"}`
class AppEnv {
  const AppEnv._();

  /// 打包内置的默认 API 基址（未传 dart-define 时生效）。
  static const String bundledDefaultApiBaseUrl = 'http://47.110.78.65/api';

  /// 后端 API 基址（通常带 `/api` 后缀）。
  static const String apiBaseUrl = String.fromEnvironment(
    'GUITAR_API_BASE_URL',
    defaultValue: bundledDefaultApiBaseUrl,
  );
}
