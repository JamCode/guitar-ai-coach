import 'package:flutter/material.dart';

import 'audio/init_guitar_audio.dart';
import 'app_theme.dart';
import 'tuner/tuner_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initGuitarAudio();
  runApp(const GuitarHelperApp());
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
        home: const TunerScreen(),
      );
  }
}
