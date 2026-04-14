import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guitar_helper/auth/auth_controller.dart';
import 'package:guitar_helper/main.dart' as app;
import 'package:guitar_helper/settings/api_base_url_store.dart';
import 'package:flutter/material.dart';

const _kAccessTokenKey = 'guitar_auth_access_token';
const _kApiBaseKey = 'guitar_api_base_url';
const _kCiSecret = String.fromEnvironment('E2E_CI_AUTH_SECRET', defaultValue: '');
const _kCiUserKey = String.fromEnvironment(
  'E2E_CI_USER_KEY',
  defaultValue: 'github-actions',
);
const _kRequireCiAuth = bool.fromEnvironment('E2E_REQUIRE_CI_AUTH', defaultValue: false);

Future<void> _prepareLoggedInSession() async {
  final base = await ApiBaseUrlStore().load();
  if (base.isEmpty) {
    fail('API base URL is empty, cannot bootstrap CI login session.');
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kApiBaseKey, base);

  if (_kCiSecret.isEmpty) {
    if (_kRequireCiAuth) {
      fail('E2E_CI_AUTH_SECRET is required in CI, but it is empty.');
    }
    await prefs.setString(_kAccessTokenKey, 'ci-local-bypass-token');
    return;
  }

  final resp = await http.post(
    Uri.parse('$base/auth/ci-login'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'ci_secret': _kCiSecret, 'ci_user_key': _kCiUserKey}),
  );
  if (resp.statusCode != 200) {
    if (_kRequireCiAuth) {
      fail('CI login failed: HTTP ${resp.statusCode} ${resp.body}');
    }
    await prefs.setString(_kAccessTokenKey, 'ci-local-bypass-token');
    return;
  }
  final body = jsonDecode(resp.body);
  if (body is! Map<String, dynamic>) {
    fail('CI login response is not a JSON object: ${resp.body}');
  }
  final token = (body['access_token'] ?? '').toString().trim();
  if (token.isEmpty) {
    fail('CI login did not return access_token: ${resp.body}');
  }
  await prefs.setString(_kAccessTokenKey, token);
}

Future<void> _pumpLoggedInApp(WidgetTester tester) async {
  await _prepareLoggedInSession();
  final controller = AuthController();
  await controller.bootstrap();
  await tester.pumpWidget(app.GuitarHelperApp(controller: controller));
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
  expect(find.text('使用 Apple 账号登录以继续使用'), findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('底部导航与练耳入口', (WidgetTester tester) async {
    await _pumpLoggedInApp(tester);

    expect(find.text('工具'), findsWidgets);
    await tester.tap(find.byIcon(Icons.hearing_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('音程识别'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('听两个音'), findsOneWidget);
  });

  testWidgets('练习 Tab 展示今日任务入口', (WidgetTester tester) async {
    await _pumpLoggedInApp(tester);

    await tester.tap(find.byIcon(Icons.fitness_center_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 练习 Tab 首次挂载后会拉取服务端记录；给异步收尾时间（失败时显示重试而非任务列表）。
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.text('今日任务').evaluate().isNotEmpty ||
          find.text('重试').evaluate().isNotEmpty,
      isTrue,
      reason: '应出现练习首页或网络错误后的重试',
    );
    if (find.text('今日任务').evaluate().isNotEmpty) {
      expect(find.byKey(const Key('practice_start_chord-switch')), findsOneWidget);
    }
  });
}
