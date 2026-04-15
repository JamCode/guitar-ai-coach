import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings/api_base_url_store.dart';
import 'chord_models.dart';
import 'chord_remote_repository.dart';

/// 使用 [http.Client] 调用后端 `/chords/transpose` 与 `/chords/explain-multi`。
///
/// [baseUrlLoader] 每次请求前拉取当前基址；[client] 可注入以便测试。
class ChordApiRepository implements ChordRemoteRepository {
  ChordApiRepository({
    ApiBaseUrlStore? baseUrlStore,
    http.Client? client,
  })  : _store = baseUrlStore ?? ApiBaseUrlStore(),
        _client = client ?? http.Client();

  final ApiBaseUrlStore _store;
  final http.Client _client;

  @override
  Future<String?> transposeChord({
    required String symbol,
    required String fromKey,
    required String toKey,
  }) async {
    final base = await _store.load();
    if (base.isEmpty) return null;
    final uri = Uri.parse('$base/chords/transpose');
    try {
      final resp = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from_key': fromKey,
          'to_key': toKey,
          'lines': [symbol],
        }),
      );
      if (resp.statusCode != 200) return null;
      final map = jsonDecode(resp.body);
      if (map is! Map<String, dynamic>) return null;
      final lines = map['lines'];
      if (lines is List && lines.isNotEmpty && lines.first is String) {
        return lines.first as String;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ChordExplainMultiPayload> explainMulti({
    required String symbol,
    required String key,
    required String level,
    bool forceRefresh = false,
  }) async {
    final base = await _store.load();
    if (base.isEmpty) {
      throw ChordApiException('当前环境未配置可用 API 地址，请联系管理员。');
    }
    final uri = Uri.parse('$base/chords/explain-multi');
    final body = <String, dynamic>{
      'symbol': symbol,
      'key': key,
      'level': level,
    };
    if (forceRefresh) {
      body['force_refresh'] = true;
    }
    http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (e) {
      throw ChordApiException('网络请求失败：$e');
    }
    final parsed = _parseErrorBody(resp.body);
    if (resp.statusCode != 200) {
      throw ChordApiException(
        parsed ?? '请求失败（HTTP ${resp.statusCode}）',
        statusCode: resp.statusCode,
      );
    }
    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw ChordApiException('返回体不是 JSON 对象');
      }
      map = decoded;
    } catch (e) {
      throw ChordApiException('解析响应失败：$e');
    }
    final payload = ChordExplainMultiPayload.tryParseMap(map);
    if (payload == null) {
      throw ChordApiException('返回数据不完整（缺少 chord_summary 或 voicings）');
    }
    return payload;
  }

  static String? _parseErrorBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final detail = decoded['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      final err = decoded['error'];
      if (err is String && err.isNotEmpty) return err;
      final msg = decoded['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    } catch (_) {}
    return null;
  }

  void close() => _client.close();
}
