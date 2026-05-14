"""
轻量和弦序列 LLM 精修：
给定调性和和弦序列，让大模型修正不符合音乐理论的错误。
token 消耗极小（一首歌 30-80 个和弦，~300-500 tokens），成本可忽略。

配置（环境变量）：
  LLM_API_KEY            必填，你的 API Key（支持 DeepSeek / Qwen / 任意 OpenAI 兼容接口）
  LLM_BASE_URL           可选，默认 https://api.deepseek.com/v1/chat/completions
  LLM_MODEL              可选，默认 deepseek-chat
  LLM_TIMEOUT            可选，默认 30 秒
  LLM_MAX_TOKENS         可选，默认 1024

向后兼容：
  如果只设了 DASHSCOPE_API_KEY 而未设 LLM_API_KEY，仍走原来的 Qwen 路径。
"""

from __future__ import annotations

import json
import os
import urllib.request
from typing import Any

# ---- 配置读取 ----
# 优先级: LLM_* > DASHSCOPE_*
# 根据设了哪套 key 来自动选择默认 endpoint 和 model
_has_llm_key = bool(os.getenv("LLM_API_KEY"))
_has_dashscope_key = bool(os.getenv("DASHSCOPE_API_KEY"))
_API_KEY = os.getenv("LLM_API_KEY") or os.getenv("DASHSCOPE_API_KEY", "")

if _has_llm_key:
    # 用户明确用了 LLM_* 系列 → 默认 DeepSeek
    _DEFAULT_URL = "https://api.deepseek.com/v1/chat/completions"
    _DEFAULT_MODEL = "deepseek-chat"
elif _has_dashscope_key:
    # 只有 DASHSCOPE_* → 默认 Qwen（向后兼容）
    _DEFAULT_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    _DEFAULT_MODEL = "qwen3.5-flash"
else:
    _DEFAULT_URL = "https://api.deepseek.com/v1/chat/completions"
    _DEFAULT_MODEL = "deepseek-chat"

_BASE_URL = os.getenv("LLM_BASE_URL", os.getenv("DASHSCOPE_ENDPOINT", _DEFAULT_URL))
_MODEL = os.getenv("LLM_MODEL", os.getenv("DASHSCOPE_MODEL", _DEFAULT_MODEL))
_TIMEOUT = int(os.getenv("LLM_TIMEOUT", os.getenv("DASHSCOPE_TIMEOUT_SECONDS", "30")))
_MAX_TOKENS = int(os.getenv("LLM_MAX_TOKENS", os.getenv("DASHSCOPE_REFINE_MAX_TOKENS", "1024")))


