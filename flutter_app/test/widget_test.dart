import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/app_theme.dart';
import 'package:guitar_helper/chords/chord_lookup_screen.dart';
import 'package:guitar_helper/chords/chord_models.dart';
import 'package:guitar_helper/main.dart';
import 'package:guitar_helper/shell/home_shell.dart';

import 'fake_chord_repository.dart';

void main() {
  testWidgets('主导航壳显示四个 Tab', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const HomeShell(),
      ),
    );
    expect(find.text('工具'), findsWidgets);
    expect(find.text('练耳'), findsWidgets);
    expect(find.text('练习'), findsWidgets);
    expect(find.text('我的谱'), findsWidgets);
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

    const json = '''
{
  "chord_summary": {
    "symbol": "C",
    "notes_letters": ["C", "E", "G"],
    "notes_explain_zh": "大三和弦。"
  },
  "voicings": [
    {
      "label_zh": "开放",
      "explain": {
        "frets": [-1, 3, 2, 0, 1, 0],
        "fingers": [null, 3, 2, null, 1, null],
        "base_fret": 1,
        "barre": null,
        "voicing_explain_zh": "常用开放把位。"
      }
    },
    {
      "label_zh": "横按",
      "explain": {
        "frets": [3, 3, 5, 5, 5, 3],
        "fingers": [1, 1, 3, 4, 4, 1],
        "base_fret": 3,
        "barre": null,
        "voicing_explain_zh": "可移动形。"
      }
    }
  ],
  "disclaimer": "仅供参考。"
}
''';
    final payload = ChordExplainMultiPayload.tryParseJsonString(json)!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChordLookupScreen(
          repository: FakeChordRepository(
            transposeResult: 'C',
            payload: payload,
          ),
        ),
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
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(find.text('按法参考'), findsOneWidget);
    expect(find.textContaining('常用把位'), findsWidgets);
    expect(find.textContaining('6→1 弦'), findsWidgets);
  });

  testWidgets('GuitarHelperApp 启动到工具 Tab', (WidgetTester tester) async {
    await tester.pumpWidget(const GuitarHelperApp());
    await tester.pump();
    expect(find.text('调音器'), findsOneWidget);
  });
}
