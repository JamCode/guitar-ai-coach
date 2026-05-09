#!/usr/bin/env python3
"""
将 AppIcon 主图背景统一为纯 #FFFFFF，并从 1024 主图重采样生成各尺寸（避免多套 PNG 处理不一致）。

用法：在仓库根目录执行：
  python3 swift_ios_host/scripts/clean_app_icons.py
"""

from __future__ import annotations

import os
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

# 亮于该亮度阈值的像素视为「背景/灰边/水印区」，改纯白；深色线条与抗锯齿低亮度保留
LUMA_THRESHOLD = 222

# 1024 主图经验值：原图大圆外缘在左右会残留浅灰线；这些列上无黑稿（无 lum<100），可整体刷白
# 左：x=0..2 已是 #FF，x=3 为灰线；右：x>=887 为灰线（图稿最右暗像素在 x=886 及以左）
STRIP_1024_LEFT = 4   # columns [0, STRIP_1024_LEFT) → 白
STRIP_1024_RIGHT = 887  # columns [STRIP_1024_RIGHT, w) → 白

# —— 吉他琴身填色（线稿内白区 → 红，笑脸与背景保持黑/白）——
# 将「黑线」格按 MaxFilter 略扩张，避免抗锯齿细缝使琴身内白与外白连通；再对 4-连通域做标记。
DARK_LUMA_FOR_LINE = 92
DILATE_MAX_FILTER_SIZE = 5
DILATE_PASSES = 2
BRIGHT_MIN_FOR_FILL = 200
# 大块白区且左缘顶到画布左缘时，多为圆内弯月背景，与下段琴身同属一连通域；裁掉 x 过小的部分
LARGE_COMP_MIN_PIXELS = 20_000
CRESCENT_TRIM_MIN_X = 100
# 实色红（线稿仍为 1px 级黑边，由「非 free」自然保留）
GUITAR_RED_RGB = (0xDC, 0x2C, 0x2A)

# 仅排除「琴桥」小区域白底（三线托之间），不涂红。与下段琴身同属一连通域，用 1024 主图半开轴对齐 bbox。
# 形式 [x0, x1) x [y0, y1)；若你改主图，用 Preview/像素拾色微调。
BRIDGE_EXCLUDE_1024_X0X1Y0Y1 = (275, 422, 885, 934)

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


def _dilated_line_barrier_luma(lum: np.ndarray) -> np.ndarray:
    """True = 障碍（黑线及其扩张），用于限制 flood；与琴身内白分离外白。"""
    line_u8 = ((lum < DARK_LUMA_FOR_LINE).astype(np.uint8) * 255)
    iml = Image.fromarray(line_u8, "L")
    for _ in range(DILATE_PASSES):
        iml = iml.filter(ImageFilter.MaxFilter(DILATE_MAX_FILTER_SIZE))
    return np.asarray(iml) > 128


def _label_free_components(
    lum: np.ndarray, *, barrier: np.ndarray
) -> tuple[np.ndarray, int]:
    """在「够亮且非障碍」格子上做 4-连通标记，返回 label 图与最大 id。"""
    h, w = lum.shape
    bright = lum >= BRIGHT_MIN_FOR_FILL
    free = bright & ~barrier
    vis = np.zeros((h, w), dtype=np.int32)
    comp = 0

    def bfs(sy: int, sx: int, cid: int) -> None:
        q: deque[tuple[int, int]] = deque([(sy, sx)])
        vis[sy, sx] = cid
        while q:
            y, x = q.popleft()
            for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                ny, nx = y + dy, x + dx
                if ny < 0 or ny >= h or nx < 0 or nx >= w:
                    continue
                if not free[ny, nx] or vis[ny, nx]:
                    continue
                vis[ny, nx] = cid
                q.append((ny, nx))

    for sy in range(h):
        for sx in range(w):
            if free[sy, sx] and not vis[sy, sx]:
                comp += 1
                bfs(sy, sx, comp)
    return vis, comp


def _guitar_red_mask(vis: np.ndarray) -> np.ndarray:
    """除面积最大的白区（整图背景）外，其余 free 连通域视为琴身/音孔内白；大块左缘裁弯月。"""
    h, w = vis.shape
    flat = vis.ravel()
    max_id = int(flat.max())
    if max_id == 0:
        return np.zeros((h, w), dtype=bool)
    counts = np.bincount(flat, minlength=max_id + 1)
    # id 0 = 非 free
    background_id = int(np.argmax(counts[1:]) + 1)
    x_idx = np.arange(w, dtype=np.int32).reshape(1, w)
    red = np.zeros((h, w), dtype=bool)
    for cid in range(1, max_id + 1):
        if cid == background_id:
            continue
        m = vis == cid
        n = int(m.sum())
        if n == 0:
            continue
        _ys, xs = np.where(m)
        min_x = int(xs.min()) if len(xs) else 0
        if n >= LARGE_COMP_MIN_PIXELS and min_x < CRESCENT_TRIM_MIN_X:
            m = m & (x_idx >= CRESCENT_TRIM_MIN_X)
        red |= m
    return red


def _bridge_exclusion_mask(h: int, w: int) -> np.ndarray:
    """
    与 BRIDGE_EXCLUDE_1024_* 对齐的布尔阵：True 表示「不填红（保持原底）」的琴桥区。
    由 1024 参考尺寸按比例缩放到 (h, w)，圆角子图标与主图同构图。
    """
    x0, x1, y0, y1 = BRIDGE_EXCLUDE_1024_X0X1Y0Y1
    if h == 1024 and w == 1024:
        ex = np.zeros((h, w), dtype=bool)
        ex[y0:y1, x0:x1] = True
        return ex
    sh, sw = 1024, 1024
    ex = np.zeros((h, w), dtype=bool)
    ax0 = int(x0 * w / sw)
    ax1 = int(np.ceil(x1 * w / sw))
    ay0 = int(y0 * h / sh)
    ay1 = int(np.ceil(y1 * h / sh))
    ax0 = max(0, min(ax0, w))
    ax1 = max(0, min(ax1, w))
    ay0 = max(0, min(ay0, h))
    ay1 = max(0, min(ay1, h))
    if ax1 > ax0 and ay1 > ay0:
        ex[ay0:ay1, ax0:ax1] = True
    return ex


def color_guitar_body_red_rgba(pil: Image.Image) -> Image.Image:
    """
    将线稿吉他封闭区域内的白底填为红色，不改动黑线；依赖上游已做纯白压平 + 去灰边。
    背景白通过「最大连通域」识别；右侧笑脸在障碍内，不进入 free。
    """
    im = pil.convert("RGBA")
    arr = np.asarray(im, dtype=np.uint8)
    r, g, b, a = arr[..., 0], arr[..., 1], arr[..., 2], arr[..., 3]
    lum = luma_key(r.astype(np.float32), g.astype(np.float32), b.astype(np.float32))
    barrier = _dilated_line_barrier_luma(lum)
    vis, _n = _label_free_components(lum, barrier=barrier)
    mask = _guitar_red_mask(vis)
    hh, ww = int(arr.shape[0]), int(arr.shape[1])
    mask &= ~_bridge_exclusion_mask(hh, ww)
    out = arr.copy()
    rr, gg, bb = GUITAR_RED_RGB
    out[mask, 0] = rr
    out[mask, 1] = gg
    out[mask, 2] = bb
    return Image.fromarray(out, "RGBA")


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
    cleaned_1024 = color_guitar_body_red_rgba(cleaned_1024)
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
