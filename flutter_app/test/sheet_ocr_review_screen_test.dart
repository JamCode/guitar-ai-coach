import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/sheets/sheet_ocr_review_screen.dart';
import 'package:guitar_helper/sheets/sheet_parsed_models.dart';

void main() {
  testWidgets('SheetOcrReviewScreen 可校对并保存结构化内容', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    late Future<SheetParsedData?> resultFuture;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  resultFuture = Navigator.of(context).push<SheetParsedData>(
                    MaterialPageRoute<SheetParsedData>(
                      builder: (_) => SheetOcrReviewScreen(
                        sheetId: 'sheet-1',
                        initialSegments: const [
                          SheetSegment(
                            chords: ['C', 'D7'],
                            melody: '0335',
                            lyrics: '我听见雨滴',
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('识别结果校对'), findsOneWidget);
    expect(find.text('C D7'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, '和弦（每行一段）'),
      'C D7 G7',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '旋律（每行一段）'),
      '033551',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '歌词（每行一段）'),
      '我听见雨滴落在',
    );

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result, isNotNull);
    expect(result!.sheetId, 'sheet-1');
    expect(result.segments, hasLength(1));
    expect(result.segments.first.chords, ['C', 'D7', 'G7']);
    expect(result.segments.first.melody, '033551');
    expect(result.segments.first.lyrics, '我听见雨滴落在');
  });
}
