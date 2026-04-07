import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../audio/guitar_chromatic_path.dart';

/// 真实吉他采样播放（来自 `tonejs-instrument-guitar-acoustic-mp3`，MIT 授权）。
/// 采样覆盖 D2–D5（MIDI 38–74），每个半音一个 mp3。
class IntervalTonePlayer {
  final Map<int, AudioSource> _cache = {};
  bool _busy = false;

  String _assetPath(int midi) => guitarChromaticAssetPath(midi);

  Future<AudioSource> _load(int midi) async {
    if (_cache.containsKey(midi)) return _cache[midi]!;
    if (!SoLoud.instance.isInitialized) {
      throw StateError('SoLoud 未初始化');
    }
    final mode = kIsWeb ? LoadMode.disk : LoadMode.memory;
    final src = await SoLoud.instance.loadAsset(_assetPath(midi), mode: mode);
    _cache[midi] = src;
    return src;
  }

  /// 依次播放 [lowMidi]、[highMidi]（先低后高）。
  /// 每个音自然起振，持续一段后用淡出收尾，避免硬切断。
  Future<void> playAscendingPair(int lowMidi, int highMidi) async {
    if (_busy) return;
    _busy = true;
    try {
      const volume = 0.56;
      const ringDuration = Duration(milliseconds: 1200);
      const fadeDuration = Duration(milliseconds: 300);
      const gap = Duration(milliseconds: 350);

      for (final midi in [lowMidi, highMidi]) {
        final src = await _load(midi);
        final handle = await SoLoud.instance.play(src, volume: volume);
        await Future<void>.delayed(ringDuration);
        SoLoud.instance.fadeVolume(handle, 0, fadeDuration);
        await Future<void>.delayed(fadeDuration);
        await SoLoud.instance.stop(handle);
        await Future<void>.delayed(gap);
      }
    } on Object catch (e, st) {
      debugPrint('IntervalTonePlayer: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    for (final src in _cache.values) {
      await SoLoud.instance.disposeSource(src);
    }
    _cache.clear();
  }
}
