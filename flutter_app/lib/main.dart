import 'dart:async';

import 'package:flutter/material.dart';

import 'audio/init_guitar_audio.dart';
import 'app_theme.dart';
import 'diagnostics/crash_log_store.dart';
import 'shell/home_shell.dart';

/// 冷启动：初始化音频与崩溃日志，再进入应用。
Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await CrashLogStore.instance.ensureInitialized();
    CrashLogStore.instance.installHandlers();
    await initGuitarAudio();
    runApp(const GuitarHelperApp());
  }, (Object error, StackTrace stack) {
    CrashLogStore.instance.recordError(error, stack, source: 'runZonedGuarded');
  });
}

class GuitarHelperApp extends StatelessWidget {
  const GuitarHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '吉他小助手',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}
