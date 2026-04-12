import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/auth/auth_api.dart';
import 'package:guitar_helper/settings/api_base_url_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('exchangeAppleIdentity 解析 access_token', () async {
    final store = _FakeBaseUrlStore('http://localhost:9/api');
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://localhost:9/api/auth/apple');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['identity_token'], 'id.jwt');
      expect(body['nonce'], 'nonce-raw');
      return http.Response(
        jsonEncode({'access_token': 'our.jwt.here'}),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    });
    final api = AuthApi(baseUrlStore: store, client: client);
    final tok = await api.exchangeAppleIdentity(
      identityToken: 'id.jwt',
      rawNonce: 'nonce-raw',
    );
    expect(tok, 'our.jwt.here');
  });
}

/// 最小假实现：避免依赖 SharedPreferences 在纯单元测试中的异步初始化。
class _FakeBaseUrlStore extends ApiBaseUrlStore {
  _FakeBaseUrlStore(this._url);
  final String _url;

  @override
  Future<String> load() async => _url;
}
