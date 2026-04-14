import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/auth/auth_controller.dart';
import 'package:guitar_helper/auth/auth_scope.dart';
import 'package:guitar_helper/profile/me_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'AI吉他',
      packageName: 'com.wanghan.guitarhelper',
      version: '1.0.0',
      buildNumber: '4',
      buildSignature: '',
      installerStore: null,
    );
  });

  testWidgets('我的页可编辑昵称并保存', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final auth = AuthController();
    await auth.bootstrap();
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScope(
          notifier: auth,
          child: const Scaffold(body: MeScreen()),
        ),
      ),
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

  testWidgets('我的页可进入关于与版本页并查看版本字段', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final auth = AuthController();
    await auth.bootstrap();
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScope(
          notifier: auth,
          child: const Scaffold(body: MeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('关于与版本'));
    await tester.pumpAndSettle();

    expect(find.text('关于与版本'), findsOneWidget);
    expect(find.text('应用版本'), findsOneWidget);
    expect(find.text('发布渠道'), findsOneWidget);
    expect(find.text('系统平台'), findsOneWidget);
  });
}
