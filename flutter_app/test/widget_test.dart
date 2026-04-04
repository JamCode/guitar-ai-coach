import 'package:flutter_test/flutter_test.dart';

import 'package:guitar_helper/main.dart';

void main() {
  testWidgets('调音器页能渲染', (WidgetTester tester) async {
    await tester.pumpWidget(const GuitarHelperApp());
    expect(find.text('调音器'), findsWidgets);
    expect(find.text('开始监听'), findsOneWidget);
  });
}
