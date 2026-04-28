"""
通用和弦谱后处理：将 raw/简化后的时间轴和弦段规整为适合整首曲谱展示的形态。
不修改模型推理，仅对 segments 做合并与吸收；可供 transcribe 或 API 后处理复用。
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Mapping

# 谱面展示偏“弹唱参考”，比逐帧识别更积极地吸收短暂经过/误判片段。
SHORT_CHORD_ABSORB_SEC = 1.5
OUT_OF_KEY_ABSORB_SEC = 2.0
COMPLEX_CHORD_ABSORB_SEC = 2.0
LOW_CONFIDENCE_ABSORB_SEC = 2.0
ADJACENT_MERGE_TOLERANCE_SEC = 0.2

# 常见大调的主干和声（与产品约定一致，可扩展）
MAJOR_KEY_CORE_CHORDS: dict[str, frozenset[str]] = {
    "A": frozenset({"A", "Bm", "C#m", "D", "E", "E7", "F#m", "C#7"}),
    "C": frozenset({"C", "Dm", "Em", "F", "G", "G7", "Am", "E7"}),
    "D": frozenset({"D", "Em", "F#m", "G", "A", "A7", "Bm", "F#7"}),
    "G": frozenset({"G", "Am", "Bm", "C", "D", "D7", "Em", "B7"}),
    "E": frozenset({"E", "F#m", "G#m", "A", "B", "B7", "C#m", "G#7"}),
}


def _core_set_for_key(estimated_key: str | None) -> frozenset[str] | None:
    """大调 A/C/D/G/E 有主干表；小调、未知调返回 None（不启用 D 类吸收）。"""
    if not estimated_key:
        return None
    k0 = str(estimated_key).strip()
    k0 = re.sub(r"(?i)\s+major\s*$", "", k0)
    if k0.lower().endswith("maj"):
        k0 = k0[:-3].strip()
    if re.match(r"^[A-G](?:#|b)?m$", k0):
        return None
    m = re.match(r"^([A-G](?:#|b)?)", k0)
    if not m:
        return None
    tonic = m.group(1)
    return MAJOR_KEY_CORE_CHORDS.get(tonic)


@dataclass
class _Seg:
    start: float
    end: float
    chord: str
    confidence: float = 1.0
    was_complex: bool = False
    original_chord: str | None = None

    @property
    def duration(self) -> float:
        return max(0.0, self.end - self.start)


def _strip_bass(chord: str) -> str:
    s = (chord or "").strip()
    if not s:
        return s
    return s.split("/")[0].strip()


def _strip_figures(chord: str) -> str:
    """用于离调/装饰判断：F#:(1) -> F#、Bm7(11) -> Bm7。"""
    s = _strip_bass(chord)
    if "(" in s:
        s = s.split("(")[0].strip()
    if ":" in s:
        s = s.split(":")[0].strip()
    s = re.sub(r"\s+", "", s)
    return s


def _chord_in_core(chord: str, core: frozenset[str] | None) -> bool:
    if not core:
        return False
    base = _strip_figures(_strip_bass(chord))
    if not base:
        return False
    if base in core:
        return True
    return False


def simplify_chord_for_reference(chord: str) -> str:
    """统一给播放器时间轴与参考和弦谱使用的保守和弦名。"""
    base = _strip_figures(_strip_bass(chord))
    if not base:
        return chord
    m = re.match(r"^([A-G](?:#|b)?)(.*)$", base)
    if not m:
        return base
    root, suffix = m.group(1), m.group(2)
    suffix_l = suffix.lower()

    if suffix_l.startswith("m") and not suffix_l.startswith("maj"):
        return f"{root}m"
    return root


def _is_complex_chord(chord: str) -> bool:
    base = _strip_figures(_strip_bass(chord))
    if not base:
        return False
    m = re.match(r"^[A-G](?:#|b)?(.*)$", base)
    if not m:
        return True
    suffix = m.group(1).lower()
    if suffix in {"", "m"}:
        return False
    return True


def _parse_raw_segment(
    s: Mapping[str, Any] | _Seg,
) -> _Seg:
    if isinstance(s, _Seg):
        return s
    start = float(s["start"])
    end = float(s["end"])
    chord = str(s.get("chord", ""))
    conf = s.get("confidence", 1.0)
    try:
        c = float(conf) if conf is not None else 1.0
    except (TypeError, ValueError):
        c = 1.0
    return _Seg(start=start, end=end, chord=chord, confidence=c)


