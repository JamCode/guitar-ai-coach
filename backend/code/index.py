# -*- coding: utf-8 -*-
import base64
import binascii
import json
import logging
from logging.handlers import TimedRotatingFileHandler
import os
import random
import re
import time
import threading
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
import urllib.error
import urllib.parse
import urllib.request

from chord_transpose import (
    REFERENCE_KEY,
    TWELVE_KEYS,
    normalize_key,
    prefer_flats_for_key,
    semitone_delta,
    transpose_lines,
    transpose_progression_line,
)
from chord_explain_db import fetch_cached_explain, save_chord_explain
from mysql_crud_sample import handle_mysql_http
from ear_db import (
    answer_ear_question,
    create_ear_attempt,
    ear_health_counts,
    ear_mysql_enabled,
    ensure_ear_schema,
    finish_ear_attempt,
    generate_or_get_daily_set,
    get_ear_mistakes,
    get_next_ear_question,
    import_ear_seed,
)
from quiz_db import (
    create_attempt,
    ensure_quiz_schema,
    finish_attempt,
    get_next_question,
    import_quiz_seed,
    quiz_health_counts,
    quiz_mysql_enabled,
    answer_question,
)
from song_chords_db import (
    ai_verify_song_chords,
    ensure_song_chords_schema,
    get_song_chords_version,
    search_song_chords,
    song_chords_mysql_enabled,
)
from auth_apple import handle_auth_apple_post, handle_auth_health_get
from practice_http import handle_practice_routes
from sheets_http import handle_sheets_routes


DASHSCOPE_ENDPOINT = os.getenv(
    "DASHSCOPE_ENDPOINT",
    "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
)
DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY", "")
DASHSCOPE_MODEL = os.getenv("DASHSCOPE_MODEL", "qwen3.5-flash")
DASHSCOPE_TIMEOUT_SECONDS = int(os.getenv("DASHSCOPE_TIMEOUT_SECONDS", "90"))
BACKEND_PORT = int(os.getenv("BACKEND_PORT", "18080"))
BACKEND_HOST = os.getenv("BACKEND_HOST", "127.0.0.1")
QUIZ_SEED_DEFAULT_PATH = os.getenv(
    "QUIZ_SEED_FILE",
    os.path.abspath(
        os.path.join(
            os.path.dirname(__file__), "..", "..", "requirements", "和弦题库-100题种子.json"
        )
    ),
)
EAR_SEED_DEFAULT_PATH = os.getenv(
    "EAR_SEED_FILE",
    os.path.abspath(
        os.path.join(
            os.path.dirname(__file__), "..", "..", "requirements", "练耳题库-一期种子.json"
        )
    ),
)

LEVEL_IDS = ("初级", "中级", "高级")
LEVEL_DEFAULT = "中级"
EAR_NOTE_PITCH_CLASSES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
EAR_NOTE_OCTAVE = 4
_EAR_NOTE_SESSIONS = {}
_EAR_NOTE_SESSION_LOCK = threading.Lock()


def _setup_logging():
    level_name = os.getenv("BACKEND_LOG_LEVEL", "INFO").strip().upper() or "INFO"
    level = getattr(logging, level_name, logging.INFO)
    log_dir = os.getenv(
        "BACKEND_LOG_DIR",
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "logs")),
    )
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, "backend.log")

    logger = logging.getLogger("guitar_ai_backend")
    logger.setLevel(level)
    logger.propagate = False
    if logger.handlers:
        return logger

    formatter = logging.Formatter(
        "%(asctime)s | %(levelname)s | %(name)s | %(message)s"
    )

    stream_handler = logging.StreamHandler()
    stream_handler.setLevel(level)
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)

    file_handler = TimedRotatingFileHandler(
        log_path,
        when="midnight",
        interval=1,
        backupCount=7,
        encoding="utf-8",
    )
    file_handler.setLevel(level)
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    logger.info("Logging initialized at %s", log_path)
    return logger


LOGGER = _setup_logging()

STYLE_TO_PROGRESSIONS = {
    "流行": [
        "C - Am - F - G",
        "Em - C - G - D",
        "F - Dm - Bb - C",
        "Am - F - C - G",
        "Dm - Bb - F - C",
    ],
    "民谣": [
        "Am - G - F - E7",
        "C - G - Am - F",
        "Dm - Bb - C - Am",
        "Em - D - C - B7",
        "G - Em - C - D",
    ],
    "摇滚": [
        "Am - C - G - D",
        "Em - C - G - D",
        "G - D - Em - C",
        "A - E - F#m - D",
        "Dm - Bb - C - Am",
    ],
    "抒情": [
        "C - G/B - Am - F",
        "Dm - Bb - F - C",
        "Em - C - D - B7",
        "F - Dm - Gm - C7",
        "Am - F - C - G (更柔和的落点)",
    ],
    "校园": [
        "C - Em - F - G",
        "Am - Em - F - C",
        "G - D - Em - C",
        "F - G - Am - Em",
        "Dm - G - C - Am",
    ],
    "轻摇滚": [
        "Em - C - G - D",
        "D - A - Bm - G",
        "A - E - F#m - D",
        "G - Bm - C - D",
        "Am - F - G - Em",
    ],
    "国风": [
        "Am - Em - F - E7",
        "Dm - G - C - A7",
        "C - G - Am - Em",
        "Dm - Bb - F - C（偏古典走向）",
        "Em - C - Am - B7（旋律导向）",
    ],
    "R&B": [
        "Am7 - D7 - Gmaj7 - Cmaj7",
        "Dm7 - G7 - Cmaj7 - Bm7b5",
        "Em7 - A7 - Dmaj7 - B7",
        "Cmaj7 - Am7 - Dm7 - G7",
        "Fm7 - Bb7 - Ebmaj7 - Abmaj7",
    ],
}


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json; charset=utf-8",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type,Authorization",
        },
        "isBase64Encoded": False,
        "body": json.dumps(payload, ensure_ascii=False),
    }


def _extract_body(event):
    raw_body = event.get("body", "")
    if not raw_body:
        return {}
    if event.get("isBase64Encoded"):
        return {}
    try:
        return json.loads(raw_body)
    except json.JSONDecodeError:
        return {}


def _normalize_event(event):
    if isinstance(event, (bytes, bytearray)):
        event = event.decode("utf-8", errors="ignore")
    if isinstance(event, str):
        try:
            event = json.loads(event) if event else {}
        except json.JSONDecodeError:
            event = {}
    if not isinstance(event, dict):
        return {}
    return event


def _is_mysql_demo_request(event):
    ctx = event.get("requestContext") or {}
    http = ctx.get("http") or {}
    path = (http.get("path") or event.get("path") or "").strip() or "/"
    if "/mysql/items" in path:
        return True
    body = _extract_body(event)
    if isinstance(body, dict) and body.get("mysql_op"):
        return True
    return False


def _request_path(event):
    ctx = event.get("requestContext") or {}
    http = ctx.get("http") or {}
    return (http.get("path") or event.get("path") or "/").strip() or "/"


def _request_method(event):
    return (
        event.get("httpMethod")
        or event.get("requestContext", {}).get("http", {}).get("method")
        or "GET"
    ).upper()


