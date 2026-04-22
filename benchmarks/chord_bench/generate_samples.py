"""chord_bench v1 样本生成器。

输出：
- benchmarks/chord_bench/samples/*.wav （PCM16, 22050Hz, mono）
- benchmarks/chord_bench/samples/ground_truth.json

设计原则：
- 第一版只做 major / minor，覆盖常见流行和弦进行。
- 所有随机种子固定，保证可复现。
- 每个样本自带 ground truth（单音/单和弦/时间段级）。
"""

from __future__ import annotations

import json
import math
import os
from dataclasses import dataclass, asdict
from typing import List

import numpy as np
import soundfile as sf


SR = 22_050
SAMPLES_DIR = os.path.join(os.path.dirname(__file__), "samples")


@dataclass
class ChordSpec:
    root: str  # 如 "C" / "A"
    quality: str  # "maj" / "min"

    @property
    def label(self) -> str:
        return self.root + ("m" if self.quality == "min" else "")


@dataclass
class SegmentGT:
    start_ms: int
    end_ms: int
    chord_label: str


@dataclass
class TestCase:
    id: str
    category: str  # "single_note" | "triad" | "progression" | "interference"
    filename: str
    sample_rate: int
    duration_ms: int
    expected_single_label: str  # 用于"单音/单和弦/干扰（底层就是一个和弦）"；时间线场景留空
    segments: List[SegmentGT]  # 时间线场景；单标签场景可空
    notes: str = ""  # 说明（生成参数、难度等）


# -----------------------------------------------------------------------------
# 合成工具
# -----------------------------------------------------------------------------

NOTE_NAMES_SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def note_to_midi(name: str, octave: int) -> int:
    return 12 * (octave + 1) + NOTE_NAMES_SHARP.index(name)


def midi_to_freq(midi: int) -> float:
    return 440.0 * (2 ** ((midi - 69) / 12))


def adsr_envelope(length: int, attack_ms=15, release_ms=150) -> np.ndarray:
    env = np.ones(length, dtype=np.float32)
    a = int(SR * attack_ms / 1000)
    r = int(SR * release_ms / 1000)
    if a > 0 and a < length:
        env[:a] = np.linspace(0, 1, a)
    if r > 0 and r < length:
        env[-r:] = np.linspace(1, 0, r)
    return env


def synth_tone(freq: float, duration_ms: int,
               n_harmonics: int = 6,
               harmonic_decay: float = 1.2,
               seed: int = 0) -> np.ndarray:
    """谐波合成的单音，模拟弦乐器；每次同样的 (freq, seed) 得到完全相同的波形。"""
    rng = np.random.RandomState(seed)
    length = int(SR * duration_ms / 1000)
    t = np.arange(length) / SR
    sig = np.zeros(length, dtype=np.float32)
    for k in range(1, n_harmonics + 1):
        amp = 1.0 / (k ** harmonic_decay)
        phase = rng.uniform(0, 2 * math.pi)
        sig += amp * np.sin(2 * math.pi * freq * k * t + phase)
    sig *= adsr_envelope(length)
    peak = float(np.max(np.abs(sig)))
    if peak > 0:
        sig /= peak
    return (sig * 0.5).astype(np.float32)


def chord_midi_notes(root: str, quality: str, base_octave: int = 3) -> List[int]:
    """返回一个接近开放指法的 triad 音符集合（MIDI）。"""
    root_midi = note_to_midi(root, base_octave)
    if quality == "maj":
        intervals = [0, 4, 7, 12, 16]  # R,3,5,R(+1),3(+1)
    else:
        intervals = [0, 3, 7, 12, 15]
    return [root_midi + i for i in intervals]


def synth_chord(spec: ChordSpec, duration_ms: int, seed: int = 0) -> np.ndarray:
    midi_notes = chord_midi_notes(spec.root, spec.quality)
    length = int(SR * duration_ms / 1000)
    sig = np.zeros(length, dtype=np.float32)
    for idx, m in enumerate(midi_notes):
        freq = midi_to_freq(m)
        tone = synth_tone(freq, duration_ms, seed=seed + idx)
        sig += tone
    peak = float(np.max(np.abs(sig)))
    if peak > 0:
        sig /= peak
    return (sig * 0.5).astype(np.float32)


