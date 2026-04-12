import 'package:flutter/material.dart';

import 'audio/init_guitar_audio.dart';
import 'app_theme.dart';
import 'auth/apple_login_screen.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_scope.dart';
import 'shell/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initGuitarAudio();
  final auth = AuthController();
  await auth.bootstrap();
  runApp(GuitarHelperApp(controller: auth));
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
          home: controller.loggedIn
              ? const HomeShell()
              : AppleLoginScreen(onLoggedIn: controller.markLoggedIn),
        );
      },
    );
  }
}
