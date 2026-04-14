/// 应用级固定配置入口。
class AppEnv {
  const AppEnv._();

  /// App 内固定后端 API 基址（线上包不允许用户或构建参数改写）。
  static const String apiBaseUrl = 'http://47.110.78.65/api';
}
