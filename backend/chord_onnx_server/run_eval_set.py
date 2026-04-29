#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any

from eval_metrics import safe_stem, summarize_payload
from inference import ChordOnnxInferenceService


def _load_manifest(path: Path) -> list[dict[str, Any]]:
    obj = json.loads(path.read_text(encoding="utf-8"))
    items = obj.get("items", [])
    if not isinstance(items, list):
        raise ValueError("manifest.items must be a list")
    out: list[dict[str, Any]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        item_id = str(item.get("id", "")).strip()
        rel_path = str(item.get("path", "")).strip()
        if not item_id or not rel_path:
            continue
        out.append(item)
    if not out:
        raise ValueError("manifest has no valid items")
    return out


def _select_items(items: list[dict[str, Any]], only: set[str]) -> list[dict[str, Any]]:
    if not only:
        return items
    out = [item for item in items if str(item.get("id")) in only]
    missing = sorted(only - {str(item.get("id")) for item in out})
    if missing:
        raise ValueError(f"unknown eval ids: {', '.join(missing)}")
    return out


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description="Run the fixed local chord regression set directly against ChordOnnxInferenceService."
    )
    parser.add_argument(
        "--manifest",
        default=str(script_dir / "eval_audio" / "eval_set.json"),
        help="Eval-set manifest JSON.",
    )
    parser.add_argument(
        "--out-dir",
        default="outputs/eval_runs/latest",
        help="Directory to store per-item JSON outputs and _summary.json.",
    )
    parser.add_argument(
        "--model-path",
        default=str(script_dir / "models" / "consonance_ace.onnx"),
        help="ONNX model path.",
    )
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        help="Limit to one or more eval ids from the manifest. Can be passed multiple times.",
    )
    args = parser.parse_args()

    manifest_path = Path(args.manifest).expanduser().resolve()
    model_path = Path(args.model_path).expanduser().resolve()
    out_dir = Path(args.out_dir).expanduser()
    if not out_dir.is_absolute():
        out_dir = (script_dir / out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    items = _select_items(_load_manifest(manifest_path), set(args.only))
    service = ChordOnnxInferenceService(model_path=model_path)
    summary: list[dict[str, Any]] = []

    for item in items:
        alias = str(item["id"])
        rel_path = Path(str(item["path"]))
        audio_path = (script_dir / rel_path).resolve()
        if not audio_path.exists():
            raise FileNotFoundError(f"missing eval file for {alias}: {audio_path}")

        started = time.perf_counter()
        result = service.transcribe(audio_path)
        elapsed = time.perf_counter() - started

        payload = {
            "success": True,
            "duration": result["duration"],
            "key": result["key"],
            "segments": result["segments"],
            "displaySegments": result.get("displaySegments", []),
            "simplifiedDisplaySegments": result.get("simplifiedDisplaySegments", []),
            "chordChartSegments": result.get("chordChartSegments", []),
            "timingVariants": result.get("timingVariants"),
            "timingVariantStats": result.get("timingVariantStats"),
            "debug": result.get("debug", {}),
            "_eval": {
                "alias": alias,
                "file": str(audio_path),
                "kind": item.get("kind"),
                "notes": item.get("notes"),
                "elapsed_sec": round(elapsed, 3),
            },
        }

        out_name = safe_stem(Path(alias))
        out_path = out_dir / f"{out_name}.json"
        out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        summary.append(
            summarize_payload(
                payload,
                alias=alias,
                file_path=str(audio_path),
                out_file=str(out_path),
                elapsed_sec=elapsed,
            )
        )
        print(
            f"[eval] {alias}: elapsed={elapsed:.3f}s "
            f"segments={len(payload['segments'])} "
            f"display={len(payload['displaySegments'])} "
            f"chart={len(payload['chordChartSegments'])}"
        )

    summary_path = out_dir / "_summary.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[eval] summary -> {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
