from __future__ import annotations

import json
import logging
import time
import traceback
import uuid
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse

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
    return {"status": "ok", "ffmpeg": ffmpeg_available()}


@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)) -> JSONResponse:
    # TODO: add app secret / token auth.
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
            "debug": result.get("debug", {}),
            "timing": {
                "receive_sec": receive_sec,
                "ingest_sec": ingest_sec,
                "inference_sec": inference_sec,
                "total_sec": elapsed,
            },
        }
        report_path = OUTPUT_DIR / f"{req_id}.json"
        with report_path.open("w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
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

