import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../audio/guitar_chromatic_path.dart';

/// 用吉他采样播放和弦或和弦进行（用于练耳种子题，替代未打包的 `ear_v1` MP3）。
///
/// 副作用：使用 [SoLoud] 播放与释放句柄；需在 [initGuitarAudio] 之后调用。
class EarChordPlayer {
  final Map<int, AudioSource> _cache = {};
  bool _busy = false;

  Future<AudioSource> _load(int midi) async {
    if (_cache.containsKey(midi)) return _cache[midi]!;
    if (!SoLoud.instance.isInitialized) {
      throw StateError('SoLoud 未初始化');
    }
    final path = guitarChromaticAssetPath(midi);
    final mode = kIsWeb ? LoadMode.disk : LoadMode.memory;
    final src = await SoLoud.instance.loadAsset(path, mode: mode);
    _cache[midi] = src;
    return src;
  }

  /// 同时起音（短间隔琶音）→ 保持 → 淡出停掉。
  Future<void> playChordMidis(List<int> midis) async {
    if (_busy || midis.isEmpty) return;
    _busy = true;
    const volume = 0.5;
    const stagger = Duration(milliseconds: 40);
    const hold = Duration(milliseconds: 1100);
    const fade = Duration(milliseconds: 280);
    final handles = <SoundHandle>[];
    try {
      for (var i = 0; i < midis.length; i++) {
        final src = await _load(midis[i]);
        final h = await SoLoud.instance.play(src, volume: volume);
        handles.add(h);
        await Future<void>.delayed(stagger);
      }
      await Future<void>.delayed(hold);
      for (final h in handles) {
        SoLoud.instance.fadeVolume(h, 0, fade);
      }
      await Future<void>.delayed(fade);
      for (final h in handles) {
        await SoLoud.instance.stop(h);
      }
    } on Object catch (e, st) {
      debugPrint('EarChordPlayer.playChordMidis: $e\n$st');
    } finally {
      for (final h in handles) {
        try {
          await SoLoud.instance.stop(h);
        } on Object {
          // ignore
        }
      }
      _busy = false;
    }
  }

  /// 依次播放多个和弦，和弦间短暂停顿。
  Future<void> playChordSequence(
    List<List<int>> chords, {
    Duration gap = const Duration(milliseconds: 220),
  }) async {
    for (var i = 0; i < chords.length; i++) {
      await playChordMidis(chords[i]);
      if (i < chords.length - 1) {
        await Future<void>.delayed(gap);
      }
    }
  }

  Future<void> dispose() async {
    for (final src in _cache.values) {
      await SoLoud.instance.disposeSource(src);
    }
    _cache.clear();
  }
}
