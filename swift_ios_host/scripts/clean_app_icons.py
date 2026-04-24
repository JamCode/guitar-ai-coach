#!/usr/bin/env python3
"""
将 AppIcon 主图背景统一为纯 #FFFFFF，并从 1024 主图重采样生成各尺寸（避免多套 PNG 处理不一致）。

用法：在仓库根目录执行：
  python3 swift_ios_host/scripts/clean_app_icons.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# 亮于该亮度阈值的像素视为「背景/灰边/水印区」，改纯白；深色线条与抗锯齿低亮度保留
LUMA_THRESHOLD = 222

# 1024 主图经验值：原图大圆外缘在左右会残留浅灰线；这些列上无黑稿（无 lum<100），可整体刷白
# 左：x=0..2 已是 #FF，x=3 为灰线；右：x>=887 为灰线（图稿最右暗像素在 x=886 及以左）
STRIP_1024_LEFT = 4   # columns [0, STRIP_1024_LEFT) → 白
STRIP_1024_RIGHT = 887  # columns [STRIP_1024_RIGHT, w) → 白

SCRIPT = Path(__file__).resolve()
DEFAULT_ICON_DIR = SCRIPT.parent.parent / "Sources" / "Assets.xcassets" / "AppIcon.appiconset"


def luma_key(r: np.ndarray, g: np.ndarray, b: np.ndarray) -> np.ndarray:
    return 0.299 * r + 0.587 * g + 0.114 * b


def to_flat_white_rgba(pil: Image.Image) -> Image.Image:
    im = pil.convert("RGBA")
    arr = np.array(im, dtype=np.float32)
    r, g, b, a = arr[..., 0], arr[..., 1], arr[..., 2], arr[..., 3]
    lum = luma_key(r, g, b)
    mask = lum > LUMA_THRESHOLD
    out = arr.copy()
    out[mask, 0:3] = 255.0
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def strip_vertical_rim_greys_1024(pil: Image.Image) -> Image.Image:
    """去掉大圆在左右外缘的浅灰圈线；仅对 1024 主图按列号处理，再经缩放作用到全尺寸。"""
    arr = np.array(pil.convert("RGBA"), dtype=np.uint8)
    h, w = arr.shape[:2]
    if w != 1024 or h != 1024:
        return Image.fromarray(arr)
    lo = min(STRIP_1024_LEFT, w)
    hi = min(STRIP_1024_RIGHT, w)
    if lo > 0:
        arr[:, :lo, :3] = 255
    if hi < w:
        arr[:, hi:, :3] = 255
    return Image.fromarray(arr)


def main() -> int:
    base = Path(os.environ.get("APPICON_DIR", str(DEFAULT_ICON_DIR)))
    if not base.is_dir():
        print("Missing:", base, file=sys.stderr)
        return 1

    master_path = base / "Icon-App-1024x1024@1x.png"
    if not master_path.is_file():
        print("Missing master:", master_path, file=sys.stderr)
        return 1

    master = Image.open(master_path).convert("RGBA")
    if master.size != (1024, 1024):
        print("Warning: expected 1024x1024 master, got", master.size)

    cleaned_1024 = to_flat_white_rgba(master)
    cleaned_1024 = strip_vertical_rim_greys_1024(cleaned_1024)
    cleaned_1024.save(master_path, format="PNG", optimize=True)
    print("Wrote", master_path)

    pngs = sorted(base.glob("Icon-App-*.png"))
    for p in pngs:
        if p.name == master_path.name:
            continue
        w, h = Image.open(p).size
        resized = cleaned_1024.resize((w, h), Image.Resampling.LANCZOS)
        resized.save(p, format="PNG", optimize=True)
        print("Wrote", p.name, w, h)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
