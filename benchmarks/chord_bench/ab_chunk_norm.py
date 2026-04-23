"""P0 chunk 归一化 A/B：在同一批 48 例 benchmark 上对比多种归一化变体。

变体（见 pipeline.NORMALIZE_MODES）：
- peak         Swift 现状：x / max(|x|)
- none         完全不做整段归一化
- rms          x * (target_rms / rms(x))，再 tanh 软截
- peak_p99     用第 99 百分位绝对值代替 max，避免偶发尖峰压扁整段
- rms_hardclip x * (target_rms / rms(x))，再硬 clip 到 ±1

输出：
- benchmarks/chord_bench/reports/ab_chunk_norm.json
- benchmarks/chord_bench/reports/ab_chunk_norm.md  （包括：按类别汇总差、单例 diff）
"""

from __future__ import annotations

import json
import os
import sys
import time
from dataclasses import asdict
from typing import Dict, List

import numpy as np
import soundfile as sf
import onnxruntime as ort

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from pipeline import (  # type: ignore  # noqa: E402
    recognize,
    NORMALIZE_MODES,
    DEFAULT_NORMALIZE_MODE,
    _chord_root,
)
from evaluate import (  # type: ignore  # noqa: E402
    score_single_label,
    score_progression,
)


SAMPLES_DIR = os.path.join(HERE, "samples")
REPORTS_DIR = os.path.join(HERE, "reports")
MODEL_PATH = os.path.join(
    "/workspace", "swift_ios_host", "Sources", "Transcription", "Resources",
    "consonance_ace.onnx",
)


# 固定顺序，让报告里栏目顺序稳定
MODES_ORDER = ["peak", "none", "rms", "peak_p99", "rms_hardclip"]


def run_single_mode(session: ort.InferenceSession, cases: List[dict],
                    mode: str) -> Dict[str, dict]:
    out: Dict[str, dict] = {}
    for case in cases:
        wav_path = os.path.join(SAMPLES_DIR, case["filename"])
        samples, sr = sf.read(wav_path, dtype="float32")
        if samples.ndim == 2:
            samples = samples.mean(axis=1)
        res = recognize(session, samples.astype(np.float32), float(sr),
                        normalize_mode=mode)
        if case["category"] == "progression":
            prog = score_progression(case["segments"], res["segments"])
            out[case["id"]] = {
                "category": "progression",
                "expected": [s["chord_label"] for s in case["segments"]],
                "predicted": [ev["predicted_label"] for ev in prog["evals"]],
                "root_hits": prog["root_hits"],
                "label_hits": prog["label_hits"],
                "total": prog["total"],
                "all_segments": res["segments"],
            }
        else:
            pred, pred_root, r, l = score_single_label(
                case["expected_single_label"], res["segments"],
                case["category"],
            )
            out[case["id"]] = {
                "category": case["category"],
                "expected": case["expected_single_label"],
                "predicted": pred,
                "predicted_root": pred_root,
                "root_hit": r,
                "label_hit": l,
                "all_segments": res["segments"],
            }
    return out


def summarize(mode_result: Dict[str, dict]) -> Dict[str, dict]:
    cat_stats = {
        "single_note":  {"count": 0, "r": 0, "l": 0},
        "triad":        {"count": 0, "r": 0, "l": 0},
        "interference": {"count": 0, "r": 0, "l": 0},
    }
    prog = {"count": 0, "segs": 0, "r": 0, "l": 0}
    for r in mode_result.values():
        cat = r["category"]
        if cat == "progression":
            prog["count"] += 1
            prog["segs"] += r["total"]
            prog["r"] += r["root_hits"]
            prog["l"] += r["label_hits"]
        else:
            cat_stats[cat]["count"] += 1
            if r["root_hit"]:
                cat_stats[cat]["r"] += 1
            if r["label_hit"]:
                cat_stats[cat]["l"] += 1
    return {
        "single_note":  cat_stats["single_note"],
        "triad":        cat_stats["triad"],
        "interference": cat_stats["interference"],
        "progression":  prog,
    }


