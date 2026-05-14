from __future__ import annotations

import shutil
import subprocess
import tempfile
import uuid
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import librosa
import numpy as np

from chord_chart_postprocess import build_chord_chart_segments
from playable_compact_postprocess import build_playable_compact_segments
from timing_compact_postprocess import build_timing_compact_segments

_ENABLE_LLM_REFINE = os.getenv("CHORD_REFINE_WITH_LLM", "").strip().lower() in {"1", "true", "yes"}


NOTE_NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
TARGET_SR = 22050
CHROMA_HOP_LENGTH = 512
CHROMA_N_CHROMA = 12

# Chord quality templates (relative to root, 12 semitones) - weighted profiles
# Root strong, 5th moderate, 3rd lighter, 7th lightest - reflects acoustic reality
CHORD_QUALITY_TEMPLATES: dict[str, list[float]] = {
    '':    [1.0, 0.0, 0.0, 0.0, 0.6, 0.0, 0.0, 0.8, 0.0, 0.0, 0.0, 0.0],  # major
    'm':   [1.0, 0.0, 0.0, 0.6, 0.0, 0.0, 0.0, 0.8, 0.0, 0.0, 0.0, 0.0],  # minor
    '7':   [1.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.7, 0.0, 0.0, 0.5, 0.0],  # dominant 7th
    'm7':  [1.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.7, 0.0, 0.0, 0.5, 0.0],  # minor 7th
    'maj7': [1.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.7, 0.0, 0.0, 0.0, 0.5],# major 7th
    'dim':  [1.0, 0.0, 0.0, 0.7, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0],  # diminished
    'aug':  [1.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.6, 0.0, 0.0, 0.0],  # augmented
    'sus4': [1.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.0, 0.8, 0.0, 0.0, 0.0, 0.0],  # sus4
    'sus2': [1.0, 0.0, 0.6, 0.0, 0.0, 0.0, 0.0, 0.8, 0.0, 0.0, 0.0, 0.0],  # sus2
    '5':    [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 0.0, 0.0, 0.0, 0.0],  # power chord
}

MAJOR_KEY_CHORDS: dict[str, list[str]] = {
    'C':  ['C', 'Dm', 'Em', 'F', 'G', 'G7', 'Am'],
    'C#': ['C#', 'D#m', 'Fm', 'F#', 'G#', 'G#7', 'A#m'],
    'Db': ['Db', 'Ebm', 'Fm', 'Gb', 'Ab', 'Ab7', 'Bbm'],
    'D':  ['D', 'Em', 'F#m', 'G', 'A', 'A7', 'Bm'],
    'Eb': ['Eb', 'Fm', 'Gm', 'Ab', 'Bb', 'Bb7', 'Cm'],
    'E':  ['E', 'F#m', 'G#m', 'A', 'B', 'B7', 'C#m'],
    'F':  ['F', 'Gm', 'Am', 'Bb', 'C', 'C7', 'Dm'],
    'F#': ['F#', 'G#m', 'A#m', 'B', 'C#', 'C#7', 'D#m'],
    'Gb': ['Gb', 'Abm', 'Bbm', 'Cb', 'Db', 'Db7', 'Ebm'],
    'G':  ['G', 'Am', 'Bm', 'C', 'D', 'D7', 'Em'],
    'G#': ['G#', 'A#m', 'Cm', 'C#', 'D#', 'D#7', 'Fm'],
    'Ab': ['Ab', 'Bbm', 'Cm', 'Db', 'Eb', 'Eb7', 'Fm'],
    'A':  ['A', 'Bm', 'C#m', 'D', 'E', 'E7', 'F#m'],
    'Bb': ['Bb', 'Cm', 'Dm', 'Eb', 'F', 'F7', 'Gm'],
    'B':  ['B', 'C#m', 'Ebm', 'E', 'F#', 'F#7', 'G#m'],
    'Cb': ['Cb', 'Dbm', 'Ebm', 'Fb', 'Gb', 'Gb7', 'Abm'],
}

