"""
踩点精简：在 timing 时间轴之上做选择性合并，不重新跑 noAbsorb / 事件吸收 / 边界吸附。
"""
from __future__ import annotations

import logging
import re
from typing import Any, Sequence

import librosa
import numpy as np

from timing_segment_postprocess import (
    HOP_LENGTH_DEFAULT,
    _Seg,
    _chroma_change_score,
    _merge_adjacent_same,
    _merge_pair_chord,
    _merged_agreement_score,
    _onset_peak_score,
    _simplify_label,
    _enforce_monotone_min_len,
)

logger = logging.getLogger("chord_onnx.timing_compact")

REMOVABLE_THRESHOLD = 0.58
TRANSITION_BLOCK = 0.52
FORCE_DUR_SEC = 0.35
FORCE_CONF_MAX = 0.48
TRANSITION_FORCE_BLOCK = 0.62
CANDIDATE_MAX_DUR = 1.5
CANDIDATE_CONF = 0.52
SANDWICH_MAX_DUR = 2.0

NOTE_NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


def _parse_root_token(chord: str) -> str | None:
    s = (chord or "").strip().split("/", 1)[0].strip()
    if not s:
        return None
    if len(s) >= 2 and s[1] in "#b":
        root = s[:2]
    else:
        root = s[:1]
    return root if root in NOTE_NAMES else None


def _root_pc(chord: str) -> int | None:
    r = _parse_root_token(chord)
    if r is None:
        return None
    return NOTE_NAMES.index(r)


def _ornamental_surface(chord: str) -> bool:
    """装饰/色彩扩展（不含仅凭 slash 判定为经过低音）。"""
    base = (chord or "").strip().split("/", 1)[0].strip().lower()
    if not base:
        return False
    if re.search(r"sus[24]?", base):
        return True
    if "add" in base:
        return True
    if "maj7" in base or "maj9" in base or "m7" in base:
        return True
    if "dim" in base or "aug" in base:
        return True
    if re.search(r"(?:^|[^m0-9])7", base) or base.endswith("7"):
        return True
    if "11" in base or "13" in base or "9" in base:
        return True
    return False


def _same_root(a: str, b: str) -> bool:
    ra, rb = _root_pc(a), _root_pc(b)
    return ra is not None and rb is not None and ra == rb


def _slash_bass_pc(chord: str) -> int | None:
    if "/" not in chord:
        return None
    bass = chord.split("/", 1)[1].strip()
    if not bass:
        return None
    return _root_pc(bass)


def _shortness_score(dur: float) -> float:
    if dur <= 0:
        return 1.0
    if dur >= CANDIDATE_MAX_DUR:
        return float(max(0.0, 0.15 - (dur - CANDIDATE_MAX_DUR) / 8.0))
    return float(min(1.0, (CANDIDATE_MAX_DUR - dur) / CANDIDATE_MAX_DUR))


def _same_function_score(prev: _Seg, mid: _Seg, nxt: _Seg) -> float:
    ps, ms, ns = _simplify_label(prev.chord), _simplify_label(mid.chord), _simplify_label(nxt.chord)
    if ps == ns and ms != ps:
        return 0.78
    if _same_root(prev.chord, mid.chord) and _ornamental_surface(mid.chord) and (ps == ms or ms == ns):
        return 0.62
    if _same_root(mid.chord, nxt.chord) and _ornamental_surface(mid.chord) and (ms == ns or ps == ns):
        return 0.55
    if _same_root(prev.chord, mid.chord) and _same_root(mid.chord, nxt.chord) and _ornamental_surface(mid.chord):
        return 0.5
    return 0.0


def _sandwich_noise_score(prev: _Seg, mid: _Seg, nxt: _Seg) -> float:
    ps, ms, ns = _simplify_label(prev.chord), _simplify_label(mid.chord), _simplify_label(nxt.chord)
    if ps != ns or ms == ps:
        return 0.0
    if mid.dur >= SANDWICH_MAX_DUR:
        return 0.25
    return float(min(1.0, 0.35 + 0.65 * (SANDWICH_MAX_DUR - mid.dur) / SANDWICH_MAX_DUR))


def _ornamental_chord_score(chord: str) -> float:
    if _ornamental_surface(chord):
        return 0.62
    return 0.0


def _bass_walk_bonus(prev_pc: int | None, bass_pc: int | None, next_pc: int | None) -> float:
    if prev_pc is None or bass_pc is None or next_pc is None:
        return 0.0
    a = (bass_pc - prev_pc) % 12
    b = (next_pc - bass_pc) % 12
    if a in (1, 2, 11) and b in (1, 2, 11):
        return 0.22
    if a in (3, 4, 5) and b in (3, 4, 5):
        return 0.15
    return 0.0