def fmt_rate(hit: int, total: int) -> str:
    if total == 0:
        return "--"
    return f"{hit / total * 100:5.1f}% ({hit}/{total})"


def write_markdown(path: str, all_summaries: Dict[str, dict],
                   per_case: Dict[str, Dict[str, dict]]):
    lines = []
    lines.append("# P0 chunk 归一化 A/B\n")
    lines.append(f"样本：48 例（single_note=12，triad=12，progression=12，interference=12）")
    lines.append(f"模型：`consonance_ace.onnx`")
    lines.append(f"默认模式：`{DEFAULT_NORMALIZE_MODE}`（与当前 Swift 一致）\n")

    # ---- 汇总表 ----
    lines.append("## 按类别汇总\n")
    headers = ["类别", "指标"] + MODES_ORDER
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("|" + "|".join(["---"] * len(headers)) + "|")

    def row(cat: str, key: str, label: str, counter: str):
        cells = [cat, label]
        for mode in MODES_ORDER:
            s = all_summaries[mode][key]
            if key == "progression":
                total = s["segs"]
            else:
                total = s["count"]
            cells.append(fmt_rate(s[counter], total))
        return "| " + " | ".join(cells) + " |"

    lines.append(row("single_note",  "single_note",  "root",  "r"))
    lines.append(row("single_note",  "single_note",  "label", "l"))
    lines.append(row("triad",        "triad",        "root",  "r"))
    lines.append(row("triad",        "triad",        "label", "l"))
    lines.append(row("interference", "interference", "root",  "r"))
    lines.append(row("interference", "interference", "label", "l"))
    lines.append(row("progression",  "progression",  "root",  "r"))
    lines.append(row("progression",  "progression",  "label", "l"))
    lines.append("")

    # ---- 相对 baseline（peak）的 delta ----
    lines.append("## 相对 baseline `peak` 的变化\n")
    headers = ["类别", "指标"] + [m for m in MODES_ORDER if m != "peak"]
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("|" + "|".join(["---"] * len(headers)) + "|")

    def delta_row(cat_key: str, label: str, counter: str):
        base = all_summaries["peak"][cat_key]
        base_total = base["segs"] if cat_key == "progression" else base["count"]
        base_rate = base[counter] / base_total if base_total else 0.0
        cells = [cat_key, label]
        for mode in [m for m in MODES_ORDER if m != "peak"]:
            s = all_summaries[mode][cat_key]
            total = s["segs"] if cat_key == "progression" else s["count"]
            rate = s[counter] / total if total else 0.0
            delta = (rate - base_rate) * 100
            arrow = "+" if delta >= 0 else ""
            cells.append(f"{arrow}{delta:4.1f}pp")
        return "| " + " | ".join(cells) + " |"

    for cat, counter, label in [
        ("triad",        "r", "root"),
        ("triad",        "l", "label"),
        ("interference", "r", "root"),
        ("interference", "l", "label"),
        ("progression",  "r", "root"),
        ("progression",  "l", "label"),
        ("single_note",  "r", "root"),
    ]:
        lines.append(delta_row(cat, label, counter))
    lines.append("")

    # ---- 单例 diff：只看 interference + progression 里 baseline 错的 ----
    lines.append("## Interference 单例对比（baseline 错 → 各变体）\n")
    lines.append("| id | 期望 | peak | none | rms | peak_p99 | rms_hardclip |")
    lines.append("|---|---|---|---|---|---|---|")
    for cid in sorted(per_case["peak"].keys()):
        if not cid.startswith("intf-"):
            continue
        base = per_case["peak"][cid]
        cells = [f"`{cid}`", base["expected"]]
        for mode in MODES_ORDER:
            r = per_case[mode][cid]
            pred = r["predicted"] if r["predicted"] else "-"
            mark = "✓" if r["root_hit"] else ("✗" if r["expected"] else "")
            cells.append(f"{pred} {mark}")
        lines.append("| " + " | ".join(cells) + " |")
    lines.append("")

    # ---- Progression 首尾段：抽几段 baseline 错的看 ----
    lines.append("## Progression 关键段对比（baseline 段错）\n")
    baseline = per_case["peak"]
    fail_samples = []
    for cid, r in baseline.items():
        if r["category"] != "progression":
            continue
        if r["root_hits"] < r["total"]:
            fail_samples.append(cid)
    for cid in sorted(fail_samples):
        lines.append(f"### `{cid}`")
        lines.append("")
        lines.append("| 段 gt | peak | none | rms | peak_p99 | rms_hardclip |")
        lines.append("|---|---|---|---|---|---|")
        seg_labels = per_case["peak"][cid]["expected"]
        for idx, gt_label in enumerate(seg_labels):
            cells = [gt_label]
            for mode in MODES_ORDER:
                r = per_case[mode][cid]
                pred = r["predicted"][idx] if idx < len(r["predicted"]) else ""
                is_hit = _chord_root(pred or "") == _chord_root(gt_label or "")
                cells.append(f"{pred or '-'} {'✓' if is_hit else '✗'}")
            lines.append("| " + " | ".join(cells) + " |")
        lines.append("")

    with open(path, "w") as f:
        f.write("\n".join(lines))


