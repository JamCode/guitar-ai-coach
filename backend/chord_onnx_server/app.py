from __future__ import annotations

import json
import logging
import time
import traceback
import uuid
from pathlib import Path
from typing import Any, Mapping

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse

from chord_auth import APP_TOKEN_ENV, app_token_status, configured_app_token
from inference import ChordOnnxInferenceService, InferenceInputShapeError, ffmpeg_available

BASE_DIR = Path(__file__).resolve().parent
UPLOAD_DIR = BASE_DIR / "uploads"
OUTPUT_DIR = BASE_DIR / "outputs"
MODEL_PATH = BASE_DIR / "models" / "consonance_ace.onnx"
MAX_UPLOAD_BYTES = 50 * 1024 * 1024
ALLOWED_EXTS = {".wav", ".mp3", ".m4a"}

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

logger = logging.getLogger("chord_onnx")
app = FastAPI(title="Chord ONNX Server", version="0.1.0")
service = ChordOnnxInferenceService(model_path=MODEL_PATH)

# 仅用于响应前调试日志：与 chord 字段做精确匹配（不改识别/后处理）。
_CHORD_DEBUG_WATCHLIST: tuple[str, ...] = (
    "Ab5",
    "B5",
    "Daug",
    "C#dim",
    "Eadd9",
    "F#sus4",
    "Em",
    "G",
)


def _chord_debug_seg_duration_sec(seg: Mapping[str, Any]) -> str:
    if "duration" in seg and seg["duration"] is not None:
        return str(seg["duration"])
    try:
        start = float(seg["start"])
        end = float(seg["end"])
        return f"{end - start:.6f}"
    except (KeyError, TypeError, ValueError):
        return "-"


def _chord_debug_format_segment_line(index: int, seg: Mapping[str, Any]) -> str:
    """列顺序: index | start | end | duration | chord | confidence（缺字段用 - 或推导）。"""
    start_s = "-" if seg.get("start", None) is None else str(seg["start"])
    end_s = "-" if seg.get("end", None) is None else str(seg["end"])
    if "duration" in seg and seg["duration"] is not None:
        dur_s = str(seg["duration"])
    else:
        dur_s = _chord_debug_seg_duration_sec(seg)
    chord_s = str(seg.get("chord", "") or "")
    conf_s = "-" if seg.get("confidence", None) is None else str(seg["confidence"])
    return " | ".join([str(index), start_s, end_s, dur_s, chord_s, conf_s])


def _chord_debug_print_segment_block(
    label: str,
    segments: list[Any],
    *,
    max_rows: int,
) -> None:
    header = "index | start | end | duration | chord | confidence"
    print(f"[CHORD_DEBUG] --- {label} (first {max_rows}, columns: {header}) ---")
    for i, seg in enumerate(segments[:max_rows]):
        if not isinstance(seg, Mapping):
            print(f"[CHORD_DEBUG] {label}[{i}] non-dict: {seg!r}")
            continue
        line = _chord_debug_format_segment_line(i, seg)
        print(f"[CHORD_DEBUG] {label} {line}")


def _chord_debug_watchlist_hits(segments: list[Any]) -> None:
    hits: dict[str, list[int]] = {name: [] for name in _CHORD_DEBUG_WATCHLIST}
    for i, seg in enumerate(segments):
        if not isinstance(seg, Mapping):
            continue
        chord = seg.get("chord")
        if chord is None:
            continue
        c = str(chord).strip()
        if c in hits:
            hits[c].append(i)
    print("[CHORD_DEBUG] watchlist (exact chord match on chordChartSegments):")
    for name in _CHORD_DEBUG_WATCHLIST:
        idxs = hits[name]
        print(f"[CHORD_DEBUG]   {name}: count={len(idxs)} positions={idxs}")


def _chord_debug_log_response_payload(
    *,
    req_id: str,
    upload_filename: str | None,
    result: Mapping[str, Any],
    payload: Mapping[str, Any],
) -> None:
    segs = payload.get("segments") or []
    disp = payload.get("displaySegments") or []
    simp = payload.get("simplifiedDisplaySegments") or []
    chart = payload.get("chordChartSegments") or []
    detected_key = result.get("key", payload.get("key"))
    original_key = result.get("originalKey", "n/a")

    title = (upload_filename or "").strip() or "n/a"
    print(
        f"[CHORD_DEBUG] request_id={req_id} song_or_filename={title!r} "
        f"detectedKey={detected_key!r} originalKey={original_key!r}"
    )
    print(
        f"[CHORD_DEBUG] counts segments={len(segs)} displaySegments={len(disp)} "
        f"simplifiedDisplaySegments={len(simp)} chordChartSegments={len(chart)}"
    )
    _chord_debug_print_segment_block("chordChartSegments", chart, max_rows=80)
    _chord_debug_watchlist_hits(chart)
    _chord_debug_print_segment_block("simplifiedDisplaySegments", simp, max_rows=80)


@app.on_event("startup")
def _startup_log_model() -> None:
    info = service.model_info
    print("[ONNX] ffmpeg on PATH:", ffmpeg_available())
    print("[ONNX] model path:", str(MODEL_PATH))
    print("[ONNX] input name:", info["input_name"])
    print("[ONNX] input shape:", info["input_shape"])
    print("[ONNX] output names:", info["output_names"])
    print("[ONNX] output shapes:", info["output_shapes"])


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "ffmpeg": ffmpeg_available(),
        "app_token_configured": bool(configured_app_token()),
    }


