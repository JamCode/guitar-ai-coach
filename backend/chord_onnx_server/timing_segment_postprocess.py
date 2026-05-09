"""
踩点优先时间轴：从 noAbsorb 简化段出发，用 onset / chroma / beat 等证据做短段吸收与边界吸附。
不修改 chord label 文本（吸收合并时沿用既有合并规则选择保留和弦名）。
"""
from __future__ import annotations

import logging
import math
from dataclasses import dataclass
from typing import Any, Callable, Sequence

import librosa
import numpy as np

from chord_chart_postprocess import simplify_chord_for_reference

logger = logging.getLogger("chord_onnx.timing")

SHORT_EVIDENCE_SEC = 1.2
KEEP_SCORE_THRESHOLD = 0.55
ONSET_WINDOW_SEC = 0.22
CHROMA_PRE_SEC = 0.15
CHROMA_POST_SEC = 0.15
SNAP_RADIUS_SEC = 0.45
SNAP_MAX_MOVE_SEC = 0.35
SNAP_PREFERRED_MAX_MOVE_SEC = 0.32
SNAP_LARGE_MOVE_MIN_GAIN = 0.22
SNAP_IMPROVE_EPS = 0.08
SNAP_DISTANCE_PENALTY_PER_SEC = 0.22
MIN_SEGMENT_SEC = 0.45
SEAL_GAP_SEC = 0.9
ANCHOR_GAP_FILL_MAX_SEC = 2.2
HOP_LENGTH_DEFAULT = 512


@dataclass
class _Seg:
    start: float
    end: float
    chord: str

    @property
    def dur(self) -> float:
        return max(0.0, self.end - self.start)


def _simplify_label(chord: str) -> str:
    return simplify_chord_for_reference(chord or "")


def _time_to_frame(t: float, sr: int, hop: int) -> int:
    return int(max(0, min(10**9, round(t * sr / hop))))


def _merged_agreement_score(start: float, end: float, label: str, merged: Sequence[_Seg], simplify: Callable[[str], str]) -> float:
    sl = simplify(label)
    tot = 0.0
    match = 0.0
    for m in merged:
        if m.end <= start or m.start >= end:
            continue
        ov = min(m.end, end) - max(m.start, start)
        if ov <= 0:
            continue
        tot += ov
        if simplify(m.chord) == sl:
            match += ov
    if tot < 1e-6:
        return 0.45
    return float(match / tot)


def _beat_proximity_score(t: float, beat_times: np.ndarray) -> float:
    if beat_times.size == 0:
        return 0.35
    d = float(np.min(np.abs(beat_times - t)))
    return float(math.exp(-d / 0.12))


def _music_theory_bonus(prev: _Seg | None, seg: _Seg, nxt: _Seg | None) -> float:
    b = 0.0
    c = (seg.chord or "").strip()
    if not c:
        return 0.0
    if "/" in c:
        b += 0.04
    low = c.lower()
    if any(x in low for x in ("sus", "add", "dim", "aug", "maj7", "m7")):
        b += 0.05
    if prev is not None and nxt is not None:
        if _simplify_label(prev.chord) != _simplify_label(nxt.chord) and _simplify_label(seg.chord) not in (
            _simplify_label(prev.chord),
            _simplify_label(nxt.chord),
        ):
            b += 0.04
    return float(min(0.12, b))


def _noise_penalty(prev: _Seg | None, seg: _Seg, nxt: _Seg | None) -> float:
    p = 0.0
    sp = _simplify_label(prev.chord) if prev else ""
    ss = _simplify_label(seg.chord)
    sn = _simplify_label(nxt.chord) if nxt else ""
    if prev is not None and nxt is not None and sp == sn and ss != sp and seg.dur < 0.85:
        p += 0.38
    if prev is not None and nxt is not None and sp == sn == ss and seg.dur < 0.55:
        p += 0.08
    return float(min(0.55, p))


def _onset_peak_score(t: float, onset_norm: np.ndarray, sr: int, hop: int) -> float:
    if onset_norm.size == 0:
        return 0.35
    fc = _time_to_frame(t, sr, hop)
    w = max(1, int(round(ONSET_WINDOW_SEC * sr / hop)))
    lo = max(0, fc - w)
    hi = min(len(onset_norm) - 1, fc + w)
    if hi < lo:
        return 0.35
    return float(np.max(onset_norm[lo : hi + 1]))


