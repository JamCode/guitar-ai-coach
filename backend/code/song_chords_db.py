# -*- coding: utf-8 -*-
import json
import os
import re
from contextlib import contextmanager
from datetime import datetime
import urllib.error
import urllib.request

import pymysql
from pymysql.cursors import DictCursor


DIFFICULTY_IDS = ("beginner", "intermediate", "advanced")

DASHSCOPE_ENDPOINT = os.getenv(
    "DASHSCOPE_ENDPOINT",
    "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
)
DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY", "")
DASHSCOPE_MODEL = os.getenv("DASHSCOPE_MODEL", "qwen3.5-flash")
DASHSCOPE_TIMEOUT_SECONDS = int(os.getenv("DASHSCOPE_TIMEOUT_SECONDS", "90"))
DASHSCOPE_SONG_MAX_TOKENS = int(os.getenv("DASHSCOPE_SONG_MAX_TOKENS", "7000"))
DASHSCOPE_SONG_CONTINUE_MAX_TOKENS = int(os.getenv("DASHSCOPE_SONG_CONTINUE_MAX_TOKENS", "3200"))
SONG_CONTINUE_MAX_ROUNDS = int(os.getenv("SONG_CONTINUE_MAX_ROUNDS", "8"))
SONG_END_MARKER = "[[SONG_COMPLETE]]"
_SCHEMA_CHECKED = False
_REQUIRED_TABLES = ("song", "song_search_alias", "song_score", "song_score_content")
_DDL_HINT_PATH = "backend/database/ddl/song_chords_tables.sql"


def _config():
    host = (os.getenv("MYSQL_HOST") or "").strip()
    if not host:
        return None
    port_s = (os.getenv("MYSQL_PORT") or "3306").strip() or "3306"
    return {
        "host": host,
        "port": int(port_s),
        "user": (os.getenv("MYSQL_USER") or "").strip(),
        "password": os.getenv("MYSQL_PASSWORD") or "",
        "database": (os.getenv("MYSQL_DATABASE") or "").strip(),
        "charset": "utf8mb4",
        "cursorclass": DictCursor,
        "connect_timeout": int(os.getenv("MYSQL_CONNECT_TIMEOUT", "8")),
        "read_timeout": int(os.getenv("MYSQL_READ_TIMEOUT", "300")),
        "write_timeout": int(os.getenv("MYSQL_WRITE_TIMEOUT", "300")),
        "autocommit": False,
    }


def song_chords_mysql_enabled():
    cfg = _config()
    return bool(cfg and cfg["user"] and cfg["database"])


@contextmanager
def _connection():
    cfg = _config()
    if not cfg or not cfg["user"] or not cfg["database"]:
        raise RuntimeError("MySQL 未配置")
    conn = pymysql.connect(**cfg)
    try:
        yield conn
    finally:
        conn.close()


def ensure_song_chords_schema():
    global _SCHEMA_CHECKED
    if _SCHEMA_CHECKED:
        return
    with _connection() as conn:
        with conn.cursor() as cur:
            placeholders = ",".join(["%s"] * len(_REQUIRED_TABLES))
            cur.execute(
                f"SELECT table_name FROM information_schema.tables "
                f"WHERE table_schema = DATABASE() AND table_name IN ({placeholders})",
                _REQUIRED_TABLES,
            )
            existed = set()
            for r in (cur.fetchall() or []):
                table_name = ""
                if isinstance(r, dict):
                    table_name = str(r.get("table_name") or r.get("TABLE_NAME") or "")
                elif isinstance(r, (tuple, list)) and r:
                    table_name = str(r[0] or "")
                if table_name:
                    existed.add(table_name)
    missing = [name for name in _REQUIRED_TABLES if name not in existed]
    if missing:
        missing_text = ", ".join(missing)
        raise RuntimeError(
            f"song_chords schema missing tables: {missing_text}. "
            f"Please execute {_DDL_HINT_PATH} once during upgrade/deployment."
        )
    _SCHEMA_CHECKED = True


def _normalize_difficulty(difficulty):
    d = (difficulty or "").strip().lower()
    return d if d in DIFFICULTY_IDS else "beginner"


def _normalize_text(s):
    s = (s or "").strip().lower()
    s = re.sub(r"\s+", "", s)
    s = s.replace("·", "").replace("-", "")
    return s[:255]


def _parse_song_query(query_text):
    q = (query_text or "").strip()
    if not q:
        return {"title": "", "artist": ""}
    parts = re.split(r"\s+", q, maxsplit=1)
    if len(parts) == 2:
        return {"title": parts[0].strip(), "artist": parts[1].strip()}
    return {"title": q, "artist": ""}


def _to_json_str(obj):
    return json.dumps(obj, ensure_ascii=False)


def _decode_json_field(raw, default):
    if raw is None:
        return default
    if isinstance(raw, (dict, list)):
        return raw
    if isinstance(raw, (bytes, bytearray)):
        raw = raw.decode("utf-8")
    if isinstance(raw, str):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return default
    return default


def _parse_progression(line):
    return [x.strip() for x in (line or "").split(" - ") if x.strip()]


def _progression_to_line(v):
    if isinstance(v, list):
        return " - ".join([str(x).strip() for x in v if str(x).strip()])
    if isinstance(v, str):
        return " - ".join([x.strip() for x in v.split("-") if x.strip()])
    return ""


