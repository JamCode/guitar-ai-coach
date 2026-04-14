import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings/api_base_url_store.dart';
import 'sight_singing_models.dart';

/// 视唱会话数据源。
abstract class SightSingingRepository {
  Future<SightSingingSessionStart> startSession({
    required String pitchRange,
    required bool includeAccidental,
    required int questionCount,
  });

  Future<void> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> answers,
    required double avgCentsAbs,
    required int stableHitMs,
    required int durationMs,
  });

  Future<SightSingingQuestion?> nextQuestion(String sessionId);
  Future<SightSingingResult> fetchResult(String sessionId);
}

/// 基于 `/ear-note/session/*` 的视唱后端实现。
class HttpSightSingingRepository implements SightSingingRepository {
  HttpSightSingingRepository({
    ApiBaseUrlStore? baseUrlStore,
    http.Client? client,
  }) : _store = baseUrlStore ?? ApiBaseUrlStore(),
       _client = client ?? http.Client();

  final ApiBaseUrlStore _store;
  final http.Client _client;

  @override
  Future<SightSingingSessionStart> startSession({
    required String pitchRange,
    required bool includeAccidental,
    required int questionCount,
  }) async {
    final data = await _post('/ear-note/session/start', {
      'mode': 'single_note',
      'pitch_range': pitchRange,
      'include_accidental': includeAccidental,
      'question_count': questionCount,
    });
    final configMap = _map(data['config']);
    return SightSingingSessionStart(
      sessionId: (data['session_id'] ?? '').toString(),
      config: SightSingingConfig(
        minNote: (_map(configMap['pitch_range'])['min_note'] ?? 'C4')
            .toString(),
        maxNote: (_map(configMap['pitch_range'])['max_note'] ?? 'B4')
            .toString(),
        questionCount: _int(
          configMap['question_count'],
          fallback: questionCount,
        ),
        includeAccidental: includeAccidental,
      ),
      question: _parseQuestion(data['question']),
    );
  }

  @override
  Future<void> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> answers,
    required double avgCentsAbs,
    required int stableHitMs,
    required int durationMs,
  }) async {
    await _post('/ear-note/session/answer', {
      'session_id': sessionId,
      'question_id': questionId,
      'answers': answers,
      'avg_cents_abs': avgCentsAbs,
      'stable_hit_ms': stableHitMs,
      'duration_ms': durationMs,
    });
  }

  @override
  Future<SightSingingQuestion?> nextQuestion(String sessionId) async {
    final data = await _post('/ear-note/session/next', {
      'session_id': sessionId,
    });
    return _parseQuestion(data['question']);
  }

  @override
  Future<SightSingingResult> fetchResult(String sessionId) async {
    final base = await _baseUrl();
    final uri = Uri.parse('$base/ear-note/session/result/$sessionId');
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      throw SightSingingApiException('获取结果失败（${resp.statusCode}）');
    }
    final data = _map(jsonDecode(resp.body));
    final summary = _map(data['summary']);
    return SightSingingResult(
      answered: _int(summary['answered']),
      correct: _int(summary['correct']),
      total: _int(summary['total']),
      accuracy: _double(summary['accuracy']),
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final base = await _baseUrl();
    final uri = Uri.parse('$base$path');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    Map<String, dynamic> data = {};
    try {
      data = _map(jsonDecode(resp.body));
    } catch (_) {}
    if (resp.statusCode != 200) {
      final msg = data['error']?.toString() ?? '请求失败';
      throw SightSingingApiException('$msg（${resp.statusCode}）');
    }
    return data;
  }

  Future<String> _baseUrl() async {
    final base = await _store.load();
    if (base.isEmpty) {
      throw SightSingingApiException('当前环境未配置 API 地址');
    }
    return base;
  }

  SightSingingQuestion? _parseQuestion(Object? obj) {
    if (obj == null) return null;
    final map = _map(obj);
    final notes = (_list(
      map['target_notes'],
    )).map((e) => e.toString()).toList();
    return SightSingingQuestion(
      id: (map['question_id'] ?? '').toString(),
      index: _int(map['index'], fallback: 1),
      totalQuestions: _int(map['total_questions'], fallback: 10),
      targetNotes: notes,
    );
  }

  static Map<String, dynamic> _map(Object? v) =>
      v is Map<String, dynamic> ? v : <String, dynamic>{};
  static List<dynamic> _list(Object? v) => v is List ? v : <dynamic>[];
  static int _int(Object? v, {int fallback = 0}) =>
      v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
  static double _double(Object? v) => v is num ? v.toDouble() : 0;
}

class SightSingingApiException implements Exception {
  SightSingingApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
