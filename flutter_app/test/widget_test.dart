import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/app_theme.dart';
import 'package:guitar_helper/chords/chord_lookup_screen.dart';
import 'package:guitar_helper/main.dart';
import 'package:guitar_helper/shell/home_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('主导航壳显示四个 Tab', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const HomeShell(),
      ),
    );
    await tester.pump();
    expect(find.text('工具'), findsWidgets);
    expect(find.text('练耳'), findsWidgets);
    expect(find.text('练习'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
  });

  testWidgets('损坏的练习 prefs 不阻塞冷启动（练习 Tab 延迟挂载）',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'practice_sessions_v1': '{"broken"',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const HomeShell(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('调音器'), findsOneWidget);
  });

  testWidgets('练耳 Tab 可进入音程识别页', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const HomeShell(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(Icons.hearing_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('音程识别'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('听两个音'), findsOneWidget);
  });

  testWidgets('和弦字典离线查询展示按法', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const ChordLookupScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(find.text('C'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('chord_lookup_offline')));
    await tester.tap(find.byKey(const Key('chord_lookup_offline')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('chord_result_sheet')), findsOneWidget);
    expect(find.text('分解试听'), findsWidgets);
    expect(find.text('齐奏试听'), findsWidgets);
    expect(find.textContaining('常用把位'), findsWidgets);
  });

  testWidgets('GuitarHelperApp 启动到工具 Tab', (WidgetTester tester) async {
    await tester.pumpWidget(const GuitarHelperApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('调音器'), findsOneWidget);
  });
}
