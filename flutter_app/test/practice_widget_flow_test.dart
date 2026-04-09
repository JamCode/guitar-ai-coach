import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/practice/practice_stub_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('练习模块可完成一次记录并显示在首页', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PracticeStubScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('practice_start_chord-switch')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('practice_timer_start')));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('practice_timer_finish')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('practice_note_input')), '状态不错');
    await tester.tap(find.byKey(const Key('practice_save_session')));
    await tester.pumpAndSettle();

    expect(find.text('记录已保存'), findsOneWidget);
    expect(find.text('和弦切换'), findsWidgets);
  });
}
