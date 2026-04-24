#!/usr/bin/env python3
"""
AppIcon 处理：纯白底、去灰边/水印；保留红色琴身与黑色线稿。

- 默认：读取现有 Icon-App-1024x1024@1x.png，清洗后重采样到各尺寸。
- 传入参考图路径时：先等比放入 1024×1024 白底，再按内容裁成居中正方形（去掉 L 形稿右侧多余白条），经清洗后写回主图与各尺寸。

用法（仓库根目录）：
  python3 swift_ios_host/scripts/clean_app_icons.py
  python3 swift_ios_host/scripts/clean_app_icons.py /path/to/new_icon.png
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# 旧版纯线稿图标：左右两列仅灰线、无墨稿时的切边列号（仅当 apply_rim_strips_if_safe 允许时生效）
STRIP_1024_LEFT = 4
STRIP_1024_RIGHT = 887

SCRIPT = Path(__file__).resolve()
DEFAULT_ICON_DIR = SCRIPT.parent.parent / "Sources" / "Assets.xcassets" / "AppIcon.appiconset"


def luma_key(r: np.ndarray, g: np.ndarray, b: np.ndarray) -> np.ndarray:
    return 0.299 * r + 0.587 * g + 0.114 * b


# 认为「接近纸白」的阈值；低于此（任一路）即参与包围盒，用于裁掉 L 形框外多出来的单侧大白条
NEAR_WHITE_FOR_BBOX = 252


def balance_crop_to_square_then_resize(
    pil: Image.Image, out_size: int = 1024
) -> Image.Image:
    """
    按非白内容紧包围盒裁剪，再居中放入正方形白底，最后缩放到 out_size。

    解决：原稿仅左/下有黑边时，右侧大面积留白在缩小后像「白色柱子」撑出视觉框的问题。
    """
    arr = np.array(pil.convert("RGBA"), dtype=np.uint8)
    h0, w0 = arr.shape[:2]
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    ink = (r < NEAR_WHITE_FOR_BBOX) | (g < NEAR_WHITE_FOR_BBOX) | (b < NEAR_WHITE_FOR_BBOX)
    if not np.any(ink):
        return pil.resize((out_size, out_size), Image.Resampling.LANCZOS)

    ys, xs = np.where(ink)
    pad = max(8, int(0.02 * max(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1)))
    x0 = max(0, int(xs.min()) - pad)
    y0 = max(0, int(ys.min()) - pad)
    x1 = min(w0 - 1, int(xs.max()) + pad)
    y1 = min(h0 - 1, int(ys.max()) + pad)
    cropped = arr[y0 : y1 + 1, x0 : x1 + 1].copy()
    ch, cw = cropped.shape[:2]
    side = max(cw, ch)
    square = np.zeros((side, side, 4), dtype=np.uint8)
    square[:, :] = (255, 255, 255, 255)
    ox = (side - cw) // 2
    oy = (side - ch) // 2
    square[oy : oy + ch, ox : ox + cw] = cropped
    out = Image.fromarray(square)
    return out.resize((out_size, out_size), Image.Resampling.LANCZOS)


def fit_contain_on_white(src: Image.Image, size: int = 1024) -> Image.Image:
    """等比缩放后居中放在白底正方形上（不拉伸变形）。"""
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


def clean_unified_rgba(arr: np.ndarray) -> np.ndarray:
    """
    彩色/黑白通用：浅灰边、纸色统一为白；保护红色琴身与深色线稿。
    """
    r = arr[:, :, 0].astype(np.float32)
    g = arr[:, :, 1].astype(np.float32)
    b = arr[:, :, 2].astype(np.float32)
    lum = luma_key(r, g, b)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    spread = mx - mn
    # 琴身红：R 主导
    is_red = (r > 82.0) & (r > g + 16.0) & (r > b + 16.0)
    is_dark = lum < 108.0
    # 浅灰杂边（含圆边灰线）、近白底
    is_sludge = (spread < 36.0) & (lum > 150.0) & (lum < 252.0) & (~is_red) & (~is_dark)
    is_paper = (lum > 242.0) & (~is_red) & (~is_dark)
    out = arr.copy()
    mask = is_sludge | is_paper
    out[mask, 0:3] = 255
    return out


def apply_rim_strips_if_safe_1024(arr: np.ndarray) -> np.ndarray:
    """
    仅当左右边 6 列内没有深色线稿时，才做历史线稿图上的左右「去灰圈线」切条。
    带整圈黑边或右侧有墨的新版彩图会整列变暗，此处自动跳过。
    """
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
    lo = min(STRIP_1024_LEFT, w)
    hi = min(STRIP_1024_RIGHT, w)
    if lo > 0:
        out[:, :lo, :3] = 255
    if hi < w:
        out[:, hi:, :3] = 255
    return out


def process_master(pil: Image.Image) -> Image.Image:
    arr = np.array(pil.convert("RGBA"), dtype=np.uint8)
    arr = clean_unified_rgba(arr)
    arr = apply_rim_strips_if_safe_1024(arr)
    return Image.fromarray(arr)


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
        stage = fit_contain_on_white(Image.open(src_path), size=1024)
        print("Loaded source:", src_path, "→ letterbox 1024")
    else:
        if not master_path.is_file():
            print("Missing master:", master_path, file=sys.stderr)
            return 1
        stage = Image.open(master_path).convert("RGBA")
        if stage.size != (1024, 1024):
            print("Warning: expected 1024×1024 master, got", stage.size)

    # 先去灰边/统白，再按内容紧裁 + 居中正方（避免先裁后洗把右侧线稿当「杂边」刷掉）
    worked = process_master(stage)
    cleaned_1024 = balance_crop_to_square_then_resize(worked, out_size=1024)
    print("→ cleaned, then content-balanced square → 1024 (fixes L-frame white pillar)")
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