def _build_chart_json(full_chart):
    out_sections = []
    current = {"name": "未命名", "lines": []}
    out_sections.append(current)
    for raw in (full_chart or "").splitlines():
        line = raw.rstrip()
        s = line.strip()
        if not s:
            continue
        m_title = re.match(r"^\[(.+?)\]$", s)
        if m_title and "歌词" not in s:
            section_name = m_title.group(1).strip() or "未命名"
            current = {"name": section_name, "lines": []}
            out_sections.append(current)
            continue
        lyric_parts = []
        chord_events = []
        cursor = 0
        for cm in re.finditer(r"\[([^\]]+)\]", line):
            pre = line[cursor : cm.start()]
            lyric_parts.append(pre)
            lyric_text = "".join(lyric_parts)
            chord_events.append({"symbol": cm.group(1).strip(), "pos": len(lyric_text)})
            cursor = cm.end()
        lyric_parts.append(line[cursor:])
        lyric = "".join(lyric_parts)
        current["lines"].append({"lyric": lyric, "chord_events": chord_events})
    return {"sections": [sec for sec in out_sections if sec["lines"]], "position_unit": "code_point"}


def _extract_dashscope_text(result):
    text = (
        result.get("output", {}).get("text")
        or result.get("output", {})
        .get("choices", [{}])[0]
        .get("message", {})
        .get("content", "")
        or result.get("choices", [{}])[0].get("message", {}).get("content", "")
    )
    if isinstance(text, list):
        text = "".join(
            [part.get("text", "") if isinstance(part, dict) else str(part) for part in text]
        )
    return (text or "").strip()


def _extract_dashscope_finish_reason(result):
    output = result.get("output", {}) if isinstance(result, dict) else {}
    choices = output.get("choices") if isinstance(output, dict) else None
    if isinstance(choices, list) and choices:
        reason = choices[0].get("finish_reason")
        if reason:
            return str(reason).strip().lower()
    choices = result.get("choices") if isinstance(result, dict) else None
    if isinstance(choices, list) and choices:
        reason = choices[0].get("finish_reason")
        if reason:
            return str(reason).strip().lower()
    return ""


def _split_non_empty_lines(text):
    return [x.strip() for x in (text or "").splitlines() if x.strip()]


def _strip_end_marker_lines(lines):
    return [ln for ln in (lines or []) if str(ln).strip() and str(ln).strip() != SONG_END_MARKER]


def _contains_end_marker(lines):
    return any(str(ln).strip() == SONG_END_MARKER for ln in (lines or []))


def _has_placeholder_text(text):
    text = (text or "").lower()
    bad_words = ("示例", "占位", "第n句", "lorem", "to be continued")
    return any(word in text for word in bad_words)


def _is_chart_complete(full_chart, require_end_marker=False):
    lines = _split_non_empty_lines(full_chart)
    has_end_marker = _contains_end_marker(lines)
    lines = _strip_end_marker_lines(lines)
    if require_end_marker and not has_end_marker:
        return False
    if len(lines) < 16:
        return False
    text = "\n".join(lines)
    if _has_placeholder_text(text):
        return False
    need_sections = ("[主歌]", "[副歌]", "[尾奏]")
    if any(sec not in text for sec in need_sections):
        return False
    lyric_lines = [ln for ln in lines if "]" in ln and "[" in ln and len(ln.replace("[", "").replace("]", "").strip()) > 2]
    return len(lyric_lines) >= 10


def _merge_lines_without_repeat(existing_lines, append_lines):
    left = [x for x in existing_lines if str(x).strip()]
    right = [x for x in append_lines if str(x).strip()]
    if not right:
        return left
    max_overlap = min(8, len(left), len(right))
    overlap = 0
    for n in range(max_overlap, 0, -1):
        if left[-n:] == right[:n]:
            overlap = n
            break
    return left + right[overlap:]


def _strip_chord_tags(line):
    s = str(line or "")
    s = re.sub(r"\[[^\]]+\]", "", s)
    return re.sub(r"\s+", " ", s).strip()


def _lyric_lines_from_chart(full_chart):
    lines = _split_non_empty_lines(full_chart)
    out = []
    for ln in lines:
        s = str(ln).strip()
        if s.startswith("[") and s.endswith("]"):
            continue
        lyric = _strip_chord_tags(s)
        if lyric:
            out.append(lyric)
    return out


def _is_lyrics_quality_low(full_chart):
    lyrics = _lyric_lines_from_chart(full_chart)
    if len(lyrics) < 8:
        return True
    freq = {}
    for line in lyrics:
        freq[line] = freq.get(line, 0) + 1
    max_repeat = max(freq.values()) if freq else 0
    unique_ratio = (len(freq) / float(len(lyrics))) if lyrics else 0.0
    # 避免把同一小段机械循环成“整首歌”
    if max_repeat >= 4:
        return True
    if unique_ratio < 0.45:
        return True
    return False


def _extract_full_chart_from_obj(obj):
    if not isinstance(obj, dict):
        return ""
    full_chart_lines = obj.get("full_chart_lines")
    if isinstance(full_chart_lines, list):
        lines = [str(x).strip() for x in full_chart_lines if str(x).strip()]
        return "\n".join(lines)
    return str(obj.get("full_chart") or "").strip()


