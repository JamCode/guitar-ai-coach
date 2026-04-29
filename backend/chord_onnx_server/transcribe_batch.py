#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Iterable


DEFAULT_URL = "http://127.0.0.1:8000/transcribe"
DEFAULT_TOKEN_ENV = "CHORD_ONNX_APP_TOKEN"
COMPLEX_CHORD_RE = re.compile(r"(maj7|m7|7|sus|dim|aug|/|5)")


def _multipart_body(field_name: str, file_path: Path, boundary: str) -> tuple[bytes, str]:
    mime_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
    file_bytes = file_path.read_bytes()
    lines: list[bytes] = [
        f"--{boundary}\r\n".encode("utf-8"),
        (
            f'Content-Disposition: form-data; name="{field_name}"; '
            f'filename="{file_path.name}"\r\n'
        ).encode("utf-8"),
        f"Content-Type: {mime_type}\r\n\r\n".encode("utf-8"),
        file_bytes,
        b"\r\n",
        f"--{boundary}--\r\n".encode("utf-8"),
    ]
    return b"".join(lines), mime_type


def _post_file(url: str, token: str, file_path: Path) -> tuple[int, bytes]:
    boundary = f"----CodexBoundary{os.urandom(12).hex()}"
    body, _mime_type = _multipart_body("file", file_path, boundary)
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(body)),
            "X-App-Token": token,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=1800) as resp:
            return int(resp.status), resp.read()
    except urllib.error.HTTPError as exc:
        return int(exc.code), exc.read()


def _iter_audio_files(paths: Iterable[str]) -> list[Path]:
    files: list[Path] = []
    for raw in paths:
        p = Path(raw).expanduser().resolve()
        if p.is_file():
            files.append(p)
            continue
        if p.is_dir():
            for child in sorted(p.iterdir()):
                if child.is_file() and child.suffix.lower() in {".wav", ".mp3", ".m4a"}:
                    files.append(child.resolve())
            continue
        raise FileNotFoundError(f"not found: {raw}")
    return files


def _safe_stem(path: Path) -> str:
    return "".join(ch if ch.isalnum() or ch in {"-", "_"} else "_" for ch in path.stem).strip("_") or "audio"


def _segment_metrics(parsed: dict[str, object], field: str) -> dict[str, int]:
    rows = parsed.get(field, [])
    if not isinstance(rows, list):
        return {"count": 0, "complex_count": 0, "unique_chords": 0, "unique_complex_chords": 0}
    chords = [
        str(row.get("chord", "")).strip()
        for row in rows
        if isinstance(row, dict) and str(row.get("chord", "")).strip()
    ]
    complex_chords = [ch for ch in chords if COMPLEX_CHORD_RE.search(ch)]
    return {
        "count": len(chords),
        "complex_count": len(complex_chords),
        "unique_chords": len(set(chords)),
        "unique_complex_chords": len(set(complex_chords)),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Batch transcribe local audio files against the chord ONNX backend API."
    )
    parser.add_argument("inputs", nargs="+", help="Audio files or directories containing .wav/.mp3/.m4a")
    parser.add_argument("--url", default=DEFAULT_URL, help=f"Transcribe API URL. Default: {DEFAULT_URL}")
    parser.add_argument(
        "--token",
        default=os.getenv(DEFAULT_TOKEN_ENV, ""),
        help=f"App token. Default: ${DEFAULT_TOKEN_ENV}",
    )
    parser.add_argument(
        "--out-dir",
        default="outputs/manual_eval",
        help="Directory to store response JSON files, relative to backend/chord_onnx_server if not absolute.",
    )
    args = parser.parse_args()

    if not args.token:
        print(
            f"Missing token. Pass --token or export {DEFAULT_TOKEN_ENV}.",
            file=sys.stderr,
        )
        return 2

    try:
        audio_files = _iter_audio_files(args.inputs)
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if not audio_files:
        print("No audio files found.", file=sys.stderr)
        return 2

    script_dir = Path(__file__).resolve().parent
    out_dir = Path(args.out_dir)
    if not out_dir.is_absolute():
        out_dir = (script_dir / out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    summary: list[dict[str, object]] = []
    for file_path in audio_files:
        status, payload = _post_file(args.url, args.token, file_path)
        stem = _safe_stem(file_path)
        out_path = out_dir / f"{stem}.json"
        try:
            parsed = json.loads(payload.decode("utf-8"))
        except json.JSONDecodeError:
            parsed = {
                "success": False,
                "error": "non-json-response",
                "status_code": status,
                "body": payload.decode("utf-8", errors="replace"),
            }

        if isinstance(parsed, dict):
            parsed.setdefault("_request", {})
            if isinstance(parsed["_request"], dict):
                parsed["_request"]["file"] = str(file_path)
                parsed["_request"]["status_code"] = status

        out_path.write_text(json.dumps(parsed, ensure_ascii=False, indent=2), encoding="utf-8")

        success = bool(isinstance(parsed, dict) and parsed.get("success") is True and status == 200)
        debug = parsed.get("debug", {}) if isinstance(parsed, dict) else {}
        timing_stats = parsed.get("timingVariantStats", {}) if isinstance(parsed, dict) else {}
        summary.append(
            {
                "file": str(file_path),
                "status_code": status,
                "success": success,
                "out_file": str(out_path),
                "segment_count": len(parsed.get("segments", [])) if isinstance(parsed, dict) else 0,
                "display_count": len(parsed.get("displaySegments", [])) if isinstance(parsed, dict) else 0,
                "chart_count": len(parsed.get("chordChartSegments", [])) if isinstance(parsed, dict) else 0,
                "segments_metrics": _segment_metrics(parsed, "segments") if isinstance(parsed, dict) else None,
                "display_metrics": _segment_metrics(parsed, "displaySegments") if isinstance(parsed, dict) else None,
                "chart_metrics": _segment_metrics(parsed, "chordChartSegments") if isinstance(parsed, dict) else None,
                "raw_segment_count": debug.get("rawSegmentCount") if isinstance(debug, dict) else None,
                "timing_stats": timing_stats if isinstance(timing_stats, dict) else None,
            }
        )
        print(f"[{status}] {file_path.name} -> {out_path}")

    summary_path = out_dir / "_summary.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Summary written to {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
