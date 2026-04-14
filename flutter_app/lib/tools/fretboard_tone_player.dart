import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../audio/guitar_chromatic_path.dart';

/// 指板点按试听播放器：点击任一音位时播放对应 MIDI 的短音。
///
/// 副作用：会调用 [SoLoud] 加载/播放音频采样；需在应用已初始化音频后使用。
class FretboardTonePlayer {
  final Map<int, AudioSource> _cache = {};

  static const double _volume = 0.52;
  static const Duration _ringDuration = Duration(milliseconds: 460);
  static const Duration _fadeDuration = Duration(milliseconds: 170);

  Future<AudioSource> _load(int midi) async {
    if (_cache.containsKey(midi)) return _cache[midi]!;
    if (!SoLoud.instance.isInitialized) {
      throw StateError('SoLoud 未初始化');
    }
    final mode = kIsWeb ? LoadMode.disk : LoadMode.memory;
    final src = await SoLoud.instance.loadAsset(
      guitarChromaticAssetPath(midi),
      mode: mode,
    );
    _cache[midi] = src;
    return src;
  }

  /// 播放一个 MIDI 对应的短音，适合点按交互反馈。
  Future<void> playMidi(int midi) async {
    try {
      final src = await _load(midi);
      final handle = await SoLoud.instance.play(src, volume: _volume);
      unawaited(
        Future<void>(() async {
          await Future<void>.delayed(_ringDuration);
          SoLoud.instance.fadeVolume(handle, 0, _fadeDuration);
          await Future<void>.delayed(_fadeDuration);
          await SoLoud.instance.stop(handle);
        }),
      );
    } on Object catch (e, st) {
      debugPrint('FretboardTonePlayer.playMidi: $e\n$st');
    }
  }

  /// 释放已缓存的采样资源。
  Future<void> dispose() async {
    for (final src in _cache.values) {
      await SoLoud.instance.disposeSource(src);
    }
    _cache.clear();
  }
}