def _transition_importance_score(
    prev: _Seg,
    mid: _Seg,
    nxt: _Seg,
    onset_norm: np.ndarray,
    chroma: np.ndarray,
    sr: int,
    hop: int,
    conf: float,
) -> float:
    ps, ms, ns = _simplify_label(prev.chord), _simplify_label(mid.chord), _simplify_label(nxt.chord)
    sc = 0.0
    c = (mid.chord or "").strip()
    if "/" in c and ps != ns:
        sc += 0.44
    elif "/" in c and ps != ms and ms != ns:
        sc += 0.36

    pr = _root_pc(prev.chord)
    nr = _root_pc(nxt.chord)
    bass_pc = _slash_bass_pc(mid.chord)
    sc += _bass_walk_bonus(pr, bass_pc, nr)

    if ps != ns and ps != ms and ms != ns:
        sc += 0.12

    o = _onset_peak_score(mid.start, onset_norm, sr, hop)
    ch = _chroma_change_score(mid.start, chroma, sr, hop)
    ev = 0.5 * o + 0.5 * ch
    sc += 0.26 * ev

    if conf >= 0.56:
        sc += 0.14 * min(1.0, (conf - 0.5) / 0.45)

    return float(min(1.0, sc))


def _strong_event_score(mid: _Seg, onset_norm: np.ndarray, chroma: np.ndarray, sr: int, hop: int) -> float:
    o = _onset_peak_score(mid.start, onset_norm, sr, hop)
    ch = _chroma_change_score(mid.start, chroma, sr, hop)
    return float(min(1.0, 0.5 * o + 0.5 * ch))


def _is_candidate(prev: _Seg, mid: _Seg, nxt: _Seg, conf: float) -> bool:
    dur = mid.dur
    ps, ms, ns = _simplify_label(prev.chord), _simplify_label(mid.chord), _simplify_label(nxt.chord)
    if dur < CANDIDATE_MAX_DUR:
        return True
    if conf < CANDIDATE_CONF:
        return True
    if ps == ns and ms != ps and dur < SANDWICH_MAX_DUR:
        return True
    if _ornamental_surface(mid.chord) and (ps == ms or ms == ns or ps == ns):
        return True
    return False


def _compress_chord_triple(prev: _Seg, mid: _Seg, nxt: _Seg) -> str:
    ps = _simplify_label(prev.chord)
    if _simplify_label(nxt.chord) == ps:
        if prev.dur >= nxt.dur:
            return prev.chord
        return nxt.chord
    return _merge_pair_chord(_merge_pair_chord(prev, mid), nxt)


def _choose_chord_compress(prev: _Seg, mid: _Seg, nxt: _Seg, into_prev: bool) -> str:
    ps, ms, ns = _simplify_label(prev.chord), _simplify_label(mid.chord), _simplify_label(nxt.chord)
    if ps == ns:
        if prev.dur + mid.dur >= nxt.dur + 1e-6:
            return prev.chord
        return nxt.chord
    if into_prev:
        if ps == ms:
            return prev.chord
        return _merge_pair_chord(prev, mid)
    if ms == ns:
        return nxt.chord
    return _merge_pair_chord(mid, nxt)


def _pick_compress_side(prev: _Seg, mid: _Seg, nxt: _Seg, merged: Sequence[_Seg]) -> tuple[str, str]:
    """返回 (\"prev\"|\"next\"|\"triple\", reason)。"""
    ps, ms, ns = _simplify_label(prev.chord), _simplify_label(mid.chord), _simplify_label(nxt.chord)
    if ps == ns and ms != ps:
        return "triple", "same_outer_simplify"
    conf_prev = _merged_agreement_score(prev.start, prev.end, prev.chord, merged, _simplify_label)
    conf_next = _merged_agreement_score(nxt.start, nxt.end, nxt.chord, merged, _simplify_label)
    same_prev_root = _same_root(prev.chord, mid.chord) and (_ornamental_surface(mid.chord) or ps == ms)
    same_next_root = _same_root(mid.chord, nxt.chord) and (_ornamental_surface(mid.chord) or ms == ns)
    if same_prev_root and not same_next_root:
        return "prev", "same_root_function_prev"
    if same_next_root and not same_prev_root:
        return "next", "same_root_function_next"
    if ps == ms and ps != ns:
        return "prev", "simplify_match_prev"
    if ms == ns and ps != ns:
        return "next", "simplify_match_next"
    score_prev = (conf_prev, prev.dur)
    score_next = (conf_next, nxt.dur)
    if score_prev > score_next:
        return "prev", "higher_conf_or_duration_prev"
    if score_next > score_prev:
        return "next", "higher_conf_or_duration_next"
    return "prev", "tie_prev"


