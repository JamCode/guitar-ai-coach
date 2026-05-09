"""chord_bench v1 evaluator.

加载 ground_truth.json + 所有 wav，调用 pipeline.recognize，产出两份报告：
- reports/bench_result.json（机器可读）
- reports/bench_report.md（人类可读）

评估口径：
- 单标签类（single_note / triad / interference）：
    * root hit = pipeline 输出的 "主标签" 的根音 == ground truth 根音
    * label hit = pipeline 输出的 "主标签" 完整 == ground truth 标签
  其中 "主标签" = pipeline 所有段落里持续时长最长的那段（去掉 "N"）。
  对 single_note 的 label hit 口径是：主标签根音命中（单音不期望输出成完整和弦名）。
- 时间线类（progression）：
    * 对每段 GT 段，取其中间 60% 窗口内 pipeline 的加权多数标签，判断 root / label
    * 段级准确率：root_hit_rate / label_hit_rate
"""

from __future__ import annotations

import json
import os
import sys
import time
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional, Tuple

import numpy as np
import soundfile as sf
import onnxruntime as ort

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from pipeline import (  # type: ignore  # noqa: E402
    recognize,
    _chord_root,
    TARGET_SR,
)


SAMPLES_DIR = os.path.join(HERE, "samples")
REPORTS_DIR = os.path.join(HERE, "reports")
MODEL_PATH = os.path.join(
    "/workspace", "swift_ios_host", "Sources", "Transcription", "Resources",
    "consonance_ace.onnx",
)


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

def extract_root(label: str) -> str:
    if not label or label == "N":
        return ""
    return _chord_root(label)


def longest_segment(segments: List[dict]) -> Optional[dict]:
    best = None
    best_dur = -1
    for s in segments:
        if s.get("chord") in ("", "N"):
            continue
        dur = s.get("end_ms", 0) - s.get("start_ms", 0)
        if dur > best_dur:
            best_dur = dur
            best = s
    return best


def majority_label_in_range(segments: List[dict],
                            window_start: int, window_end: int) -> Tuple[str, int]:
    """在 [window_start, window_end) 里按时长加权取多数标签。"""
    weights: Dict[str, int] = {}
    for s in segments:
        a = max(s["start_ms"], window_start)
        b = min(s["end_ms"], window_end)
        if b <= a:
            continue
        weights[s["chord"]] = weights.get(s["chord"], 0) + (b - a)
    if not weights:
        return "", 0
    label, dur = max(weights.items(), key=lambda kv: kv[1])
    return label, dur


# -----------------------------------------------------------------------------
# Scoring
# -----------------------------------------------------------------------------

@dataclass
class CaseResult:
    id: str
    category: str
    duration_ms: int

    expected_single_label: str
    predicted_main_label: str
    predicted_main_root: str
    root_hit: bool
    label_hit: bool

    # 仅 progression 用
    segment_evaluations: List[dict]
    segment_root_hits: int
    segment_label_hits: int
    segment_total: int

    original_key: str
    raw_frame_count: int
    all_segments: List[dict]  # 原始输出，便于人类排查


def score_single_label(expected_label: str, segments: List[dict],
                       category: str) -> Tuple[str, str, bool, bool]:
    main = longest_segment(segments)
    if not main:
        return "", "", False, False
    pred = main["chord"]
    pred_root = extract_root(pred)
    if category == "single_note":
        # 单音不要求完整和弦名命中，只看 root
        root_hit = pred_root == expected_label
        label_hit = root_hit  # 单音场景下 label 口径等同 root
    else:
        root_hit = pred_root == extract_root(expected_label)
        label_hit = pred == expected_label
    return pred, pred_root, root_hit, label_hit


def score_progression(gt_segments: List[dict], pred_segments: List[dict]) -> dict:
    evals = []
    root_hits = 0
    label_hits = 0
    for seg in gt_segments:
        start = seg["start_ms"]
        end = seg["end_ms"]
        span = end - start
        # 每段只看中间 60%，避开边界瞬态
        window_start = start + int(span * 0.2)
        window_end = end - int(span * 0.2)
        label, _ = majority_label_in_range(pred_segments, window_start, window_end)
        pred_root = extract_root(label)
        gt_label = seg["chord_label"]
        gt_root = extract_root(gt_label)
        r = pred_root == gt_root
        l = label == gt_label
        if r:
            root_hits += 1
        if l:
            label_hits += 1
        evals.append({
            "gt_start_ms": start,
            "gt_end_ms": end,
            "gt_label": gt_label,
            "window": [window_start, window_end],
            "predicted_label": label,
            "predicted_root": pred_root,
            "root_hit": r,
            "label_hit": l,
        })
    return {
        "evals": evals,
        "root_hits": root_hits,
        "label_hits": label_hits,
        "total": len(gt_segments),
    }


