#!/usr/bin/env python3
"""
App Icon：白底、红色琴身/黑色线稿；去掉截图深灰外框与装饰性黑条，不再做会制造「对称柱子」的紧裁 + 重排。

- 从四角识别「整图深灰/黑底」的截图边，先裁掉再进 1024，避免左右两条深色柱。
- 将边缘整列/整行接近纯黑、且明显是框条（非吉他/笑脸细线）的像素刷白。
- 轻量 clean：浅灰、纸白；不做 balance_crop_to_square（易与 L 形框、截图边叠加成两条竖向视觉柱）。

用法（仓库根目录）：
  python3 swift_ios_host/scripts/clean_app_icons.py
  python3 swift_ios_host/scripts/clean_app_icons.py /path/to/icon.png
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# 旧线稿去灰圈线（仅当边缘全浅且无墨时仍可用）
STRIP_1024_LEFT = 4
STRIP_1024_RIGHT = 887

SCRIPT = Path(__file__).resolve()
DEFAULT_ICON_DIR = SCRIPT.parent.parent / "Sources" / "Assets.xcassets" / "AppIcon.appiconset"


def luma_key(r: np.ndarray, g: np.ndarray, b: np.ndarray) -> np.ndarray:
    return 0.299 * r + 0.587 * g + 0.114 * b


def crop_screenshot_letterbox(pil: Image.Image) -> Image.Image:
    """
    许多导出图在四周是均匀深灰/黑 #151515 一类。裁掉最外层「几乎全是该底色」的条，
    避免等比进 1024 时两侧变成粗深色条。
    """
    a = np.array(pil.convert("RGB"), dtype=np.float32)
    h, w = a.shape[:2]
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = np.maximum(np.maximum(r, g), b)
    # 中灰 UI 或黑底：全通道都低
    is_chrome = mx < 72.0
    inner = ~is_chrome
    if not np.any(inner):
        return pil
    ys, xs = np.where(inner)
    pad = 2
    x0 = max(0, int(xs.min()) - pad)
    y0 = max(0, int(ys.min()) - pad)
    x1 = min(w - 1, int(xs.max()) + pad)
    y1 = min(h - 1, int(ys.max()) + pad)
    if x1 - x0 < 32 or y1 - y0 < 32:
        return pil
    return pil.crop((x0, y0, x1 + 1, y1 + 1))


def whiten_solid_frame_bars_rgba(arr: np.ndarray) -> np.ndarray:
    """
    把边缘「整段几乎纯黑、明显是外框/竖条」的像素刷成白；保护中间区域的吉他/脸黑线（列均值会混白/红）。
    """
    r = arr[:, :, 0].astype(np.float32)
    g = arr[:, :, 1].astype(np.float32)
    b = arr[:, :, 2].astype(np.float32)
    lum = luma_key(r, g, b)
    h, w = arr.shape[:2]
    out = arr.copy()
    if w < 8 or h < 8:
        return out
    # 从左侧起：该列 90% 分位 luma 仍很暗，视为实心底条
    for x in range(0, min(w, 120)):
        col = lum[:, x]
        if float(np.mean(col)) < 60.0 and float(np.percentile(col, 90)) < 88.0:
            out[:, x, 0:3] = 255
        else:
            break
    for x in range(w - 1, max(0, w - 1 - 120), -1):
        col = lum[:, x]
        if float(np.mean(col)) < 60.0 and float(np.percentile(col, 90)) < 88.0:
            out[:, x, 0:3] = 255
        else:
            break
    # 底边横条
    for y in range(h - 1, max(0, h - 1 - 80), -1):
        row = lum[y, :]
        if float(np.mean(row)) < 60.0 and float(np.percentile(row, 90)) < 88.0:
            out[y, :, 0:3] = 255
        else:
            break
    # 顶边
    for y in range(0, min(60, h)):
        row = lum[y, :]
        if float(np.mean(row)) < 60.0 and float(np.percentile(row, 90)) < 88.0:
            out[y, :, 0:3] = 255
        else:
            break
    return out


def clean_unified_rgba(arr: np.ndarray) -> np.ndarray:
    r = arr[:, :, 0].astype(np.float32)
    g = arr[:, :, 1].astype(np.float32)
    b = arr[:, :, 2].astype(np.float32)
    lum = luma_key(r, g, b)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    spread = mx - mn
    is_red = (r > 82.0) & (r > g + 16.0) & (r > b + 16.0)
    is_dark = lum < 108.0
    is_sludge = (spread < 36.0) & (lum > 150.0) & (lum < 252.0) & (~is_red) & (~is_dark)
    is_paper = (lum > 242.0) & (~is_red) & (~is_dark)
    out = arr.copy()
    out[is_sludge | is_paper, 0:3] = 255
    return out


def apply_rim_strips_if_safe_1024(arr: np.ndarray) -> np.ndarray:
    h, w = arr.shape[:2]
    if w != 1024 or h != 1024:
        return arr
    r = arr[:, :, 0].astype(np.float32)
    g = arr[:, :, 1].astype(np.float32)
    b = arr[:, :, 2].astype(np.float32)
    lum = luma_key(r, g, b)
    left = lum[:, :6]
    right = lum[:, -6:]
    if np.min(left) <= 115.0 or np.min(right) <= 115.0:
        return arr
    out = arr.copy()
    if STRIP_1024_LEFT > 0:
        out[:, : min(STRIP_1024_LEFT, w), :3] = 255
    if STRIP_1024_RIGHT < w:
        out[:, min(STRIP_1024_RIGHT, w) :, :3] = 255
    return out


def process_master(pil: Image.Image) -> Image.Image:
    arr = np.array(pil.convert("RGBA"), dtype=np.uint8)
    arr = whiten_solid_frame_bars_rgba(arr)
    arr = clean_unified_rgba(arr)
    arr = apply_rim_strips_if_safe_1024(arr)
    return Image.fromarray(arr)


def fit_contain_on_white(src: Image.Image, size: int = 1024) -> Image.Image:
    src = src.convert("RGBA")
    w, h = src.size
    if w <= 0 or h <= 0:
        raise ValueError("invalid source size")
    scale = min(size / w, size / h)
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    resized = src.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    x = (size - nw) // 2
    y = (size - nh) // 2
    canvas.paste(resized, (x, y), resized)
    return canvas


def main() -> int:
    base = Path(os.environ.get("APPICON_DIR", str(DEFAULT_ICON_DIR)))
    if not base.is_dir():
        print("Missing:", base, file=sys.stderr)
        return 1

    master_path = base / "Icon-App-1024x1024@1x.png"
    if len(sys.argv) > 1:
        src_path = Path(sys.argv[1]).expanduser()
        if not src_path.is_file():
            print("Source not found:", src_path, file=sys.stderr)
            return 1
        base_img = Image.open(src_path)
        base_img = crop_screenshot_letterbox(base_img)
        stage = fit_contain_on_white(base_img, size=1024)
        print("Loaded source:", src_path, "→ crop UI chrome, letterbox 1024")
    else:
        if not master_path.is_file():
            print("Missing master:", master_path, file=sys.stderr)
            return 1
        base_img = Image.open(master_path).convert("RGBA")
        base_img = crop_screenshot_letterbox(base_img)
        stage = fit_contain_on_white(base_img, size=1024)
        if stage.size != (1024, 1024):
            print("Warning: expected 1024×1024, got", stage.size)
        print("Re-read master → crop chrome, letterbox 1024")

    cleaned_1024 = process_master(stage)
    cleaned_1024.save(master_path, format="PNG", optimize=True)
    print("Wrote", master_path)

    for p in sorted(base.glob("Icon-App-*.png")):
        if p.name == master_path.name:
            continue
        w, h = Image.open(p).size
        resized = cleaned_1024.resize((w, h), Image.Resampling.LANCZOS)
        resized.save(p, format="PNG", optimize=True)
        print("Wrote", p.name, w, h)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