def concatenate(blocks: List[np.ndarray], crossfade_ms: int = 20) -> np.ndarray:
    """串联若干段，段间做短 crossfade 避免咔嚓声。"""
    if not blocks:
        return np.zeros(0, dtype=np.float32)
    xf = int(SR * crossfade_ms / 1000)
    out = blocks[0]
    for nxt in blocks[1:]:
        if xf > 0 and len(out) > xf and len(nxt) > xf:
            fade_out = out[-xf:] * np.linspace(1, 0, xf)
            fade_in = nxt[:xf] * np.linspace(0, 1, xf)
            mixed = fade_out + fade_in
            out = np.concatenate([out[:-xf], mixed, nxt[xf:]])
        else:
            out = np.concatenate([out, nxt])
    return out


def mix(signal: np.ndarray, extra: np.ndarray, level: float) -> np.ndarray:
    n = min(len(signal), len(extra))
    out = signal[:n].copy()
    out += (extra[:n] * level).astype(np.float32)
    peak = float(np.max(np.abs(out)))
    if peak > 0:
        out /= peak
    return (out * 0.5).astype(np.float32)


def white_noise(duration_ms: int, seed: int = 42) -> np.ndarray:
    rng = np.random.RandomState(seed)
    return rng.standard_normal(int(SR * duration_ms / 1000)).astype(np.float32)


def low_frequency_rumble(duration_ms: int, seed: int = 7) -> np.ndarray:
    rng = np.random.RandomState(seed)
    n = int(SR * duration_ms / 1000)
    noise = rng.standard_normal(n).astype(np.float32)
    out = np.zeros_like(noise)
    for i in range(1, n):
        out[i] = 0.995 * out[i - 1] + 0.005 * noise[i]  # 很陡的低通
    peak = float(np.max(np.abs(out)))
    if peak > 0:
        out /= peak
    return out


def melody_line(duration_ms: int, notes_midi: List[int], seed: int = 11) -> np.ndarray:
    """把一串音做成简单旋律（每个 step 等长）。"""
    if not notes_midi:
        return np.zeros(int(SR * duration_ms / 1000), dtype=np.float32)
    step_ms = duration_ms // len(notes_midi)
    blocks = [
        synth_tone(midi_to_freq(m), step_ms, n_harmonics=3,
                   harmonic_decay=1.5, seed=seed + i)
        for i, m in enumerate(notes_midi)
    ]
    out = concatenate(blocks)
    total = int(SR * duration_ms / 1000)
    if len(out) > total:
        out = out[:total]
    elif len(out) < total:
        pad = np.zeros(total - len(out), dtype=np.float32)
        out = np.concatenate([out, pad])
    return out


def voice_band_interference(duration_ms: int, seed: int = 19) -> np.ndarray:
    """简单模拟人声频段：150~3000Hz 之间几个带噪的共振峰。"""
    rng = np.random.RandomState(seed)
    length = int(SR * duration_ms / 1000)
    t = np.arange(length) / SR
    sig = np.zeros(length, dtype=np.float32)
    # 三个类似 vowel 的 formant（主频 + 少量 FM）
    for base_f, weight in [(300, 1.0), (900, 0.6), (2300, 0.3)]:
        fm = 2 * math.pi * rng.uniform(3, 7)
        mod = 0.02 * np.sin(fm * t)
        sig += weight * np.sin(2 * math.pi * base_f * (t + mod) + rng.uniform(0, math.pi))
    sig *= adsr_envelope(length, attack_ms=40, release_ms=250)
    peak = float(np.max(np.abs(sig)))
    if peak > 0:
        sig /= peak
    return sig.astype(np.float32)


# -----------------------------------------------------------------------------
# 保存
# -----------------------------------------------------------------------------

def save_wav(samples: np.ndarray, path: str) -> int:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = np.clip(samples, -1.0, 1.0)
    sf.write(path, pcm, SR, subtype="PCM_16")
    return int(round(len(samples) / SR * 1000))


# -----------------------------------------------------------------------------
# 测试集定义
# -----------------------------------------------------------------------------

# 1. 单音（12 个半音，C4~B4）
SINGLE_NOTE_SPECS = [
    ("C", 4), ("C#", 4), ("D", 4), ("D#", 4),
    ("E", 4), ("F", 4), ("F#", 4), ("G", 4),
    ("G#", 4), ("A", 4), ("A#", 4), ("B", 4),
]

# 2. 三和弦（12 个）
TRIAD_SPECS = [
    ("C", "maj"), ("G", "maj"), ("F", "maj"), ("D", "maj"),
    ("A", "maj"), ("E", "maj"),
    ("A", "min"), ("E", "min"), ("D", "min"),
    ("B", "min"), ("C", "min"), ("G", "min"),
]