def _verify_app_token(request: Request) -> None:
    status = app_token_status(request.headers.get("X-App-Token", ""))
    if status == "missing_config":
        logger.error("[transcribe] missing required env var: %s", APP_TOKEN_ENV)
        raise HTTPException(status_code=503, detail="service auth is not configured")
    if status != "ok":
        raise HTTPException(status_code=401, detail="unauthorized")


@app.post("/transcribe")
async def transcribe(request: Request, file: UploadFile = File(...)) -> JSONResponse:
    _verify_app_token(request)
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in ALLOWED_EXTS:
        raise HTTPException(status_code=400, detail=f"unsupported file type: {suffix}")

    req_id = str(uuid.uuid4())
    upload_path = UPLOAD_DIR / f"{req_id}{suffix}"
    started = time.perf_counter()
    receive_sec = 0.0
    ingest_sec = 0.0
    inference_sec = 0.0

    try:
        t0 = time.perf_counter()
        content = await file.read()
        receive_sec = time.perf_counter() - t0
        if len(content) > MAX_UPLOAD_BYTES:
            raise HTTPException(status_code=413, detail="file too large (max 50MB)")
        t1 = time.perf_counter()
        with upload_path.open("wb") as f:
            f.write(content)
        ingest_sec = time.perf_counter() - t1

        t2 = time.perf_counter()
        result = service.transcribe(upload_path)
        inference_sec = time.perf_counter() - t2
        elapsed = time.perf_counter() - started
        print(
            f"[TRANSCRIBE] req={req_id} file={file.filename} "
            f"total={elapsed:.3f}s receive={receive_sec:.3f}s ingest={ingest_sec:.3f}s infer={inference_sec:.3f}s"
        )

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
            "timing": {
                "receive_sec": receive_sec,
                "ingest_sec": ingest_sec,
                "inference_sec": inference_sec,
                "total_sec": elapsed,
            },
        }
        tv_stats = result.get("timingVariantStats") or {}
        n_stats = tv_stats.get("normal") or {}
        na_stats = tv_stats.get("noAbsorb") or {}
        t_stats = tv_stats.get("timing") or {}
        tc_stats = tv_stats.get("timingCompact") or {}
        pc_stats = tv_stats.get("playableCompact") or {}
        logger.info(
            "[timing_variants] normal display=%s simplified=%s chart=%s | "
            "noAbsorb display=%s simplified=%s chart=%s | "
            "delta_na display=%s simplified=%s chart=%s | "
            "timing display=%s chart=%s absorbed=%s keptShort=%s snapped=%s | "
            "timingCompact display=%s chart=%s compressed=%s preservedTrans=%s | "
            "playableCompact display=%s chart=%s compressed=%s simplifiedNames=%s preservedTrans=%s targetDensity=%s",
            n_stats.get("displayCount"),
            n_stats.get("simplifiedCount"),
            n_stats.get("chordChartCount"),
            na_stats.get("displayCount"),
            na_stats.get("simplifiedCount"),
            na_stats.get("chordChartCount"),
            (na_stats.get("displayCount") or 0) - (n_stats.get("displayCount") or 0),
            (na_stats.get("simplifiedCount") or 0) - (n_stats.get("simplifiedCount") or 0),
            (na_stats.get("chordChartCount") or 0) - (n_stats.get("chordChartCount") or 0),
            t_stats.get("displayCount"),
            t_stats.get("chordChartCount"),
            t_stats.get("absorbedCount"),
            t_stats.get("keptShortCount"),
            t_stats.get("snappedBoundaryCount"),
            tc_stats.get("displayCount"),
            tc_stats.get("chordChartCount"),
            tc_stats.get("compressedCount"),
            tc_stats.get("preservedTransitionCount"),
            pc_stats.get("displayCount"),
            pc_stats.get("chordChartCount"),
            pc_stats.get("compressedCount"),
            pc_stats.get("simplifiedChordNameCount"),
            pc_stats.get("preservedTransitionCount"),
            pc_stats.get("targetDensityAppliedCount"),
        )
        report_path = OUTPUT_DIR / f"{req_id}.json"
        with report_path.open("w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        _chord_debug_log_response_payload(
            req_id=req_id,
            upload_filename=file.filename,
            result=result,
            payload=payload,
        )
        return JSONResponse(content=payload)
    except InferenceInputShapeError as exc:
        logger.warning(
            "[transcribe] request_id=%s input_shape_mismatch: %s",
            req_id,
            exc,
            exc_info=True,
        )
        return JSONResponse(
            status_code=400,
            content={
                "success": False,
                "error": "input_shape_mismatch",
                "detail": str(exc),
                "request_id": req_id,
            },
        )
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        tb = traceback.format_exc()
        logger.error(
            "[transcribe] request_id=%s inference_failed: %r\n%s",
            req_id,
            exc,
            tb,
        )
        # str(exc) 有时为空，用类名 + repr 便于排障；完整栈只在服务端日志
        detail = f"{type(exc).__name__}: {exc!r}" if not str(exc) else str(exc)
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": "inference_failed",
                "detail": detail,
                "request_id": req_id,
            },
        )
    finally:
        if upload_path.exists():
            try:
                upload_path.unlink()
            except OSError:
                # Best effort: do not fail the request because cleanup failed.
                pass
        await file.close()

