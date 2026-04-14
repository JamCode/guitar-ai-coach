import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/ear/sight_singing_repository.dart';
import 'package:guitar_helper/settings/api_base_url_store.dart';
import 'package:http/testing.dart';

void main() {
  test('startSession maps network failure to readable error', () async {
    final client = MockClient((_) async {
      throw const SocketException('No route to host');
    });
    final repo = HttpSightSingingRepository(
      baseUrlStore: _MemBaseUrl('http://example.com/api'),
      client: client,
    );

    expect(
      () => repo.startSession(
        pitchRange: 'mid',
        includeAccidental: false,
        questionCount: 10,
      ),
      throwsA(
        isA<SightSingingApiException>().having(
          (e) => e.message,
          'message',
          '网络不可达，请检查网络连接或稍后重试',
        ),
      ),
    );
  });
}

class _MemBaseUrl extends ApiBaseUrlStore {
  _MemBaseUrl(this._value);

  final String _value;

  @override
  Future<String> load() async => _value;
}