# 3. 和弦进行（12 个）—— 每个 4 个和弦，每段 2000ms
PROGRESSION_SPECS = [
    ("C-G-Am-F",    [("C", "maj"), ("G", "maj"), ("A", "min"), ("F", "maj")]),
    ("G-D-Em-C",    [("G", "maj"), ("D", "maj"), ("E", "min"), ("C", "maj")]),
    ("Am-F-C-G",    [("A", "min"), ("F", "maj"), ("C", "maj"), ("G", "maj")]),
    ("D-A-Bm-G",    [("D", "maj"), ("A", "maj"), ("B", "min"), ("G", "maj")]),
    ("Em-C-G-D",    [("E", "min"), ("C", "maj"), ("G", "maj"), ("D", "maj")]),
    ("F-C-Dm-Am",   [("F", "maj"), ("C", "maj"), ("D", "min"), ("A", "min")]),
    ("C-Am-F-G",    [("C", "maj"), ("A", "min"), ("F", "maj"), ("G", "maj")]),
    ("G-Em-C-D",    [("G", "maj"), ("E", "min"), ("C", "maj"), ("D", "maj")]),
    ("Am-G-F-E",    [("A", "min"), ("G", "maj"), ("F", "maj"), ("E", "maj")]),
    ("C-F-G-C",     [("C", "maj"), ("F", "maj"), ("G", "maj"), ("C", "maj")]),
    ("Dm-G-C-F",    [("D", "min"), ("G", "maj"), ("C", "maj"), ("F", "maj")]),
    ("Em-Am-D-G",   [("E", "min"), ("A", "min"), ("D", "maj"), ("G", "maj")]),
]

PROG_SEG_MS = 2000  # 每个进行里每段时长
PROG_CROSSFADE_MS = 20


# -----------------------------------------------------------------------------
# 生成逻辑
# -----------------------------------------------------------------------------

def _progression_segments(seq):
    segs = []
    cursor = 0
    for i, (root, quality) in enumerate(seq):
        start = cursor
        end = cursor + PROG_SEG_MS
        segs.append(SegmentGT(
            start_ms=start,
            end_ms=end,
            chord_label=root + ("m" if quality == "min" else ""),
        ))
        cursor = end
    return segs


def _synth_progression(seq, seed: int = 0) -> np.ndarray:
    blocks = []
    for i, (root, quality) in enumerate(seq):
        spec = ChordSpec(root=root, quality=quality)
        blocks.append(synth_chord(spec, PROG_SEG_MS, seed=seed + i * 13))
    return concatenate(blocks, crossfade_ms=PROG_CROSSFADE_MS)


def _save_case(case: TestCase, audio: np.ndarray):
    wav_path = os.path.join(SAMPLES_DIR, case.filename)
    case.duration_ms = save_wav(audio, wav_path)


