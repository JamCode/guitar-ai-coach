import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings/api_base_url_store.dart';

/// Apple 登录后与 `/auth/apple` 换发本站 [access_token]。
///
/// [baseUrlStore]、[client] 可注入以便测试。
class AuthApi {
  AuthApi({
    ApiBaseUrlStore? baseUrlStore,
    http.Client? client,
  })  : _store = baseUrlStore ?? ApiBaseUrlStore(),
        _client = client ?? http.Client();

  final ApiBaseUrlStore _store;
  final http.Client _client;

  /// 将 Apple [identityToken] 与原始 [rawNonce] 交给后端；成功返回 access_token。
  Future<String> exchangeAppleIdentity({
    required String identityToken,
    required String rawNonce,
  }) async {
    final base = await _store.load();
    if (base.isEmpty) {
      throw AuthApiException('请先在登录页配置 API 服务地址（通常以 /api 结尾）。');
    }
    final uri = Uri.parse('$base/auth/apple');
    http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identity_token': identityToken,
          'nonce': rawNonce,
        }),
      );
    } catch (e) {
      throw AuthApiException('网络错误：$e');
    }
    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(resp.body);
      map = decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      map = null;
    }
    if (resp.statusCode != 200) {
      final msg = map?['detail'] ?? map?['error'] ?? resp.body;
      throw AuthApiException('登录失败（${resp.statusCode}）：$msg');
    }
    final token = map?['access_token'];
    if (token is! String || token.trim().isEmpty) {
      throw AuthApiException('服务端未返回 access_token');
    }
    return token.trim();
  }
}

/// [AuthApi] 的可读错误。
class AuthApiException implements Exception {
  AuthApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