def _repair_lyrics_accuracy_with_ai(template, title_hint, artist_hint, difficulty):
    prompt = (
        "你是中文歌曲歌词校对助手。请将下面这份带和弦歌谱中的歌词，"
        "校正为该歌曲常见版本（尽量逐字准确），并保持可弹唱结构。\n"
        "规则：\n"
        "1) 仅返回 JSON 对象。\n"
        "2) 字段仅允许：full_chart_lines(array)。\n"
        "3) 保留 [和弦]歌词 格式；必须包含 [主歌]、[副歌]、[尾奏]。\n"
        "4) 禁止将同一小段机械重复超过 3 次。\n"
        "5) 不输出解释，不输出 Markdown。\n"
        f"歌曲: {title_hint} - {artist_hint or '未知'}\n"
        f"difficulty: {difficulty}\n"
        "待校对歌谱：\n"
        "--- CHART_BEGIN ---\n"
        f"{template.get('full_chart', '')}\n"
        "--- CHART_END ---\n"
    )
    result = _call_dashscope(prompt, max_tokens=DASHSCOPE_SONG_MAX_TOKENS)
    text = _extract_dashscope_text(result)
    if not text:
        return ""
    obj = _parse_json_object_from_llm_text(text)
    return _extract_full_chart_from_obj(obj)


def _call_dashscope(prompt, max_tokens=2200):
    if not DASHSCOPE_API_KEY:
        raise RuntimeError("DASHSCOPE_API_KEY 未配置，无法生成真实歌谱")
    if "compatible-mode" in DASHSCOPE_ENDPOINT:
        payload = {
            "model": DASHSCOPE_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "enable_thinking": False,
            "max_tokens": max_tokens,
        }
    else:
        payload = {
            "model": DASHSCOPE_MODEL,
            "input": {"messages": [{"role": "user", "content": prompt}]},
            "parameters": {"enable_thinking": False, "max_tokens": max_tokens},
        }
    req = urllib.request.Request(
        DASHSCOPE_ENDPOINT,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {DASHSCOPE_API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=DASHSCOPE_TIMEOUT_SECONDS) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw)


def _parse_json_object_from_llm_text(text):
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("model output is not a valid JSON object")
    return json.loads(text[start : end + 1])


def _difficulty_cn(difficulty):
    return {
        "beginner": "新手",
        "intermediate": "中级",
        "advanced": "进阶",
    }.get(difficulty, "新手")


def _sanitize_template_from_model(obj, title_hint, difficulty):
    if not isinstance(obj, dict):
        raise ValueError("model output JSON must be object")
    key_original = str(obj.get("key_original") or "C").strip()[:16] or "C"
    key_recommended = str(obj.get("key_recommended") or key_original).strip()[:16] or key_original
    title_display = str(obj.get("title_display") or f"{title_hint} · {_difficulty_cn(difficulty)}版").strip()[:255]
    source_type = str(obj.get("source_type") or "ai").strip().lower()
    if source_type not in ("ai", "hybrid", "library"):
        source_type = "ai"
    why_recommended = str(obj.get("why_recommended") or "基于检索与生成能力给出可弹唱版本。").strip()[:512]

    verse_line = _progression_to_line(obj.get("verse_progression"))
    chorus_line = _progression_to_line(obj.get("chorus_progression"))
    if not verse_line or not chorus_line:
        raise ValueError("model output missing valid progression")

    full_chart_lines = obj.get("full_chart_lines")
    if isinstance(full_chart_lines, list):
        full_lines = [str(x).strip() for x in full_chart_lines if str(x).strip()]
        full_chart = "\n".join(full_lines)
    else:
        full_chart = str(obj.get("full_chart") or "").strip()
    if not full_chart:
        raise ValueError("model output missing full chart")

    quality_score = obj.get("quality_score")
    try:
        quality_score = int(quality_score)
    except Exception:
        quality_score = 78
    quality_score = max(1, min(100, quality_score))

    return {
        "title_display": title_display,
        "source_type": source_type,
        "key_original": key_original,
        "key_recommended": key_recommended,
        "why_recommended": why_recommended,
        "verse": verse_line,
        "chorus": chorus_line,
        "quality_score": quality_score,
        "full_chart": full_chart,
    }


