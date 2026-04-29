"""
Playable compact chord chart:
- Build from timingCompact timeline (do not re-run timing/noAbsorb logic)
- Stronger compression for readable guitar-playable chart
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from typing import Any, Sequence

import librosa
import numpy as np

from timing_segment_postprocess import (
    HOP_LENGTH_DEFAULT,
    _Seg,
    _chroma_change_score,
    _enforce_monotone_min_len,
    _merge_adjacent_same,
    _merged_agreement_score,
    _onset_peak_score,
    _simplify_label,
)

logger = logging.getLogger("chord_onnx.playable_compact")

TARGET_CHANGES_PER_MIN = 35.0
MAX_CHANGES_PER_MIN = 50.0
WINDOW_FALLBACK_SEC = 2.2
MIN_TRANSITION_SEC = 0.45

NOTE_NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


@dataclass
class _PItem:
    start: float
    end: float
    original_chord: str
    chord: str
    confidence: float
    strong_event: float
    transition_importance: float

    @property
    def dur(self) -> float:
        return max(0.0, self.end - self.start)


def _root_pc(chord: str) -> int | None:
    s = (chord or "").strip()
    if not s:
        return None
    token = s.split("/", 1)[0].strip()
    root = token[:2] if len(token) >= 2 and token[1] in {"#", "b"} else token[:1]
    if root not in NOTE_NAMES:
        return None
    return NOTE_NAMES.index(root)


def _slash_bass_pc(chord: str) -> int | None:
    if "/" not in chord:
        return None
    bass = chord.split("/", 1)[1].strip()
    return _root_pc(bass)


def _base_quality_reduce(chord: str) -> str:
    """Reduce extended/sus/add chords to playable triad-like name."""
    c = (chord or "").strip()
    if not c:
        return c
    base = c.split("/", 1)[0].strip()
    m = re.match(r"^([A-G](?:#|b)?)(.*)$", base)
    if not m:
        return base
    root, suffix = m.group(1), m.group(2).lower()
    is_minor = suffix.startswith("m") and not suffix.startswith("maj")
    return f"{root}m" if is_minor else root


def _complexity_penalty(chord: str) -> float:
    low = (chord or "").lower()
    p = 0.0
    if "/" in low:
        p += 0.45
    if any(k in low for k in ("sus", "add", "maj7", "m7", "6", "9", "11", "13")):
        p += 0.35
    if any(k in low for k in ("dim", "aug")):
        p += 0.45
    return float(min(1.0, p))


def _simplicity_score(chord: str) -> float:
    return float(max(0.0, 1.0 - _complexity_penalty(chord)))


def _slash_transition_importance(
    prev: _PItem | None,
    cur: _PItem,
    nxt: _PItem | None,
) -> float:
    if prev is None or nxt is None:
        return 0.0
    if "/" not in cur.original_chord:
        return 0.0
    sp = _simplify_label(prev.chord)
    sn = _simplify_label(nxt.chord)
    if sp == sn:
        return 0.0
    p_root = _root_pc(prev.chord)
    n_root = _root_pc(nxt.chord)
    bass = _slash_bass_pc(cur.original_chord)
    if p_root is None or n_root is None or bass is None:
        return 0.25
    a = (bass - p_root) % 12
    b = (n_root - bass) % 12
    walk = 0.38 if a in (1, 2, 11) and b in (1, 2, 11) else 0.2
    return float(min(1.0, 0.45 + walk))


def _window_bounds(duration: float, beat_times: np.ndarray) -> list[tuple[float, float]]:
    if beat_times.size >= 8:
        ibi = np.diff(beat_times)
        med = float(np.median(ibi))
        stable = med > 1e-4 and float(np.std(ibi) / (med + 1e-6)) <= 0.35
        if stable:
            out: list[tuple[float, float]] = []
            t0 = 0.0
            for i in range(0, max(1, len(beat_times) - 2), 2):
                t1 = float(beat_times[min(i + 2, len(beat_times) - 1)])
                if t1 <= t0 + 1e-3:
                    continue
                out.append((t0, t1))
                t0 = t1
            if t0 < duration - 1e-3:
                out.append((t0, duration))
            return out
    out = []
    t = 0.0
    while t < duration - 1e-6:
        t2 = min(duration, t + WINDOW_FALLBACK_SEC)
        out.append((t, t2))
        t = t2
    return out


def _dominant_score(
    it: _PItem,
    w0: float,
    w1: float,
    prev_label: str | None,
    beat_times: np.ndarray,
) -> float:
    ov = max(0.0, min(it.end, w1) - max(it.start, w0))
    wr = max(1e-6, w1 - w0)
    duration_ratio = ov / wr
    downbeat = 0.0
    if beat_times.size > 0:
        d = float(np.min(np.abs(beat_times - it.start)))
        downbeat = float(np.exp(-d / 0.12))
    continuity = 1.0 if prev_label is not None and _simplify_label(prev_label) == _simplify_label(it.chord) else 0.4
    complexity = _complexity_penalty(it.chord)
    return float(
        0.35 * duration_ratio
        + 0.25 * it.confidence
        + 0.20 * _simplicity_score(it.chord)
        + 0.10 * downbeat
        + 0.10 * continuity
        - 0.20 * complexity
    )


def _pick_merge_target(items: list[_PItem], idx: int) -> tuple[int | None, str]:
    prev_i = idx - 1 if idx > 0 else None
    next_i = idx + 1 if idx + 1 < len(items) else None
    if prev_i is None and next_i is None:
        return None, ""
    if prev_i is not None and _simplify_label(items[prev_i].chord) == _simplify_label(items[idx].chord):
        return prev_i, "same_function_prev"
    if next_i is not None and _simplify_label(items[next_i].chord) == _simplify_label(items[idx].chord):
        return next_i, "same_function_next"
    if prev_i is not None and next_i is not None:
        p, n = items[prev_i], items[next_i]
        p_score = (p.confidence, p.dur)
        n_score = (n.confidence, n.dur)
        if p_score >= n_score:
            return prev_i, "longer_or_higher_conf_prev"
        return next_i, "longer_or_higher_conf_next"
    if prev_i is not None:
        return prev_i, "only_prev"
    return next_i, "only_next"


def _merge_into(items: list[_PItem], i: int, j: int) -> None:
    if i == j:
        return
    lo, hi = (i, j) if i < j else (j, i)
    a, b = items[lo], items[hi]
    merged = _PItem(
        start=min(a.start, b.start),
        end=max(a.end, b.end),
        original_chord=a.original_chord if a.dur >= b.dur else b.original_chord,
        chord=a.chord if a.dur >= b.dur else b.chord,
        confidence=max(a.confidence, b.confidence),
        strong_event=max(a.strong_event, b.strong_event),
        transition_importance=max(a.transition_importance, b.transition_importance),
    )
    items[lo] = merged
    del items[hi]


def build_playable_compact_segments(
    *,
    y: np.ndarray,
    sr: int,
    timing_compact_segments: Sequence[Any],
    merged_segments: Sequence[Any],
    hop_length: int = HOP_LENGTH_DEFAULT,
    target_chord_changes_per_minute: float = TARGET_CHANGES_PER_MIN,
    max_chord_changes_per_minute: float = MAX_CHANGES_PER_MIN,
) -> dict[str, Any]:
    # parse
    segs: list[_Seg] = []
    for s in timing_compact_segments:
        if isinstance(s, dict):
            segs.append(_Seg(start=float(s["start"]), end=float(s["end"]), chord=str(s.get("chord", "") or "")))
        else:
            segs.append(
                _Seg(start=float(getattr(s, "start")), end=float(getattr(s, "end")), chord=str(getattr(s, "chord", "") or ""))
            )
    segs = [s for s in segs if s.end > s.start + 1e-6]
    segs.sort(key=lambda x: (x.start, x.end))
    if not segs:
        return {
            "segments": [],
            "stats": {
                "compressedCount": 0,
                "simplifiedChordNameCount": 0,
                "preservedTransitionCount": 0,
                "targetDensityAppliedCount": 0,
            },
            "debug": {"playableCompactActions": []},
        }

    merged: list[_Seg] = []
    for m in merged_segments:
        if isinstance(m, dict):
            merged.append(_Seg(start=float(m["start"]), end=float(m["end"]), chord=str(m.get("chord", "") or "")))
        else:
            merged.append(
                _Seg(start=float(getattr(m, "start")), end=float(getattr(m, "end")), chord=str(getattr(m, "chord", "") or ""))
            )

    hop = hop_length
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
    onset_norm = (onset_env - float(np.min(onset_env))) / (float(np.ptp(onset_env)) + 1e-6)
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=hop, n_chroma=12)
    try:
        _, beat_frames = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr, hop_length=hop, tightness=105.0)
        beat_times = librosa.frames_to_time(beat_frames, sr=sr, hop_length=hop)
    except Exception:  # noqa: BLE001
        beat_times = np.asarray([], dtype=np.float32)

    items: list[_PItem] = []
    debug_rows: list[dict[str, Any]] = []
    simplified_count = 0
    preserved_transition_count = 0

    for i, s in enumerate(segs):
        conf = _merged_agreement_score(s.start, s.end, s.chord, merged, _simplify_label)
        strong = float(0.5 * _onset_peak_score(s.start, onset_norm, sr, hop) + 0.5 * _chroma_change_score(s.start, chroma, sr, hop))
        prev = items[i - 1] if i > 0 else None
        nxt_src = segs[i + 1] if i + 1 < len(segs) else None
        nxt = (
            _PItem(nxt_src.start, nxt_src.end, nxt_src.chord, nxt_src.chord, 0.5, 0.0, 0.0)
            if nxt_src is not None
            else None
        )
        cur = _PItem(s.start, s.end, s.chord, s.chord, conf, strong, 0.0)
        trans = _slash_transition_importance(prev, cur, nxt)
        cur.transition_importance = trans
        keep_transition = trans >= 0.62 and cur.dur >= MIN_TRANSITION_SEC and conf >= 0.52 and strong >= 0.35
        if keep_transition:
            preserved_transition_count += 1

        display = cur.chord
        simplified_reason = ""
        if not keep_transition:
            if ("/" in display) and (cur.dur < 1.8 or conf < 0.62):
                display = display.split("/", 1)[0].strip()
                simplified_reason = "slash_to_root"
            reduced = _base_quality_reduce(display)
            if reduced != display and (cur.dur < 1.6 or conf < 0.62 or _complexity_penalty(display) >= 0.35):
                display = reduced
                simplified_reason = simplified_reason + "+triad_reduce" if simplified_reason else "triad_reduce"
        if display != cur.chord:
            simplified_count += 1

        cur.chord = display
        items.append(cur)
        if simplified_reason:
            debug_rows.append(
                {
                    "originalChord": s.chord,
                    "displayChord": display,
                    "start": round(s.start, 4),
                    "end": round(s.end, 4),
                    "duration": round(s.dur, 4),
                    "windowIndex": -1,
                    "dominantScore": 0.0,
                    "removableScore": 0.0,
                    "simplifiedReason": simplified_reason,
                    "compressedInto": "",
                    "preservedTransition": keep_transition,
                    "reason": "display_simplify",
                }
            )

    # merge same display names
    merged_items: list[_PItem] = []
    for it in items:
        if merged_items and _simplify_label(merged_items[-1].chord) == _simplify_label(it.chord) and it.start <= merged_items[-1].end + 1e-6:
            last = merged_items[-1]
            merged_items[-1] = _PItem(
                start=last.start,
                end=max(last.end, it.end),
                original_chord=last.original_chord if last.dur >= it.dur else it.original_chord,
                chord=last.chord if last.dur >= it.dur else it.chord,
                confidence=max(last.confidence, it.confidence),
                strong_event=max(last.strong_event, it.strong_event),
                transition_importance=max(last.transition_importance, it.transition_importance),
            )
        else:
            merged_items.append(it)
    items = merged_items

    duration = max(items[-1].end, 1.0)
    windows = _window_bounds(duration, beat_times)

    # window dominant keep-set
    keep_idx: set[int] = set()
    idx_to_window: dict[int, int] = {}
    prev_dom_label: str | None = None
    for wi, (w0, w1) in enumerate(windows):
        candidates: list[tuple[int, float]] = []
        for idx, it in enumerate(items):
            ov = max(0.0, min(it.end, w1) - max(it.start, w0))
            if ov <= 1e-6:
                continue
            sc = _dominant_score(it, w0, w1, prev_dom_label, beat_times)
            candidates.append((idx, sc))
            idx_to_window[idx] = wi
        if not candidates:
            continue
        candidates.sort(key=lambda x: x[1], reverse=True)
        keep_idx.add(candidates[0][0])
        prev_dom_label = items[candidates[0][0]].chord
        if len(candidates) >= 2:
            idx2, sc2 = candidates[1]
            it2 = items[idx2]
            if (
                sc2 >= candidates[0][1] - 0.12
                and it2.transition_importance >= 0.52
                and it2.strong_event >= 0.5
                and it2.dur >= MIN_TRANSITION_SEC
            ):
                keep_idx.add(idx2)

    compressed_count = 0
    target_density_applied = 0

    # remove non-dominant low-value segments
    i = 0
    while i < len(items):
        if i in keep_idx:
            i += 1
            continue
        if i == 0 or i == len(items) - 1:
            i += 1
            continue
        it = items[i]
        if it.transition_importance >= 0.62 and it.strong_event >= 0.4 and it.dur >= MIN_TRANSITION_SEC:
            i += 1
            continue
        removable = float(
            0.35 * min(1.0, max(0.0, (1.5 - it.dur) / 1.5))
            + 0.25 * (1.0 - it.confidence)
            + 0.20 * _complexity_penalty(it.original_chord)
            + 0.20 * (1.0 - it.strong_event)
            - 0.35 * it.transition_importance
        )
        if removable < 0.54:
            i += 1
            continue
        tgt, why = _pick_merge_target(items, i)
        if tgt is None:
            i += 1
            continue
        debug_rows.append(
            {
                "originalChord": it.original_chord,
                "displayChord": it.chord,
                "start": round(it.start, 4),
                "end": round(it.end, 4),
                "duration": round(it.dur, 4),
                "windowIndex": idx_to_window.get(i, -1),
                "dominantScore": 0.0,
                "removableScore": round(removable, 4),
                "simplifiedReason": "",
                "compressedInto": "previous" if tgt < i else "next",
                "preservedTransition": False,
                "reason": f"window_compact:{why}",
            }
        )
        logger.info(
            "[playable_compact] compress chord=%s display=%s dur=%.3f removable=%.3f into=%s reason=%s",
            it.original_chord,
            it.chord,
            it.dur,
            removable,
            "previous" if tgt < i else "next",
            why,
        )
        _merge_into(items, i, tgt)
        compressed_count += 1
        target_density_applied += 1
        i = max(1, min(i, tgt) - 1)

    # density control (changes per minute)
    def changes_per_min(local_items: list[_PItem]) -> float:
        if not local_items:
            return 0.0
        dur = max(1e-6, local_items[-1].end - local_items[0].start)
        return (max(0, len(local_items) - 1) / dur) * 60.0

    safety = 0
    while changes_per_min(items) > max_chord_changes_per_minute and len(items) > 2 and safety < 2000:
        safety += 1
        removable_idx = -1
        best = -1.0
        for i in range(1, len(items) - 1):
            it = items[i]
            if it.transition_importance >= 0.62 and it.dur >= MIN_TRANSITION_SEC:
                continue
            score = (
                0.35 * min(1.0, max(0.0, (1.2 - it.dur) / 1.2))
                + 0.25 * (1.0 - it.confidence)
                + 0.20 * _complexity_penalty(it.original_chord)
                + 0.20 * (1.0 - it.strong_event)
            )
            if score > best:
                best = score
                removable_idx = i
        if removable_idx < 0 or best < 0.45:
            break
        tgt, why = _pick_merge_target(items, removable_idx)
        if tgt is None:
            break
        it = items[removable_idx]
        debug_rows.append(
            {
                "originalChord": it.original_chord,
                "displayChord": it.chord,
                "start": round(it.start, 4),
                "end": round(it.end, 4),
                "duration": round(it.dur, 4),
                "windowIndex": idx_to_window.get(removable_idx, -1),
                "dominantScore": 0.0,
                "removableScore": round(best, 4),
                "simplifiedReason": "",
                "compressedInto": "previous" if tgt < removable_idx else "next",
                "preservedTransition": False,
                "reason": f"target_density:{why}",
            }
        )
        _merge_into(items, removable_idx, tgt)
        compressed_count += 1
        target_density_applied += 1

    # if still above target CPM, do one soft pass
    if changes_per_min(items) > target_chord_changes_per_minute and len(items) > 3:
        i = 1
        while i < len(items) - 1 and changes_per_min(items) > target_chord_changes_per_minute:
            it = items[i]
            if it.dur < 0.75 and it.confidence < 0.55 and it.transition_importance < 0.5:
                tgt, why = _pick_merge_target(items, i)
                if tgt is not None:
                    debug_rows.append(
                        {
                            "originalChord": it.original_chord,
                            "displayChord": it.chord,
                            "start": round(it.start, 4),
                            "end": round(it.end, 4),
                            "duration": round(it.dur, 4),
                            "windowIndex": idx_to_window.get(i, -1),
                            "dominantScore": 0.0,
                            "removableScore": 0.5,
                            "simplifiedReason": "",
                            "compressedInto": "previous" if tgt < i else "next",
                            "preservedTransition": False,
                            "reason": f"target_density_soft:{why}",
                        }
                    )
                    _merge_into(items, i, tgt)
                    compressed_count += 1
                    target_density_applied += 1
                    i = max(1, min(i, tgt) - 1)
                    continue
            i += 1

    base_segs = [_Seg(start=it.start, end=it.end, chord=it.chord) for it in items]
    base_segs = _merge_adjacent_same(base_segs, 0.0)
    final = _enforce_monotone_min_len(base_segs)
    payload = [{"start": round(s.start, 3), "end": round(s.end, 3), "chord": s.chord, "confidence": 1.0} for s in final]

    return {
        "segments": payload,
        "stats": {
            "compressedCount": compressed_count,
            "simplifiedChordNameCount": simplified_count,
            "preservedTransitionCount": preserved_transition_count,
            "targetDensityAppliedCount": target_density_applied,
        },
        "debug": {"playableCompactActions": debug_rows},
    }

