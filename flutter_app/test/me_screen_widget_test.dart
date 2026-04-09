import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/profile/me_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('我的页可编辑昵称并保存', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MeScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('设置昵称'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '可编辑昵称');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('昵称已更新'), findsOneWidget);
    expect(find.text('可编辑昵称'), findsOneWidget);
  });
}
