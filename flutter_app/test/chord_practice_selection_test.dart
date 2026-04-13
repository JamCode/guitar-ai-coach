import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/practice/chord_practice_selection_screen.dart';
import 'package:guitar_helper/practice/chord_progression_library.dart';
import 'package:guitar_helper/practice/practice_fake_store.dart';
import 'package:guitar_helper/practice/practice_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const chordTask = PracticeTask(
    id: 'chord-switch',
    name: '和弦切换',
    targetMinutes: 5,
    description: '多种进行 · 12 调 · 3 档复杂度',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Widget buildApp() {
    return MaterialApp(
      home: ChordPracticeSelectionScreen(
        task: chordTask,
        store: PracticeFakeStore(),
      ),
    );
  }

  testWidgets('选择页显示默认选中的进行与 C 调预览', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('和弦切换练习'), findsOneWidget);
    expect(find.text('当前选择预览'), findsOneWidget);
    expect(find.text('流行经典'), findsWidgets);

    final defaultChords = ChordProgressionEngine.resolveChordNames(
      romanNumerals: kChordProgressions.first.romanNumerals,
      key: 'C',
      complexity: ChordComplexity.basic,
    );
    for (final chord in defaultChords) {
      expect(find.text(chord), findsWidgets);
    }
  });

  testWidgets('切换调性后预览和弦变化', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('C'), findsWidgets);
    expect(find.text('Am'), findsWidgets);

    await tester.tap(find.byKey(const Key('practice_key_dropdown')));
    await tester.pumpAndSettle();
    // 选 D 调；下拉菜单在测试视口下偶发 hit-test 告警，关闭以免误判失败。
    await tester.tap(
      find.byKey(const Key('key_dropdown_item_D')).last,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Bm'), findsWidgets);
  });

  testWidgets('切换复杂度后预览和弦变化', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Am'), findsWidgets);

    await tester.tap(find.text('进阶'));
    await tester.pumpAndSettle();

    expect(find.text('Am7'), findsWidgets);
  });

  testWidgets('选择不同进行后预览变化', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('progression_picker_tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('progression_pop-50s')));
    await tester.pumpAndSettle();

    expect(find.text('50 年代'), findsWidgets);
  });

  testWidgets('点击开始练习进入计时页', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_chord_practice')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chord_practice_timer')), findsOneWidget);
    expect(find.text('流行经典 · C 调'), findsOneWidget);
  });

  testWidgets('预览区和弦可点开指法底部层', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('preview_chord_C_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chord_result_sheet')), findsOneWidget);
  });

  testWidgets('完整流程：选择 → 计时 → 结束 → 保存', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_chord_practice')));
    await tester.pumpAndSettle();

    // 手动启动计时器（auto-start 已移除）并让秒表跑 2 秒
    await tester.tap(find.byKey(const Key('chord_timer_start')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('chord_timer_finish')));
    await tester.pumpAndSettle();

    expect(find.text('本次练习完成'), findsOneWidget);

    await tester.tap(find.byKey(const Key('practice_save_session')));
    await tester.pumpAndSettle();

    expect(find.text('记录已保存'), findsOneWidget);
    expect(find.text('和弦切换练习'), findsOneWidget);
  });
}
