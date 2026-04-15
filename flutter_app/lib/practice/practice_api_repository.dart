import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session_store.dart';
import '../settings/api_base_url_store.dart';
import 'practice_models.dart';

/// 调用后端 `/practice/sessions`：列表与上报（Bearer JWT）。
///
/// 依赖已登录的 [AuthSessionStore] 与 [ApiBaseUrlStore]。
class PracticeApiRepository {
  PracticeApiRepository({
    AuthSessionStore? sessionStore,
    ApiBaseUrlStore? baseUrlStore,
    http.Client? client,
  })  : _session = sessionStore ?? AuthSessionStore(),
        _baseStore = baseUrlStore ?? ApiBaseUrlStore(),
        _client = client ?? http.Client();

  final AuthSessionStore _session;
  final ApiBaseUrlStore _baseStore;
  final http.Client _client;

  Future<String> _base() async {
    final b = await _baseStore.load();
    if (b.isEmpty) {
      throw PracticeApiException('当前环境未配置可用 API 地址，请联系管理员。');
    }
    return b;
  }

  Future<String> _token() async {
    final t = await _session.loadAccessToken();
    if (t == null || t.isEmpty) {
      throw PracticeApiException('请先登录。');
    }
    return t;
  }

  Future<Map<String, String>> _authHeaders() async {
    final t = await _token();
    return {
      'Authorization': 'Bearer $t',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  /// GET `/practice/sessions`。
  Future<List<PracticeSession>> listSessions({int limit = 200}) async {
    final base = await _base();
    final uri = Uri.parse('$base/practice/sessions').replace(
      queryParameters: <String, String>{'limit': '$limit'},
    );
    http.Response resp;
    try {
      resp = await _client.get(uri, headers: await _authHeaders());
    } catch (e) {
      throw PracticeApiException('网络错误：$e');
    }
    if (resp.statusCode != 200) {
      throw PracticeApiException(_errMessage(resp));
    }
    Map<String, dynamic>? map;
    try {
      final d = jsonDecode(resp.body);
      map = d is Map<String, dynamic> ? d : null;
    } catch (_) {
      map = null;
    }
    final list = map?['sessions'];
    if (list is! List) {
      return <PracticeSession>[];
    }
    final out = <PracticeSession>[];
    for (final x in list) {
      if (x is! Map<String, dynamic>) {
        continue;
      }
      try {
        out.add(PracticeSession.fromJson(x));
      } catch (_) {
        // 跳过损坏项，避免整页失败
      }
    }
    return out;
  }

  /// POST `/practice/sessions`，请求体为单条 [PracticeSession] 的 JSON。
  Future<void> createSession(PracticeSession session) async {
    final base = await _base();
    final uri = Uri.parse('$base/practice/sessions');
    http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: await _authHeaders(),
        body: jsonEncode(session.toJson()),
      );
    } catch (e) {
      throw PracticeApiException('网络错误：$e');
    }
    if (resp.statusCode != 200) {
      throw PracticeApiException(_errMessage(resp));
    }
  }

  static String _errMessage(http.Response resp) {
    Map<String, dynamic>? map;
    try {
      final d = jsonDecode(resp.body);
      map = d is Map<String, dynamic> ? d : null;
    } catch (_) {
      map = null;
    }
    final msg = map?['detail'] ?? map?['error'] ?? resp.body;
    return '请求失败（${resp.statusCode}）：$msg';
  }
}

/// [PracticeApiRepository] 的可读错误。
class PracticeApiException implements Exception {
  PracticeApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