def _merge_request_headers(event):
    """合并 API 网关 [headers] / [multiValueHeaders] 为单值 dict（保留原始键名大小写混合）。"""
    h = {}
    raw = event.get("headers")
    if isinstance(raw, dict):
        for k, v in raw.items():
            if isinstance(v, list) and v:
                h[k] = v[-1]
            else:
                h[k] = v
    mv = event.get("multiValueHeaders") or event.get("multi_value_headers")
    if isinstance(mv, dict):
        for k, v in mv.items():
            if isinstance(v, list) and v:
                h[k] = v[-1]
    return h


def _response_binary(status_code, body_bytes, content_type):
    """返回图片等二进制体（函数计算常用 base64）。"""
    if not isinstance(body_bytes, (bytes, bytearray)):
        body_bytes = bytes(body_bytes or b"")
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": content_type,
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type,Authorization",
        },
        "isBase64Encoded": True,
        "body": base64.b64encode(body_bytes).decode("ascii"),
    }


def _normalize_ear_note_mode(mode):
    m = str(mode or "").strip().lower()
    return m if m in ("single_note", "multi_note") else "single_note"


def _ear_note_allowed_pitches(include_accidental):
    if include_accidental:
        pcs = EAR_NOTE_PITCH_CLASSES
    else:
        pcs = ["C", "D", "E", "F", "G", "A", "B"]
    return [f"{pc}{EAR_NOTE_OCTAVE}" for pc in pcs]


def _ear_note_pitch_label(note):
    return str(note or "").strip().upper().replace(str(EAR_NOTE_OCTAVE), "")


def _generate_ear_note_questions(*, question_count, notes_per_question, include_accidental):
    allowed_notes = _ear_note_allowed_pitches(include_accidental)
    if not allowed_notes:
        return []
    max_repeat = max(2, int((question_count * notes_per_question) / max(1, len(allowed_notes))) + 2)
    pitch_counts = {n: 0 for n in allowed_notes}
    questions = []
    prev_head = None
    for idx in range(question_count):
        target = []
        tries = 0
        while len(target) < notes_per_question and tries < 200:
            tries += 1
            pool = []
            for n in allowed_notes:
                if pitch_counts[n] >= max_repeat:
                    continue
                if notes_per_question > 1 and n in target:
                    continue
                if len(target) == 0 and prev_head == n and len(allowed_notes) > 1:
                    continue
                pool.append(n)
            if not pool:
                # Fallback: relax constraints to avoid dead-end.
                pool = [n for n in allowed_notes if not (notes_per_question > 1 and n in target)]
            chosen = random.choice(pool)
            target.append(chosen)
            pitch_counts[chosen] = pitch_counts.get(chosen, 0) + 1
        if not target:
            target = [random.choice(allowed_notes)]
        prev_head = target[0]
        questions.append(
            {
                "question_id": f"q_{idx + 1}",
                "index": idx + 1,
                "target_notes": target,
            }
        )
    return questions


def _ear_note_public_question(session, question):
    notes = session.get("notes") or []
    labels = [_ear_note_pitch_label(n) for n in notes]
    return {
        "question_id": question["question_id"],
        "index": int(question["index"]),
        "total_questions": int(session.get("question_count") or 0),
        "notes_per_question": int(session.get("notes_per_question") or 1),
        "candidate_notes": notes,
        "candidate_labels": labels,
        "target_notes": list(question.get("target_notes") or []),
    }


def _pick_random_unique(arr, count):
    copy = list(arr)
    random.shuffle(copy)
    return copy[: min(count, len(copy))]


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


def _normalize_level(name):
    if not name or not isinstance(name, str):
        return LEVEL_DEFAULT
    n = name.strip()
    return n if n in LEVEL_IDS else LEVEL_DEFAULT


def _level_prompt_block(style, level):
    common = (
        "【风格与难度一致】所选难度必须与「{style}」常见作品相符："
        "例如民谣/校园在初级多用干净骨架；摇滚可略粗粝但仍遵守该档和弦规则；"
        "R&B、爵士向风格在中高级可更自由使用色彩与延伸，但不要堆砌与「{style}」无关的和声语汇。\n"
    ).format(style=style)
    if level == "初级":
        return common + (
            "【难度档：初级 — 基础 / 骨架和弦】\n"
            "只用**大三、小三三和弦**（及转位低音如 G/B、C/E），听感干净、直白、稳，适合弹唱入门。\n"
            "禁止：任何七和弦、九/十一/十三和弦、sus、add、dim、aug、变化音与爵士替代。\n"
            "符号示例：C、Am、F、G、Dm、Em、G/B。\n"
        )
    if level == "中级":
        return common + (
            "【难度档：中级 — 色彩 / 现代流行】\n"
            "核心使用**七和弦**：maj7、m7、属七(7)、半减七(m7b5 或 ø) 等；可少量 **add9、sus2、sus4**。\n"
            "贴近主流华语流行、歌手伴奏常用厚度；避免 9/11/13 延伸与 b9、#9、#11、b13 等爵士变化（本档不要）。\n"
            "符号示例：Cmaj7、Am7、G7、Dm7、Fmaj7、Gsus4、Cadd9。\n"
        )
    return common + (
        "【难度档：高级 — 爵士延伸 / 高阶色彩】\n"
        "可使用 **9、11、13** 与变化音 **b9、#9、#11、b13**，替代和弦、**ii-V-I** 等爵士向进行；"
        "听感偏 R&B、爵士、精致编曲，但仍要符合「{style}」语境（国风/校园也可做精致版，勿生硬照搬无关爵士套子）。\n"
        "符号示例：Cmaj9、Am11、G13、C7b9、F#m7b5、Bb13、三全音替代等。\n"
    ).format(style=style)


def _split_progression_tokens(chords_line):
    return [t.strip() for t in chords_line.split(" - ") if t.strip()]


_TOKEN_BEGINNER = re.compile(r"^[A-G][#b]?m?(?:/[A-G][#b]?)?$")

# 中级：不允许明显爵士向 11/13 与变化九、#11、b13 等（避免与高级混淆）
_RE_TOO_JAZZY_FOR_MID = re.compile(
    r"(?i)(b9|#9|#11|b13|maj11|m11|add11|sus11|11(?![0-9])|13(?![0-9]))"
)

_TOKEN_MID_OK = re.compile(
    r"^[A-G][#b]?[A-Za-z0-9°Øø#()+,\-]*(?:/[A-G][#b]?[A-Za-z0-9°Øø#()+,\-]*)?$"
)

_TOKEN_ADV_OK = re.compile(
    r"^[A-G][#b]?.+$"
)


def _progression_matches_level(chords_line, level):
    tokens = _split_progression_tokens(chords_line)
    if len(tokens) < 4 or len(tokens) > 8:
        return False
    if level == "初级":
        return all(_TOKEN_BEGINNER.match(t) for t in tokens)
    if level == "中级":
        for t in tokens:
            if _RE_TOO_JAZZY_FOR_MID.search(t):
                return False
            if not _TOKEN_MID_OK.match(t) or len(t) > 48:
                return False
        return True
    for t in tokens:
        if not _TOKEN_ADV_OK.match(t) or len(t) > 56:
            return False
    return True


