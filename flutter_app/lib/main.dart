import 'dart:async';

import 'package:flutter/material.dart';

import 'audio/init_guitar_audio.dart';
import 'app_theme.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_scope.dart';
import 'diagnostics/crash_log_store.dart';
import 'shell/home_shell.dart';

/// 冷启动：初始化音频、崩溃日志与登录态，再进入应用。
Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await CrashLogStore.instance.ensureInitialized();
    CrashLogStore.instance.installHandlers();
    await initGuitarAudio();
    final auth = AuthController();
    await auth.bootstrap();
    runApp(GuitarHelperApp(controller: auth));
  }, (Object error, StackTrace stack) {
    CrashLogStore.instance.recordError(error, stack, source: 'runZonedGuarded');
  });
}

class GuitarHelperApp extends StatelessWidget {
  const GuitarHelperApp({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.ready) {
          return MaterialApp(
            title: '吉他小助手',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.system,
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return MaterialApp(
          title: '吉他小助手',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.system,
          builder: (context, child) {
            return AuthScope(
              notifier: controller,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const HomeShell(),
        );
      },
    );
  }
}
