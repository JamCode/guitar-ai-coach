import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/app_theme.dart';
import 'package:guitar_helper/shell/home_shell.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('底部导航与练耳入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.light,
        home: const HomeShell(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('工具'), findsWidgets);
    await tester.tap(find.byIcon(Icons.hearing_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('音程识别'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('听两个音'), findsOneWidget);
  });

  testWidgets('练习 Tab 展示今日任务入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.light,
        home: const HomeShell(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(Icons.fitness_center_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 练习 Tab 首次挂载后会拉取服务端记录；给异步收尾时间（失败时显示重试而非任务列表）。
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.text('今日任务').evaluate().isNotEmpty ||
          find.text('重试').evaluate().isNotEmpty,
      isTrue,
      reason: '应出现练习首页或网络错误后的重试',
    );
    if (find.text('今日任务').evaluate().isNotEmpty) {
      expect(find.byKey(const Key('practice_start_chord-switch')), findsOneWidget);
    }
  });
}
