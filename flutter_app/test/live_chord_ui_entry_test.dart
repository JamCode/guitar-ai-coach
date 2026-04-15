import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/tools/tools_screen.dart';

void main() {
  testWidgets('工具页包含实时和弦入口并可进入页面', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ToolsScreen()),
      ),
    );

    expect(find.text('实时和弦建议（Beta）'), findsOneWidget);
    await tester.tap(find.text('实时和弦建议（Beta）'));
    await tester.pumpAndSettle();

    expect(find.text('实时和弦建议（Beta）'), findsWidgets);
    expect(find.text('快速识别'), findsOneWidget);
    expect(find.text('稳定识别'), findsOneWidget);
  });
}