def _to_output_dicts(segs: list[_Seg]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for s in segs:
        d: dict[str, Any] = {
            "start": round(s.start, 3),
            "end": round(s.end, 3),
            "chord": s.chord,
            "confidence": round(s.confidence, 4),
        }
        out.append(d)
    return out


def _merge_adjacent_same(segs: list[_Seg], tolerance_sec: float = 0.0) -> list[_Seg]:
    if not segs:
        return []
    segs = sorted(segs, key=lambda x: (x.start, x.end))
    out: list[_Seg] = [segs[0]]
    for s in segs[1:]:
        last = out[-1]
        touch = s.start <= last.end + tolerance_sec
        if s.chord == last.chord and touch:
            c_dur = last.duration + s.duration
            w = 0.0 if c_dur <= 0 else (last.confidence * last.duration + s.confidence * s.duration) / c_dur
            out[-1] = _Seg(
                start=last.start,
                end=max(last.end, s.end),
                chord=last.chord,
                confidence=w,
                was_complex=last.was_complex or s.was_complex,
                original_chord=last.original_chord or s.original_chord,
            )
        else:
            out.append(s)
    return out


def _merge_pair_chord(a: _Seg, b: _Seg, core: frozenset[str] | None) -> str:
    """两段时间合并为一段后展示用的和弦名。"""
    if _chord_in_core(a.chord, core) and not _chord_in_core(b.chord, core):
        return a.chord
    if _chord_in_core(b.chord, core) and not _chord_in_core(a.chord, core):
        return b.chord
    if a.chord == b.chord:
        return a.chord
    if a.duration >= b.duration:
        return a.chord
    return b.chord


def _has_same_surrounding_chord(i: int, working: list[_Seg]) -> bool:
    seg = working[i]
    prev = working[i - 1] if i > 0 else None
    nxt = working[i + 1] if i + 1 < len(working) else None
    return (
        prev is not None
        and nxt is not None
        and prev.chord == nxt.chord
        and prev.duration >= 1.0
        and nxt.duration >= 1.0
    )


def _pick_target_absorb(
    i: int,
    working: list[_Seg],
    core: frozenset[str] | None,
) -> int | None:
    """B：优先同和弦邻居、再主干、再较长邻居。返回要合并到的一侧 index。"""
    seg = working[i]
    prev = i - 1 if i > 0 else None
    nxt = i + 1 if i + 1 < len(working) else None
    if prev is None and nxt is None:
        return None
    if prev is not None and working[prev].chord == seg.chord:
        return prev
    if nxt is not None and working[nxt].chord == seg.chord:
        return nxt
    if prev is not None and _chord_in_core(working[prev].chord, core):
        return prev
    if nxt is not None and _chord_in_core(working[nxt].chord, core):
        return nxt
    if prev is not None and nxt is not None:
        pd, nd = working[prev].duration, working[nxt].duration
        return prev if pd >= nd else nxt
    return prev if prev is not None else nxt


def _absorb_index_into(working: list[_Seg], i: int, j: int, core: frozenset[str] | None) -> None:
    if i == j:
        return
    a, b = working[i], working[j]
    lo, hi = (i, j) if i < j else (j, i)
    s1, s2 = working[lo], working[hi]
    wsum = s1.duration + s2.duration
    w = 1.0 if wsum <= 0 else (s1.confidence * s1.duration + s2.confidence * s2.duration) / wsum
    merged = _Seg(
        start=min(s1.start, s2.start),
        end=max(s1.end, s2.end),
        chord=_merge_pair_chord(s1, s2, core),
        confidence=w,
        was_complex=s1.was_complex or s2.was_complex,
        original_chord=s1.original_chord or s2.original_chord,
    )
    working[lo] = merged
    working.pop(hi)


def _iter_absorb(
    working: list[_Seg],
    core: frozenset[str] | None,
    rule: str,
) -> int:
    """尝试一次只吸收一个片段；返回本规则下吸收次数 0/1（外层循环到不动）。"""
    for i, seg in enumerate(working):
        d = seg.duration
        if d <= 0:
            continue
        absorb = False
        if rule == "B" and d < SHORT_CHORD_ABSORB_SEC and _has_same_surrounding_chord(i, working):
            absorb = True
        elif rule == "D" and core is not None and not _chord_in_core(seg.chord, core) and d < OUT_OF_KEY_ABSORB_SEC:
            absorb = True
        elif rule == "C" and seg.was_complex and d < COMPLEX_CHORD_ABSORB_SEC:
            absorb = True
        elif rule == "E" and seg.confidence < 0.45 and d < LOW_CONFIDENCE_ABSORB_SEC:
            absorb = True
        if not absorb:
            continue
        t = _pick_target_absorb(i, working, core)
        if t is None:
            continue
        _absorb_index_into(working, i, t, core)
        return 1
    return 0


def _run_absorption_loop(working: list[_Seg], core: frozenset[str] | None) -> dict[str, int]:
    """顺序：B 系列 -> D 系列 -> E 系列，各系列内吸到稳定再下一系列。"""
    short = 0
    ood = 0
    complex_ = 0
    lowc = 0
    for rule, which in (("C", "complex"), ("D", "ood"), ("B", "short"), ("E", "low")):
        while True:
            n = _iter_absorb(working, core, rule)
            if n == 0:
                break
            if which == "short":
                short += 1
            elif which == "ood":
                ood += 1
            elif which == "complex":
                complex_ += 1
            else:
                lowc += 1
            working[:] = _merge_adjacent_same(working, ADJACENT_MERGE_TOLERANCE_SEC)
    return {
        "absorbedShortChordCount": short,
        "absorbedOutOfKeyCount": ood,
        "absorbedComplexChordCount": complex_,
        "absorbedLowConfidenceCount": lowc,
    }


def build_chord_chart_text(chord_names: list[str]) -> str:
    """每 4 个和弦一行，只含和弦名，空格分隔。"""
    if not chord_names:
        return ""
    lines: list[str] = []
    for i in range(0, len(chord_names), 4):
        lines.append(" ".join(chord_names[i : i + 4]).strip())
    return "\n".join(lines).strip()


def build_chord_chart_segments(
    raw_segments: list[Mapping[str, Any] | _Seg] | list[Any],
    estimated_key: str | None = None,
) -> dict[str, Any]:
    """
    从时间轴 raw segments 构建 chord chart 用片段与文字。

    每个输入 segment 建议包含: start, end, chord；可选 confidence（缺省 1.0）。

    返回:
      - chordChartSegments: list[dict]（含 confidence）
      - chordChartText: 多行字符串
      - debug: 统计与 chordChartText
    """
    raw_n = len(raw_segments)
    if not raw_segments:
        return {
            "chordChartSegments": [],
            "chordChartText": "",
            "debug": {
                "rawSegmentCount": 0,
                "chordChartSegmentCount": 0,
                "absorbedShortChordCount": 0,
                "absorbedOutOfKeyCount": 0,
                "absorbedLowConfidenceCount": 0,
                "estimatedKey": estimated_key,
                "chordChartText": "",
            },
        }

    parsed = [_parse_raw_segment(s) for s in raw_segments]
    simplified_complex_count = 0
    segs: list[_Seg] = []
    for seg in parsed:
        simplified = simplify_chord_for_reference(seg.chord)
        was_complex = _is_complex_chord(seg.chord)
        if simplified != _strip_figures(_strip_bass(seg.chord)):
            simplified_complex_count += 1
        segs.append(
            _Seg(
                start=seg.start,
                end=seg.end,
                chord=simplified,
                confidence=seg.confidence,
                was_complex=was_complex,
                original_chord=seg.chord,
            )
        )
    # A. 先合并相邻同和弦
    working = _merge_adjacent_same(segs, ADJACENT_MERGE_TOLERANCE_SEC)
    core = _core_set_for_key(estimated_key)

    absorb_stats = _run_absorption_loop(working, core)
    # F. 再合并
    final = _merge_adjacent_same(working, 0.0)
    names = [s.chord for s in final]
    text = build_chord_chart_text(names)
    out_segs = _to_output_dicts(final)
    debug: dict[str, Any] = {
        "rawSegmentCount": raw_n,
        "chordChartSegmentCount": len(final),
        "absorbedShortChordCount": absorb_stats["absorbedShortChordCount"],
        "absorbedOutOfKeyCount": absorb_stats["absorbedOutOfKeyCount"],
        "absorbedComplexChordCount": absorb_stats["absorbedComplexChordCount"],
        "absorbedLowConfidenceCount": absorb_stats["absorbedLowConfidenceCount"],
        "simplifiedComplexChordCount": simplified_complex_count,
        "estimatedKey": estimated_key,
        "chordChartText": text,
    }
    return {
        "chordChartSegments": out_segs,
        "chordChartText": text,
        "debug": debug,
    }
