import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/app_theme.dart';
import 'package:guitar_helper/ear/ear_mcq_session_screen.dart';
import 'package:guitar_helper/ear/ear_seed_models.dart';

void main() {
  testWidgets('和弦听辨会话展示题干（注入题目，不播放）', (WidgetTester tester) async {
    final q = EarBankItem(
      id: 't1',
      mode: 'A',
      questionType: 'single_chord_quality',
      promptZh: '单元测试题干',
      options: const [
        EarMcqOption(key: 'A', label: '大三'),
        EarMcqOption(key: 'B', label: '小三'),
        EarMcqOption(key: 'C', label: '属七'),
        EarMcqOption(key: 'D', label: 'maj7'),
      ],
      correctOptionKey: 'A',
      root: 'C',
      targetQuality: 'major',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: EarMcqSessionScreen(
          title: '和弦听辨',
          bank: 'A',
          totalQuestions: 1,
          overrideItems: [q],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('单元测试题干'), findsOneWidget);
    expect(find.text('大三'), findsOneWidget);
  });
}