# Default fallback state space (C major diatonic)
DEFAULT_STATES = ['C', 'Dm', 'Em', 'F', 'G', 'G7', 'Am', 'Bdim']

RELATIVE_MAJOR: dict[str, str] = {
    'Am': 'C', 'Em': 'G', 'Bm': 'D', 'F#m': 'A', 'C#m': 'E',
    'Dm': 'F', 'Gm': 'Bb', 'Cm': 'Eb', 'Fm': 'Ab', 'Bbm': 'Db',
}

# Post-process constants (kept for backward compat with reused methods)
DISPLAY_KEEP_DOMINANT7_MIN_SEC = 2.4


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def _decode_to_temp_wav_with_ffmpeg(src: Path) -> Path:
    """Decode arbitrary container/codec to 22050 Hz mono WAV for librosa."""
    if not ffmpeg_available():
        raise RuntimeError("ffmpeg not found on PATH; cannot decode this audio file")
    out = Path(tempfile.gettempdir()) / f"chord_onnx_ff_{uuid.uuid4().hex}.wav"
    try:
        subprocess.run(
            ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
             "-i", str(src), "-ac", "1", "-ar", str(TARGET_SR), "-f", "wav", str(out)],
            check=True, timeout=900, capture_output=True,
        )
    except Exception:
        out.unlink(missing_ok=True)
        raise
    return out


def load_audio_mono_22050(audio_path: Path) -> np.ndarray:
    """Load audio at TARGET_SR mono; try librosa first, then ffmpeg -> wav -> librosa."""
    try:
        y, _sr = librosa.load(str(audio_path), sr=TARGET_SR, mono=True)
        return y
    except Exception as exc:
        print(f"[ONNX] librosa.load failed ({audio_path.suffix}): {exc!r}; trying ffmpeg")
        tmp = _decode_to_temp_wav_with_ffmpeg(audio_path)
        try:
            y, _sr = librosa.load(str(tmp), sr=TARGET_SR, mono=True)
            return y
        finally:
            tmp.unlink(missing_ok=True)


@dataclass
class Segment:
    start: float
    end: float
    chord: str


