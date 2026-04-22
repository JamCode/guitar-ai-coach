"""Python 复刻的扒歌识别 pipeline，逐行对齐当前 Swift 实现。

对齐对象（`swift_ios_host/Sources/Transcription/Services/`）：
- TranscriptionCQTFeatureExtractor（伪 CQT：每个目标频率只取 1~2 个 FFT bin 线性插值）
- OnnxChordRecognizer.runOnnxModel（20s chunk，分块推理，chunk 偏移合并）
- OnnxChordRecognizer.resampleForChunking
- OnnxChordLabelDecoder.decodeFrames / decodeLabel / classifyChordSuffix / removeShortFrames
- TranscriptionEngine.mergeSegments

不在本版：runDSPFallback（在 ONNX 模型可用时不会走到）。
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import List, Optional

import numpy as np
import onnxruntime as ort


# =============================================================================
# 常量（与 Swift 默认值一致）
# =============================================================================

TARGET_SR = 22_050
HOP_LENGTH = 512
BINS_PER_OCTAVE = 24
NUM_OCTAVES = 6
CHUNK_DURATION_SEC = 20.0
FFT_SIZE = 4_096
C1_HZ = 32.70319566257483

ONNX_THRESHOLD = 0.5
MIN_CHORD_DURATION_MS = 300

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
INTERVAL_SYMBOLS = [
    "1", "b9", "9", "b3", "3", "4", "b5", "5", "b6", "6", "b7", "7",
]


# =============================================================================
# 特征提取（对齐 TranscriptionCQTFeatureExtractor）
# =============================================================================

def make_sample_points(sample_rate=TARGET_SR, fft_size=FFT_SIZE,
                       bpo=BINS_PER_OCTAVE, octaves=NUM_OCTAVES):
    nyquist_idx = fft_size // 2 - 1
    resolution = sample_rate / fft_size
    points = []
    for bin_idx in range(bpo * octaves):
        freq = C1_HZ * (2 ** (bin_idx / bpo))
        exact = max(1.0, min(float(nyquist_idx), freq / resolution))
        lower = int(math.floor(exact))
        upper = min(nyquist_idx, lower + 1)
        weight = float(exact - lower)
        points.append((lower, upper, weight))
    return points


_WINDOW = np.hanning(FFT_SIZE).astype(np.float32)  # 近似 vDSP `.hanningDenormalized`
_SAMPLE_POINTS = make_sample_points()


# -----------------------------------------------------------------------------
# Chunk-level normalization variants (A/B 排查用)
# -----------------------------------------------------------------------------

NORMALIZE_MODES = {
    "peak",           # Swift 现状：x / max(|x|)
    "none",           # 完全不做整段归一化
    "rms",            # RMS 归一化到目标响度 + tanh 软截
    "peak_p99",       # 用第 99 百分位绝对值代替 max，去掉偶发尖峰
    "rms_hardclip",   # RMS 归一化到目标响度 + 硬 clip 到 ±1
}

# 默认跟随 Swift 当前 baseline：以绝对值第 99 百分位归一化 + 钳到 ±1。
# 切回 "peak" 可复现 chunk-norm-p99 合入前的旧基线。
DEFAULT_NORMALIZE_MODE = "peak_p99"

_RMS_TARGET = 0.1


def _normalize_chunk(samples: np.ndarray, mode: str) -> np.ndarray:
    if mode == "none" or samples.size == 0:
        return samples

    if mode == "peak":
        peak = float(np.max(np.abs(samples)))
        if peak <= 0:
            return samples
        return samples / peak

    if mode == "peak_p99":
        abs_x = np.abs(samples)
        if not abs_x.any():
            return samples
        scale = float(np.percentile(abs_x, 99.0))
        if scale <= 0:
            scale = float(abs_x.max())
        if scale <= 0:
            return samples
        return np.clip(samples / scale, -1.0, 1.0).astype(samples.dtype)

    if mode == "rms":
        rms = float(np.sqrt(np.mean(samples.astype(np.float64) ** 2)))
        if rms <= 1e-9:
            return samples
        scaled = samples * (_RMS_TARGET / rms)
        return np.tanh(scaled).astype(samples.dtype)

    if mode == "rms_hardclip":
        rms = float(np.sqrt(np.mean(samples.astype(np.float64) ** 2)))
        if rms <= 1e-9:
            return samples
        scaled = samples * (_RMS_TARGET / rms)
        return np.clip(scaled, -1.0, 1.0).astype(samples.dtype)

    raise ValueError(f"unknown normalize mode: {mode}")


def _pad_or_trim(samples: np.ndarray, length: int) -> np.ndarray:
    if len(samples) == length:
        return samples
    if len(samples) > length:
        return samples[:length]
    out = np.zeros(length, dtype=np.float32)
    out[: len(samples)] = samples
    return out


def extract_chunk(samples: np.ndarray, sample_rate: int = TARGET_SR,
                  normalize_mode: str = DEFAULT_NORMALIZE_MODE) -> np.ndarray:
    """返回 shape 为 [1, 1, binCount, frameCount] 的 float32 张量。"""
    samples = _normalize_chunk(samples.astype(np.float32), normalize_mode)
    samples_per_chunk = int(round(TARGET_SR * CHUNK_DURATION_SEC))
    padded = _pad_or_trim(samples, samples_per_chunk)
    frame_count = int(math.ceil(samples_per_chunk / HOP_LENGTH))
    bin_count = BINS_PER_OCTAVE * NUM_OCTAVES
    out = np.zeros((bin_count, frame_count), dtype=np.float32)

    for frame_idx in range(frame_count):
        start = frame_idx * HOP_LENGTH
        frame = np.zeros(FFT_SIZE, dtype=np.float32)
        avail = min(FFT_SIZE, max(0, len(padded) - start))
        if avail > 0:
            frame[:avail] = padded[start:start + avail]
        spec = np.fft.rfft(frame * _WINDOW)[: FFT_SIZE // 2]
        mags = (np.abs(spec) ** 2).astype(np.float32)  # vDSP_zvmags 返回 |X|^2

        for bin_idx, (lo, hi, w) in enumerate(_SAMPLE_POINTS):
            lower = math.sqrt(max(0.0, float(mags[lo])))
            upper = math.sqrt(max(0.0, float(mags[hi])))
            blended = lower * (1 - w) + upper * w
            out[bin_idx, frame_idx] = math.log1p(blended)

    return out[None, None, :, :]


def frame_duration_ms() -> int:
    return int(round(HOP_LENGTH / TARGET_SR * 1000))


def samples_per_chunk() -> int:
    return int(round(TARGET_SR * CHUNK_DURATION_SEC))


# =============================================================================
# 重采样（对齐 resampleForChunking）
# =============================================================================

def resample_to_22050(samples: np.ndarray, source_sr: float) -> np.ndarray:
    if len(samples) == 0:
        return samples
    if abs(source_sr - TARGET_SR) <= 1:
        return samples.astype(np.float32)
    target_count = max(1, int(round(len(samples) * TARGET_SR / source_sr)))
    max_idx = len(samples) - 1
    out = np.zeros(target_count, dtype=np.float32)
    for i in range(target_count):
        pos = i * source_sr / TARGET_SR
        lo = min(max_idx, int(math.floor(pos)))
        hi = min(max_idx, lo + 1)
        frac = float(pos - lo)
        out[i] = samples[lo] + (samples[hi] - samples[lo]) * frac
    return out


# =============================================================================
# 规则解码（对齐 OnnxChordLabelDecoder）
# =============================================================================

def _matches(intervals: set, required: set, optional: set = frozenset()) -> bool:
    if not required.issubset(intervals):
        return False
    return intervals.difference(required).issubset(optional)


def classify_chord_suffix(intervals: set) -> Optional[str]:
    """逐条按 Swift 代码顺序匹配，保留命中优先级。"""
    if _matches(intervals, {0, 4, 7, 11}, {2}):
        return "maj9" if 2 in intervals else "maj7"
    if _matches(intervals, {0, 4, 7, 10}, {2}):
        return "9" if 2 in intervals else "7"
    if _matches(intervals, {0, 3, 7, 10}, {2}):
        return "m9" if 2 in intervals else "m7"
    if _matches(intervals, {0, 3, 6, 9}):
        return "dim7"
    if _matches(intervals, {0, 3, 6}):
        return "dim"
    if _matches(intervals, {0, 4, 8}):
        return "aug"
    if _matches(intervals, {0, 4, 7, 9}):
        return "6"
    if _matches(intervals, {0, 3, 7, 9}):
        return "m6"
    if _matches(intervals, {0, 5, 7}, {10}):
        return "7sus4" if 10 in intervals else "sus4"
    if _matches(intervals, {0, 2, 7}, {10}):
        return "7sus2" if 10 in intervals else "sus2"
    if _matches(intervals, {0, 4, 7, 2}):
        return "add9"
    if _matches(intervals, {0, 3, 7, 2}):
        return "madd9"
    if _matches(intervals, {0, 4, 7}):
        return ""
    if _matches(intervals, {0, 3, 7}):
        return "m"
    if _matches(intervals, {0, 7}):
        return "5"
    return None


def decode_label(root_idx: int, bass_idx: int, chord_probs: np.ndarray,
                 threshold: float) -> str:
    if root_idx < 0 or root_idx >= 13:
        return "N"
    if bass_idx < 0 or bass_idx >= 13:
        return "N"
    if chord_probs.size != 12:
        return "N"
    if root_idx == 12:
        return "N"

    intervals = {0}
    for abs_i in range(12):
        if chord_probs[abs_i] > threshold:
            rel = (abs_i - root_idx + 12) % 12
            intervals.add(rel)

    if (3 in intervals or 4 in intervals) and 7 not in intervals:
        intervals.add(7)

    # Round 1: 仅当只有 {0,7}（power chord）时，软补三度。
    # 动机：模型对 major/minor 的三度音级 sigmoid 经常刚好不过 0.5，
    # 导致 intervals 只剩 {0,7} 被错误分类为 "5"（Em→E5 / E→E:(1) 等）。
    # 判据：比较 chord_probs[(root+3)%12] 和 chord_probs[(root+4)%12]：
    #   - 胜者 >= SOFT_MIN                 （不低到完全没响应）
    #   - 胜者 >= SOFT_RATIO * 败者        （明显偏向一方，避免真 power chord 被误补）
    # 满足以上两条才补。其它任何情况保留 {0,7} 继续判 "5"。
    SOFT_MIN = 0.15
    SOFT_RATIO = 2.0
    if intervals == {0, 7}:
        b3_score = float(chord_probs[(root_idx + 3) % 12])
        maj3_score = float(chord_probs[(root_idx + 4) % 12])
        winner = max(b3_score, maj3_score)
        loser = min(b3_score, maj3_score)
        if winner >= SOFT_MIN and winner >= SOFT_RATIO * max(loser, 1e-6):
            intervals.add(4 if maj3_score >= b3_score else 3)

    root_name = NOTE_NAMES[root_idx]
    suffix = classify_chord_suffix(intervals)
    if suffix is not None:
        base = root_name + suffix
    else:
        degrees = ",".join(INTERVAL_SYMBOLS[i] for i in sorted(intervals))
        base = f"{root_name}:({degrees})"

    if bass_idx == 12 or bass_idx == root_idx:
        return base
    return f"{base}/{NOTE_NAMES[bass_idx]}"


@dataclass(frozen=True)
class RawChordFrame:
    start_ms: int
    end_ms: int
    chord: str


def _remove_short_frames(frames: List[RawChordFrame], min_duration_ms: int) -> List[RawChordFrame]:
    filtered: List[RawChordFrame] = []
    for frame in frames:
        duration = frame.end_ms - frame.start_ms
        if duration < min_duration_ms:
            if filtered:
                last = filtered[-1]
                filtered[-1] = RawChordFrame(last.start_ms, frame.end_ms, last.chord)
        else:
            filtered.append(frame)
    return filtered


def decode_frames(root_indices: List[int], bass_indices: List[int],
                  chord_probabilities: List[np.ndarray],
                  frame_duration_ms_: int,
                  threshold: float,
                  min_duration_ms: int) -> List[RawChordFrame]:
    if not (len(root_indices) == len(bass_indices) == len(chord_probabilities)):
        return []
    if frame_duration_ms_ <= 0 or not root_indices:
        return []

    merged: List[RawChordFrame] = []
    pending_start = 0
    pending_label = decode_label(root_indices[0], bass_indices[0],
                                 chord_probabilities[0], threshold)

    for i in range(1, len(root_indices)):
        label = decode_label(root_indices[i], bass_indices[i],
                             chord_probabilities[i], threshold)
        if label == pending_label:
            continue
        merged.append(RawChordFrame(
            start_ms=pending_start * frame_duration_ms_,
            end_ms=i * frame_duration_ms_,
            chord=pending_label,
        ))
        pending_start = i
        pending_label = label

    merged.append(RawChordFrame(
        start_ms=pending_start * frame_duration_ms_,
        end_ms=len(root_indices) * frame_duration_ms_,
        chord=pending_label,
    ))

    merged = [f for f in merged if f.chord != "N"]
    return _remove_short_frames(merged, min_duration_ms)


# =============================================================================
# TranscriptionEngine.mergeSegments
# =============================================================================

@dataclass(frozen=True)
class Segment:
    start_ms: int
    end_ms: int
    chord: str


def merge_segments(raw: List[RawChordFrame]) -> List[Segment]:
    if not raw:
        return []
    current = raw[0]
    out: List[Segment] = []
    for frame in raw[1:]:
        if frame.chord == current.chord and frame.start_ms == current.end_ms:
            current = RawChordFrame(current.start_ms, frame.end_ms, current.chord)
        else:
            out.append(Segment(current.start_ms, current.end_ms, current.chord))
            current = frame
    out.append(Segment(current.start_ms, current.end_ms, current.chord))
    return out


# =============================================================================
# ONNX runner
# =============================================================================

def _argmax_indices(logits_2d: np.ndarray) -> List[int]:
    return logits_2d.argmax(axis=-1).astype(int).tolist()


def _sigmoid(x: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-x))


def run_onnx(session: ort.InferenceSession, samples: np.ndarray,
             source_sr: float,
             normalize_mode: str = DEFAULT_NORMALIZE_MODE) -> List[RawChordFrame]:
    normalized = resample_to_22050(samples, source_sr)
    if len(normalized) == 0:
        return []

    spc = samples_per_chunk()
    total_duration_ms = int(round(len(normalized) / TARGET_SR * 1000))
    chunk_count = max(1, int(math.ceil(len(normalized) / spc)))
    all_frames: List[RawChordFrame] = []

    input_name = session.get_inputs()[0].name
    fdm = frame_duration_ms()

    for chunk_idx in range(chunk_count):
        start = chunk_idx * spc
        end = min(len(normalized), start + spc)
        chunk = normalized[start:end]
        actual_duration_ms = min(
            int(round(len(chunk) / TARGET_SR * 1000)),
            max(0, total_duration_ms - int(round(start / TARGET_SR * 1000))),
        )
        if actual_duration_ms <= 0:
            continue

        feat = extract_chunk(chunk, TARGET_SR,
                             normalize_mode=normalize_mode).astype(np.float32)
        out = session.run(
            ["root_logits", "bass_logits", "chord_logits"],
            {input_name: feat},
        )
        root_logits = out[0][0]   # (T, 13)
        bass_logits = out[1][0]   # (T, 13)
        chord_logits = out[2][0]  # (T, 12)

        frame_count = min(
            root_logits.shape[0],
            bass_logits.shape[0],
            chord_logits.shape[0],
            max(1, int(math.ceil(actual_duration_ms / fdm))),
        )
        if frame_count <= 0:
            continue

        chord_probs = _sigmoid(chord_logits[:frame_count])
        root_idx = _argmax_indices(root_logits[:frame_count])
        bass_idx = _argmax_indices(bass_logits[:frame_count])
        probs_per_frame = [chord_probs[i] for i in range(frame_count)]

        decoded = decode_frames(
            root_indices=root_idx,
            bass_indices=bass_idx,
            chord_probabilities=probs_per_frame,
            frame_duration_ms_=fdm,
            threshold=ONNX_THRESHOLD,
            min_duration_ms=MIN_CHORD_DURATION_MS,
        )

        chunk_start_ms = int(round(start / TARGET_SR * 1000))
        chunk_end_ms = chunk_start_ms + actual_duration_ms
        for f in decoded:
            if f.start_ms >= actual_duration_ms:
                continue
            all_frames.append(RawChordFrame(
                start_ms=chunk_start_ms + f.start_ms,
                end_ms=min(chunk_end_ms, chunk_start_ms + f.end_ms),
                chord=f.chord,
            ))

    return [f for f in all_frames if f.end_ms > f.start_ms]


def detect_original_key(frames: List[RawChordFrame]) -> str:
    duration_by_root = {}
    for f in frames:
        root = _chord_root(f.chord)
        duration_by_root[root] = duration_by_root.get(root, 0) + max(1, f.end_ms - f.start_ms)
    if not duration_by_root:
        return "C"
    return max(duration_by_root.items(), key=lambda kv: kv[1])[0]


def _chord_root(chord: str) -> str:
    flats = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"}
    for root in ["C#", "D#", "F#", "G#", "A#", "Db", "Eb", "Gb", "Ab", "Bb",
                 "C", "D", "E", "F", "G", "A", "B"]:
        if chord.startswith(root):
            return flats.get(root, root)
    return "C"


# =============================================================================
# 对外接口
# =============================================================================

def recognize(session: ort.InferenceSession, samples: np.ndarray,
              source_sr: float,
              normalize_mode: str = DEFAULT_NORMALIZE_MODE):
    raw = run_onnx(session, samples, source_sr, normalize_mode=normalize_mode)
    if not raw:
        return {
            "segments": [],
            "original_key": "C",
            "raw_frame_count": 0,
        }
    segments = merge_segments(raw)
    return {
        "segments": [s.__dict__ for s in segments],
        "original_key": detect_original_key(raw),
        "raw_frame_count": len(raw),
    }