def main():
    if not os.path.exists(MODEL_PATH):
        print("ERROR: model not found:", MODEL_PATH, file=sys.stderr)
        sys.exit(1)

    gt_path = os.path.join(SAMPLES_DIR, "ground_truth.json")
    with open(gt_path) as f:
        gt = json.load(f)

    sess = ort.InferenceSession(MODEL_PATH,
                                providers=["CPUExecutionProvider"])
    print("Loaded ACE model:", MODEL_PATH)

    all_per_case: Dict[str, Dict[str, dict]] = {}
    all_summaries: Dict[str, dict] = {}

    for mode in MODES_ORDER:
        if mode not in NORMALIZE_MODES:
            raise ValueError(f"unknown mode: {mode}")
        print(f"-> running mode={mode}")
        t0 = time.time()
        per_case = run_single_mode(sess, gt["cases"], mode)
        all_per_case[mode] = per_case
        all_summaries[mode] = summarize(per_case)
        print(f"   done in {time.time() - t0:.2f}s")

    os.makedirs(REPORTS_DIR, exist_ok=True)
    json_path = os.path.join(REPORTS_DIR, "ab_chunk_norm.json")
    with open(json_path, "w") as f:
        json.dump({
            "summaries": all_summaries,
            "per_case": all_per_case,
        }, f, indent=2, ensure_ascii=False)
    print("Wrote", json_path)

    md_path = os.path.join(REPORTS_DIR, "ab_chunk_norm.md")
    write_markdown(md_path, all_summaries, all_per_case)
    print("Wrote", md_path)

    # 控制台简表
    print()
    print("=" * 80)
    print(f"{'category':<14} {'metric':<6} " + " ".join(f"{m:>13}" for m in MODES_ORDER))
    print("-" * 80)
    for cat, key in [("single_note", "single_note"), ("triad", "triad"),
                     ("interference", "interference"), ("progression", "progression")]:
        for metric, counter in [("root", "r"), ("label", "l")]:
            cells = []
            for mode in MODES_ORDER:
                s = all_summaries[mode][key]
                total = s["segs"] if key == "progression" else s["count"]
                rate = s[counter] / total if total else 0.0
                cells.append(f"{rate * 100:5.1f}% ({s[counter]:>2}/{total:<2})")
            print(f"{cat:<14} {metric:<6} " + " ".join(f"{c:>13}" for c in cells))
    print("=" * 80)


if __name__ == "__main__":
    main()
