import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:guitar_helper/main.dart' as app;
import 'package:flutter/material.dart';
Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const app.GuitarHelperApp());
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('底部导航与练耳入口', (WidgetTester tester) async {
    await _pumpApp(tester);

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
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.fitness_center_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('今日任务'), findsOneWidget);
    expect(find.byKey(const Key('practice_start_chord-switch')), findsOneWidget);
  });
}