def _call_llm(prompt: str, max_tokens: int = 1024) -> str:
    """Call an OpenAI-compatible LLM API (DeepSeek, Qwen, etc.)."""
    if not _API_KEY:
        raise RuntimeError("LLM_API_KEY not configured")

    payload = {
        "model": _MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.3,
    }
    req = urllib.request.Request(
        _BASE_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {_API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
        raw = resp.read().decode("utf-8")
        result = json.loads(raw)
    return result["choices"][0]["message"]["content"]


def refine_chord_sequence(
    segments: list[dict[str, Any]],
    estimated_key: str,
) -> tuple[list[dict[str, Any]], str]:
    """
    Use LLM to correct musically implausible chords AND verify/refine the key.

    Args:
        segments: list of {"start": float, "end": float, "chord": str}
        estimated_key: estimated key (e.g. "C", "Am")

    Returns:
        (refined_segments, corrected_key)
        Falls back to (original_segments, estimated_key) on error.
    """
    if not _API_KEY:
        return segments, estimated_key
    if not segments:
        return segments, estimated_key

    # Build compact chord text
    chord_lines = []
    for s in segments:
        start_s = f"{int(s['start']) // 60:02d}:{int(s['start']) % 60:02d}"
        dur = round(s["end"] - s["start"], 1)
        chord_lines.append(f"{start_s} {s['chord']} {dur}s")
    chord_text = " | ".join(chord_lines)

    prompt = (
        "你是吉他谱专家。下面是一段和弦序列，请做两件事：\n"
        "1. 判断给定的调性（key）是否正确\n"
        "2. 修正明显错误的和弦\n\n"
        f"给定的调性: {estimated_key}\n\n"
        "和弦序列 (起始时间 和弦名 时长):\n"
        f"{chord_text}\n\n"
        "修正规则:\n"
        "1. 先判断调性。如果和弦序列明显属于另一个调性，请修正 key\n"
        "2. 修正不在当前调性内的明显错误和弦（非经过音、非副属和弦）\n"
        "3. 允许合理的离调和弦（如 G7→C、E7→Am 是合法的）\n"
        "4. 不要改动起始时间和时长\n"
        "5. 如果没有需要修改的地方，原样返回\n\n"
        "请严格按照以下 JSON 格式输出（仅输出 JSON，不要其他文字）：\n"
        '{\n'
        '  "key": "修正后的调性",\n'
        '  "chords": ["和弦1", "和弦2", "和弦3", ...]\n'
        '}'
    )

    try:
        reply = _call_llm(prompt, max_tokens=_MAX_TOKENS)
    except Exception as exc:
        print(f"[LLM_REFINE] API call failed: {exc!r}; keeping original")
        return segments, estimated_key

    parsed = _parse_refine_response(reply)
    if parsed is None:
        print("[LLM_REFINE] failed to parse LLM response; keeping original")
        return segments, estimated_key

    chords = parsed["chords"]
    corrected_key = parsed["key"]

    n_original = len(segments)
    n_returned = len(chords)
    if n_returned != n_original:
        print(f"[LLM_REFINE] chord count mismatch: expected {n_original}, got {n_returned}; keeping original")
        return segments, estimated_key

    refined = []
    for i, s in enumerate(segments):
        ch = (chords[i] or "").strip()
        if not ch:
            ch = s["chord"]
        refined.append({"start": s["start"], "end": s["end"], "chord": ch})

    chord_changes = sum(1 for i in range(n_original) if refined[i]["chord"] != segments[i]["chord"])
    key_changed = corrected_key != estimated_key
    if chord_changes > 0 or key_changed:
        print(f"[LLM_REFINE] key={estimated_key}->{corrected_key}, chords corrected={chord_changes}/{n_original}")

    return refined, corrected_key


def _parse_refine_response(reply: str) -> dict | None:
    """Parse LLM response expecting {"key": ..., "chords": [...]}."""
    try:
        data = json.loads(reply)
        if isinstance(data, dict) and "chords" in data and "key" in data:
            chords = data["chords"]
            key = str(data["key"]).strip()
            if isinstance(chords, list) and key:
                return {"chords": [str(c) for c in chords], "key": key}
    except (json.JSONDecodeError, TypeError):
        pass
    # Fallback: extract JSON from text
    start = reply.find("{")
    end = reply.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return None
    try:
        data = json.loads(reply[start:end+1])
        if isinstance(data, dict) and "chords" in data and "key" in data:
            chords = data["chords"]
            key = str(data["key"]).strip()
            if isinstance(chords, list) and key:
                return {"chords": [str(c) for c in chords], "key": key}
    except (json.JSONDecodeError, TypeError):
        pass
    return None


def _parse_chord_list(reply: str) -> list[str] | None:
    """Extract chord list from LLM response (JSON or text)."""
    # Try JSON first
    try:
        data = json.loads(reply)
        chords = data.get("chords")
        if isinstance(chords, list):
            return [str(c) for c in chords]
    except (json.JSONDecodeError, TypeError):
        pass

    # Fallback: try to find JSON in the text
    start = reply.find('"chords"')
    if start == -1:
        return None
    brace = reply.find("[", start)
    if brace == -1:
        return None
    end = reply.find("]", brace)
    if end == -1:
        return None
    try:
        chords = json.loads(reply[brace : end + 1])
        return [str(c) for c in chords]
    except (json.JSONDecodeError, TypeError):
        return None