# -----------------------------------------------------------------------------
# Runner
# -----------------------------------------------------------------------------

def run():
    if not os.path.exists(MODEL_PATH):
        print("ERROR: model not found:", MODEL_PATH, file=sys.stderr)
        sys.exit(1)

    gt_path = os.path.join(SAMPLES_DIR, "ground_truth.json")
    with open(gt_path) as f:
        gt = json.load(f)

    sess = ort.InferenceSession(MODEL_PATH,
                                providers=["CPUExecutionProvider"])
    print("Loaded ACE model:", MODEL_PATH)

    results: List[CaseResult] = []
    run_errors = []

    t0 = time.time()
    for case in gt["cases"]:
        wav_path = os.path.join(SAMPLES_DIR, case["filename"])
        try:
            samples, sr = sf.read(wav_path, dtype="float32")
            if samples.ndim == 2:
                samples = samples.mean(axis=1)
            out = recognize(sess, samples.astype(np.float32), float(sr))
        except Exception as exc:  # noqa: BLE001
            run_errors.append({"id": case["id"], "error": str(exc)})
            continue

        if case["category"] == "progression":
            prog = score_progression(case["segments"], out["segments"])
            # progression 不做 single-label 判定，只做段级
            results.append(CaseResult(
                id=case["id"],
                category=case["category"],
                duration_ms=case["duration_ms"],
                expected_single_label="",
                predicted_main_label="",
                predicted_main_root="",
                root_hit=False,
                label_hit=False,
                segment_evaluations=prog["evals"],
                segment_root_hits=prog["root_hits"],
                segment_label_hits=prog["label_hits"],
                segment_total=prog["total"],
                original_key=out["original_key"],
                raw_frame_count=out["raw_frame_count"],
                all_segments=out["segments"],
            ))
        else:
            pred, pred_root, r, l = score_single_label(
                case["expected_single_label"],
                out["segments"],
                case["category"],
            )
            results.append(CaseResult(
                id=case["id"],
                category=case["category"],
                duration_ms=case["duration_ms"],
                expected_single_label=case["expected_single_label"],
                predicted_main_label=pred,
                predicted_main_root=pred_root,
                root_hit=r,
                label_hit=l,
                segment_evaluations=[],
                segment_root_hits=0,
                segment_label_hits=0,
                segment_total=0,
                original_key=out["original_key"],
                raw_frame_count=out["raw_frame_count"],
                all_segments=out["segments"],
            ))

    elapsed = time.time() - t0

    # ---- 聚合 ----
    def summarize(category: str, use_segment: bool = False):
        rs = [r for r in results if r.category == category]
        if use_segment:
            total = sum(r.segment_total for r in rs)
            rh = sum(r.segment_root_hits for r in rs)
            lh = sum(r.segment_label_hits for r in rs)
            return {
                "count": len(rs),
                "segment_total": total,
                "segment_root_hit_rate": (rh / total) if total else 0.0,
                "segment_label_hit_rate": (lh / total) if total else 0.0,
            }
        return {
            "count": len(rs),
            "root_hit_rate": (sum(1 for r in rs if r.root_hit) / len(rs)) if rs else 0.0,
            "label_hit_rate": (sum(1 for r in rs if r.label_hit) / len(rs)) if rs else 0.0,
        }

    summary = {
        "sample_count": len(gt["cases"]),
        "evaluated_count": len(results),
        "run_errors": run_errors,
        "elapsed_sec": round(elapsed, 2),
        "per_category": {
            "single_note": summarize("single_note"),
            "triad": summarize("triad"),
            "progression": summarize("progression", use_segment=True),
            "interference": summarize("interference"),
        },
    }

    os.makedirs(REPORTS_DIR, exist_ok=True)
    json_path = os.path.join(REPORTS_DIR, "bench_result.json")
    with open(json_path, "w") as f:
        json.dump({
            "summary": summary,
            "cases": [asdict(r) for r in results],
        }, f, indent=2, ensure_ascii=False)
    print("Wrote", json_path)

    md_path = os.path.join(REPORTS_DIR, "bench_report.md")
    write_markdown(md_path, summary, results)
    print("Wrote", md_path)

    print_console_summary(summary, results)


