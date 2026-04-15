import 'dart:math' as math;
import 'dart:typed_data';

/// 调音器用的基频估计：归一化自相关 peak + RMS/峰峭度门控，削弱环境稳态噪声。
class PitchDetectorConfig {
  const PitchDetectorConfig({
    this.sampleRate = 44100,
    this.minRms = 0.018,
    this.minFrequency = 70,
    this.maxFrequency = 420,
    this.minPeakCorrelation = 0.34,
    this.minPeakToMedianRatio = 1.35,
  });

  final int sampleRate;
  /// 波形在 [-1,1] 下，低于则认为「太安静」不更新。
  final double minRms;
  /// 吉他空弦基频搜索下界（Hz）。
  final double minFrequency;
  /// 吉他空弦基频搜索上界（Hz），略留余量。
  final double maxFrequency;
  /// 归一化自相关系数峰值下限，过低多为噪声或非周期声。
  final double minPeakCorrelation;
  /// 峰值相对中游的自相关分布要够突出，否则容易跟错峰。
  final double minPeakToMedianRatio;
}

/// 单帧检测结果。
sealed class PitchFrameResult {}

/// 通过门控且无有效周期（可显示「等待弹奏」）。
final class PitchFrameSilent extends PitchFrameResult {
  PitchFrameSilent(this.reason);
  final String reason;
}

/// 能量够但被门控掉（杂音/非弦乐倾向）。
final class PitchFrameRejected extends PitchFrameResult {
  PitchFrameRejected(this.reason);
  final String reason;
}

/// 有效基频（Hz）。
final class PitchFramePitch extends PitchFrameResult {
  PitchFramePitch({
    required this.frequencyHz,
    required this.peakCorrelation,
    required this.rms,
  });
  final double frequencyHz;
  final double peakCorrelation;
  final double rms;
}

/// 将 PCM16 小端字节转为 [-1,1] double。
void pcm16LeToFloat(Uint8List bytes, Float64List out) {
  final n = math.min(bytes.length ~/ 2, out.length);
  for (var i = 0; i < n; i++) {
    final lo = bytes[i * 2];
    final hi = bytes[i * 2 + 1];
    var v = lo | (hi << 8);
    if (v & 0x8000 != 0) v = v - 0x10000;
    out[i] = v / 32768.0;
  }
}

/// 对一帧 PCM（已在 [-1,1]）做去直流 + 归一化自相关，在 [minFrequency,maxFrequency] 内找主峰。
PitchFrameResult estimatePitch(
  Float64List samples,
  int length,
  PitchDetectorConfig cfg,
) {
  if (length < 1024) {
    return PitchFrameSilent('缓冲过短');
  }

  var sum = 0.0;
  for (var i = 0; i < length; i++) {
    sum += samples[i];
  }
  final mean = sum / length;

  var energy = 0.0;
  for (var i = 0; i < length; i++) {
    final x = samples[i] - mean;
    samples[i] = x;
    energy += x * x;
  }

  if (energy <= 1e-18) {
    return PitchFrameSilent('无能量');
  }

  final rms = math.sqrt(energy / length);
  if (rms < cfg.minRms) {
    return PitchFrameSilent('音量过低');
  }

  final minLag = math.max(2, (cfg.sampleRate / cfg.maxFrequency).floor());
  final maxLag = math.min(
    length ~/ 2 - 1,
    (cfg.sampleRate / cfg.minFrequency).ceil(),
  );
  if (minLag >= maxLag) {
    return PitchFrameRejected('滞后范围无效');
  }

  var bestCorr = -double.infinity;
  var bestLag = minLag;
  final corrs = Float64List(maxLag - minLag + 1);

  var idx = 0;
  for (var lag = minLag; lag <= maxLag; lag++) {
    var c = 0.0;
    final limit = length - lag;
    for (var i = 0; i < limit; i++) {
      c += samples[i] * samples[i + lag];
    }
    final norm = c / energy;
    corrs[idx++] = norm;
    if (norm > bestCorr) {
      bestCorr = norm;
      bestLag = lag;
    }
  }

  corrs.sort();
  final medianCorr = corrs[corrs.length ~/ 2];
  if (bestCorr < cfg.minPeakCorrelation) {
    return PitchFrameRejected('周期性不足');
  }
  if (medianCorr > 1e-6 && bestCorr < medianCorr * cfg.minPeakToMedianRatio) {
    return PitchFrameRejected('峰值不突出');
  }

  final refinedLag = _parabolicRefineLag(
    samples,
    length,
    energy,
    bestLag,
    minLag,
    maxLag,
  );
  final hz = cfg.sampleRate / refinedLag;
  if (hz < cfg.minFrequency || hz > cfg.maxFrequency) {
    return PitchFrameRejected('频率越界');
  }

  return PitchFramePitch(
    frequencyHz: hz,
    peakCorrelation: bestCorr,
    rms: rms,
  );
}

double _correlationAtLag(
  Float64List x,
  int length,
  double energy,
  int lag,
) {
  if (lag < 1 || lag >= length) return 0;
  var c = 0.0;
  final limit = length - lag;
  for (var i = 0; i < limit; i++) {
    c += x[i] * x[i + lag];
  }
  return c / energy;
}

double _parabolicRefineLag(
  Float64List x,
  int length,
  double energy,
  int peakLag,
  int minLag,
  int maxLag,
) {
  final y0 = peakLag > minLag
      ? _correlationAtLag(x, length, energy, peakLag - 1)
      : 0.0;
  final y1 = _correlationAtLag(x, length, energy, peakLag);
  final y2 = peakLag < maxLag
      ? _correlationAtLag(x, length, energy, peakLag + 1)
      : 0.0;
  final a = (y0 + y2) / 2 - y1;
  final b = (y2 - y0) / 2;
  if (a.abs() < 1e-8) return peakLag.toDouble();
  final delta = (-b / (2 * a)).clamp(-0.5, 0.5);
  return peakLag + delta;
}
