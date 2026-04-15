import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'note_math.dart';
import 'pitch_detector.dart';
import 'reference_tone_player.dart';

/// 麦克风采样与基频估计控制器（带简易噪声门控）。
class TunerController extends ChangeNotifier {
  TunerController({
    PitchDetectorConfig detectorConfig = const PitchDetectorConfig(),
  })  : _config = detectorConfig,
        _recorder = AudioRecorder(),
        _referenceTonePlayer = ReferenceTonePlayer();

  final AudioRecorder _recorder;
  final ReferenceTonePlayer _referenceTonePlayer;
  final PitchDetectorConfig _config;

  StreamSubscription<Uint8List>? _sub;
  final List<double> _accumulator = [];

  static const int _sampleRate = 44100;
  static const int _windowSamples = 8192;
  static const int _hopSamples = 4096;

  final Float64List _windowBuffer = Float64List(_windowSamples);
  final Float64List _workBuffer = Float64List(_windowSamples);

  bool _listening = false;
  String? _error;
  double? _frequencyHz;
  double? _smoothedHz;
  String _statusMessage = '点「开始监听」';
  /// 当前选中的弦 0=6弦 E .. 5=1弦 e
  int selectedStringIndex = 0;
  final double _emaAlpha = 0.18;

  bool get isListening => _listening;
  String? get error => _error;
  double? get frequencyHz => _frequencyHz;
  double? get smoothedHz => _smoothedHz;
  String get statusMessage => _statusMessage;
  double get targetHz => guitarOpenStringsHz[selectedStringIndex];

  Future<bool> ensurePermission() async {
    return _recorder.hasPermission(request: true);
  }

  Future<void> start() async {
    if (_listening) return;
    _error = null;
    final ok = await ensurePermission();
    if (!ok) {
      _error = '需要麦克风权限';
      notifyListeners();
      return;
    }

    _accumulator.clear();
    _smoothedHz = null;
    _frequencyHz = null;

    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    _listening = true;
    _statusMessage = '监听中…';
    notifyListeners();

    _sub = stream.listen(
      _onPcm,
      onError: (Object e, StackTrace st) {
        _error = e.toString();
        notifyListeners();
      },
    );
  }

  void _onPcm(Uint8List chunk) {
    final floatScratch = Float64List(chunk.length ~/ 2);
    pcm16LeToFloat(chunk, floatScratch);
    final n = chunk.length ~/ 2;
    for (var i = 0; i < n; i++) {
      _accumulator.add(floatScratch[i]);
    }

    while (_accumulator.length >= _windowSamples) {
      for (var i = 0; i < _windowSamples; i++) {
        _windowBuffer[i] = _accumulator[i];
      }
      _accumulator.removeRange(0, _hopSamples);
      _processWindow();
    }
  }

  void _processWindow() {
    _workBuffer.setRange(0, _windowSamples, _windowBuffer);
    final result = estimatePitch(_workBuffer, _windowSamples, _config);

    switch (result) {
      case PitchFramePitch(:final frequencyHz, :final rms):
        _frequencyHz = frequencyHz;
        final alpha = _emaAlpha;
        _smoothedHz = _smoothedHz == null
            ? frequencyHz
            : _smoothedHz! * (1 - alpha) + frequencyHz * alpha;
        _statusMessage =
            'RMS ${rms.toStringAsFixed(3)} · 已锁定基频';
      case PitchFrameSilent(:final reason):
        _statusMessage = reason;
      case PitchFrameRejected(:final reason):
        _statusMessage = reason;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (_listening) {
      await _recorder.stop();
    }
    _listening = false;
    _statusMessage = '已停止';
    notifyListeners();
  }

  Future<void> setSelectedString(int index, {bool playReferenceTone = true}) async {
    if (index < 0 || index > 5) return;
    selectedStringIndex = index;
    notifyListeners();
    if (playReferenceTone) {
      await _referenceTonePlayer.playOpenString(selectedStringIndex);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    if (_listening) {
      unawaited(_recorder.stop());
    }
    unawaited(_recorder.dispose());
    unawaited(_referenceTonePlayer.dispose());
    super.dispose();
  }
}
