import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// 标准调弦空弦参考音：**SoLoud** 播放（方案 B），素材与 Vite 一致（`tonejs-instrument-guitar-acoustic-mp3`）。
/// 见 `assets/audio/tone_guitar_reference/ATTRIBUTION.txt`。应用启动时已调用 [initGuitarAudio]。
class ReferenceTonePlayer {
  /// 6 弦(E2) … 1 弦(E4)，与 Tone.js 包内音符命名一致。
  static const _assetPaths = <String>[
    'assets/audio/tone_guitar_reference/E2.mp3',
    'assets/audio/tone_guitar_reference/A2.mp3',
    'assets/audio/tone_guitar_reference/D3.mp3',
    'assets/audio/tone_guitar_reference/G3.mp3',
    'assets/audio/tone_guitar_reference/B3.mp3',
    'assets/audio/tone_guitar_reference/E4.mp3',
  ];

  static List<AudioSource>? _sources;
  static Future<void>? _loading;

  /// 对齐前端 `g.volume.value = -5`（约 -5 dBFS）。
  static const double _volume = 0.562;

  static Future<void> _ensureSources() async {
    if (_sources != null) return;
    _loading ??= _loadSources();
    await _loading;
  }

  static Future<void> _loadSources() async {
    if (!SoLoud.instance.isInitialized) {
      throw StateError('SoLoud 未初始化：请在 main 中先调用 initGuitarAudio()');
    }
    final list = <AudioSource>[];
    for (final path in _assetPaths) {
      final mode = kIsWeb ? LoadMode.disk : LoadMode.memory;
      list.add(await SoLoud.instance.loadAsset(path, mode: mode));
    }
    _sources = list;
  }

  /// [stringIndex]：0 = 6 弦 … 5 = 1 弦（与 [TunerController.selectedStringIndex] 一致）。
  Future<void> playOpenString(int stringIndex) async {
    if (stringIndex < 0 || stringIndex >= _assetPaths.length) return;
    try {
      await _ensureSources();
      await SoLoud.instance.play(
        _sources![stringIndex],
        volume: _volume,
      );
    } on Object catch (e, st) {
      debugPrint('ReferenceTonePlayer: $e\n$st');
    }
  }

  Future<void> dispose() async {
    /// SoLoud 与采样由应用生命周期管理；此处不 deinit，供后续练耳模块共用。
  }
}
