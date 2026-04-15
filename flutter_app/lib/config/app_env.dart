/// 应用级固定配置入口。
class AppEnv {
  const AppEnv._();

  /// 离线版不再依赖后端 API；保留空值兼容历史调用。
  static const String apiBaseUrl = '';
}
