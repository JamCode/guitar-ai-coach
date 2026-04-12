import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/practice/practice_fake_store.dart';
import 'package:guitar_helper/practice/practice_stub_screen.dart';

void main() {
  testWidgets('和弦切换按钮跳转到选择页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeStubScreen(sessionStore: PracticeFakeStore()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('practice_start_chord-switch')));
    await tester.pumpAndSettle();

    expect(find.text('和弦切换练习'), findsOneWidget);
    expect(find.text('当前选择预览'), findsOneWidget);
  });

  testWidgets('节奏扫弦按钮直接进入计时页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeStubScreen(sessionStore: PracticeFakeStore()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('practice_start_rhythm-strum')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('practice_timer')), findsOneWidget);
    expect(find.text('节奏扫弦'), findsOneWidget);
  });

  testWidgets('通用任务可完成记录并返回首页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeStubScreen(sessionStore: PracticeFakeStore()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('practice_start_scale-walk')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('practice_timer_start')));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('practice_timer_finish')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('practice_note_input')),
      '状态不错',
    );
    await tester.tap(find.byKey(const Key('practice_save_session')));
    await tester.pumpAndSettle();

    expect(find.text('记录已保存'), findsOneWidget);
    expect(find.text('音阶爬格子'), findsWidgets);
  });
}