class ChordOnnxInferenceService:
    """Chord recognition service using chroma + beat-sync + HMM (no ONNX model needed)."""

    def __init__(self, model_path: Path | None = None) -> None:
        self._build_templates()

    def _build_templates(self) -> None:
        templates: dict[str, np.ndarray] = {}
        for root_idx in range(12):
            root_name = NOTE_NAMES[root_idx]
            for suffix, profile in CHORD_QUALITY_TEMPLATES.items():
                shifted = np.roll(profile, root_idx)
                templates[f"{root_name}{suffix}"] = shifted.astype(np.float32)
        self.chord_templates = templates
        self.template_names = sorted(templates.keys())

    # ------------------------------------------------------------------ #
    # Public API
    # ------------------------------------------------------------------ #

    def transcribe(self, audio_path: Path) -> dict[str, Any]:
        y = load_audio_mono_22050(audio_path)
        duration = float(len(y) / TARGET_SR)

        chroma = self._extract_chroma(y)
        tempo, beat_frames = self._beat_track(y)
        beat_chromas = self._aggregate_per_beat(chroma, beat_frames)

        if beat_chromas.shape[0] == 0:
            return self._empty_result(duration, "no beats detected")

        key_result = self._estimate_key_from_chroma(beat_chromas)
        states = self._get_key_consistent_states(key_result.get("key", "C"))
        labels = self._viterbi_decode(beat_chromas, states)

        beat_times = librosa.frames_to_time(
            beat_frames, sr=TARGET_SR, hop_length=CHROMA_HOP_LENGTH
        )
        raw_segments: list[Segment] = []
        for i, label in enumerate(labels):
            if i < len(beat_times) - 1 and label:
                raw_segments.append(Segment(
                    start=round(float(beat_times[i]), 3),
                    end=round(float(beat_times[i+1]), 3),
                    chord=label,
                ))

        merged = self._merge_adjacent_segments(raw_segments, tolerance_sec=0.05)
        display, display_stats = self._make_display_segments(merged)
        noab_display, _ = self._make_display_segments(merged, short_absorb=False, boundary_refinement=False)
        simplified = self._make_simplified_segments(display)
        noab_simplified = self._make_simplified_segments(noab_display)

        seg_key_result = self._estimate_key(merged)
        key = seg_key_result.get("key", "C")

        chart_res = build_chord_chart_segments(
            [{"start": s.start, "end": s.end, "chord": s.chord, "confidence": 1.0} for s in simplified],
            estimated_key=key, enable_segment_absorption=True,
        )
        chart_noab = build_chord_chart_segments(
            [{"start": s.start, "end": s.end, "chord": s.chord, "confidence": 1.0} for s in noab_simplified],
            estimated_key=key, enable_segment_absorption=False,
        )

        # Optional LLM refinement (also corrects key)
        if _ENABLE_LLM_REFINE:
            try:
                from llm_refine import refine_chord_sequence
                chart_segs = chart_res.get("chordChartSegments", [])
                if chart_segs:
                    refined, llm_key = refine_chord_sequence(chart_segs, key)
                    if refined and len(refined) == len(chart_segs):
                        # Rebuild chart with refined chords and possibly corrected key
                        chart_res = build_chord_chart_segments(
                            refined, estimated_key=llm_key, enable_segment_absorption=True,
                        )
                        if llm_key != key:
                            print(f"[LLM_REFINE] key corrected: {key} -> {llm_key}")
                            key = llm_key
            except Exception as exc:
                print(f"[LLM_REFINE] error: {exc!r}; skipping")

        compact_build = build_timing_compact_segments(
            y=y, sr=int(TARGET_SR), timing_segments=list(simplified),
            merged_segments=merged, hop_length=CHROMA_HOP_LENGTH,
        )
        compact_dicts = compact_build["segments"]
        compact_segs = [Segment(start=float(d["start"]), end=float(d["end"]), chord=str(d["chord"]))
                        for d in compact_dicts]
        chart_tc = build_chord_chart_segments(
            [dict(d) for d in compact_dicts], estimated_key=key, enable_segment_absorption=True,
        )

        playable_build = build_playable_compact_segments(
            y=y, sr=int(TARGET_SR), timing_compact_segments=compact_segs,
            merged_segments=merged, hop_length=CHROMA_HOP_LENGTH,
        )
        playable_dicts = playable_build["segments"]
        chart_pc = build_chord_chart_segments(
            [dict(d) for d in playable_dicts], estimated_key=key, enable_segment_absorption=True,
        )

        chart_debug = dict(chart_res.get("debug", {}))
        chart_debug["chordChartSourceSegmentCount"] = chart_debug.pop("rawSegmentCount", len(simplified))

        ndp = [s.__dict__ for s in simplified]
        nadp = [s.__dict__ for s in noab_simplified]
        cdp = [s.__dict__ for s in compact_segs]
        pdp = list(playable_dicts)

        def _gs(n, k):
            return n.get(k) if isinstance(n, dict) else 0

        return {
            "duration": round(duration, 3),
            "key": key,
            "segments": [s.__dict__ for s in merged],
            "displaySegments": ndp,
            "simplifiedDisplaySegments": ndp,
            "chordChartSegments": chart_res.get("chordChartSegments", []),
            "timingVariants": {
                "normal": {"displaySegments": ndp, "simplifiedDisplaySegments": ndp,
                           "chordChartSegments": chart_res.get("chordChartSegments", [])},
                "noAbsorb": {"displaySegments": nadp, "simplifiedDisplaySegments": nadp,
                             "chordChartSegments": chart_noab.get("chordChartSegments", [])},
                "timing": {"displaySegments": cdp, "simplifiedDisplaySegments": cdp,
                           "chordChartSegments": chart_tc.get("chordChartSegments", [])},
                "timingCompact": {"displaySegments": cdp, "simplifiedDisplaySegments": cdp,
                                  "chordChartSegments": chart_tc.get("chordChartSegments", [])},
                "playableCompact": {"displaySegments": pdp, "simplifiedDisplaySegments": pdp,
                                    "chordChartSegments": chart_pc.get("chordChartSegments", [])},
            },
            "timingVariantStats": {
                "normal": {"displayCount": len(ndp), "simplifiedCount": len(ndp),
                           "chartSegmentCount": _gs(chart_res.get("chordChartSegments"), "count")},
                "noAbsorb": {"displayCount": len(nadp), "simplifiedCount": len(nadp),
                             "chartSegmentCount": _gs(chart_noab.get("chordChartSegments"), "count")},
                "timing": {"displayCount": len(cdp), "simplifiedCount": len(cdp),
                           "chartSegmentCount": _gs(chart_tc.get("chordChartSegments"), "count")},
                "timingCompact": {"displayCount": len(cdp), "simplifiedCount": len(cdp),
                                  "compressedCount": _gs(compact_build.get("stats"), "compressedCount")},
                "playableCompact": {"displayCount": len(pdp), "simplifiedCount": len(pdp),
                                    "compressedCount": _gs(playable_build.get("stats"), "compressedCount")},
            },
            "debug": {
                "duration": round(duration, 3),
                "sampleRate": TARGET_SR,
                "hopLength": CHROMA_HOP_LENGTH,
                "tempo_bpm": round(float(tempo), 1),
                "beat_count": len(beat_frames),
                "chroma_beats": beat_chromas.shape[0],
                "rawSegmentCount": len(raw_segments),
                "mergedSegmentCount": len(merged),
                "displaySegmentCount": len(simplified),
                "estimatedKey": key,
                "keyConfidence": seg_key_result.get("confidence", 0.0),
                "removedShortSegmentCount": display_stats.get("removed_short_count", 0),
                "sameSecondConflictCount": display_stats.get("same_second_conflict_count", 0),
                "displayChordText": self._build_display_chord_text(simplified, max_lines=20),
                **chart_debug,
                **compact_build.get("debug", {}),
                **playable_build.get("debug", {}),
            },
        }

    def _empty_result(self, duration: float, reason: str) -> dict[str, Any]:
        return {
            "duration": round(duration, 3), "key": "C",
            "segments": [], "displaySegments": [], "simplifiedDisplaySegments": [],
            "chordChartSegments": [], "timingVariants": {}, "timingVariantStats": {},
            "debug": {"error": reason, "duration": round(duration, 3)},
        }

    # ---- Chroma extraction ----

    def _extract_chroma(self, y: np.ndarray) -> np.ndarray:
        if y.size == 0:
            return np.zeros((CHROMA_N_CHROMA, 1), dtype=np.float32)
        # HPSS: remove percussive elements (drums) for cleaner harmonic analysis
        y_harm = librosa.effects.harmonic(y=y, margin=3.0)
        # chroma_cqt gives better harmonic resolution for chord recognition
        return librosa.feature.chroma_cqt(
            y=y_harm, sr=TARGET_SR, hop_length=CHROMA_HOP_LENGTH, n_chroma=CHROMA_N_CHROMA,
        ).astype(np.float32)

    def _beat_track(self, y: np.ndarray) -> tuple[float, np.ndarray]:
        if y.size < TARGET_SR:
            return 120.0, np.array([0], dtype=np.int32)
        tempo, beats = librosa.beat.beat_track(
            y=y, sr=TARGET_SR, hop_length=CHROMA_HOP_LENGTH, units='frames',
        )
        if len(beats) < 2:
            return float(tempo), np.array([0, y.size // CHROMA_HOP_LENGTH], dtype=np.int32)
        return float(tempo), beats.astype(np.int32)

    def _aggregate_per_beat(self, chroma: np.ndarray, beat_frames: np.ndarray) -> np.ndarray:
        n_beats = len(beat_frames) - 1
        if n_beats < 1:
            return np.zeros((0, CHROMA_N_CHROMA), dtype=np.float32)
        result = np.zeros((n_beats, CHROMA_N_CHROMA), dtype=np.float32)
        for i in range(n_beats):
            s, e = int(beat_frames[i]), int(beat_frames[i + 1])
            if e <= s:
                result[i] = chroma[:, min(s, chroma.shape[1] - 1)]
            else:
                result[i] = np.mean(chroma[:, s:e], axis=1)  # mean more stable than median for few frames
        rs = np.sum(result, axis=1, keepdims=True)
        return result / np.maximum(rs, 1e-10)

    # ---- Key estimation ----

    def _estimate_key_from_chroma(self, bc: np.ndarray) -> dict[str, Any]:
        """Krumhansl-Schmuckler key estimation from beat-level chroma."""
        major_prof = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88], dtype=np.float32)
        minor_prof = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17], dtype=np.float32)
        major_prof /= np.sum(major_prof)
        minor_prof /= np.sum(minor_prof)
        mc = np.mean(bc, axis=0)
        mc /= max(np.sum(mc), 1e-10)
        scores = []
        for t in range(12):
            scores.append({"key": NOTE_NAMES[t], "score": float(np.dot(mc, np.roll(major_prof, t))), "mode": "major"})
            scores.append({"key": f"{NOTE_NAMES[t]}m", "score": float(np.dot(mc, np.roll(minor_prof, t))), "mode": "minor"})
        scores.sort(key=lambda x: x["score"], reverse=True)
        b = scores[0]
        s = scores[1] if len(scores) > 1 else {"score": 0.0}
        c = round(max(0.0, (b["score"] - s["score"]) / max(b["score"], 1e-10)), 3) if b["score"] > 0 else 0.0
        return {"key": b["key"], "top5": scores[:5], "confidence": c}

    @staticmethod
    def _normalize_chord_name(chord: str) -> str:
        """Map sharp/flat note names to NOTE_NAMES canonical spelling for template lookup."""
        root = chord[:2] if len(chord) >= 2 and chord[1] in '#b' else chord[:1]
        suffix = chord[len(root):]
        root_map = {
            'D#': 'Eb', 'G#': 'Ab', 'A#': 'Bb', 'B#': 'C', 'E#': 'F',
            'Db': 'C#', 'Gb': 'F#', 'Cb': 'B', 'Fb': 'E',
        }
        return root_map.get(root, root) + suffix

    def _get_key_consistent_states(self, key: str) -> list[str]:
        """Get chord state space constrained by key. Filters to chords that exist in templates."""
        r = key.rstrip('m')
        if r in MAJOR_KEY_CHORDS:
            states = MAJOR_KEY_CHORDS[r]
        elif key in RELATIVE_MAJOR:
            r = RELATIVE_MAJOR[key]
            states = MAJOR_KEY_CHORDS.get(r, DEFAULT_STATES)
        else:
            states = DEFAULT_STATES
        # Normalize enharmonic spellings and filter to chords that exist in templates
        return [s for s in (self._normalize_chord_name(c) for c in states) if s in self.chord_templates]

    # ---- HMM Viterbi ----

    def _build_transition_matrix(self, names: list[str]) -> np.ndarray:
        n = len(names)
        t = np.full((n, n), 0.001, dtype=np.float32)
        np.fill_diagonal(t, 0.85)  # self-transition: avg ~6.7 beats per chord
        def br(x):
            for sfx in ['m', '7', 'dim', 'aug', 'sus2', 'sus4']:
                if x.endswith(sfx): return x[:-len(sfx)]
            return x
        up = {'C': 'F', 'G': 'C', 'D': 'G', 'A': 'D', 'E': 'A', 'F': 'Bb', 'Bb': 'Eb', 'Eb': 'Ab'}
        dn = {'C': 'G', 'F': 'C', 'Bb': 'F', 'Eb': 'Bb', 'G': 'D', 'D': 'A', 'A': 'E'}
        for i, ca in enumerate(names):
            ra = br(ca)
            for j, cb in enumerate(names):
                if i == j: continue
                rb = br(cb)
                if up.get(ra) == rb: t[i, j] = 0.15
                elif dn.get(ra) == rb: t[i, j] = 0.12
                elif (ca.rstrip('m') == rb and 'm' in cb) or (cb.rstrip('m') == ra and 'm' in ca):
                    t[i, j] = 0.10
                else: t[i, j] = 0.03
        rs = t.sum(axis=1, keepdims=True)
        return t / np.maximum(rs, 1e-10)

    def _viterbi_decode(self, obs: np.ndarray, names: list[str]) -> list[str]:
        n_s, n_t = len(names), obs.shape[0]
        if n_s == 0 or n_t == 0:
            return []
        tm = np.array([self.chord_templates[n] for n in names])
        tn = np.linalg.norm(tm, axis=1, keepdims=True)
        tu = tm / np.maximum(tn, 1e-10)

        em = np.zeros((n_t, n_s), dtype=np.float32)
        for t in range(n_t):
            on = np.linalg.norm(obs[t])
            if on > 1e-10:
                s = (obs[t] / on) @ tu.T
                em[t] = np.clip(s, 0.0, 1.0) ** 2
            else:
                em[t] = 1.0 / n_s

        # Smooth emission over time (window=5 beats)
        for j in range(n_s):
            em[:, j] = np.convolve(em[:, j], np.ones(5)/5, mode='same')

        tr = self._build_transition_matrix(names)
        lt = np.log(np.maximum(tr, 1e-10))
        nl = -np.log(np.maximum(em, 1e-10))
        dl = nl[0].copy()
        ps = np.zeros((n_t, n_s), dtype=np.int32)
        for t in range(1, n_t):
            prev_dl = dl.copy()
            for j in range(n_s):
                c = prev_dl + lt[:, j]
                bi = int(np.argmin(c))
                ps[t, j] = bi
                dl[j] = c[bi] + nl[t, j]
        p = [int(np.argmin(dl))]
        for t in range(n_t - 1, 0, -1):
            p.insert(0, int(ps[t, p[0]]))
        labels = [names[s] for s in p]
        from scipy.ndimage import median_filter
        label_ids = np.array([names.index(l) for l in labels], dtype=np.int32)
        smoothed = median_filter(label_ids, size=5, mode='nearest')
        return [names[int(s)] for s in smoothed]

    # ------------------------------------------------------------------ #
    # Reused postprocess methods
    # ------------------------------------------------------------------ #

    def _merge_labels(self, labels: list[str], frame_sec: float) -> list[Segment]:
        if not labels:
            return []
        out: list[Segment] = []
        start, cur = 0, labels[0]
        for i in range(1, len(labels)):
            if labels[i] == cur:
                continue
            if cur != "N":
                out.append(Segment(start=round(start * frame_sec, 3), end=round(i * frame_sec, 3), chord=cur))
            cur, start = labels[i], i
        if cur != "N":
            out.append(Segment(start=round(start * frame_sec, 3), end=round(len(labels) * frame_sec, 3), chord=cur))
        return out

    def _collect_boundary_frame_diagnostics(self, **kwargs):
        return []

    def _label_at_time(self, segments: list[Segment], time_sec: float) -> str:
        for s in segments:
            if s.start <= time_sec < s.end: return s.chord
        return "-"

    def _log_boundary_frame_diagnostics(self, rows): pass

    def _merge_adjacent_segments(self, segments: list[Segment], tolerance_sec: float) -> list[Segment]:
        if not segments:
            return []
        segs = sorted(segments, key=lambda s: (s.start, s.end))
        out: list[Segment] = [segs[0]]
        for s in segs[1:]:
            if s.chord == out[-1].chord and s.start <= out[-1].end + tolerance_sec:
                out[-1] = Segment(start=out[-1].start, end=max(out[-1].end, s.end), chord=out[-1].chord)
            else:
                out.append(s)
        return out

    def _make_display_segments(self, raw_segments, *, short_absorb=True, boundary_refinement=True):
        min_dur = 0.3  # was 0.5—too aggressive for fast tempos where one beat < 0.5s
        if not raw_segments:
            return [], {"removed_short_count": 0, "same_second_conflict_count": 0}
        def valid(c):
            return (c or "").strip().lower() not in {"", "-", "—", "n", "nc", "unknown"}
        w = [s for s in raw_segments if valid(s.chord) and s.end > s.start]
        w = self._merge_adjacent_segments(w, 0.2)
        removed = 0
        if short_absorb:
            changed = True
            while changed and w:
                changed = False
                i = 0
                while i < len(w):
                    if w[i].end - w[i].start >= min_dur:
                        i += 1; continue
                    p = i - 1 if i > 0 else None
                    n = i + 1 if i + 1 < len(w) else None
                    if p is None and n is None:
                        i += 1; continue
                    def mp(a, b):
                        k = a.chord if (a.end - a.start) >= (b.end - b.start) else b.chord
                        return Segment(start=min(a.start, b.start), end=max(a.end, b.end), chord=k)
                    t = None
                    if p is not None and w[p].chord == w[i].chord: t = p
                    elif n is not None and w[n].chord == w[i].chord: t = n
                    elif p is not None and n is not None: t = p if (w[p].end - w[p].start) >= (w[n].end - w[n].start) else n
                    else: t = p if p is not None else n
                    if t is None: i += 1; continue
                    f, s = min(i, t), max(i, t)
                    merged = mp(w[i], w[t])
                    w[s] = merged
                    w.pop(f)
                    removed += 1
                    changed = True
                    i = max(0, f - 1)
                w = self._merge_adjacent_segments(w, 0.2)
        by_sec: dict[int, list[Segment]] = {}
        for seg in w:
            by_sec.setdefault(int(seg.start), []).append(seg)
        conflicts = 0
        resolved: list[Segment] = []
        for sec in sorted(by_sec):
            bucket = by_sec[sec]
            if len({s.chord for s in bucket}) <= 1:
                resolved.extend(bucket)
            else:
                conflicts += 1
                resolved.append(max(bucket, key=lambda s: s.end - s.start))
        resolved.sort(key=lambda s: (s.start, s.end))
        resolved = self._merge_adjacent_segments(resolved, 0.2)
        if not boundary_refinement:
            return [Segment(start=round(s.start, 3), end=round(s.end, 3), chord=s.chord) for s in resolved], \
                   {"removed_short_count": removed, "same_second_conflict_count": conflicts}
        normal: list[Segment] = []
        for s in resolved:
            st = max(s.start, normal[-1].end if normal else s.start)
            normal.append(Segment(start=round(st, 3), end=round(max(s.end, st + 0.001), 3), chord=s.chord))
        return normal, {"removed_short_count": removed, "same_second_conflict_count": conflicts}

    def _build_display_chord_text(self, segs: list[Segment], max_lines: int = 20) -> list[str]:
        if not segs:
            return []
        out = []
        for i in range(0, len(segs), 4):
            if len(out) >= max_lines: break
            row = segs[i:i+4]
            t = f"{int(row[0].start)//60:02d}:{int(row[0].start)%60:02d}"
            out.append(f"{t} | {' | '.join(s.chord for s in row)} |")
        return out

    def _format_mmss(self, sec: float) -> str:
        t = max(0, int(sec))
        return f"{t // 60:02d}:{t % 60:02d}"

    def _make_simplified_segments(self, segs: list[Segment]) -> list[Segment]:
        if not segs:
            return []
        m = [Segment(start=s.start, end=s.end, chord=self._simplify_display_chord(s)) for s in segs]
        return self._merge_adjacent_segments(m, 0.2)

    def _simplify_display_chord(self, seg: Segment) -> str:
        base = seg.chord.split("/")[0].strip()
        if not base:
            return seg.chord
        parsed = self._parse_chord(base)
        if parsed is None:
            return base
        rp, q = parsed
        r = NOTE_NAMES[rp]
        d = max(0.0, seg.end - seg.start)
        if q in {"minor", "m7", "minor_extension"}:
            return f"{r}m"
        if q == "dominant7":
            return f"{r}7" if d >= DISPLAY_KEEP_DOMINANT7_MIN_SEC else r
        return r

    def _estimate_key(self, segments: list[Segment]) -> dict[str, Any]:
        if not segments:
            return {"key": "C", "top5": [], "confidence": 0.0}
        mw = {0: 3.0, 5: 2.6, 7: 3.0, 9: 2.4, 2: 1.6, 4: 1.3, 11: 0.8}
        miw = {0: 3.0, 3: 2.3, 5: 1.7, 7: 2.4, 8: 2.2, 10: 2.0, 2: 1.0}
        scores = []
        for t in range(12):
            scores.append(self._score_key_candidate(t, "major", segments, mw))
            scores.append(self._score_key_candidate(t, "minor", segments, miw))
        scores.sort(key=lambda x: x["score"], reverse=True)
        b = scores[0]
        s = scores[1] if len(scores) > 1 else {"score": 0.0}
        c = round(max(0.0, (b["score"] - s["score"]) / b["score"]), 3) if b["score"] > 0 else 0.0
        return {"key": b["key"], "top5": scores[:5], "confidence": c}

    def _score_key_candidate(self, tp: int, mode: str, segs: list[Segment], dw: dict[int, float]) -> dict[str, Any]:
        kn = NOTE_NAMES[tp] if mode == "major" else f"{NOTE_NAMES[tp]}m"
        score = 0.0
        for seg in segs:
            d = max(0.0, seg.end - seg.start)
            if d <= 0: continue
            p = self._parse_chord(seg.chord)
            if p is None: continue
            rp, q = p
            deg = (rp - tp) % 12
            score += d * (dw.get(deg, -1.2) + self._quality_adjustment(mode, deg, q))
        return {"key": kn, "score": round(score, 3), "supports": []}

    def _parse_chord(self, chord: str) -> tuple[int, str] | None:
        token = chord.split("/")[0].strip()
        if not token:
            return None
        root = token[:2] if len(token) >= 2 and token[1] in {"#", "b"} else token[:1]
        if root not in NOTE_NAMES:
            return None
        rp = NOTE_NAMES.index(root)
        s = token[len(root):].lower()
        if "maj7" in s: q = "maj7"
        elif "m7" in s: q = "m7"
        elif s.startswith("m") and any(e in s for e in ("add", "sus", "9", "11", "13", "6")): q = "minor_extension"
        elif s.startswith("m"): q = "minor"
        elif "7" in s: q = "dominant7"
        else: q = "major"
        return rp, q

    def _quality_adjustment(self, mode: str, degree: int, quality: str) -> float:
        if quality == "dominant7":
            return 1.2 if degree == 7 else 0.2
        if mode == "major":
            if degree in {0, 5, 7} and quality in {"major", "maj7"}: return 0.6
            if degree in {2, 4, 9} and quality in {"minor", "m7"}: return 0.45
            if degree == 11 and quality in {"minor", "m7"}: return 0.2
        else:
            if degree in {0, 3, 8} and quality in {"minor", "m7"}: return 0.55
            if degree in {5, 10} and quality in {"major", "maj7"}: return 0.35
            if degree == 7 and quality == "dominant7": return 0.6
        if quality in {"major", "maj7"} and mode == "minor" and degree in {0, 3, 8}: return -0.25
        if quality in {"minor", "m7"} and mode == "major" and degree in {0, 5, 7}: return -0.25
        return 0.0