def _chroma_change_score(t: float, chroma: np.ndarray, sr: int, hop: int) -> float:
    f_mid = _time_to_frame(t, sr, hop)
    f_lo = _time_to_frame(t - CHROMA_PRE_SEC, sr, hop)
    f_hi = _time_to_frame(t + CHROMA_POST_SEC, sr, hop)
    n = chroma.shape[1]
    if n <= 1:
        return 0.35

    def mean_vec(f0: int, f1: int) -> np.ndarray:
        f0 = int(np.clip(f0, 0, n - 1))
        f1 = int(np.clip(f1, 0, n - 1))
        if f1 < f0:
            f0, f1 = f1, f0
        block = chroma[:, f0 : f1 + 1]
        if block.size == 0:
            return np.zeros(12, dtype=np.float32)
        return np.mean(block, axis=1).astype(np.float32)

    a = mean_vec(f_lo, max(f_lo, f_mid - 1))
    b = mean_vec(min(f_mid + 1, f_hi), f_hi)
    num = float(np.linalg.norm(a - b))
    den = float(np.linalg.norm(a) + np.linalg.norm(b) + 1e-6)
    raw = num / den
    return float(np.clip(raw / 1.25, 0.0, 1.0))


def _boundary_evidence_score(t: float, onset_norm: np.ndarray, chroma: np.ndarray, beat_times: np.ndarray, sr: int, hop: int) -> float:
    o = _onset_peak_score(t, onset_norm, sr, hop)
    c = _chroma_change_score(t, chroma, sr, hop)
    b = _beat_proximity_score(t, beat_times)
    return float(0.5 * o + 0.35 * c + 0.15 * b)


def _compute_keep_record(
    seg: _Seg,
    prev: _Seg | None,
    nxt: _Seg | None,
    merged: Sequence[_Seg],
    onset_norm: np.ndarray,
    chroma: np.ndarray,
    beat_times: np.ndarray,
    sr: int,
    hop: int,
) -> dict[str, Any]:
    onset_s = _onset_peak_score(seg.start, onset_norm, sr, hop)
    chroma_s = _chroma_change_score(seg.start, chroma, sr, hop)
    conf_s = _merged_agreement_score(seg.start, seg.end, seg.chord, merged, _simplify_label)
    beat_s = _beat_proximity_score(seg.start, beat_times)
    theory = _music_theory_bonus(prev, seg, nxt)
    noise = _noise_penalty(prev, seg, nxt)
    keep = (
        0.35 * onset_s
        + 0.30 * chroma_s
        + 0.20 * conf_s
        + 0.15 * beat_s
        + theory
        - noise
    )
    return {
        "chord": seg.chord,
        "start": round(seg.start, 4),
        "end": round(seg.end, 4),
        "duration": round(seg.dur, 4),
        "onsetScore": round(onset_s, 4),
        "chromaChangeScore": round(chroma_s, 4),
        "confidenceScore": round(conf_s, 4),
        "beatProximityScore": round(beat_s, 4),
        "musicTheoryBonus": round(theory, 4),
        "noisePenalty": round(noise, 4),
        "keepScore": round(keep, 4),
    }


def _merge_pair_chord(a: _Seg, b: _Seg) -> str:
    if a.chord == b.chord:
        return a.chord
    if a.dur >= b.dur:
        return a.chord
    return b.chord


def _pick_absorb_target_index(i: int, segs: list[_Seg], merged: Sequence[_Seg]) -> tuple[int | None, str]:
    seg = segs[i]
    prev_i = i - 1 if i > 0 else None
    next_i = i + 1 if i + 1 < len(segs) else None
    if prev_i is None and next_i is None:
        return None, ""
    if prev_i is not None and segs[prev_i].chord == seg.chord:
        return prev_i, "same_chord_prev"
    if next_i is not None and segs[next_i].chord == seg.chord:
        return next_i, "same_chord_next"
    cand: list[tuple[int, float, float]] = []
    if prev_i is not None:
        p = segs[prev_i]
        conf = _merged_agreement_score(p.start, p.end, p.chord, merged, _simplify_label)
        cand.append((prev_i, p.dur, conf))
    if next_i is not None:
        n = segs[next_i]
        conf = _merged_agreement_score(n.start, n.end, n.chord, merged, _simplify_label)
        cand.append((next_i, n.dur, conf))
    cand.sort(key=lambda x: (-x[2], -x[1], x[0]))
    return cand[0][0], "higher_evidence_neighbor"


