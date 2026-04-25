"""
歌谱 OCR 后处理：在 PaddleOCR 的 lines 上尽量只保留「和弦名」与「中文歌词行」。

说明：
- 英文和弦若印刷很小或与六线/和弦图贴在一起，OCR 常漏认；本模块只能「从已识别行里再筛」。
- 简谱行（长数字串、附点/下划线等）通过规则与中文占比压掉。
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

# 常见吉他和弦 token（可含 Am7、Gadd9、F#m、Bb、C#7sus4、A/C# 等；偏保守，减少误把歌词当和弦）
CHORD_TOKEN = re.compile(
    r"(?<![A-Za-z#b♯♭])"
    r"([A-G](?:#|b|♯|♭)?"
    r"(?:maj7?|M7|m(?:aj7|7|9|11)?|7|9|11|6|4|2|5|sus2|sus4|"
    r"add(?:9|11)|"
    r"dim|aug|°|Ø|\+|"
    r"m(?!a)|m)"
    r"(?:(?:/|on)(?=[A-G])([A-G](?:#|b)?))?)"
)

# 乐谱里常见无关行（写窄一点，避免把「当我们拿起吉他」等歌词头尾裁掉）
_META_PATTERNS = [
    re.compile(p, re.I)
    for p in [
        r"^1\s*=\s*[A-G]",
        r"^变调夹",
        r"革命吉他制谱",  # 制谱/页眉
        r"^恋人$",  # 单标题
        r"^.{1,3}/.{1,3}$",  # 1/1、2/2
        r"^NEVER\s*GIVE\s*UP$",
    ]
]

# 纯简谱/节奏：以数字、附点、下划线、× 等为主
_JIANPU_LIKE = re.compile(r"^[\d.\s·×xX\-_|]{2,}$")


def _box_center_y(box: list[list[float]] | list[tuple]) -> float:
    if not box or len(box) < 2:
        return 0.0
    return sum(float(p[1]) for p in box) / float(len(box))


def _cjk_ratio(s: str) -> float:
    if not s:
        return 0.0
    n = sum(1 for c in s if "\u4e00" <= c <= "\u9fff")
    return n / len(s)


def _is_likely_jianpu_or_tab_noise(text: str) -> bool:
    t = text.strip()
    if len(t) <= 1 and t in "×xX0123456789.":
        return True
    if _JIANPU_LIKE.match(t):
        return True
    # 长串以数字/附点为主
    digitish = sum(1 for c in t if c.isdigit() or c in "·.")
    if len(t) >= 4 and digitish / len(t) >= 0.75 and _cjk_ratio(t) < 0.1:
        return True
    return False


# 常见 OCR 碎字/简谱与歌词断条，不当作句歌词
_LYRIC_NOISE: frozenset[str] = frozenset({"量一", "里一", "一"})


def _is_metadata_line(text: str) -> bool:
    t = text.strip()
    for rx in _META_PATTERNS:
        if rx.search(t):
            return True
    return False


def _chord_tokens_in_line(text: str) -> list[str]:
    out: list[str] = []
    for m in CHORD_TOKEN.finditer(text):
        tok = m.group(1) if m.lastindex else m.group(0)
        if tok and tok not in out:
            out.append(tok)
    return out


def _is_chord_dominant_line(text: str) -> bool:
    """
    整行以英文和弦名为主（允许空格、少量 markdown），中文很少。
    例：「Am7  D7  Gadd9」
    """
    t = text.strip()
    toks = _chord_tokens_in_line(t)
    if not toks:
        return False
    # 覆盖比例：有效和弦字符 / 行长度
    rest = t
    cover = 0
    for tok in toks:
        cover += len(tok) + t.count(" ")  # 近似
    cover = min(len("".join(toks)) + 3 * (len(toks) - 1), len(t))
    if _cjk_ratio(t) > 0.15:
        return False
    alnum = sum(1 for c in t if c.isalnum() or c in "#b♯♭/")
    if alnum < 0.3 * max(len(t), 1):
        return False
    return bool(toks) and (len("".join(toks)) / max(len(t), 1) >= 0.5 or (len(toks) >= 2 and _cjk_ratio(t) < 0.1))


@dataclass
class SongFilterResult:
    chord_lines: list[dict[str, Any]] = field(default_factory=list)
    lyric_lines: list[dict[str, Any]] = field(default_factory=list)
    chord_tokens_flat: list[str] = field(default_factory=list)
    dropped_jianpu: list[str] = field(default_factory=list)
    dropped_meta: list[str] = field(default_factory=list)
    note: str = ""


def filter_ocr_for_song(lines: list[dict[str, Any]], image_height: float) -> dict[str, Any]:
    """
    输入：OCR 的 lines（每项含 text, score, box）
    输出：和弦行、歌词行、平铺和弦列表，以及被丢弃的简谱/页眉样例（便于调参）
    """
    if image_height <= 0:
        image_height = 1.0

    sorted_lines = sorted(
        [dict(x) for x in lines],
        key=lambda d: _box_center_y(d.get("box", [])),
    )

    res = SongFilterResult()
    res.note = (
        "chord 仅来自 OCR 文本中有英文和弦行或行内能正则抽到的块；"
        "谱面顶部小字和弦若未进 OCR 则此处不会出现。"
    )

    for item in sorted_lines:
        text = (item.get("text") or "").strip()
        if not text:
            continue
        if _is_metadata_line(text):
            if len(res.dropped_meta) < 20:
                res.dropped_meta.append(text)
            continue
        if _is_likely_jianpu_or_tab_noise(text):
            if len(res.dropped_jianpu) < 40:
                res.dropped_jianpu.append(text)
            continue

        # 先尝试英文和弦行
        if _is_chord_dominant_line(text):
            toks = _chord_tokens_in_line(text)
            res.chord_lines.append({**item, "tokens": toks})
            for t_ in toks:
                if t_ not in res.chord_tokens_flat:
                    res.chord_tokens_flat.append(t_)
            continue
        toks = _chord_tokens_in_line(text)
        if toks and not any("\u4e00" <= c <= "\u9fff" for c in text) and len(text) < 32:
            res.chord_lines.append({**item, "tokens": toks})
            for t_ in toks:
                if t_ not in res.chord_tokens_flat:
                    res.chord_tokens_flat.append(t_)

            continue

        # 中文歌词：至少 2 字、中文占比高；且过滤碎字行
        if _cjk_ratio(text) >= 0.5 and len(text) >= 2 and text not in _LYRIC_NOISE:
            if len(text) == 2 and _cjk_ratio(text) < 1.0:
                continue
            res.lyric_lines.append(item)
            continue

    return {
        "chord_lines": res.chord_lines,
        "lyric_lines": res.lyric_lines,
        "chord_tokens_flat": res.chord_tokens_flat,
        "dropped_jianpu_sample": res.dropped_jianpu,
        "dropped_meta_sample": res.dropped_meta,
        "note": res.note,
    }