def _generate_song_template_with_ai(query_text, difficulty, *, song_title="", song_artist="", current_chart=""):
    difficulty = _normalize_difficulty(difficulty)
    title_hint = (song_title or _parse_song_query(query_text).get("title") or query_text or "未命名歌曲").strip()[:120]
    artist_hint = (song_artist or _parse_song_query(query_text).get("artist") or "").strip()[:120]
    verify_block = ""
    if current_chart:
        verify_block = (
            "这是当前版本歌谱（可能有误），请在此基础上修正并输出更可靠版本：\n"
            "--- CURRENT_CHART_BEGIN ---\n"
            + current_chart[:6000]
            + "\n--- CURRENT_CHART_END ---\n"
        )
    prompt = (
        "你是资深吉他编配老师。请为用户生成一份可弹唱歌曲歌谱，并返回 JSON 对象（不要 Markdown，不要额外说明）。\n"
        "歌曲信息：\n"
        f"- title: {title_hint}\n"
        f"- artist: {artist_hint or '未知'}\n"
        f"- difficulty: {difficulty}\n"
        "要求：\n"
        "1) 必须给出真实可演奏的和弦进行，禁止输出“示例第1句”等占位文案。\n"
        "2) 需要包含完整结构：前奏、主歌、至少一段副歌、桥段(可选)、尾奏。\n"
        "3) full_chart_lines 里每行使用 [和弦]歌词 格式，必须写完整首，不得省略中间段落。\n"
        "4) 歌词必须尽量逐字贴近该歌曲常见版本，禁止同一段机械重复堆满整首。\n"
        "5) 若歌词不确定，优先基于已知版本修正，不要编造无关新句子。\n"
        f"6) full_chart_lines 最后一行必须是 {SONG_END_MARKER}，只允许出现一次。\n"
        "7) 输出字段严格为："
        "title_display, key_original, key_recommended, source_type, why_recommended, "
        "verse_progression(array), chorus_progression(array), full_chart_lines(array), quality_score(number)。\n"
        f"{verify_block}"
    )

    last_err = None
    for _ in range(3):
        try:
            result = _call_dashscope(prompt, max_tokens=DASHSCOPE_SONG_MAX_TOKENS)
            text = _extract_dashscope_text(result)
            if not text:
                raise ValueError("model empty output")
            obj = _parse_json_object_from_llm_text(text)
            template = _sanitize_template_from_model(obj, title_hint, difficulty)

            finish_reason = _extract_dashscope_finish_reason(result)
            chart_lines = _split_non_empty_lines(template.get("full_chart", ""))
            need_continue = finish_reason in ("length", "max_tokens") or not _is_chart_complete(
                "\n".join(chart_lines), require_end_marker=True
            )

            if need_continue:
                merged_lines = chart_lines[:]
                for _r in range(SONG_CONTINUE_MAX_ROUNDS):
                    recent_lines = "\n".join(merged_lines[-70:])
                    continue_prompt = (
                        "你正在分段补全同一首歌谱，请继续输出尚未给出的后半部分，直到整首结束。\n"
                        "不要重复已有行，不要改写已有行，不要输出解释。\n"
                        f"必须继续包含 [和弦]歌词，且最终补到 {SONG_END_MARKER}。\n"
                        f"title: {title_hint}\n"
                        f"artist: {artist_hint or '未知'}\n"
                        f"difficulty: {difficulty}\n"
                        f"已输出行数: {len(merged_lines)}\n"
                        "最近已输出内容（仅供衔接）：\n"
                        "--- EXISTING_TAIL_BEGIN ---\n"
                        f"{recent_lines}\n"
                        "--- EXISTING_TAIL_END ---\n"
                        "请仅返回 JSON 对象，字段严格为：append_lines(array), is_complete(boolean)。\n"
                    )
                    next_result = _call_dashscope(
                        continue_prompt, max_tokens=DASHSCOPE_SONG_CONTINUE_MAX_TOKENS
                    )
                    next_text = _extract_dashscope_text(next_result)
                    if not next_text:
                        break
                    next_obj = _parse_json_object_from_llm_text(next_text)
                    append_lines = next_obj.get("append_lines")
                    if not isinstance(append_lines, list):
                        append_lines = next_obj.get("full_chart_lines")
                    if not isinstance(append_lines, list):
                        append_lines = []
                    append_lines = [str(x).strip() for x in append_lines if str(x).strip()]
                    if not append_lines:
                        break
                    merged_lines = _merge_lines_without_repeat(merged_lines, append_lines)
                    if _contains_end_marker(merged_lines) and _is_chart_complete(
                        "\n".join(merged_lines), require_end_marker=True
                    ):
                        break
                    if bool(next_obj.get("is_complete")) and _is_chart_complete(
                        "\n".join(merged_lines), require_end_marker=True
                    ):
                        break
                template["full_chart"] = "\n".join(merged_lines)

            if not _is_chart_complete(template.get("full_chart", ""), require_end_marker=False):
                for _repair in range(2):
                    repair_prompt = (
                        "下面这份歌谱不完整，请你补齐为整首可弹唱版本。\n"
                        "仅返回 JSON 对象，字段严格为：full_chart_lines(array)。\n"
                        "硬性要求：\n"
                        "1) 必须包含 [前奏]、[主歌]、[副歌]、[尾奏] 段。\n"
                        "2) 总行数至少 22 行。\n"
                        "3) 每行使用 [和弦]歌词 格式，不要输出解释。\n"
                        "4) 禁止出现“示例/占位/第N句/lorem”。\n"
                        f"title: {title_hint}\n"
                        f"artist: {artist_hint or '未知'}\n"
                        f"difficulty: {difficulty}\n"
                        f"verse_progression: {template.get('verse', '')}\n"
                        f"chorus_progression: {template.get('chorus', '')}\n"
                        "当前不完整歌谱如下：\n"
                        "--- INCOMPLETE_CHART_BEGIN ---\n"
                        f"{template.get('full_chart', '')}\n"
                        "--- INCOMPLETE_CHART_END ---\n"
                    )
                    repair_result = _call_dashscope(repair_prompt, max_tokens=DASHSCOPE_SONG_MAX_TOKENS)
                    repair_text = _extract_dashscope_text(repair_result)
                    if not repair_text:
                        continue
                    repair_obj = _parse_json_object_from_llm_text(repair_text)
                    repaired_chart = _extract_full_chart_from_obj(repair_obj)
                    if not repaired_chart:
                        continue
                    template["full_chart"] = repaired_chart
                    if _is_chart_complete(template.get("full_chart", ""), require_end_marker=False):
                        break

            strict_ok = _is_chart_complete(template.get("full_chart", ""), require_end_marker=True)
            relaxed_ok = _is_chart_complete(template.get("full_chart", ""), require_end_marker=False)
            if not (strict_ok or relaxed_ok):
                raise ValueError("model output incomplete full chart")
            if _is_lyrics_quality_low(template.get("full_chart", "")):
                for _lyric_fix in range(2):
                    repaired_chart = _repair_lyrics_accuracy_with_ai(
                        template, title_hint, artist_hint, difficulty
                    )
                    if repaired_chart:
                        template["full_chart"] = repaired_chart
                    if _is_chart_complete(template.get("full_chart", ""), require_end_marker=False) and not _is_lyrics_quality_low(
                        template.get("full_chart", "")
                    ):
                        break
                if _is_lyrics_quality_low(template.get("full_chart", "")):
                    why = str(template.get("why_recommended") or "").strip()
                    suffix = "歌词准确性存在不确定性，建议人工核对关键句。"
                    template["why_recommended"] = f"{why} {suffix}".strip()[:512]
                    template["quality_score"] = min(int(template.get("quality_score") or 70), 70)
            template["full_chart"] = "\n".join(
                _strip_end_marker_lines(_split_non_empty_lines(template.get("full_chart", "")))
            )
            return template
        except (ValueError, urllib.error.URLError, TimeoutError, json.JSONDecodeError, RuntimeError) as e:
            last_err = e
            continue
    raise RuntimeError(f"AI generate failed: {last_err}")