def _absorb_index_into(segs: list[_Seg], i: int, j: int) -> None:
    if i == j:
        return
    a, b = segs[i], segs[j]
    lo, hi = (i, j) if i < j else (j, i)
    s1, s2 = segs[lo], segs[hi]
    merged = _Seg(start=min(s1.start, s2.start), end=max(s1.end, s2.end), chord=_merge_pair_chord(s1, s2))
    segs[lo] = merged
    segs.pop(hi)


def _merge_adjacent_same(segs: list[_Seg], tolerance_sec: float = 0.0) -> list[_Seg]:
    if not segs:
        return []
    out = [segs[0]]
    for s in segs[1:]:
        last = out[-1]
        touch = s.start <= last.end + tolerance_sec
        if s.chord == last.chord and touch:
            out[-1] = _Seg(start=last.start, end=max(last.end, s.end), chord=last.chord)
        else:
            out.append(s)
    return out


def _parse_segments(items: Sequence[Any]) -> list[_Seg]:
    segs: list[_Seg] = []
    for s in items:
        if isinstance(s, dict):
            chord = str(s.get("chord", "") or "")
            segs.append(_Seg(start=float(s["start"]), end=float(s["end"]), chord=chord))
        else:
            chord = str(getattr(s, "chord", "") or "")
            segs.append(_Seg(start=float(getattr(s, "start")), end=float(getattr(s, "end")), chord=chord))
    segs = [s for s in segs if s.end > s.start + 1e-6]
    segs.sort(key=lambda x: (x.start, x.end))
    return segs


def _event_aware_absorb(
    segs: list[_Seg],
    merged: Sequence[_Seg],
    onset_norm: np.ndarray,
    chroma: np.ndarray,
    beat_times: np.ndarray,
    sr: int,
    hop: int,
) -> tuple[int, list[dict[str, Any]], list[dict[str, Any]]]:
    absorbed = 0
    kept_short: list[dict[str, Any]] = []
    absorbed_log: list[dict[str, Any]] = []
    changed = True
    safety = 0
    while changed and safety < 5000:
        safety += 1
        changed = False
        i = 0
        while i < len(segs):
            seg = segs[i]
            if seg.dur >= SHORT_EVIDENCE_SEC - 1e-9:
                i += 1
                continue
            prev = segs[i - 1] if i > 0 else None
            nxt = segs[i + 1] if i + 1 < len(segs) else None
            rec = _compute_keep_record(seg, prev, nxt, merged, onset_norm, chroma, beat_times, sr, hop)
            if rec["keepScore"] >= KEEP_SCORE_THRESHOLD:
                rec["decision"] = "keep"
                kept_short.append(rec)
                i += 1
                continue
            tgt, reason = _pick_absorb_target_index(i, segs, merged)
            if tgt is None:
                rec["decision"] = "keep"
                rec["reason"] = "no_neighbor"
                kept_short.append(rec)
                i += 1
                continue
            into = "previous" if tgt < i else "next"
            rec["decision"] = "absorb"
            rec["absorbInto"] = into
            rec["absorbReason"] = reason
            absorbed_log.append(rec)
            logger.info(
                "[timing_short] absorb chord=%s dur=%.3f keepScore=%.3f into=%s (%s)",
                seg.chord,
                seg.dur,
                rec["keepScore"],
                into,
                reason,
            )
            _absorb_index_into(segs, i, tgt)
            absorbed += 1
            changed = True
            i = max(0, min(i, tgt) - 1)
        segs[:] = _merge_adjacent_same(segs, 0.0)
    return absorbed, kept_short, absorbed_log


