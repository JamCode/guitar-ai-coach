import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/chords_live/live_chord_models.dart';
import 'package:guitar_helper/chords_live/live_chord_platform_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/live_chord');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'init':
          return null;
        case 'process':
          return <String, Object>{
            'best': 'Am',
            'confidence': 0.81,
            'status': '🎵 Listening…',
            'timestampMs': 123,
            'topK': <Map<String, Object>>[
              <String, Object>{'label': 'Am', 'score': 0.81},
              <String, Object>{'label': 'F', 'score': 0.11},
            ],
          };
        case 'reset':
        case 'dispose':
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('processChunk 正确解析通道返回结构', () async {
    final repo = MethodChannelLiveChordRepository(channel: channel);
    await repo.initialize(
      sampleRate: 16000,
      windowSec: 2,
      hopSec: 0.5,
      mode: LiveChordMode.stable,
      confidenceThreshold: 0.6,
    );

    final frame = await repo.processChunk(Uint8List(1600));
    expect(frame.best, 'Am');
    expect(frame.confidence, closeTo(0.81, 0.0001));
    expect(frame.status, '🎵 Listening…');
    expect(frame.topK.length, 2);
    expect(frame.topK.first.label, 'Am');
  });
}