_MOCK_HIT = {
    "beginner": {
        "title_display": "夜空中最亮的星 · 新手版",
        "source_type": "library",
        "key_original": "B",
        "key_recommended": "G",
        "why_recommended": "减少横按，优先开放和弦，适合直接开唱",
        "verse": "G - D - Em - C",
        "chorus": "C - D - Bm - Em",
        "quality_score": 89,
        "full_chart": "[前奏]\n[G] [D] [Em] [C]\n[主歌]\n[G]夜空中最亮的星 [D]请照亮我前行\n[Em]每当我找不到存在的意义 [C]每当我迷失在黑夜里\n[副歌]\n[C]夜空中最亮的星 [D]请指引我靠近你\n[Bm]给我再去相信的勇气 [Em]越过谎言去拥抱你",
    },
    "intermediate": {
        "title_display": "夜空中最亮的星 · 原调简化",
        "source_type": "hybrid",
        "key_original": "B",
        "key_recommended": "A",
        "why_recommended": "尽量保留原曲听感，降低部分指法难度",
        "verse": "A - E - F#m - D",
        "chorus": "D - E - C#m - F#m",
        "quality_score": 85,
        "full_chart": "[前奏]\n[A] [E] [F#m] [D]\n[主歌]\n[A]夜空中最亮的星 [E]请照亮我前行\n[F#m]每当我找不到存在的意义 [D]每当我迷失在黑夜里\n[副歌]\n[D]夜空中最亮的星 [E]请指引我靠近你\n[C#m]给我再去相信的勇气 [F#m]越过谎言去拥抱你",
    },
    "advanced": {
        "title_display": "夜空中最亮的星 · 进阶版",
        "source_type": "hybrid",
        "key_original": "B",
        "key_recommended": "B",
        "why_recommended": "保留更多原曲色彩和和弦张力，适合进阶弹唱",
        "verse": "B - F# - G#m - Emaj7",
        "chorus": "Emaj7 - F# - D#m - G#m",
        "quality_score": 82,
        "full_chart": "[前奏]\n[B] [F#] [G#m] [Emaj7]\n[主歌]\n[B]夜空中最亮的星 [F#]请照亮我前行\n[G#m]每当我找不到存在的意义 [Emaj7]每当我迷失在黑夜里\n[副歌]\n[Emaj7]夜空中最亮的星 [F#]请指引我靠近你\n[D#m]给我再去相信的勇气 [G#m]越过谎言去拥抱你",
    },
}


_MOCK_FALLBACK = {
    "beginner": {
        "title_display": "最接近版本 · AI 快速补全（新手）",
        "source_type": "ai",
        "key_original": "未知",
        "key_recommended": "C",
        "why_recommended": "未命中曲库，已生成可直接开唱的简化歌谱",
        "verse": "C - G - Am - F",
        "chorus": "F - G - Em - Am",
        "quality_score": 73,
        "full_chart": "[前奏]\n[C] [G] [Am] [F]\n[主歌]\n[C]示例主歌一句 [G]示例主歌二句\n[Am]示例主歌三句 [F]示例主歌四句\n[副歌]\n[F]示例副歌一句 [G]示例副歌二句\n[Em]示例副歌三句 [Am]示例副歌四句",
    },
    "intermediate": {
        "title_display": "最接近版本 · AI 快速补全（中级）",
        "source_type": "ai",
        "key_original": "未知",
        "key_recommended": "D",
        "why_recommended": "在可唱前提下保留更多进行变化",
        "verse": "D - A - Bm - G",
        "chorus": "G - A - F#m - Bm",
        "quality_score": 70,
        "full_chart": "[前奏]\n[D] [A] [Bm] [G]\n[主歌]\n[D]示例主歌一句 [A]示例主歌二句\n[Bm]示例主歌三句 [G]示例主歌四句\n[副歌]\n[G]示例副歌一句 [A]示例副歌二句\n[F#m]示例副歌三句 [Bm]示例副歌四句",
    },
    "advanced": {
        "title_display": "最接近版本 · AI 快速补全（进阶）",
        "source_type": "ai",
        "key_original": "未知",
        "key_recommended": "E",
        "why_recommended": "提供更丰富和弦色彩，适合进阶用户",
        "verse": "E - B - C#m - Amaj7",
        "chorus": "Amaj7 - B - G#m - C#m",
        "quality_score": 68,
        "full_chart": "[前奏]\n[E] [B] [C#m] [Amaj7]\n[主歌]\n[E]示例主歌一句 [B]示例主歌二句\n[C#m]示例主歌三句 [Amaj7]示例主歌四句\n[副歌]\n[Amaj7]示例副歌一句 [B]示例副歌二句\n[G#m]示例副歌三句 [C#m]示例副歌四句",
    },
}


