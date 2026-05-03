#!/usr/bin/env python3
"""
重绘 appstore_screenshots 各尺寸 PNG 顶部中文营销区（扒歌重点 + 练习服务扒歌）。
依赖：Pillow（`pip install Pillow`）。

用法（仓库根目录）：
  python3 scripts/render_appstore_screenshots_zh.py
"""

from __future__ import annotations

import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[1]
SHOT = REPO / "appstore_screenshots"

# 各设备模板里，中心线「误入」手机大留白前的扫描起点（避免字幕单行高亮被当成手机顶）。
SCAN_Y0 = {
    "iphone_6_5_1242x2688": 280,
    "iphone_6_9_1290x2796": 520,
    "ipad_12_9_2064x2752": 400,
}

MARGIN_BELOW_PHONE_TOP = 14

DEVICE_FOLDERS = [
    "iphone_6_5_1242x2688",
    "iphone_6_9_1290x2796",
    "ipad_12_9_2064x2752",
]

ACCENT = (255, 82, 119)
TITLE_RGB = (245, 245, 247)
SUBTITLE_RGB = (160, 160, 168)

# 01 / 05 / 06 作为「扒歌」三条主线；02–04 练习统一贴「为扒歌训练」。
CAPTIONS: dict[str, dict[str, str]] = {
    "01_song_to_chords": {
        "badge": "扒歌练习",
        "title": "一首歌，扒成可练的和弦",
        "subtitle": "导入音频/视频，看当前和弦、附近变化与参考谱，边听边练",
    },
    "02_training_modules": {
        "badge": "扒歌训练",
        "title": "为了更稳地扒歌而练",
        "subtitle": "练耳、和弦听辨与节奏同步练：先听懂歌里在进行什么，再去对照谱子",
    },
    "03_chord_switching": {
        "badge": "扒歌配套",
        "title": "级数进行跟着练，扒歌更快对上和弦",
        "subtitle": "指法图、节拍器与级数提示同屏，把常见 I–vi–ii–V 耳感练进手里",
    },
    "04_strumming": {
        "badge": "扒歌节奏",
        "title": "扫弦跟得住，扒歌不「晃拍」",
        "subtitle": "上下扫与空拍标清楚，和节拍器同步，先把原曲律动练稳",
    },
    "05_tools": {
        "badge": "扒歌工具箱",
        "title": "调音 · 节拍 · 指板 · 和弦，扒歌一路用得到",
        "subtitle": "扒歌前调弦、扒歌中打拍、忘记把位随时速查，少打断心流",
    },
    "06_tuner": {
        "badge": "扒歌前准备",
        "title": "先把音高调准，再对着原曲扒",
        "subtitle": "麦克风拾音与 cents 表头，对齐录音音高，和弦识别更不容易偏",
    },
}