def write_markdown(path: str, summary: dict, results: List[CaseResult]):
    lines = []
    lines.append("# chord_bench v1 report\n")
    lines.append(f"- 模型：`consonance_ace.onnx`")
    lines.append(f"- 样本总数：{summary['sample_count']}")
    lines.append(f"- 成功评估：{summary['evaluated_count']}")
    lines.append(f"- 用时：{summary['elapsed_sec']}s")
    if summary["run_errors"]:
        lines.append(f"- 运行报错：{len(summary['run_errors'])}")
        for err in summary["run_errors"]:
            lines.append(f"  - `{err['id']}`: {err['error']}")
    lines.append("")

    # 汇总表
    pc = summary["per_category"]
    lines.append("## 按类别汇总\n")
    lines.append("| 类别 | 数量 | root 命中率 | label 命中率 |")
    lines.append("|---|---|---|---|")
    for cat in ["single_note", "triad", "interference"]:
        c = pc[cat]
        rr = f"{c['root_hit_rate'] * 100:.1f}%"
        lr = f"{c['label_hit_rate'] * 100:.1f}%"
        lines.append(f"| {cat} | {c['count']} | {rr} | {lr} |")
    pp = pc["progression"]
    lines.append(
        f"| progression (段级) | {pp['count']} | "
        f"{pp['segment_root_hit_rate'] * 100:.1f}% ({int(round(pp['segment_root_hit_rate'] * pp['segment_total']))}/{pp['segment_total']}) | "
        f"{pp['segment_label_hit_rate'] * 100:.1f}% ({int(round(pp['segment_label_hit_rate'] * pp['segment_total']))}/{pp['segment_total']}) |"
    )
    lines.append("")

    # 明细：单标签类
    for cat_title, cat in [
        ("单音（single_note）", "single_note"),
        ("三和弦（triad）", "triad"),
        ("干扰样本（interference）", "interference"),
    ]:
        rs = [r for r in results if r.category == cat]
        if not rs:
            continue
        lines.append(f"## {cat_title} 明细\n")
        lines.append("| id | 期望 | 预测主标签 | 预测根音 | root | label |")
        lines.append("|---|---|---|---|---|---|")
        for r in rs:
            lines.append(
                f"| `{r.id}` | {r.expected_single_label} | "
                f"{r.predicted_main_label or '-'} | {r.predicted_main_root or '-'} | "
                f"{'✓' if r.root_hit else '✗'} | {'✓' if r.label_hit else '✗'} |"
            )
        lines.append("")

    # 明细：和弦进行
    progs = [r for r in results if r.category == "progression"]
    if progs:
        lines.append("## 和弦进行（progression）明细\n")
        for r in progs:
            lines.append(f"### `{r.id}`  (原调估计：{r.original_key})\n")
            # pipeline 实际分段
            lines.append("pipeline 分段：")
            lines.append("")
            lines.append("| start_ms | end_ms | chord |")
            lines.append("|---|---|---|")
            for s in r.all_segments:
                lines.append(f"| {s['start_ms']} | {s['end_ms']} | `{s['chord']}` |")
            lines.append("")
            lines.append("段级对齐：")
            lines.append("")
            lines.append("| gt 段 | gt 标签 | 预测标签 | 预测根音 | root | label |")
            lines.append("|---|---|---|---|---|---|")
            for ev in r.segment_evaluations:
                lines.append(
                    f"| {ev['gt_start_ms']}–{ev['gt_end_ms']}ms | {ev['gt_label']} | "
                    f"{ev['predicted_label'] or '-'} | {ev['predicted_root'] or '-'} | "
                    f"{'✓' if ev['root_hit'] else '✗'} | {'✓' if ev['label_hit'] else '✗'} |"
                )
            lines.append("")
            lines.append(
                f"小计：root {r.segment_root_hits}/{r.segment_total}，"
                f"label {r.segment_label_hits}/{r.segment_total}\n"
            )

    with open(path, "w") as f:
        f.write("\n".join(lines))


def print_console_summary(summary: dict, results: List[CaseResult]):
    pc = summary["per_category"]
    print()
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    for cat in ["single_note", "triad", "interference"]:
        c = pc[cat]
        print(
            f"  {cat:<14} count={c['count']:<3}  "
            f"root={c['root_hit_rate'] * 100:5.1f}%  "
            f"label={c['label_hit_rate'] * 100:5.1f}%"
        )
    pp = pc["progression"]
    print(
        f"  progression    count={pp['count']:<3}  "
        f"root={pp['segment_root_hit_rate'] * 100:5.1f}%  "
        f"label={pp['segment_label_hit_rate'] * 100:5.1f}% "
        f"(segs={pp['segment_total']})"
    )
    print("=" * 60)


if __name__ == "__main__":
    run()
