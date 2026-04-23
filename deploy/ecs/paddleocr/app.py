"""
本机/ECS 上运行的轻量 HTTP OCR 服务，供歌谱图片上传后返回文字行（中/英及和弦符号如 Am、F#m 等，取决于印刷与分割）。

使用 PaddleOCR 2.7 经典 API。监听默认 127.0.0.1:18081，建议由 Nginx 反代到公网或仅内网访问。
"""
from __future__ import annotations

import os
import threading
from typing import Any

import cv2
import numpy as np
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from paddleocr import PaddleOCR

# 在 import paddle 之后若仍遇 MKLDNN 问题可在外层环境变量中关闭，此处留常用键名
os.environ.setdefault("FLAGS_enable_mkldnn", "0")

_ocr: PaddleOCR | None = None
_ocr_lock = threading.Lock()

app = FastAPI(title="Guitar sheet OCR (PaddleOCR)", version="0.1.0")


def get_ocr() -> PaddleOCR:
    global _ocr
    with _ocr_lock:
        if _ocr is None:
            _ocr = PaddleOCR(
                use_angle_cls=True,
                lang="ch",
                use_gpu=False,
                show_log=False,
            )
    return _ocr


def _flatten_ocr(ocr_out: list[Any] | None) -> list[dict[str, Any]]:
    """将 PaddleOCR 2.7 的 ocr.ocr 结果整理为 {text, score, box} 列表（仅保留识别成功的行）。"""
    lines: list[dict[str, Any]] = []
    if not ocr_out:
        return lines
    for page in ocr_out:
        if not page:
            continue
        for item in page:
            if not item or len(item) < 2:
                continue
            box, tx = item[0], item[1]
            if not tx or len(tx) < 2:
                continue
            text, score = str(tx[0]), float(tx[1])
            lines.append({"text": text, "score": score, "box": box})
    return lines


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/ocr")
async def ocr_image(file: UploadFile = File(...)) -> JSONResponse:
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="请上传 image/* 图片（如歌谱页照片或截图）")
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="空文件")
    arr = np.frombuffer(data, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(status_code=400, detail="无法解析为图片")
    ocr = get_ocr()
    try:
        result = ocr.ocr(img, cls=True)
    except Exception as e:  # noqa: BLE001
        return JSONResponse(
            status_code=500,
            content={"ok": False, "error": str(e), "type": type(e).__name__},
        )
    lines = _flatten_ocr(result)
    full_text = "\n".join(x["text"] for x in lines)
    return JSONResponse(
        {
            "ok": True,
            "lines": lines,
            "full_text": full_text,
        }
    )
