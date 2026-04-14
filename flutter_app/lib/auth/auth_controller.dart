import 'package:flutter/foundation.dart';

import 'auth_api.dart';
import 'auth_session_store.dart';

/// 应用级登录态：冷启动从 [AuthSessionStore] 恢复，登录/登出时通知监听者。
class AuthController extends ChangeNotifier {
  AuthController({AuthSessionStore? sessionStore})
      : _session = sessionStore ?? AuthSessionStore(),
        _authApi = AuthApi();

  final AuthSessionStore _session;
  final AuthApi _authApi;
  var _ready = false;
  var _loggedIn = false;

  bool get ready => _ready;
  bool get loggedIn => _loggedIn;

  /// 在 [runApp] 前调用：读取本地 token 决定是否已登录。
  Future<void> bootstrap() async {
    _loggedIn = await _session.isLoggedIn();
    if (!_loggedIn) {
      try {
        final access = await _authApi.loginTestUser();
        await _session.saveAccessToken(access);
        _loggedIn = true;
      } on AuthApiException {
        _loggedIn = false;
      }
    }
    _ready = true;
    notifyListeners();
  }

  /// Apple 换票成功后由登录页调用。
  void markLoggedIn() {
    _loggedIn = true;
    notifyListeners();
  }

  /// 清除 token 并回到登录页。
  Future<void> logout() async {
    await _session.clear();
    _loggedIn = false;
    notifyListeners();
  }
}