def _generate_chords_with_llm(style, level):
    level = _normalize_level(level)
    prompt = (
        "你是专业音乐制作人和乐理老师。为「{style}」风格、按下列难度档给出 **6 条**和弦进行。\n"
        "{level_block}"
        "硬性要求：\n"
        "1) 乐理准确，功能和声合理，难度与风格一致。\n"
        "2) 每条进行 4-8 个和弦，和弦之间用 \" - \" 分隔。\n"
        "3) 参考歌曲：每条 2-3 首，**优先大陆/港台耳熟能详的主流中文流行歌**（不要太冷门）；"
        "每条里英文歌最多 1 首，其余必须为中文歌。格式「歌名 - 歌手」。\n"
        "4) 六条进行互不重复。\n"
        "5) **所有和弦必须按 C 大调固定调记谱**（字母和弦），禁止首调改写，便于程序变调。\n\n"
        "输出格式严格为 6 行纯文本，每行：\n"
        "和弦进行 || 歌曲A - 歌手; 歌曲B - 歌手; 歌曲C - 歌手\n"
        "不要编号，不要解释，不要 Markdown。"
    ).format(style=style, level_block=_level_prompt_block(style, level))

    max_tokens = 1100 if level == "高级" else 950

    for _ in range(3):
        result = _call_dashscope(prompt, max_tokens=max_tokens)
        text = _extract_dashscope_text(result)
        if not text:
            continue
        cleaned = []
        seen = set()
        for raw_line in text.splitlines():
            line = raw_line.strip().lstrip("-").strip()
            if not line or "||" not in line:
                continue
            chords, refs_part = line.split("||", 1)
            chords = chords.strip()
            if (
                not chords
                or chords in seen
                or not _progression_matches_level(chords, level)
            ):
                continue
            refs = [x.strip() for x in refs_part.split(";") if x.strip()]
            cleaned.append({"chords": chords, "song_refs": refs[:3]})
            seen.add(chords)
            if len(cleaned) >= 6:
                break
        if len(cleaned) >= 6:
            return {
                "style": style,
                "level": level,
                "progressions": cleaned,
                "raw": result,
            }

    raise ValueError(
        "Model returned fewer than 6 valid chord progressions"
    )


def _call_dashscope(prompt, max_tokens=900):
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


CHORD_EXPLAIN_DISCLAIMER = (
    "指法与音名由 AI 生成，可能与个人手型或不同版本谱例略有差异；"
    "请以实际音高为准，必要时对照标准教材或老师示范。"
)


def _parse_json_object_from_llm_text(text):
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("Model output is not valid JSON object")
    return json.loads(text[start : end + 1])


def _normalize_one_fret_cell(val):
    if val is None:
        return -1
    if isinstance(val, str):
        s = val.strip().lower()
        if s in ("x", "m", "mute", ""):
            return -1
        try:
            val = int(s)
        except ValueError:
            raise ValueError("invalid fret cell")
    if not isinstance(val, int) or isinstance(val, bool):
        raise ValueError("invalid fret cell")
    if val == -1:
        return -1
    if val == 0:
        return 0
    if 1 <= val <= 24:
        return val
    raise ValueError("fret out of range")


def _validate_and_normalize_chord_explain(obj):
    if not isinstance(obj, dict):
        raise ValueError("explain payload not an object")
    frets_raw = obj.get("frets")
    if not isinstance(frets_raw, list) or len(frets_raw) != 6:
        raise ValueError("frets must be array of length 6 (6th→1st string)")
    frets = [_normalize_one_fret_cell(x) for x in frets_raw]
    if not any(f >= 0 for f in frets):
        raise ValueError("at least one open or fretted string required")

    fingers_out = None
    fingers_raw = obj.get("fingers")
    if isinstance(fingers_raw, list) and len(fingers_raw) == 6:
        fingers_out = []
        for x in fingers_raw:
            if x is None:
                fingers_out.append(None)
            elif isinstance(x, int) and not isinstance(x, bool) and 0 <= x <= 4:
                fingers_out.append(x)
            else:
                fingers_out.append(None)

    bf = obj.get("base_fret")
    if isinstance(bf, int) and not isinstance(bf, bool) and bf >= 1:
        base_fret = bf
    else:
        pressed = [f for f in frets if f > 0]
        base_fret = min(pressed) if pressed else 1
    pressed = [f for f in frets if f > 0]
    if pressed:
        base_fret = max(1, min(base_fret, min(pressed)))

    notes_letters = obj.get("notes_letters")
    if not isinstance(notes_letters, list):
        notes_letters = []

    barre = obj.get("barre")
    if barre is not None and not isinstance(barre, dict):
        barre = None
    if isinstance(barre, dict):
        try:
            bfret = int(barre.get("fret"))
            fs = int(barre.get("from_string"))
            ts = int(barre.get("to_string"))
            if not (1 <= bfret <= 24 and 1 <= fs <= 6 and 1 <= ts <= 6):
                barre = None
            else:
                barre = {"fret": bfret, "from_string": fs, "to_string": ts}
        except (TypeError, ValueError):
            barre = None

    return {
        "symbol": str(obj.get("symbol") or "").strip(),
        "notes_letters": [str(x).strip() for x in notes_letters if str(x).strip()],
        "notes_explain_zh": str(obj.get("notes_explain_zh") or "").strip(),
        "voicing_explain_zh": str(obj.get("voicing_explain_zh") or "").strip(),
        "frets": frets,
        "fingers": fingers_out,
        "base_fret": base_fret,
        "barre": barre,
    }


def _truthy_body_flag(val):
    if val is True:
        return True
    if val is False or val is None:
        return False
    if isinstance(val, (int, float)) and not isinstance(val, bool):
        return val != 0
    if isinstance(val, str):
        return val.strip().lower() in ("1", "true", "yes", "on")
    return False


def _explain_chord_with_llm(symbol, key, level, *, recalibrate=False):
    level = _normalize_level(level)
    recalibrate_block = ""
    if recalibrate:
        recalibrate_block = (
            "\n【重要】有用户反馈上一版指法或文字说明可能有误，请求**重新校准**。"
            "请从标准调弦与和弦符号出发**独立复核**：核对每个按弦音高是否与 notes_letters、symbol 一致，"
            "修正 frets/fingers/base_fret/barre 的自洽性；文字说明须与最终指法严格对应。"
            "不要复述「可能错误」之类套话，直接输出修正后的完整 JSON。\n"
        )
    prompt = (
        "你是严谨的吉他乐理与演奏教师。标准调弦从 **6 弦到 1 弦**（粗→细）音名为：E A D G B E。\n"
        "用户给出的和弦符号是：「{symbol}」。当前页面选调：**{key}**，练习难度档：**{level}**。"
        "{recalibrate_block}\n"
        "请只输出 **一个 JSON 对象**，不要 Markdown，不要代码围栏，不要任何 JSON 以外的文字。\n"
        "字段必须全部存在，类型严格如下：\n"
        '1) "symbol": 字符串，与「{symbol}」一致。\n'
        '2) "notes_letters": 字符串数组，列出该和弦在和弦语义下的**音名字母**（如 ["A","C","E","G"]），不写八度，须与 symbol 和弦类型一致。\n'
        '3) "notes_explain_zh": 字符串，50～140 字，说明根音、和弦性质（大三/小三/属七/小七等）、主要音程关系；必须与 symbol 严格对应。\n'
        '4) "voicing_explain_zh": 字符串，80～200 字，说明本按法把位选择理由（开放/常用把位、是否省略重复音、是否利于弹唱转换）；并提醒以实际音准为准。\n'
        '5) "frets": 长度 **6** 的整数数组，顺序为 **6 弦→1 弦**。-1 表示不弹/闷音，0 表示空弦，正整数为相对**琴枕**的品格。\n'
        '6) "fingers": 长度 6 的数组，元素为 null 或 1～4（食指到小指正按该弦时使用的手指），空弦与闷音用 null。\n'
        '7) "base_fret": 整数 ≥1，为指法图左侧应标注的起始品格；开放和弦一般为 1；高把位取所按最低品格。\n'
        '8) "barre": 若无横按则为 null；否则为对象 {{"fret":整数,"from_string":6~1,"to_string":6~1}}，弦号 6=最粗、1=最细。\n\n'
        "准确性要求：frets 与 fingers 必须自洽；按法在人类正常跨度内；"
        "notes_letters 与和弦类型不得矛盾。若 symbol 含转位低音（如 G/B），frets 须体现该低音在对应弦上。"
    ).format(symbol=symbol, key=key, level=level, recalibrate_block=recalibrate_block)

    result = _call_dashscope(prompt, max_tokens=900)
    text = _extract_dashscope_text(result)
    if not text:
        raise ValueError("Model returned empty text")
    obj = _parse_json_object_from_llm_text(text)
    normalized = _validate_and_normalize_chord_explain(obj)
    if not normalized["symbol"]:
        normalized["symbol"] = symbol
    return {
        "explain": normalized,
        "disclaimer": CHORD_EXPLAIN_DISCLAIMER,
    }