def _apply_triple_merge(segs: list[_Seg], i: int, chord: str) -> None:
    prev, mid, nxt = segs[i - 1], segs[i], segs[i + 1]
    segs[i - 1] = _Seg(start=prev.start, end=nxt.end, chord=chord)
    del segs[i + 1]
    del segs[i]


def _apply_merge_into_prev(segs: list[_Seg], i: int, chord: str) -> None:
    prev, mid = segs[i - 1], segs[i]
    segs[i - 1] = _Seg(start=prev.start, end=max(prev.end, mid.end), chord=chord)
    del segs[i]


def _apply_merge_into_next(segs: list[_Seg], i: int, chord: str) -> None:
    mid, nxt = segs[i], segs[i + 1]
    segs[i + 1] = _Seg(start=mid.start, end=max(mid.end, nxt.end), chord=chord)
    del segs[i]


def _compute_compact_record(
    prev: _Seg,
    mid: _Seg,
    nxt: _Seg,
    merged: Sequence[_Seg],
    onset_norm: np.ndarray,
    chroma: np.ndarray,
    sr: int,
    hop: int,
) -> dict[str, Any]:
    conf = _merged_agreement_score(mid.start, mid.end, mid.chord, merged, _simplify_label)
    shortness = _shortness_score(mid.dur)
    same_fn = _same_function_score(prev, mid, nxt)
    low_conf = float(min(1.0, max(0.0, 1.0 - conf)))
    sandwich = _sandwich_noise_score(prev, mid, nxt)
    ornamental = _ornamental_chord_score(mid.chord)
    trans = _transition_importance_score(prev, mid, nxt, onset_norm, chroma, sr, hop, conf)
    strong_ev = _strong_event_score(mid, onset_norm, chroma, sr, hop)
    removable = (
        0.30 * shortness
        + 0.25 * same_fn
        + 0.20 * low_conf
        + 0.15 * sandwich
        + 0.10 * ornamental
        - 0.30 * trans
        - 0.20 * strong_ev
    )
    removable = float(max(0.0, min(1.2, removable)))
    return {
        "chord": mid.chord,
        "start": round(mid.start, 4),
        "end": round(mid.end, 4),
        "duration": round(mid.dur, 4),
        "confidence": round(conf, 4),
        "removableScore": round(removable, 4),
        "shortnessScore": round(shortness, 4),
        "sameFunctionScore": round(same_fn, 4),
        "lowConfidenceScore": round(low_conf, 4),
        "sandwichNoiseScore": round(sandwich, 4),
        "ornamentalChordScore": round(ornamental, 4),
        "transitionImportanceScore": round(trans, 4),
        "strongEventScore": round(strong_ev, 4),
    }


