import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/tools/fretboard_screen.dart';

void main() {
  testWidgets('吉他指板页展示竖向滚动与空弦音名', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FretboardScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fretboard_scroll')), findsOneWidget);
    expect(find.text('吉他指板'), findsOneWidget);
    expect(find.text('E'), findsWidgets);
    expect(find.textContaining('标准调弦'), findsOneWidget);
  });
}
