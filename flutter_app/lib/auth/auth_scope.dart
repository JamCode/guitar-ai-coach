import 'package:flutter/material.dart';

import 'auth_controller.dart';

/// 将 [AuthController] 注入子树，供「我的」等页面调用 [logout]。
class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({
    super.key,
    required AuthController super.notifier,
    required super.child,
  });

  static AuthController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope not found');
    return scope!.notifier!;
  }
}