def _pick_template(query_text, difficulty, source_override=None):
    difficulty = _normalize_difficulty(difficulty)
    if source_override in ("hit", "fallback"):
        bank = _MOCK_HIT if source_override == "hit" else _MOCK_FALLBACK
    else:
        bank = _MOCK_FALLBACK if "测试找不到" in (query_text or "") else _MOCK_HIT
    return bank[difficulty]


def _serialize_score_payload(song_row, score_row, content_row):
    verse = _decode_json_field(content_row.get("verse_progression_json"), [])
    chorus = _decode_json_field(content_row.get("chorus_progression_json"), [])
    full_lines = _decode_json_field(content_row.get("full_chart_lines_json"), [])
    chart_json = _decode_json_field(content_row.get("chart_json"), {"sections": []})
    return {
        "song_id": int(song_row["id"]),
        "version_id": int(score_row["id"]),
        "version_no": score_row["version_no"],
        "previous_version_no": "v2",
        "title_display": score_row["title_display"],
        "difficulty_level": score_row["difficulty_level"],
        "key_original": score_row["key_original"],
        "key_recommended": score_row["key_recommended"],
        "verse_progression": verse,
        "chorus_progression": chorus,
        "full_chart_lines": full_lines,
        "chart_json": chart_json,
        "quality_score": int(score_row.get("quality_score") or 0),
        "source_type": score_row["source_type"],
        "why_recommended": score_row["why_recommended"],
        "last_verified_at": _to_timestr(score_row.get("last_verified_at")),
    }


def _serialize_chorus_only_payload(song_row, score_row, content_row):
    full_payload = _serialize_score_payload(song_row, score_row, content_row)
    chart_json = full_payload.get("chart_json") or {"sections": []}
    sections = chart_json.get("sections") if isinstance(chart_json, dict) else []
    chorus_sections = []
    for sec in sections or []:
        name = str((sec or {}).get("name") or "").strip()
        lowered = name.lower()
        if ("副歌" in name) or ("chorus" in lowered):
            chorus_sections.append(sec)
    chorus_chart_json = {
        "sections": chorus_sections,
        "position_unit": chart_json.get("position_unit", "code_point")
        if isinstance(chart_json, dict)
        else "code_point",
    }
    return {
        "song_id": full_payload["song_id"],
        "version_id": full_payload["version_id"],
        "version_no": full_payload["version_no"],
        "title_display": full_payload["title_display"],
        "difficulty_level": full_payload["difficulty_level"],
        "key_original": full_payload["key_original"],
        "key_recommended": full_payload["key_recommended"],
        "chorus_progression": full_payload.get("chorus_progression") or [],
        "chart_json": chorus_chart_json,
        "quality_score": full_payload["quality_score"],
        "source_type": full_payload["source_type"],
        "why_recommended": full_payload["why_recommended"],
        "last_verified_at": full_payload["last_verified_at"],
    }


def _looks_like_legacy_mock(song_row, score_row, content_row):
    title_display = str(score_row.get("title_display") or "")
    song_title = str(song_row.get("title") or "")
    full_lines = _decode_json_field(content_row.get("full_chart_lines_json"), [])
    full_text = "\n".join([str(x) for x in full_lines if str(x).strip()])
    if "示例" in full_text or "第1句歌词" in full_text:
        return True
    if "夜空中最亮的星" in title_display and "夜空中最亮的星" not in song_title:
        return True
    return False


def _to_timestr(v):
    if isinstance(v, datetime):
        return v.isoformat(sep=" ", timespec="seconds")
    return str(v) if v is not None else None


def _get_current_score(cur, song_id, difficulty):
    cur.execute(
        "SELECT * FROM song_score WHERE song_id=%s AND difficulty_level=%s AND version_no='v1' LIMIT 1",
        (song_id, difficulty),
    )
    score_row = cur.fetchone()
    if not score_row:
        return None, None
    cur.execute(
        "SELECT * FROM song_score_content WHERE song_score_id=%s LIMIT 1",
        (int(score_row["id"]),),
    )
    content_row = cur.fetchone()
    return score_row, content_row