def _load_font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    ]
    for path in candidates:
        p = Path(path)
        if p.is_file():
            try:
                return ImageFont.truetype(str(p), size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def _avg_corner_bg(im: Image.Image) -> tuple[int, int, int]:
    pix = im.load()
    w, h = im.size
    samples: list[tuple[int, int, int]] = []
    for x, y in [(2, 2), (w - 3, 2), (2, h // 6), (w - 3, h // 6)]:
        samples.append(pix[x, y][:3])
    r = sum(s[0] for s in samples) // len(samples)
    g = sum(s[1] for s in samples) // len(samples)
    b = sum(s[2] for s in samples) // len(samples)
    return (r, g, b)


def _first_phone_row_y(im: Image.Image, y_start: int) -> int:
    """取横屏中线附近，自上而下第一条「接近纯白」的扫描行，作为手机内容区上缘。"""
    w, h = im.size
    xc = w // 2
    y_start = max(0, min(y_start, h - 8))
    for y in range(y_start, int(h * 0.86), 1):
        r, g, b = im.getpixel((xc, y))
        if r + g + b > 650:
            return y
    return int(h * 0.38)


def _compute_fill_bottom(im: Image.Image, folder: str) -> int:
    y0 = SCAN_Y0.get(folder, 400)
    phone_y = _first_phone_row_y(im, y0)
    fb = phone_y - MARGIN_BELOW_PHONE_TOP
    lo = int(im.height * 0.09)
    hi = int(im.height * 0.62)
    return max(lo, min(fb, hi))


def _text_width(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> int:
    if hasattr(draw, "textlength"):
        return int(draw.textlength(text, font=font))
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0]


def _wrap_to_width(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont,
    max_width: int,
) -> list[str]:
    lines: list[str] = []
    for paragraph in text.split("\n"):
        if not paragraph.strip():
            continue
        for line in textwrap.wrap(
            paragraph,
            width=60,
            break_long_words=False,
            break_on_hyphens=False,
        ):
            while line and _text_width(draw, line, font) > max_width:
                cut = len(line) - 1
                while cut > 0 and _text_width(draw, line[:cut], font) > max_width:
                    cut -= 1
                if cut <= 0:
                    break
                lines.append(line[:cut])
                line = line[cut:].lstrip()
            if line:
                lines.append(line)
    return lines


def _draw_badge(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    text: str,
    font: ImageFont.FreeTypeFont,
    pad_x: int = 22,
    pad_y: int = 10,
) -> int:
    tw = _text_width(draw, text, font)
    fs = int(getattr(font, "size", 28))
    h = fs + pad_y * 2
    w = tw + pad_x * 2
    x0, y0 = xy
    rect = (x0, y0, x0 + w, y0 + h)
    r = h // 2
    draw.rounded_rectangle(rect, radius=r, fill=ACCENT)
    draw.text((x0 + pad_x, y0 + pad_y), text, font=font, fill=(255, 255, 255))
    return y0 + h


def render_one(path: Path) -> None:
    folder = path.parent.name
    if folder not in SCAN_Y0:
        return
    stem = path.stem
    if stem not in CAPTIONS:
        return
    cap = CAPTIONS[stem]

    im = Image.open(path).convert("RGB")
    w, h = im.size
    fill_bottom = _compute_fill_bottom(im, folder)
    bg = _avg_corner_bg(im)
    draw = ImageDraw.Draw(im)
    draw.rectangle((0, 0, w, fill_bottom), fill=bg)

    pad_x = int(w * 0.06)
    max_text_w = w - 2 * pad_x

    badge_font = _load_font(max(26, int(w * 0.034)))
    title_font = _load_font(max(34, int(w * 0.052)))
    sub_font = _load_font(max(24, int(w * 0.028)))

    y = int(h * 0.028)
    y = _draw_badge(draw, (pad_x, y), cap["badge"], badge_font) + int(h * 0.022)

    title_lines = _wrap_to_width(draw, cap["title"], title_font, max_text_w)
    for line in title_lines:
        draw.text((pad_x, y), line, font=title_font, fill=TITLE_RGB)
        y += int(getattr(title_font, "size", 40)) + int(h * 0.012)

    y += int(h * 0.008)
    sub_lines = _wrap_to_width(draw, cap["subtitle"], sub_font, max_text_w)
    for line in sub_lines:
        draw.text((pad_x, y), line, font=sub_font, fill=SUBTITLE_RGB)
        y += int(getattr(sub_font, "size", 26)) + int(h * 0.008)

    im.save(path, format="PNG", optimize=True)


def render_contact_sheet(device_folder: str, out_name: str, cols: int = 2) -> None:
    folder = SHOT / device_folder
    paths = sorted(folder.glob("*.png"))
    if not paths:
        return
    ims = [Image.open(p).convert("RGB") for p in paths]
    n = len(ims)
    rows = (n + cols - 1) // cols
    mw = max(im.width for im in ims)
    mh = max(im.height for im in ims)
    gap = 24
    sheet_w = cols * mw + (cols + 1) * gap
    sheet_h = rows * mh + (rows + 1) * gap
    sheet = Image.new("RGB", (sheet_w, sheet_h), (12, 12, 16))
    for i, im in enumerate(ims):
        r, c = divmod(i, cols)
        x = gap + c * (mw + gap) + (mw - im.width) // 2
        y = gap + r * (mh + gap) + (mh - im.height) // 2
        sheet.paste(im, (x, y))
    out = SHOT / out_name
    sheet.save(out, format="JPEG", quality=88, optimize=True)


def main() -> None:
    for folder in DEVICE_FOLDERS:
        d = SHOT / folder
        if not d.is_dir():
            continue
        for png in sorted(d.glob("*.png")):
            render_one(png)
            print("updated", png.relative_to(REPO))

    render_contact_sheet("iphone_6_5_1242x2688", "contact_sheet_iphone_6_5.jpg")
    render_contact_sheet("iphone_6_9_1290x2796", "contact_sheet_iphone_6_9.jpg")
    render_contact_sheet("ipad_12_9_2064x2752", "contact_sheet_ipad_12_9.jpg")
    print("contact sheets written")


if __name__ == "__main__":
    main()
