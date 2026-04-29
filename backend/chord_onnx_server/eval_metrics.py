from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Mapping, Sequence


COMPLEX_CHORD_RE = re.compile(r"(maj7|m7|7|sus|dim|aug|/|5)")


def safe_stem(path: Path) -> str:
    return "".join(ch if ch.isalnum() or ch in {"-", "_"} else "_" for ch in path.stem).strip("_") or "audio"


def segment_rows(payload: Mapping[str, Any], field: str) -> list[dict[str, Any]]:
    rows = payload.get(field, [])
    if not isinstance(rows, list):
        return []
    return [row for row in rows if isinstance(row, dict)]


def segment_metrics(payload: Mapping[str, Any], field: str) -> dict[str, int]:
    rows = segment_rows(payload, field)
    chords = [str(row.get("chord", "")).strip() for row in rows if str(row.get("chord", "")).strip()]
    complex_chords = [ch for ch in chords if COMPLEX_CHORD_RE.search(ch)]
    return {
        "count": len(chords),
        "complex_count": len(complex_chords),
        "unique_chords": len(set(chords)),
        "unique_complex_chords": len(set(complex_chords)),
    }


def short_segment_count(
    payload: Mapping[str, Any],
    field: str,
    *,
    max_duration_sec: float,
) -> int:
    total = 0
    for row in segment_rows(payload, field):
        try:
            dur = float(row["end"]) - float(row["start"])
        except (KeyError, TypeError, ValueError):
            continue
        if dur < max_duration_sec:
            total += 1
    return total


def gap_metrics(rows: Sequence[Mapping[str, Any]]) -> dict[str, float]:
    max_gap = 0.0
    gap_count = 0
    for prev, cur in zip(rows, rows[1:]):
        try:
            gap = float(cur["start"]) - float(prev["end"])
        except (KeyError, TypeError, ValueError):
            continue
        if gap > 1e-6:
            gap_count += 1
            max_gap = max(max_gap, gap)
    return {
        "gap_count": gap_count,
        "max_gap_sec": round(max_gap, 3),
    }


def summarize_payload(
    payload: Mapping[str, Any],
    *,
    alias: str,
    file_path: str,
    out_file: str,
    elapsed_sec: float | None = None,
) -> dict[str, Any]:
    timing_stats = payload.get("timingVariantStats", {})
    timing_variant = {}
    if isinstance(timing_stats, dict):
        timing_variant = timing_stats.get("timing", {}) if isinstance(timing_stats.get("timing", {}), dict) else {}
    timing_rows = []
    timing_variants = payload.get("timingVariants", {})
    if isinstance(timing_variants, dict):
        timing = timing_variants.get("timing", {})
        if isinstance(timing, dict):
            rows = timing.get("displaySegments", [])
            if isinstance(rows, list):
                timing_rows = [row for row in rows if isinstance(row, dict)]
    debug = payload.get("debug", {})
    return {
        "alias": alias,
        "file": file_path,
        "success": bool(payload.get("success") is True),
        "out_file": out_file,
        "key": payload.get("key"),
        "duration": payload.get("duration"),
        "elapsed_sec": round(elapsed_sec, 3) if elapsed_sec is not None else None,
        "segment_count": len(segment_rows(payload, "segments")),
        "display_count": len(segment_rows(payload, "displaySegments")),
        "chart_count": len(segment_rows(payload, "chordChartSegments")),
        "segments_metrics": segment_metrics(payload, "segments"),
        "display_metrics": segment_metrics(payload, "displaySegments"),
        "chart_metrics": segment_metrics(payload, "chordChartSegments"),
        "short_raw_lt_0_7": short_segment_count(payload, "segments", max_duration_sec=0.7),
        "timing_stats": timing_variant,
        "timing_gap_metrics": gap_metrics(timing_rows),
        "raw_segment_count": debug.get("rawSegmentCount") if isinstance(debug, dict) else None,
    }


def get_nested(summary_row: Mapping[str, Any], path: str) -> Any:
    cur: Any = summary_row
    for part in path.split("."):
        if not isinstance(cur, Mapping) or part not in cur:
            return None
        cur = cur[part]
    return cur