def _upsert_song_by_query(cur, query_text):
    q = _parse_song_query(query_text)
    title = q["title"] or "未命名歌曲"
    artist = q["artist"] or ""
    title_norm = _normalize_text(title)
    artist_norm = _normalize_text(artist)

    cur.execute(
        "SELECT * FROM song WHERE title_norm=%s AND artist_norm=%s LIMIT 1",
        (title_norm, artist_norm),
    )
    song = cur.fetchone()
    if song:
        return song
    cur.execute(
        "INSERT INTO song (title, artist, title_norm, artist_norm) VALUES (%s,%s,%s,%s)",
        (title, artist, title_norm, artist_norm),
    )
    sid = int(cur.lastrowid)
    cur.execute(
        "INSERT INTO song_search_alias (song_id, alias_text, alias_norm, is_primary) VALUES (%s,%s,%s,1) "
        "ON DUPLICATE KEY UPDATE song_id=VALUES(song_id), updated_at=CURRENT_TIMESTAMP",
        (sid, query_text.strip() or title, _normalize_text(query_text or title)),
    )
    cur.execute("SELECT * FROM song WHERE id=%s LIMIT 1", (sid,))
    return cur.fetchone()


def _insert_or_update_v1(cur, song_id, difficulty, template):
    cur.execute(
        "INSERT INTO song_score "
        "(song_id, difficulty_level, version_no, is_current, title_display, key_original, key_recommended, source_type, why_recommended, quality_score, last_verified_at) "
        "VALUES (%s,%s,'v1',1,%s,%s,%s,%s,%s,%s,NULL) "
        "ON DUPLICATE KEY UPDATE "
        "is_current=1, title_display=VALUES(title_display), key_original=VALUES(key_original), "
        "key_recommended=VALUES(key_recommended), source_type=VALUES(source_type), "
        "why_recommended=VALUES(why_recommended), quality_score=VALUES(quality_score), "
        "updated_at=CURRENT_TIMESTAMP",
        (
            song_id,
            difficulty,
            template["title_display"],
            template["key_original"],
            template["key_recommended"],
            template["source_type"],
            template["why_recommended"],
            int(template["quality_score"]),
        ),
    )
    cur.execute(
        "SELECT * FROM song_score WHERE song_id=%s AND difficulty_level=%s AND version_no='v1' LIMIT 1",
        (song_id, difficulty),
    )
    score = cur.fetchone()
    verse = _parse_progression(template["verse"])
    chorus = _parse_progression(template["chorus"])
    full_lines = [x for x in template["full_chart"].splitlines() if x.strip()]
    chart_json = _build_chart_json(template["full_chart"])
    cur.execute(
        "INSERT INTO song_score_content (song_score_id, verse_progression_json, chorus_progression_json, full_chart_lines_json, chart_json) "
        "VALUES (%s,%s,%s,%s,%s) "
        "ON DUPLICATE KEY UPDATE verse_progression_json=VALUES(verse_progression_json), "
        "chorus_progression_json=VALUES(chorus_progression_json), full_chart_lines_json=VALUES(full_chart_lines_json), "
        "chart_json=VALUES(chart_json), updated_at=CURRENT_TIMESTAMP",
        (
            int(score["id"]),
            _to_json_str(verse),
            _to_json_str(chorus),
            _to_json_str(full_lines),
            _to_json_str(chart_json),
        ),
    )
    cur.execute("SELECT * FROM song_score_content WHERE song_score_id=%s LIMIT 1", (int(score["id"]),))
    content = cur.fetchone()
    return score, content


def search_song_chords(query_text, difficulty):
    difficulty = _normalize_difficulty(difficulty)
    query_text = (query_text or "").strip()
    if not query_text:
        raise ValueError("query_text required")
    if len(query_text) > 255:
        raise ValueError("query_text too long")

    with _connection() as conn:
        with conn.cursor() as cur:
            ensure_song_chords_schema()
            qn = _normalize_text(query_text)
            cur.execute(
                "SELECT s.* FROM song_search_alias a JOIN song s ON s.id=a.song_id WHERE a.alias_norm=%s LIMIT 1",
                (qn,),
            )
            song = cur.fetchone()
            if not song:
                song = _upsert_song_by_query(cur, query_text)
                template = _generate_song_template_with_ai(
                    query_text,
                    difficulty,
                    song_title=song.get("title") or "",
                    song_artist=song.get("artist") or "",
                )
                score, content = _insert_or_update_v1(cur, int(song["id"]), difficulty, template)
                search_status = "fallback" if template["source_type"] == "ai" else "ok"
            else:
                cur.execute(
                    "INSERT INTO song_search_alias (song_id, alias_text, alias_norm, is_primary) VALUES (%s,%s,%s,0) "
                    "ON DUPLICATE KEY UPDATE song_id=VALUES(song_id), updated_at=CURRENT_TIMESTAMP",
                    (int(song["id"]), query_text, qn),
                )
                score, content = _get_current_score(cur, int(song["id"]), difficulty)
                if not score or not content:
                    template = _generate_song_template_with_ai(
                        query_text,
                        difficulty,
                        song_title=song.get("title") or "",
                        song_artist=song.get("artist") or "",
                    )
                    score, content = _insert_or_update_v1(cur, int(song["id"]), difficulty, template)
                elif _looks_like_legacy_mock(song, score, content):
                    template = _generate_song_template_with_ai(
                        query_text,
                        difficulty,
                        song_title=song.get("title") or "",
                        song_artist=song.get("artist") or "",
                    )
                    score, content = _insert_or_update_v1(cur, int(song["id"]), difficulty, template)
                search_status = "ok"
        conn.commit()
    payload_score = _serialize_chorus_only_payload(song, score, content)
    return {
        "query_text": query_text,
        "search_status": search_status,
        "active_difficulty_filter": difficulty,
        "score": payload_score,
    }


