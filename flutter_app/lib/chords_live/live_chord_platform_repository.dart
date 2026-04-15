import 'package:flutter/services.dart';
import 'dart:typed_data';

import 'live_chord_models.dart';

/// Flutter ↔ iOS MethodChannel 数据契约封装。
abstract class LiveChordPlatformRepository {
  Future<void> initialize({
    required int sampleRate,
    required double windowSec,
    required double hopSec,
    required LiveChordMode mode,
    required double confidenceThreshold,
  });

  Future<LiveChordFrame> processChunk(Uint8List pcm16ChunkLe);
  Future<void> reset();
  Future<void> dispose();
}

class MethodChannelLiveChordRepository implements LiveChordPlatformRepository {
  MethodChannelLiveChordRepository({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('guitar_helper/live_chord');

  final MethodChannel _channel;

  @override
  Future<void> initialize({
    required int sampleRate,
    required double windowSec,
    required double hopSec,
    required LiveChordMode mode,
    required double confidenceThreshold,
  }) async {
    await _channel.invokeMethod<void>('init', <String, Object>{
      'sampleRate': sampleRate,
      'windowSec': windowSec,
      'hopSec': hopSec,
      'mode': mode == LiveChordMode.fast ? 'fast' : 'stable',
      'confidenceThreshold': confidenceThreshold,
    });
  }

  @override
  Future<LiveChordFrame> processChunk(Uint8List pcm16ChunkLe) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'process',
      <String, Object>{
        'pcm16le': pcm16ChunkLe,
      },
    );
    final map = (raw ?? <Object?, Object?>{}).cast<Object?, Object?>();
    final topKRaw = (map['topK'] as List<Object?>?) ?? const <Object?>[];
    final topK = topKRaw
        .map((e) => (e as Map<Object?, Object?>).cast<Object?, Object?>())
        .map(
          (e) => LiveChordCandidate(
            label: (e['label'] ?? 'Unknown').toString(),
            score: _toDouble(e['score']),
          ),
        )
        .toList(growable: false);
    return LiveChordFrame(
      best: (map['best'] ?? 'Unknown').toString(),
      topK: topK,
      confidence: _toDouble(map['confidence']),
      status: (map['status'] ?? 'No clear chord detected').toString(),
      timestampMs: _toInt(map['timestampMs']),
    );
  }

  @override
  Future<void> reset() => _channel.invokeMethod<void>('reset');

  @override
  Future<void> dispose() => _channel.invokeMethod<void>('dispose');

  static double _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static int _toInt(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
