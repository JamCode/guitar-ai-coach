import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'live_chord_models.dart';
import 'live_chord_platform_repository.dart';
import 'live_chord_state_machine.dart';

/// 抽象音频源，便于测试替换。
abstract class LiveAudioSource {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startStream({required int sampleRate});
  Future<void> stop();
  Future<void> dispose();
}

class RecordLiveAudioSource implements LiveAudioSource {
  RecordLiveAudioSource() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission(request: true);

  @override
  Future<Stream<Uint8List>> startStream({required int sampleRate}) {
    return _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
  }

  @override
  Future<void> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// 管理实时识别会话：采样、通道调用、状态机更新。
class LiveChordController extends ChangeNotifier {
  LiveChordController({
    LiveChordPlatformRepository? repository,
    LiveAudioSource? audioSource,
    LiveChordStateMachine? stateMachine,
  })  : _repository = repository ?? MethodChannelLiveChordRepository(),
        _audioSource = audioSource ?? RecordLiveAudioSource(),
        _stateMachine = stateMachine ?? LiveChordStateMachine();

  static const int _sampleRate = 16000;
  static const double _windowSec = 2.0;
  static const double _hopSec = 0.5;

  final LiveChordPlatformRepository _repository;
  final LiveAudioSource _audioSource;
  final LiveChordStateMachine _stateMachine;

  LiveChordUiState _state = LiveChordUiState.initial();
  LiveChordUiState get state => _state;

  StreamSubscription<Uint8List>? _sub;
  bool _processing = false;

  Future<void> start() async {
    if (_state.isListening) return;
    _state = _state.copyWith(status: '请求麦克风权限…', clearError: true);
    notifyListeners();

    final ok = await _audioSource.hasPermission();
    if (!ok) {
      _state = _state.copyWith(
        isListening: false,
        status: '需要麦克风权限',
        error: '需要麦克风权限',
      );
      notifyListeners();
      return;
    }

    try {
      await _repository.initialize(
        sampleRate: _sampleRate,
        windowSec: _windowSec,
        hopSec: _hopSec,
        mode: _state.mode,
        confidenceThreshold: 0.6,
      );
      final stream = await _audioSource.startStream(sampleRate: _sampleRate);
      _stateMachine.reset();
      _state = _state.copyWith(
        isListening: true,
        status: '🎵 Listening…',
        clearError: true,
      );
      notifyListeners();
      _sub = stream.listen(
        _onChunk,
        onError: (Object e, StackTrace st) {
          _state = _state.copyWith(
            isListening: false,
            status: '采样错误',
            error: e.toString(),
          );
          notifyListeners();
        },
      );
    } catch (e) {
      _state = _state.copyWith(
        isListening: false,
        status: '初始化失败',
        error: e.toString(),
      );
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _audioSource.stop();
    await _repository.reset();
    _stateMachine.reset();
    _state = _state.copyWith(
      isListening: false,
      status: '已暂停',
      stableChord: 'Unknown',
      confidence: 0,
    );
    notifyListeners();
  }

  Future<void> setMode(LiveChordMode mode) async {
    if (_state.mode == mode) return;
    _state = _state.copyWith(mode: mode);
    notifyListeners();
    if (_state.isListening) {
      await _repository.initialize(
        sampleRate: _sampleRate,
        windowSec: _windowSec,
        hopSec: _hopSec,
        mode: mode,
        confidenceThreshold: 0.6,
      );
      await _repository.reset();
      _stateMachine.reset();
    }
  }

  Future<void> _onChunk(Uint8List chunk) async {
    if (!_state.isListening || _processing) return;
    _processing = true;
    try {
      final frame = await _repository.processChunk(chunk);
      _state = _stateMachine.applyFrame(_state, frame);
    } catch (e) {
      _state = _state.copyWith(
        status: 'No clear chord detected',
        error: e.toString(),
      );
    } finally {
      _processing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_audioSource.stop());
    unawaited(_audioSource.dispose());
    unawaited(_repository.dispose());
    super.dispose();
  }
}