def get_song_chords_version(song_id, difficulty, version_no):
    difficulty = _normalize_difficulty(difficulty)
    version_no = (version_no or "").strip().lower()
    if version_no not in ("v1", "v2"):
        raise ValueError("version_no must be v1 or v2")
    with _connection() as conn:
        with conn.cursor() as cur:
            ensure_song_chords_schema()
            cur.execute("SELECT * FROM song WHERE id=%s LIMIT 1", (int(song_id),))
            song = cur.fetchone()
            if not song:
                raise ValueError("song not found")
            cur.execute(
                "SELECT * FROM song_score WHERE song_id=%s AND difficulty_level=%s AND version_no=%s LIMIT 1",
                (int(song_id), difficulty, version_no),
            )
            score = cur.fetchone()
            if not score:
                return None
            cur.execute("SELECT * FROM song_score_content WHERE song_score_id=%s LIMIT 1", (int(score["id"]),))
            content = cur.fetchone()
            if not content:
                return None
    return _serialize_score_payload(song, score, content)


def ai_verify_song_chords(song_id, difficulty):
    difficulty = _normalize_difficulty(difficulty)
    with _connection() as conn:
        with conn.cursor() as cur:
            ensure_song_chords_schema()
            cur.execute("SELECT * FROM song WHERE id=%s LIMIT 1", (int(song_id),))
            song = cur.fetchone()
            if not song:
                raise ValueError("song not found")
            cur.execute(
                "SELECT * FROM song_score WHERE song_id=%s AND difficulty_level=%s AND version_no='v1' LIMIT 1",
                (int(song_id), difficulty),
            )
            v1 = cur.fetchone()
            if not v1:
                raise ValueError("v1 not found")
            cur.execute("SELECT * FROM song_score_content WHERE song_score_id=%s LIMIT 1", (int(v1["id"]),))
            v1_content = cur.fetchone()
            if not v1_content:
                raise ValueError("v1 content not found")

            cur.execute(
                "INSERT INTO song_score "
                "(song_id, difficulty_level, version_no, is_current, title_display, key_original, key_recommended, source_type, why_recommended, quality_score, last_verified_at) "
                "VALUES (%s,%s,'v2',0,%s,%s,%s,%s,%s,%s,%s) "
                "ON DUPLICATE KEY UPDATE "
                "title_display=VALUES(title_display), key_original=VALUES(key_original), key_recommended=VALUES(key_recommended), "
                "source_type=VALUES(source_type), why_recommended=VALUES(why_recommended), quality_score=VALUES(quality_score), "
                "last_verified_at=VALUES(last_verified_at), updated_at=CURRENT_TIMESTAMP",
                (
                    int(song["id"]),
                    difficulty,
                    v1["title_display"],
                    v1["key_original"],
                    v1["key_recommended"],
                    v1["source_type"],
                    v1["why_recommended"],
                    int(v1.get("quality_score") or 0),
                    datetime.utcnow(),
                ),
            )
            cur.execute(
                "SELECT * FROM song_score WHERE song_id=%s AND difficulty_level=%s AND version_no='v2' LIMIT 1",
                (int(song["id"]), difficulty),
            )
            v2 = cur.fetchone()
            cur.execute(
                "INSERT INTO song_score_content (song_score_id, verse_progression_json, chorus_progression_json, full_chart_lines_json, chart_json) "
                "VALUES (%s,%s,%s,%s,%s) "
                "ON DUPLICATE KEY UPDATE verse_progression_json=VALUES(verse_progression_json), "
                "chorus_progression_json=VALUES(chorus_progression_json), full_chart_lines_json=VALUES(full_chart_lines_json), "
                "chart_json=VALUES(chart_json), updated_at=CURRENT_TIMESTAMP",
                (
                    int(v2["id"]),
                    _to_json_str(_decode_json_field(v1_content.get("verse_progression_json"), [])),
                    _to_json_str(_decode_json_field(v1_content.get("chorus_progression_json"), [])),
                    _to_json_str(_decode_json_field(v1_content.get("full_chart_lines_json"), [])),
                    _to_json_str(_decode_json_field(v1_content.get("chart_json"), {"sections": []})),
                ),
            )

            v1_full_lines = _decode_json_field(v1_content.get("full_chart_lines_json"), [])
            current_chart = "\n".join([str(x) for x in v1_full_lines if str(x).strip()])
            template = _generate_song_template_with_ai(
                f"{song.get('title') or ''} {song.get('artist') or ''}".strip(),
                difficulty,
                song_title=song.get("title") or "",
                song_artist=song.get("artist") or "",
                current_chart=current_chart,
            )
            score, content = _insert_or_update_v1(cur, int(song["id"]), difficulty, template)
            cur.execute(
                "UPDATE song_score SET last_verified_at=CURRENT_TIMESTAMP WHERE id=%s",
                (int(score["id"]),),
            )
            cur.execute("SELECT * FROM song_score WHERE id=%s LIMIT 1", (int(score["id"]),))
            score = cur.fetchone()
            cur.execute("SELECT * FROM song_score_content WHERE song_score_id=%s LIMIT 1", (int(score["id"]),))
            content = cur.fetchone()
        conn.commit()
    return _serialize_score_payload(song, score, content)