_MULTI_CACHE_LEVEL_SUFFIX = "·multi"


def _fetch_cached_chord_multi(symbol, music_key, level):
    lvl = _normalize_level(level)
    cache_level = f"{lvl}{_MULTI_CACHE_LEVEL_SUFFIX}"
    raw = fetch_cached_explain(symbol, music_key, cache_level)
    if not isinstance(raw, dict) or raw.get("kind") != "multi":
        return None
    return raw


def _save_chord_multi_cache(symbol, music_key, level, payload_dict):
    lvl = _normalize_level(level)
    cache_level = f"{lvl}{_MULTI_CACHE_LEVEL_SUFFIX}"
    save_chord_explain(symbol, music_key, cache_level, payload_dict)


def _normalize_multi_voicings_response(obj, symbol_fallback, key, level):
    if not isinstance(obj, dict):
        raise ValueError("multi explain root not an object")
    sym = str(obj.get("symbol") or symbol_fallback).strip() or symbol_fallback
    notes_letters = obj.get("notes_letters")
    if not isinstance(notes_letters, list):
        notes_letters = []
    notes_letters = [str(x).strip() for x in notes_letters if str(x).strip()]
    notes_explain_zh = str(obj.get("notes_explain_zh") or "").strip()
    voicings_raw = obj.get("voicings")
    if not isinstance(voicings_raw, list) or len(voicings_raw) < 2:
        raise ValueError("voicings must be array with at least 2 items")
    out_v = []
    for i, v in enumerate(voicings_raw[:8]):
        if not isinstance(v, dict):
            continue
        label_zh = str(v.get("label_zh") or f"按法 {i + 1}").strip()
        merged = {
            "symbol": sym,
            "notes_letters": list(notes_letters),
            "notes_explain_zh": notes_explain_zh,
            "voicing_explain_zh": str(v.get("voicing_explain_zh") or "").strip(),
            "frets": v.get("frets"),
            "fingers": v.get("fingers"),
            "base_fret": v.get("base_fret"),
            "barre": v.get("barre"),
        }
        norm = _validate_and_normalize_chord_explain(merged)
        out_v.append({"label_zh": label_zh, "explain": norm})
    if len(out_v) < 2:
        raise ValueError("fewer than 2 valid voicings after validation")
    chord_summary = {
        "symbol": sym,
        "notes_letters": notes_letters,
        "notes_explain_zh": notes_explain_zh,
        "key": key,
        "level": _normalize_level(level),
    }
    return {
        "kind": "multi",
        "chord_summary": chord_summary,
        "voicings": out_v,
    }


def _explain_chord_multi_with_llm(symbol, key, level, *, recalibrate=False):
    level = _normalize_level(level)
    recalibrate_block = ""
    if recalibrate:
        recalibrate_block = (
            "\n【重要】用户请求**重新生成**多套按法。请忽略任何旧版，从标准调弦与和弦符号**独立**给出"
            " **3～5 种**明显不同的常用吉他按法（开放/不同把位/横按等），每种须自洽。\n"
        )
    prompt = (
        "你是严谨的吉他乐理与演奏教师。标准调弦从 **6 弦到 1 弦**（粗→细）音名为：E A D G B E。\n"
        "和弦符号：「{symbol}」。当前页面选调：**{key}**，练习难度档：**{level}**。"
        "{recalibrate_block}\n"
        "请只输出 **一个 JSON 对象**，不要 Markdown，不要代码围栏，不要任何 JSON 以外的文字。\n"
        "顶层字段：\n"
        '1) "symbol": 字符串，与「{symbol}」一致。\n'
        '2) "notes_letters": 字符串数组，该和弦在和弦语义下的音名字母（不写八度）。\n'
        '3) "notes_explain_zh": 字符串，60～160 字，说明根音、和弦性质、主要音程；与 symbol 严格对应。\n'
        '4) "voicings": **数组**，长度 **3～5**，每个元素为对象，字段：\n'
        '   - "label_zh": 短标签，如「开放把位」「第3品附近」「横按」「高把位简化」等。\n'
        '   - "voicing_explain_zh": 50～160 字，说明该按法适用场景、与邻近和弦衔接等。\n'
        '   - "frets": 长度 6 的整数数组，6 弦→1 弦，-1 闷音，0 空弦，正整数为相对琴枕品格。\n'
        '   - "fingers": 长度 6，元素 null 或 1～4。\n'
        '   - "base_fret": 整数 ≥1。\n'
        '   - "barre": null 或 {{ "fret","from_string","to_string" }}（弦号 6=最粗）。\n'
        "要求：各 voicing 之间**把位或按法形态须明显不同**；frets/fingers 自洽；"
        "若 symbol 含 slash 低音，至少一种按法须体现该低音在对应弦上。\n"
    ).format(symbol=symbol, key=key, level=level, recalibrate_block=recalibrate_block)

    result = _call_dashscope(prompt, max_tokens=2800)
    text = _extract_dashscope_text(result)
    if not text:
        raise ValueError("Model returned empty text")
    obj = _parse_json_object_from_llm_text(text)
    return _normalize_multi_voicings_response(obj, symbol, key, level)