def build_cases() -> List[TestCase]:
    cases: List[TestCase] = []

    # 1) 单音
    for name, octave in SINGLE_NOTE_SPECS:
        midi = note_to_midi(name, octave)
        audio = synth_tone(midi_to_freq(midi), duration_ms=2500, seed=101)
        cid = f"single-{name.replace('#','s')}{octave}"
        case = TestCase(
            id=cid, category="single_note",
            filename=f"{cid}.wav",
            sample_rate=SR, duration_ms=0,
            expected_single_label=name,  # 单音的期望 root
            segments=[],
            notes=f"harmonic tone {name}{octave}, 6 harmonics",
        )
        _save_case(case, audio)
        cases.append(case)

    # 2) 三和弦
    for root, quality in TRIAD_SPECS:
        spec = ChordSpec(root=root, quality=quality)
        audio = synth_chord(spec, duration_ms=3500, seed=203)
        cid = f"triad-{spec.label.replace('#','s')}"
        case = TestCase(
            id=cid, category="triad",
            filename=f"{cid}.wav",
            sample_rate=SR, duration_ms=0,
            expected_single_label=spec.label,
            segments=[],
            notes=f"triad {spec.label}",
        )
        _save_case(case, audio)
        cases.append(case)

    # 3) 和弦进行
    for label, seq in PROGRESSION_SPECS:
        audio = _synth_progression(seq, seed=307)
        cid = f"prog-{label.replace('#','s')}"
        case = TestCase(
            id=cid, category="progression",
            filename=f"{cid}.wav",
            sample_rate=SR, duration_ms=0,
            expected_single_label="",
            segments=_progression_segments(seq),
            notes=f"{label}, each {PROG_SEG_MS}ms, xf {PROG_CROSSFADE_MS}ms",
        )
        _save_case(case, audio)
        cases.append(case)

    # 4) 干扰测试（12 个）—— 复用前面的和弦/进行
    # 组合一：triad + 白噪声 (3)
    for idx, (root, quality) in enumerate([("C", "maj"), ("A", "min"), ("G", "maj")]):
        spec = ChordSpec(root=root, quality=quality)
        base = synth_chord(spec, duration_ms=3500, seed=401)
        noise = white_noise(3500, seed=400 + idx)
        audio = mix(base, noise, level=0.25)
        cid = f"intf-noise-{spec.label.replace('#','s')}"
        case = TestCase(
            id=cid, category="interference",
            filename=f"{cid}.wav",
            sample_rate=SR, duration_ms=0,
            expected_single_label=spec.label,
            segments=[],
            notes=f"triad {spec.label} + white noise @0.25",
        )
        _save_case(case, audio)
        cases.append(case)

    # 组合二：triad + 低频 rumble (3)
    for idx, (root, quality) in enumerate([("F", "maj"), ("E", "min"), ("D", "maj")]):
        spec = ChordSpec(root=root, quality=quality)
        base = synth_chord(spec, duration_ms=3500, seed=501)
        rumble = low_frequency_rumble(3500, seed=500 + idx)
        audio = mix(base, rumble, level=0.45)
        cid = f"intf-rumble-{spec.label.replace('#','s')}"
        case = TestCase(
            id=cid, category="interference",
            filename=f"{cid}.wav",
            sample_rate=SR, duration_ms=0,
            expected_single_label=spec.label,
            segments=[],
            notes=f"triad {spec.label} + low-freq rumble @0.45",
        )
        _save_case(case, audio)
        cases.append(case)

    # 组合三：triad + 旋律线 (3)
    melody_phrases = [
        [note_to_midi("E", 5), note_to_midi("D", 5), note_to_midi("C", 5), note_to_midi("D", 5)],
        [note_to_midi("A", 4), note_to_midi("G", 4), note_to_midi("E", 4), note_to_midi("G", 4)],
        [note_to_midi("B", 4), note_to_midi("A", 4), note_to_midi("G", 4), note_to_midi("A", 4)],
    ]
    for idx, ((root, quality), phrase) in enumerate(zip(
        [("C", "maj"), ("A", "min"), ("G", "maj")],
        melody_phrases,
    )):
        spec = ChordSpec(root=root, quality=quality)
        base = synth_chord(spec, duration_ms=3500, seed=601)
        mel = melody_line(3500, phrase, seed=600 + idx)
        audio = mix(base, mel, level=0.35)
        cid = f"intf-melody-{spec.label.replace('#','s')}"
        case = TestCase(
            id=cid, category="interference",
            filename=f"{cid}.wav",
            sample_rate=SR, duration_ms=0,
            expected_single_label=spec.label,
            segments=[],
            notes=f"triad {spec.label} + melody line @0.35",
        )
        _save_case(case, audio)
        cases.append(case)

    # 组合四：triad + 人声频段干扰 (3)
    for idx, (root, quality) in enumerate([("D", "min"), ("B", "min"), ("F", "maj")]):
        spec = ChordSpec(root=root, quality=quality)
        base = synth_chord(spec, duration_ms=3500, seed=701)
        voice = voice_band_interference(3500, seed=700 + idx)
        audio = mix(base, voice, level=0.35)
        cid = f"intf-voice-{spec.label.replace('#','s')}"
        case = TestCase(
            id=cid, category="interference",
            filename=f"{cid}.wav",
            sample_rate=SR, duration_ms=0,
            expected_single_label=spec.label,
            segments=[],
            notes=f"triad {spec.label} + voice-band interference @0.35",
        )
        _save_case(case, audio)
        cases.append(case)

    return cases


def main():
    os.makedirs(SAMPLES_DIR, exist_ok=True)
    cases = build_cases()
    ground_truth = {
        "sample_rate": SR,
        "cases": [
            {
                **{k: v for k, v in asdict(c).items() if k != "segments"},
                "segments": [asdict(s) for s in c.segments],
            }
            for c in cases
        ],
    }
    gt_path = os.path.join(SAMPLES_DIR, "ground_truth.json")
    with open(gt_path, "w") as f:
        json.dump(ground_truth, f, indent=2, ensure_ascii=False)

    by_cat: dict = {}
    for c in cases:
        by_cat[c.category] = by_cat.get(c.category, 0) + 1
    print("Generated", len(cases), "cases:")
    for k, v in by_cat.items():
        print(f"  - {k}: {v}")
    print("Ground truth:", gt_path)


if __name__ == "__main__":
    main()