def _snap_boundaries(
    segs: list[_Seg],
    onset_norm: np.ndarray,
    chroma: np.ndarray,
    beat_times: np.ndarray,
    sr: int,
    hop: int,
) -> tuple[int, list[dict[str, Any]]]:
    if len(segs) <= 1:
        return 0, []
    snaps: list[dict[str, Any]] = []
    snapped = 0
    for k in range(len(segs) - 1):
        t = float(segs[k + 1].start)
        if abs(segs[k].end - t) > 1e-3:
            t = float(min(segs[k].end, segs[k + 1].start))
        base = _boundary_evidence_score(t, onset_norm, chroma, beat_times, sr, hop)
        best_t = t
        best_s = base
        for step in range(-45, 46, 2):
            dt = step * 0.01
            if abs(dt) > SNAP_MAX_MOVE_SEC + 1e-6:
                continue
            if abs(dt) > SNAP_RADIUS_SEC + 1e-6:
                continue
            t2 = t + dt
            if t2 <= segs[k].start + MIN_SEGMENT_SEC:
                continue
            if t2 >= segs[k + 1].end - MIN_SEGMENT_SEC:
                continue
            raw_score = _boundary_evidence_score(t2, onset_norm, chroma, beat_times, sr, hop)
            if abs(dt) > SNAP_PREFERRED_MAX_MOVE_SEC and raw_score < base + SNAP_LARGE_MOVE_MIN_GAIN:
                continue
            penalized_score = raw_score - SNAP_DISTANCE_PENALTY_PER_SEC * abs(dt)
            if penalized_score > best_s + SNAP_IMPROVE_EPS:
                best_s = penalized_score
                best_t = t2
        if abs(best_t - t) > 1e-4:
            left_dur = best_t - segs[k].start
            right_dur = segs[k + 1].end - best_t
            if left_dur < MIN_SEGMENT_SEC or right_dur < MIN_SEGMENT_SEC:
                continue
            reason = "onset_chroma_beat"
            snaps.append(
                {
                    "old_t": round(t, 4),
                    "new_t": round(best_t, 4),
                    "delta": round(best_t - t, 4),
                    "reason": reason,
                }
            )
            logger.info("[timing_snap] old_t=%.4f new_t=%.4f delta=%+.4f", t, best_t, best_t - t)
            segs[k] = _Seg(start=segs[k].start, end=best_t, chord=segs[k].chord)
            segs[k + 1] = _Seg(start=best_t, end=segs[k + 1].end, chord=segs[k + 1].chord)
            snapped += 1
    segs[:] = _merge_adjacent_same(segs, 0.0)
    return snapped, snaps


def _seal_short_gaps(segs: list[_Seg]) -> list[_Seg]:
    if len(segs) <= 1:
        return segs
    out: list[_Seg] = [segs[0]]
    for cur in segs[1:]:
        prev = out[-1]
        gap = cur.start - prev.end
        if gap < -1e-6:
            boundary = round((prev.end + cur.start) / 2.0, 3)
            out[-1] = _Seg(start=prev.start, end=max(prev.start, boundary), chord=prev.chord)
            cur = _Seg(start=max(boundary, out[-1].end), end=cur.end, chord=cur.chord)
        elif gap <= SEAL_GAP_SEC + 1e-6:
            if prev.chord == cur.chord or _simplify_label(prev.chord) == _simplify_label(cur.chord):
                out[-1] = _Seg(start=prev.start, end=max(prev.end, cur.end), chord=_merge_pair_chord(prev, cur))
                continue
            boundary = round((prev.end + cur.start) / 2.0, 3)
            out[-1] = _Seg(start=prev.start, end=max(prev.start, boundary), chord=prev.chord)
            cur = _Seg(start=max(boundary, out[-1].end), end=cur.end, chord=cur.chord)
        out.append(cur)
    return _merge_adjacent_same(out, 0.0)


def _best_anchor_for_gap(start: float, end: float, anchors: Sequence[_Seg]) -> _Seg | None:
    if not anchors or end <= start:
        return None
    mid = (start + end) / 2.0
    covering = [a for a in anchors if a.start - 1e-6 <= mid <= a.end + 1e-6]
    if covering:
        covering.sort(key=lambda a: (a.dur, a.end - a.start), reverse=True)
        return covering[0]
    best: _Seg | None = None
    best_overlap = 0.0
    for a in anchors:
        ov = min(a.end, end) - max(a.start, start)
        if ov > best_overlap + 1e-6:
            best_overlap = ov
            best = a
    return best


