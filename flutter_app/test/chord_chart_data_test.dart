import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/chords/chord_diagram_widget.dart';
import 'package:guitar_helper/theory/chord_chart_screen.dart';
import 'package:guitar_helper/theory/common_chord_chart_data.dart';

void main() {
  test('和弦表分三段且每条均为 6 弦品位', () {
    expect(kChordChartSections.length, 3);
    for (final s in kChordChartSections) {
      expect(s.entries, isNotEmpty);
      for (final e in s.entries) {
        expect(e.frets.length, 6, reason: '${e.symbol} frets length');
        if (e.fingers != null) {
          expect(e.fingers!.length, 6, reason: '${e.symbol} fingers length');
        }
      }
    }
  });

  test('chordDiagramLayout 在 baseFret 过大时收束到最低按品', () {
    final lay = chordDiagramLayout(
      [-1, 3, 5, 5, 5, 3],
      baseFret: 12,
    );
    expect(lay.base, 3);
    expect(lay.rows, greaterThanOrEqualTo(4));
  });

  testWidgets('和弦表屏展示初/中/高分段', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChordChartScreen()),
    );
    expect(find.text('初级 · 开放把位'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('中级 · 横按与七和弦、挂留'),
      400,
    );
    expect(find.text('中级 · 横按与七和弦、挂留'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('高级 · 色彩、转位与扩展'),
      400,
    );
    expect(find.text('高级 · 色彩、转位与扩展'), findsOneWidget);
  });
}
