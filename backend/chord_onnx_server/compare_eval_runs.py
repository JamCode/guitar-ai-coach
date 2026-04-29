#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Mapping

from eval_metrics import get_nested


METRICS: list[tuple[str, str]] = [
    ("segment_count", "raw"),
    ("short_raw_lt_0_7", "raw<0.7s"),
    ("display_count", "display"),
    ("chart_count", "chart"),
    ("segments_metrics.complex_count", "raw_complex"),
    ("display_metrics.complex_count", "display_complex"),
    ("chart_metrics.complex_count", "chart_complex"),
    ("timing_stats.displayCount", "timing_display"),
    ("timing_stats.chordChartCount", "timing_chart"),
    ("timing_gap_metrics.gap_count", "timing_gaps"),
    ("timing_gap_metrics.max_gap_sec", "timing_max_gap"),
]


def _load_summary(path: Path) -> list[dict[str, Any]]:
    summary_path = path / "_summary.json" if path.is_dir() else path
    obj = json.loads(summary_path.read_text(encoding="utf-8"))
    if not isinstance(obj, list):
        raise ValueError(f"summary must be a list: {summary_path}")
    return [row for row in obj if isinstance(row, dict)]


def _index_by_alias(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for row in rows:
        alias = str(row.get("alias", "")).strip()
        if not alias:
            continue
        out[alias] = row
    return out


def _fmt_value(value: Any) -> str:
    if isinstance(value, float):
        return f"{value:.3f}"
    return str(value)


def _fmt_delta(before: Any, after: Any) -> str:
    if before is None or after is None:
        return f"{_fmt_value(before)} -> {_fmt_value(after)}"
    if isinstance(before, (int, float)) and isinstance(after, (int, float)):
        delta = after - before
        if isinstance(before, int) and isinstance(after, int):
            return f"{before} -> {after} ({delta:+d})"
        return f"{before:.3f} -> {after:.3f} ({delta:+.3f})"
    return f"{_fmt_value(before)} -> {_fmt_value(after)}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare two local chord eval run summaries.")
    parser.add_argument("baseline", help="Baseline eval run dir or _summary.json path.")
    parser.add_argument("candidate", help="Candidate eval run dir or _summary.json path.")
    parser.add_argument(
        "--out-json",
        help="Optional path to write machine-readable comparison JSON.",
    )
    args = parser.parse_args()

    baseline_rows = _load_summary(Path(args.baseline).expanduser().resolve())
    candidate_rows = _load_summary(Path(args.candidate).expanduser().resolve())
    baseline = _index_by_alias(baseline_rows)
    candidate = _index_by_alias(candidate_rows)
    aliases = sorted(set(baseline) | set(candidate))

    compare_rows: list[dict[str, Any]] = []
    print("alias")
    for alias in aliases:
        left = baseline.get(alias, {})
        right = candidate.get(alias, {})
        print(f"- {alias}")
        row: dict[str, Any] = {"alias": alias, "metrics": {}}
        for path, label in METRICS:
            before = get_nested(left, path)
            after = get_nested(right, path)
            row["metrics"][path] = {"before": before, "after": after}
            print(f"  {label}: {_fmt_delta(before, after)}")
        compare_rows.append(row)

    if args.out_json:
        out_path = Path(args.out_json).expanduser().resolve()
        out_path.write_text(json.dumps(compare_rows, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\ncomparison_json: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