def build_timing_compact_segments(
    *,
    y: np.ndarray,
    sr: int,
    timing_segments: Sequence[Any],
    merged_segments: Sequence[Any],
    hop_length: int = HOP_LENGTH_DEFAULT,
) -> dict[str, Any]:
    segs: list[_Seg] = []
    for s in timing_segments:
        if isinstance(s, dict):
            segs.append(
                _Seg(start=float(s["start"]), end=float(s["end"]), chord=str(s.get("chord", "") or ""))
            )
        else:
            segs.append(
                _Seg(
                    start=float(getattr(s, "start")),
                    end=float(getattr(s, "end")),
                    chord=str(getattr(s, "chord", "") or ""),
                )
            )
    segs = [s for s in segs if s.end > s.start + 1e-6]
    segs.sort(key=lambda x: (x.start, x.end))
    merged: list[_Seg] = []
    for m in merged_segments:
        if isinstance(m, dict):
            merged.append(
                _Seg(
                    start=float(m["start"]),
                    end=float(m["end"]),
                    chord=str(m.get("chord", "") or ""),
                )
            )
        else:
            merged.append(
                _Seg(
                    start=float(getattr(m, "start")),
                    end=float(getattr(m, "end")),
                    chord=str(getattr(m, "chord", "") or ""),
                )
            )

    hop = hop_length
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
    onset_norm = (onset_env - float(np.min(onset_env))) / (float(np.ptp(onset_env)) + 1e-6)
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=hop, n_chroma=12)

    debug_rows: list[dict[str, Any]] = []
    compressed = 0
    safety = 0
    changed = True
    while changed and safety < 4000:
        safety += 1
        changed = False
        if len(segs) < 3:
            break
        for i in range(1, len(segs) - 1):
            prev, mid, nxt = segs[i - 1], segs[i], segs[i + 1]
            conf = _merged_agreement_score(mid.start, mid.end, mid.chord, merged, _simplify_label)
            if not _is_candidate(prev, mid, nxt, conf):
                continue
            rec = _compute_compact_record(prev, mid, nxt, merged, onset_norm, chroma, sr, hop)
            trans = rec["transitionImportanceScore"]
            rem = rec["removableScore"]
            force = mid.dur < FORCE_DUR_SEC and conf < FORCE_CONF_MAX

            if trans >= TRANSITION_BLOCK:
                rec["decision"] = "preserve"
                rec["compressInto"] = ""
                rec["reason"] = "transition_importance_block"
                debug_rows.append(rec)
                logger.info(
                    "[timing_compact] preserve chord=%s dur=%.3f removable=%.3f trans=%.3f strongEv=%.3f reason=%s",
                    mid.chord,
                    mid.dur,
                    rem,
                    trans,
                    rec["strongEventScore"],
                    rec["reason"],
                )
                continue

            if force and trans >= TRANSITION_FORCE_BLOCK:
                rec["decision"] = "preserve"
                rec["compressInto"] = ""
                rec["reason"] = "force_short_low_conf_blocked_by_transition"
                debug_rows.append(rec)
                logger.info(
                    "[timing_compact] preserve chord=%s dur=%.3f removable=%.3f trans=%.3f reason=%s",
                    mid.chord,
                    mid.dur,
                    rem,
                    trans,
                    rec["reason"],
                )
                continue

            if rem < REMOVABLE_THRESHOLD and not force:
                rec["decision"] = "preserve"
                rec["compressInto"] = ""
                rec["reason"] = "below_removable_threshold"
                debug_rows.append(rec)
                logger.info(
                    "[timing_compact] preserve chord=%s dur=%.3f removable=%.3f trans=%.3f reason=%s",
                    mid.chord,
                    mid.dur,
                    rem,
                    trans,
                    rec["reason"],
                )
                continue

            side, why = _pick_compress_side(prev, mid, nxt, merged)
            if side == "triple":
                chord = _compress_chord_triple(prev, mid, nxt)
                rec["decision"] = "compress"
                rec["compressInto"] = "both"
                rec["reason"] = why
                debug_rows.append(rec)
                logger.info(
                    "[timing_compact] compress triple chord=%s dur=%.3f removable=%.3f trans=%.3f",
                    mid.chord,
                    mid.dur,
                    rem,
                    trans,
                )
                _apply_triple_merge(segs, i, chord)
                compressed += 1
                changed = True
                break

            if side == "prev":
                chord = _choose_chord_compress(prev, mid, nxt, True)
                rec["decision"] = "compress"
                rec["compressInto"] = "previous"
                rec["reason"] = why
                debug_rows.append(rec)
                logger.info(
                    "[timing_compact] compress->prev chord=%s dur=%.3f removable=%.3f reason=%s",
                    mid.chord,
                    mid.dur,
                    rem,
                    why,
                )
                _apply_merge_into_prev(segs, i, chord)
            else:
                chord = _choose_chord_compress(prev, mid, nxt, False)
                rec["decision"] = "compress"
                rec["compressInto"] = "next"
                rec["reason"] = why
                debug_rows.append(rec)
                logger.info(
                    "[timing_compact] compress->next chord=%s dur=%.3f removable=%.3f reason=%s",
                    mid.chord,
                    mid.dur,
                    rem,
                    why,
                )
                _apply_merge_into_next(segs, i, chord)
            compressed += 1
            changed = True
            break

    segs = _merge_adjacent_same(segs, 0.0)
    final_list = _enforce_monotone_min_len(segs)
    segments_payload = [
        {"start": round(s.start, 3), "end": round(s.end, 3), "chord": s.chord, "confidence": 1.0} for s in final_list
    ]

    preserved_transition = sum(
        1
        for r in debug_rows
        if r.get("decision") == "preserve"
        and float(r.get("transitionImportanceScore", 0.0) or 0.0) >= 0.42
        and (
            r.get("reason") == "transition_importance_block"
            or r.get("reason") == "force_short_low_conf_blocked_by_transition"
            or ("/" in str(r.get("chord", "")) and float(r.get("removableScore", 0.0) or 0.0) >= REMOVABLE_THRESHOLD)
        )
    )

    return {
        "segments": segments_payload,
        "stats": {
            "compressedCount": compressed,
            "preservedTransitionCount": preserved_transition,
        },
        "debug": {
            "timingCompactSegments": debug_rows,
        },
    }
