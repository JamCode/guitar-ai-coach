import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/auth/auth_session_store.dart';
import 'package:guitar_helper/practice/practice_api_repository.dart';
import 'package:guitar_helper/practice/practice_models.dart';
import 'package:guitar_helper/settings/api_base_url_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('listSessions parses sessions array', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/practice/sessions');
      expect(request.headers['Authorization'], 'Bearer tok');
      return http.Response(
        jsonEncode({
          'sessions': [
            {
              'id': '550e8400-e29b-41d4-a716-446655440000',
              'taskId': 'a',
              'taskName': 'A',
              'startedAt': '2026-04-09T10:00:00.000',
              'endedAt': '2026-04-09T10:01:00.000',
              'durationSeconds': 60,
              'completed': true,
              'difficulty': 3,
            },
          ],
        }),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    });
    final base = _MemBaseUrl('http://example.com/api');
    final session = _MemSession('tok');
    final repo = PracticeApiRepository(
      sessionStore: session,
      baseUrlStore: base,
      client: client,
    );
    final list = await repo.listSessions();
    expect(list.length, 1);
    expect(list.first.taskId, 'a');
    expect(list.first.durationSeconds, 60);
  });

  test('createSession posts JSON body', () async {
    PracticeSession? posted;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/practice/sessions');
      posted = PracticeSession.fromJson(
        jsonDecode(request.body) as Map<String, dynamic>,
      );
      return http.Response('{"ok":true}', 200);
    });
    final repo = PracticeApiRepository(
      sessionStore: _MemSession('tok'),
      baseUrlStore: _MemBaseUrl('http://example.com/api'),
      client: client,
    );
    final s = PracticeSession(
      id: '550e8400-e29b-41d4-a716-446655440000',
      taskId: 't',
      taskName: 'T',
      startedAt: DateTime(2026, 4, 9, 10),
      endedAt: DateTime(2026, 4, 9, 10, 1),
      durationSeconds: 60,
      completed: true,
      difficulty: 3,
    );
    await repo.createSession(s);
    expect(posted?.id, s.id);
  });
}

class _MemBaseUrl extends ApiBaseUrlStore {
  _MemBaseUrl(this._v);

  final String _v;

  @override
  Future<String> load() async => _v;
}

class _MemSession extends AuthSessionStore {
  _MemSession(this._t);

  final String _t;

  @override
  Future<String?> loadAccessToken() async => _t;
}