def _fill_gaps_from_anchor(segs: list[_Seg], anchors: Sequence[_Seg]) -> list[_Seg]:
    if len(segs) <= 1 or not anchors:
        return segs
    out: list[_Seg] = [segs[0]]
    for cur in segs[1:]:
        prev = out[-1]
        gap = cur.start - prev.end
        if gap <= SEAL_GAP_SEC + 1e-6 or gap > ANCHOR_GAP_FILL_MAX_SEC + 1e-6:
            out.append(cur)
            continue
        anchor = _best_anchor_for_gap(prev.end, cur.start, anchors)
        if anchor is None:
            out.append(cur)
            continue
        anchor_label = anchor.chord
        prev_label = prev.chord
        next_label = cur.chord
        if _simplify_label(anchor_label) == _simplify_label(prev_label):
            out[-1] = _Seg(start=prev.start, end=cur.start, chord=prev.chord)
            out.append(cur)
            continue
        if _simplify_label(anchor_label) == _simplify_label(next_label):
            cur = _Seg(start=prev.end, end=cur.end, chord=cur.chord)
            out.append(cur)
            continue
        out.append(_Seg(start=round(prev.end, 3), end=round(cur.start, 3), chord=anchor_label))
        out.append(cur)
    return _merge_adjacent_same(out, 0.0)


def _enforce_monotone_min_len(segs: list[_Seg]) -> list[_Seg]:
    if not segs:
        return []
    fixed: list[_Seg] = []
    for s in segs:
        start = max(0.0, s.start)
        end = max(start + MIN_SEGMENT_SEC, s.end)
        if fixed:
            start = max(start, fixed[-1].end)
            end = max(end, start + MIN_SEGMENT_SEC)
        fixed.append(_Seg(start=round(start, 3), end=round(end, 3), chord=s.chord))
    merged = _merge_adjacent_same(fixed, 0.2)
    out: list[_Seg] = []
    for s in merged:
        if s.dur < MIN_SEGMENT_SEC - 1e-6:
            if not out:
                out.append(s)
                continue
            prev = out[-1]
            if s.dur + prev.dur >= MIN_SEGMENT_SEC:
                out[-1] = _Seg(start=prev.start, end=max(prev.end, s.end), chord=_merge_pair_chord(prev, s))
            else:
                out[-1] = _Seg(start=prev.start, end=max(prev.end, s.end), chord=_merge_pair_chord(prev, s))
        else:
            out.append(s)
    return _merge_adjacent_same(out, 0.2)


def build_timing_priority_segments(
    *,
    y: np.ndarray,
    sr: int,
    no_absorb_simplified: Sequence[Any],
    merged_segments: Sequence[Any],
    anchor_segments: Sequence[Any] | None = None,
    hop_length: int = HOP_LENGTH_DEFAULT,
) -> dict[str, Any]:
    """
    no_absorb_simplified / merged_segments: items with .start, .end, .chord or dict keys.
    返回 segments 为 list[dict]（start/end/chord/confidence），供 inference 转为 Segment。
    """
    segs = _parse_segments(no_absorb_simplified)
    merged = _parse_segments(merged_segments)
    anchors = _parse_segments(anchor_segments or [])

    hop = hop_length
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
    onset_norm = (onset_env - float(np.min(onset_env))) / (float(np.ptp(onset_env)) + 1e-6)
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=hop, n_chroma=12)
    try:
        _, beat_frames = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr, hop_length=hop, tightness=110.0)
        beat_times = librosa.frames_to_time(beat_frames, sr=sr, hop_length=hop)
    except Exception:  # noqa: BLE001
        beat_times = np.asarray([], dtype=np.float32)

    absorbed, kept_short, absorbed_log = _event_aware_absorb(segs, merged, onset_norm, chroma, beat_times, sr, hop)
    snapped, snap_log = _snap_boundaries(segs, onset_norm, chroma, beat_times, sr, hop)
    segs[:] = _seal_short_gaps(segs)
    segs[:] = _fill_gaps_from_anchor(segs, anchors)
    final_list = _enforce_monotone_min_len(segs)
    segments_payload = [
        {"start": round(s.start, 3), "end": round(s.end, 3), "chord": s.chord, "confidence": 1.0} for s in final_list
    ]

    debug = {
        "timingShortSegments": kept_short + absorbed_log,
        "timingBoundarySnaps": snap_log,
        "timingAbsorbedCount": absorbed,
        "timingKeptShortCount": len(kept_short),
        "timingSnappedBoundaryCount": snapped,
    }
    return {
        "segments": segments_payload,
        "stats": {
            "absorbedCount": absorbed,
            "keptShortCount": len(kept_short),
            "snappedBoundaryCount": snapped,
        },
        "debug": debug,
    }