def handler(event, context):
    event = _normalize_event(event)
    event["headers"] = _merge_request_headers(event)
    if event.get("isBase64Encoded"):
        try:
            raw_b = event.get("body") or ""
            event["bodyRaw"] = base64.b64decode(raw_b) if isinstance(raw_b, str) else bytes(raw_b or b"")
        except (ValueError, TypeError, binascii.Error):
            event["bodyRaw"] = b""
    elif "bodyRaw" not in event:
        btxt = event.get("body")
        event["bodyRaw"] = btxt.encode("utf-8", errors="ignore") if isinstance(btxt, str) else b""
    path = _request_path(event)
    method = _request_method(event)
    LOGGER.debug("Incoming request method=%s path=%s", method, path)

    def _sheets_resp(code, payload):
        return _response(code, payload)

    def _sheets_bin(code, data, ctype):
        return _response_binary(code, data, ctype)

    sheets_out = handle_sheets_routes(event, _sheets_resp, _sheets_bin)
    if sheets_out is not None:
        return sheets_out

    def _practice_resp(code, payload):
        return _response(code, payload)

    practice_out = handle_practice_routes(event, _practice_resp)
    if practice_out is not None:
        return practice_out

    if method == "OPTIONS":
        return _response(204, {"ok": True})

    if method == "GET" and path in ("/auth/health", "/api/auth/health"):
        code, payload = handle_auth_health_get()
        return _response(code, payload)

    if method == "POST" and path in ("/auth/apple", "/api/auth/apple"):
        body = _extract_body(event)
        code, payload = handle_auth_apple_post(body)
        return _response(code, payload)

    if method == "GET" and path in ("/styles", "/api/styles"):
        styles = list(STYLE_TO_PROGRESSIONS.keys())
        return _response(
            200,
            {
                "styles": styles,
                "defaultStyle": styles[0] if styles else "",
            },
        )

    if method == "GET" and path in ("/keys", "/api/keys"):
        return _response(
            200,
            {
                "keys": TWELVE_KEYS,
                "defaultKey": REFERENCE_KEY,
                "referenceKey": REFERENCE_KEY,
            },
        )

    if method == "GET" and path in ("/levels", "/api/levels"):
        return _response(
            200,
            {
                "levels": list(LEVEL_IDS),
                "defaultLevel": LEVEL_DEFAULT,
            },
        )

    if method == "GET" and path in ("/song-chords/health", "/api/song-chords/health"):
        if not song_chords_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        try:
            ensure_song_chords_schema()
            return _response(200, {"ok": True, "mysql_enabled": True})
        except Exception as e:
            return _response(500, {"error": "song chords health failed", "detail": str(e)})

    if method == "POST" and path in ("/song-chords/search", "/api/song-chords/search"):
        if not song_chords_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        query_text = (body.get("query_text") or body.get("query") or "").strip()
        difficulty = (body.get("difficulty") or "beginner").strip().lower()
        if not query_text:
            return _response(400, {"error": "query_text required"})
        t0 = time.time()
        try:
            out = search_song_chords(query_text, difficulty)
            out["latency_ms"] = int((time.time() - t0) * 1000)
            return _response(200, out)
        except ValueError as e:
            return _response(400, {"error": str(e)})
        except Exception as e:
            return _response(500, {"error": "song chords search failed", "detail": str(e)})

    if method == "POST" and path in ("/song-chords/ai-verify", "/api/song-chords/ai-verify"):
        if not song_chords_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        song_id = body.get("song_id")
        difficulty = (body.get("difficulty") or "beginner").strip().lower()
        if not isinstance(song_id, int):
            return _response(400, {"error": "song_id must be integer"})
        try:
            score = ai_verify_song_chords(song_id, difficulty)
            return _response(
                200,
                {
                    "ok": True,
                    "message": "AI核对完成：已备份旧版到 v2，并将新结果覆盖当前 v1",
                    "score": score,
                },
            )
        except ValueError as e:
            return _response(400, {"error": str(e)})
        except Exception as e:
            return _response(500, {"error": "song chords ai verify failed", "detail": str(e)})

    if method == "POST" and path in ("/song-chords/version", "/api/song-chords/version"):
        if not song_chords_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        song_id = body.get("song_id")
        difficulty = (body.get("difficulty") or "beginner").strip().lower()
        version_no = (body.get("version_no") or "v2").strip().lower()
        if not isinstance(song_id, int):
            return _response(400, {"error": "song_id must be integer"})
        try:
            score = get_song_chords_version(song_id, difficulty, version_no)
            if score is None:
                return _response(404, {"error": "version not found"})
            return _response(200, {"score": score})
        except ValueError as e:
            return _response(400, {"error": str(e)})
        except Exception as e:
            return _response(500, {"error": "song chords version fetch failed", "detail": str(e)})

    if method == "GET" and path in ("/quiz/health", "/api/quiz/health"):
        if not quiz_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        try:
            ensure_quiz_schema()
            return _response(
                200,
                {
                    "ok": True,
                    "mysql_enabled": True,
                    "seed_file_default": QUIZ_SEED_DEFAULT_PATH,
                    "counts": quiz_health_counts(),
                },
            )
        except Exception as e:
            return _response(500, {"error": "quiz health failed", "detail": str(e)})

    if method == "POST" and path in ("/quiz/admin/init-seed", "/api/quiz/admin/init-seed"):
        if not quiz_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        seed_file = (body.get("seed_file") or QUIZ_SEED_DEFAULT_PATH).strip()
        overwrite_status = (body.get("status") or "active").strip() or "active"
        version = (body.get("version") or "").strip() or None
        try:
            ensure_quiz_schema()
            imported = import_quiz_seed(
                seed_file,
                version=version,
                status=overwrite_status,
            )
            return _response(
                200,
                {
                    "ok": True,
                    "seed_file": seed_file,
                    "imported": imported,
                    "counts": quiz_health_counts(),
                },
            )
        except Exception as e:
            return _response(500, {"error": "quiz seed import failed", "detail": str(e)})

    if method == "POST" and path in ("/quiz/session/start", "/api/quiz/session/start"):
        if not quiz_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        learner_id = (body.get("learner_id") or "").strip()
        difficulty = (body.get("difficulty") or "").strip().lower()
        wrong_only = _truthy_body_flag(body.get("wrong_only"))
        if not learner_id:
            return _response(400, {"error": "learner_id required"})
        try:
            ensure_quiz_schema()
            attempt = create_attempt(learner_id, difficulty, wrong_only=wrong_only)
            q = get_next_question(attempt["attempt_id"])
            return _response(200, {"attempt": attempt, "question": q})
        except Exception as e:
            return _response(500, {"error": "quiz session start failed", "detail": str(e)})

    if method == "POST" and path in ("/quiz/session/next", "/api/quiz/session/next"):
        if not quiz_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        attempt_id = body.get("attempt_id")
        if not isinstance(attempt_id, int):
            return _response(400, {"error": "attempt_id must be integer"})
        try:
            q = get_next_question(attempt_id)
            return _response(200, {"question": q})
        except Exception as e:
            return _response(400, {"error": "quiz next failed", "detail": str(e)})

    if method == "POST" and path in ("/quiz/session/answer", "/api/quiz/session/answer"):
        if not quiz_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        attempt_id = body.get("attempt_id")
        question_id = (body.get("question_id") or "").strip()
        selected_option_key = (body.get("selected_option_key") or "").strip()
        if not isinstance(attempt_id, int):
            return _response(400, {"error": "attempt_id must be integer"})
        if not question_id:
            return _response(400, {"error": "question_id required"})
        try:
            out = answer_question(attempt_id, question_id, selected_option_key)
            return _response(200, out)
        except Exception as e:
            return _response(400, {"error": "quiz answer failed", "detail": str(e)})

    if method == "POST" and path in ("/quiz/session/finish", "/api/quiz/session/finish"):
        if not quiz_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        attempt_id = body.get("attempt_id")
        if not isinstance(attempt_id, int):
            return _response(400, {"error": "attempt_id must be integer"})
        try:
            out = finish_attempt(attempt_id)
            return _response(200, out)
        except Exception as e:
            return _response(400, {"error": "quiz finish failed", "detail": str(e)})

    if method == "GET" and path in ("/ear/health", "/api/ear/health"):
        if not ear_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        try:
            ensure_ear_schema()
            return _response(
                200,
                {
                    "ok": True,
                    "mysql_enabled": True,
                    "seed_file_default": EAR_SEED_DEFAULT_PATH,
                    "counts": ear_health_counts(),
                },
            )
        except Exception as e:
            return _response(500, {"error": "ear health failed", "detail": str(e)})

    if method == "POST" and path in (
        "/ear-note/session/start",
        "/api/ear-note/session/start",
    ):
        body = _extract_body(event)
        mode = _normalize_ear_note_mode(body.get("mode"))
        include_accidental = _truthy_body_flag(body.get("include_accidental"))
        notes_per_question = body.get("notes_per_question", 1)
        question_count = body.get("question_count", 10)
        try:
            notes_per_question = int(notes_per_question)
            question_count = int(question_count)
        except (TypeError, ValueError):
            return _response(400, {"error": "notes_per_question/question_count must be integer"})
        if mode == "single_note":
            notes_per_question = 1
        elif notes_per_question <= 1:
            notes_per_question = 3
        notes_per_question = max(1, min(notes_per_question, 5))
        question_count = max(1, min(question_count, 50))
        session_id = f"ens_{uuid.uuid4().hex[:16]}"
        questions = _generate_ear_note_questions(
            question_count=question_count,
            notes_per_question=notes_per_question,
            include_accidental=include_accidental,
        )
        notes = _ear_note_allowed_pitches(include_accidental)
        now_ts = int(time.time())
        session = {
            "session_id": session_id,
            "mode": mode,
            "include_accidental": bool(include_accidental),
            "notes_per_question": notes_per_question,
            "question_count": question_count,
            "notes": notes,
            "questions": questions,
            "current_index": 0,
            "answers": [],
            "started_at": now_ts,
        }
        with _EAR_NOTE_SESSION_LOCK:
            _EAR_NOTE_SESSIONS[session_id] = session
        return _response(
            200,
            {
                "session_id": session_id,
                "config": {
                    "mode": mode,
                    "include_accidental": bool(include_accidental),
                    "notes_per_question": notes_per_question,
                    "question_count": question_count,
                    "pitch_range": f"C{EAR_NOTE_OCTAVE}-B{EAR_NOTE_OCTAVE}",
                    "standard_tone": "A4",
                },
                "question": _ear_note_public_question(session, questions[0]) if questions else None,
            },
        )

    if method == "POST" and path in (
        "/ear-note/session/answer",
        "/api/ear-note/session/answer",
    ):
        body = _extract_body(event)
        session_id = (body.get("session_id") or "").strip()
        question_id = (body.get("question_id") or "").strip()
        answers = body.get("answers") or []
        if not session_id or not question_id:
            return _response(400, {"error": "session_id/question_id required"})
        if not isinstance(answers, list):
            return _response(400, {"error": "answers must be array"})
        with _EAR_NOTE_SESSION_LOCK:
            session = _EAR_NOTE_SESSIONS.get(session_id)
        if not session:
            return _response(404, {"error": "session not found"})
        q = None
        for item in session.get("questions") or []:
            if item.get("question_id") == question_id:
                q = item
                break
        if not q:
            return _response(404, {"error": "question not found"})
        correct_labels = [_ear_note_pitch_label(n) for n in q.get("target_notes") or []]
        user_labels = [_ear_note_pitch_label(x) for x in answers]
        is_correct = user_labels == correct_labels
        answer_item = {
            "question_id": question_id,
            "user_answers": user_labels,
            "correct_answers": correct_labels,
            "is_correct": bool(is_correct),
            "answered_at": int(time.time()),
        }
        with _EAR_NOTE_SESSION_LOCK:
            # de-duplicate same question answer, keep latest
            kept = [x for x in session["answers"] if x.get("question_id") != question_id]
            kept.append(answer_item)
            session["answers"] = kept
            answered = len(kept)
            correct = sum(1 for x in kept if x.get("is_correct"))
        return _response(
            200,
            {
                "question_id": question_id,
                "is_correct": bool(is_correct),
                "correct_answers": correct_labels,
                "user_answers": user_labels,
                "progress": {
                    "answered": answered,
                    "correct": correct,
                    "total": int(session.get("question_count") or 0),
                    "accuracy": (correct / answered) if answered else 0.0,
                },
            },
        )

    if method == "POST" and path in (
        "/ear-note/session/next",
        "/api/ear-note/session/next",
    ):
        body = _extract_body(event)
        session_id = (body.get("session_id") or "").strip()
        if not session_id:
            return _response(400, {"error": "session_id required"})
        with _EAR_NOTE_SESSION_LOCK:
            session = _EAR_NOTE_SESSIONS.get(session_id)
            if not session:
                return _response(404, {"error": "session not found"})
            next_index = int(session.get("current_index") or 0) + 1
            session["current_index"] = next_index
            questions = session.get("questions") or []
            if next_index >= len(questions):
                return _response(200, {"question": None, "has_next": False})
            q = questions[next_index]
        return _response(200, {"question": _ear_note_public_question(session, q), "has_next": True})

    if method == "GET" and (
        path.startswith("/ear-note/session/result/")
        or path.startswith("/api/ear-note/session/result/")
    ):
        session_id = path.rsplit("/", 1)[-1].strip()
        if not session_id:
            return _response(400, {"error": "session_id required"})
        with _EAR_NOTE_SESSION_LOCK:
            session = _EAR_NOTE_SESSIONS.get(session_id)
        if not session:
            return _response(404, {"error": "session not found"})
        answers = list(session.get("answers") or [])
        answered = len(answers)
        correct = sum(1 for x in answers if x.get("is_correct"))
        return _response(
            200,
            {
                "session_id": session_id,
                "config": {
                    "mode": session.get("mode"),
                    "include_accidental": session.get("include_accidental"),
                    "notes_per_question": session.get("notes_per_question"),
                    "question_count": session.get("question_count"),
                },
                "summary": {
                    "answered": answered,
                    "correct": correct,
                    "total": int(session.get("question_count") or 0),
                    "accuracy": (correct / answered) if answered else 0.0,
                },
                "wrongs": [
                    x
                    for x in answers
                    if not x.get("is_correct")
                ][:30],
            },
        )

    if method == "POST" and path in ("/ear/admin/init-seed", "/api/ear/admin/init-seed"):
        if not ear_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        seed_file = (body.get("seed_file") or EAR_SEED_DEFAULT_PATH).strip()
        status = (body.get("status") or "active").strip() or "active"
        version = (body.get("version") or "").strip() or None
        try:
            ensure_ear_schema()
            imported = import_ear_seed(seed_file, version=version, status=status)
            return _response(
                200,
                {
                    "ok": True,
                    "seed_file": seed_file,
                    "imported": imported,
                    "counts": ear_health_counts(),
                },
            )
        except Exception as e:
            return _response(500, {"error": "ear seed import failed", "detail": str(e)})

    if method == "POST" and path in ("/ear/daily/generate", "/api/ear/daily/generate"):
        if not ear_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        learner_id = (body.get("learner_id") or "").strip()
        force = _truthy_body_flag(body.get("force_regenerate"))
        if not learner_id:
            return _response(400, {"error": "learner_id required"})
        try:
            ensure_ear_schema()
            out = generate_or_get_daily_set(learner_id, force_regenerate=force)
            return _response(200, out)
        except Exception as e:
            return _response(500, {"error": "ear daily generate failed", "detail": str(e)})

    if method == "GET" and path in ("/ear/daily/today", "/api/ear/daily/today"):
        if not ear_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        q = event.get("queryStringParameters") or {}
        learner_id = (q.get("learner_id") or "").strip()
        if not learner_id:
            return _response(400, {"error": "learner_id required"})
        try:
            ensure_ear_schema()
            out = generate_or_get_daily_set(learner_id, force_regenerate=False)
            return _response(200, out)
        except Exception as e:
            return _response(500, {"error": "ear daily today failed", "detail": str(e)})

    if method == "GET" and path in ("/ear/mistakes", "/api/ear/mistakes"):
        if not ear_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        q = event.get("queryStringParameters") or {}
        learner_id = (q.get("learner_id") or "").strip()
        if not learner_id:
            return _response(400, {"error": "learner_id required"})
        try:
            ensure_ear_schema()
            rows = get_ear_mistakes(learner_id)
            return _response(200, {"mistakes": rows})
        except Exception as e:
            return _response(500, {"error": "ear mistakes failed", "detail": str(e)})

    if method == "GET" and path in ("/ear/train/start", "/api/ear/train/start"):
        if not ear_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        q = event.get("queryStringParameters") or {}
        learner_id = (q.get("learner_id") or "").strip()
        mode = (q.get("mode") or "A").strip().upper()
        if not learner_id:
            return _response(400, {"error": "learner_id required"})
        try:
            ensure_ear_schema()
            daily_set_id = None
            if mode == "C":
                daily = generate_or_get_daily_set(learner_id, force_regenerate=False)
                daily_set_id = daily["daily_set_id"]
            attempt = create_ear_attempt(learner_id, mode, daily_set_id=daily_set_id)
            question = get_next_ear_question(attempt["attempt_id"])
            return _response(200, {"attempt": attempt, "question": question})
        except Exception as e:
            return _response(500, {"error": "ear start failed", "detail": str(e)})

    if method == "POST" and path in ("/ear/train/next", "/api/ear/train/next"):
        if not ear_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        attempt_id = body.get("attempt_id")
        if not isinstance(attempt_id, int):
            return _response(400, {"error": "attempt_id must be integer"})
        try:
            ensure_ear_schema()
            question = get_next_ear_question(attempt_id)
            return _response(200, {"question": question})
        except Exception as e:
            return _response(400, {"error": "ear next failed", "detail": str(e)})

    if method == "POST" and path in ("/ear/train/answer", "/api/ear/train/answer"):
        if not ear_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        body = _extract_body(event)
        attempt_id = body.get("attempt_id")
        question_id = (body.get("question_id") or "").strip()
        selected_option_key = (body.get("selected_option_key") or "").strip()
        if not isinstance(attempt_id, int):
            return _response(400, {"error": "attempt_id must be integer"})
        if not question_id:
            return _response(400, {"error": "question_id required"})
        try:
            ensure_ear_schema()
            out = answer_ear_question(attempt_id, question_id, selected_option_key)
            return _response(200, out)
        except Exception as e:
            return _response(400, {"error": "ear answer failed", "detail": str(e)})

    if method == "GET" and (
        path.startswith("/api/ear/train/result/") or path.startswith("/ear/train/result/")
    ):
        if not ear_mysql_enabled():
            return _response(
                503,
                {
                    "error": "MySQL 未配置",
                    "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
                },
            )
        try:
            ensure_ear_schema()
            attempt_id_s = path.rsplit("/", 1)[-1]
            attempt_id = int(attempt_id_s)
            out = finish_ear_attempt(attempt_id)
            return _response(200, out)
        except Exception as e:
            return _response(400, {"error": "ear result failed", "detail": str(e)})

    if method == "POST" and path in ("/chords/explain", "/api/chords/explain"):
        body = _extract_body(event)
        symbol = (body.get("symbol") or "").strip()
        if not symbol or len(symbol) > 48:
            return _response(
                400,
                {"error": "Missing or invalid field: symbol (non-empty string, max 48 chars)"},
            )
        if not re.match(r"^[A-Za-z0-9#/()+°Øø\-\s]+$", symbol):
            return _response(400, {"error": "symbol contains invalid characters"})
        key = normalize_key(body.get("key") or REFERENCE_KEY)
        level = _normalize_level((body.get("level") or "").strip())
        force_refresh = _truthy_body_flag(
            body.get("force_refresh", body.get("recalibrate"))
        )
        if not force_refresh:
            cached_raw = fetch_cached_explain(symbol, key, level)
            if cached_raw is not None:
                try:
                    normalized = _validate_and_normalize_chord_explain(cached_raw)
                    if not normalized["symbol"]:
                        normalized["symbol"] = symbol
                    return _response(
                        200,
                        {
                            "explain": normalized,
                            "disclaimer": CHORD_EXPLAIN_DISCLAIMER,
                            "from_cache": True,
                        },
                    )
                except (ValueError, TypeError, KeyError):
                    pass
        if not DASHSCOPE_API_KEY:
            return _response(
                500,
                {
                    "error": "Missing DASHSCOPE_API_KEY",
                    "message": "Set DASHSCOPE_API_KEY to enable chord explain (no cache for this symbol/key/level).",
                },
            )
        try:
            payload = _explain_chord_with_llm(symbol, key, level, recalibrate=force_refresh)
            save_chord_explain(symbol, key, level, payload["explain"])
            out = dict(payload)
            out["from_cache"] = False
            if force_refresh:
                out["recalibrated"] = True
            return _response(200, out)
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="ignore")
            return _response(
                e.code,
                {"error": "DashScope HTTP error", "status": e.code, "detail": detail},
            )
        except urllib.error.URLError as e:
            return _response(502, {"error": "DashScope network error", "detail": str(e)})
        except (ValueError, json.JSONDecodeError, KeyError, TypeError) as e:
            return _response(
                502,
                {"error": "Chord explain parse failed", "detail": str(e)},
            )
        except Exception as e:
            return _response(500, {"error": "Chord explain failed", "detail": str(e)})

    if method == "POST" and path in (
        "/chords/explain-multi",
        "/api/chords/explain-multi",
    ):
        body = _extract_body(event)
        symbol = (body.get("symbol") or "").strip()
        if not symbol or len(symbol) > 48:
            return _response(
                400,
                {"error": "Missing or invalid field: symbol (non-empty string, max 48 chars)"},
            )
        if not re.match(r"^[A-Za-z0-9#/()+°Øø\-\s]+$", symbol):
            return _response(400, {"error": "symbol contains invalid characters"})
        key = normalize_key(body.get("key") or REFERENCE_KEY)
        level = _normalize_level((body.get("level") or "").strip())
        force_refresh = _truthy_body_flag(
            body.get("force_refresh", body.get("recalibrate"))
        )
        if not force_refresh:
            cached = _fetch_cached_chord_multi(symbol, key, level)
            if cached is not None:
                return _response(
                    200,
                    {
                        "chord_summary": cached.get("chord_summary"),
                        "voicings": cached.get("voicings"),
                        "disclaimer": CHORD_EXPLAIN_DISCLAIMER,
                        "from_cache": True,
                    },
                )
        if not DASHSCOPE_API_KEY:
            return _response(
                500,
                {
                    "error": "Missing DASHSCOPE_API_KEY",
                    "message": "Set DASHSCOPE_API_KEY to enable chord explain-multi.",
                },
            )
        try:
            normalized = _explain_chord_multi_with_llm(
                symbol, key, level, recalibrate=force_refresh
            )
            _save_chord_multi_cache(symbol, key, level, normalized)
            out = {
                "chord_summary": normalized["chord_summary"],
                "voicings": normalized["voicings"],
                "disclaimer": CHORD_EXPLAIN_DISCLAIMER,
                "from_cache": False,
            }
            if force_refresh:
                out["recalibrated"] = True
            return _response(200, out)
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="ignore")
            return _response(
                e.code,
                {"error": "DashScope HTTP error", "status": e.code, "detail": detail},
            )
        except urllib.error.URLError as e:
            return _response(502, {"error": "DashScope network error", "detail": str(e)})
        except (ValueError, json.JSONDecodeError, KeyError, TypeError) as e:
            return _response(
                502,
                {"error": "Chord explain-multi parse failed", "detail": str(e)},
            )
        except Exception as e:
            return _response(500, {"error": "Chord explain-multi failed", "detail": str(e)})

    if method == "POST" and path in ("/chords/transpose", "/api/chords/transpose"):
        body = _extract_body(event)
        lines = body.get("lines")
        if not isinstance(lines, list) or not lines:
            return _response(
                400,
                {"error": "Missing or invalid field: lines (non-empty array of strings)"},
            )
        fk = normalize_key(body.get("from_key") or REFERENCE_KEY)
        tk = normalize_key(body.get("to_key") or REFERENCE_KEY)
        try:
            out_lines = transpose_lines(lines, fk, tk)
        except Exception as e:
            return _response(500, {"error": "Transpose failed", "detail": str(e)})
        return _response(
            200,
            {
                "lines": out_lines,
                "from_key": fk,
                "to_key": tk,
            },
        )

    if method == "POST" and path in ("/chords/generate", "/api/chords/generate"):
        body = _extract_body(event)
        style = (body.get("style") or "").strip() or "流行"
        level = _normalize_level((body.get("level") or "").strip())
        target_key = normalize_key(body.get("key") or REFERENCE_KEY)
        if not DASHSCOPE_API_KEY:
            return _response(
                500,
                {
                    "error": "Missing DASHSCOPE_API_KEY",
                    "message": "Set DASHSCOPE_API_KEY to enable model-based chord generation.",
                },
            )
        try:
            generated = _generate_chords_with_llm(style, level)
            delta = semitone_delta(REFERENCE_KEY, target_key)
            prefer_flats = prefer_flats_for_key(target_key)
            for item in generated.get("progressions", []):
                base = (item.get("chords") or "").strip()
                item["chords_base"] = base
                item["chords"] = transpose_progression_line(base, delta, prefer_flats)
            generated["reference_key"] = REFERENCE_KEY
            generated["target_key"] = target_key
            generated["level"] = level
            return _response(200, generated)
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="ignore")
            return _response(
                e.code,
                {"error": "DashScope HTTP error", "status": e.code, "detail": detail},
            )
        except urllib.error.URLError as e:
            return _response(502, {"error": "DashScope network error", "detail": str(e)})
        except Exception as e:
            return _response(500, {"error": "Chord generation failed", "detail": str(e)})

    if _is_mysql_demo_request(event):
        out = handle_mysql_http(event, _extract_body)
        return _response(out["statusCode"], out["payload"])

    if not DASHSCOPE_API_KEY:
        return _response(
            500,
            {
                "error": "Missing DASHSCOPE_API_KEY",
                "message": "Set DASHSCOPE_API_KEY in serverless environment variables.",
            },
        )

    if method == "GET":
        return _response(
            200,
            {
                "message": "DashScope serverless endpoint is running.",
                "usage": {
                    "method": "POST",
                    "body": {"prompt": "Write a short guitar practice plan."},
                },
                "model": DASHSCOPE_MODEL,
            },
        )

    body = _extract_body(event)
    prompt = (body.get("prompt") or "").strip()
    if not prompt:
        return _response(400, {"error": "Missing required field: prompt"})

    try:
        result = _call_dashscope(prompt)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="ignore")
        return _response(
            e.code,
            {"error": "DashScope HTTP error", "status": e.code, "detail": detail},
        )
    except urllib.error.URLError as e:
        return _response(502, {"error": "DashScope network error", "detail": str(e)})
    except Exception as e:
        return _response(500, {"error": "Unexpected error", "detail": str(e)})

    text = _extract_dashscope_text(result)
    return _response(
        200,
        {
            "prompt": prompt,
            "reply": text,
            "model": DASHSCOPE_MODEL,
            "raw": result,
        },
    )


class _LocalHTTPHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _serve(self, method):
        t0 = time.time()
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        raw_body = self.rfile.read(content_length) if content_length > 0 else b""
        path, _, query = self.path.partition("?")
        query_dict = {}
        if query:
            parsed = urllib.parse.parse_qs(query, keep_blank_values=True)
            query_dict = {k: (v[-1] if isinstance(v, list) and v else "") for k, v in parsed.items()}
        hdrs = {k: v for k, v in self.headers.items()}
        event = {
            "httpMethod": method,
            "path": path,
            "body": raw_body.decode("utf-8", errors="ignore"),
            "bodyRaw": raw_body,
            "headers": hdrs,
            "isBase64Encoded": False,
            "requestContext": {"http": {"method": method, "path": path}},
            "queryStringParameters": query_dict,
        }
        out = handler(event, None)
        status_code = int(out.get("statusCode", 200))
        headers = out.get("headers", {})
        body = out.get("body", "")
        if out.get("isBase64Encoded"):
            try:
                payload = base64.b64decode(body) if isinstance(body, str) else body
            except (ValueError, TypeError):
                payload = (body or "").encode("utf-8") if isinstance(body, str) else b""
        else:
            payload = body.encode("utf-8") if isinstance(body, str) else body

        self.send_response(status_code)
        for key, value in headers.items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if payload:
            self.wfile.write(payload)
        LOGGER.info(
            "Local HTTP %s %s -> %s (%d ms)",
            method,
            path,
            status_code,
            int((time.time() - t0) * 1000),
        )

    def do_GET(self):
        self._serve("GET")

    def do_POST(self):
        self._serve("POST")

    def do_PUT(self):
        self._serve("PUT")

    def do_DELETE(self):
        self._serve("DELETE")

    def do_OPTIONS(self):
        self._serve("OPTIONS")

    def log_message(self, fmt, *args):
        return


def run_local_server():
    LOGGER.info("Backend listening on http://%s:%s", BACKEND_HOST, BACKEND_PORT)
    class _ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
        daemon_threads = True

    with _ThreadingHTTPServer((BACKEND_HOST, BACKEND_PORT), _LocalHTTPHandler) as server:
        server.serve_forever()


if __name__ == "__main__":
    run_local_server()
