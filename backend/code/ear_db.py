# -*- coding: utf-8 -*-
import json
import os
import random
from contextlib import contextmanager
from datetime import date, datetime
from pathlib import Path

import pymysql
from pymysql.cursors import DictCursor

EAR_MODES = ("A", "B", "C")
_SCHEMA_CHECKED = False
_REQUIRED_TABLES = (
    "ear_question",
    "ear_attempt",
    "ear_attempt_item",
    "ear_mistake_book",
    "ear_daily_set",
)
_DDL_HINT_PATH = "backend/database/ddl/ear_training_tables.sql"
_RECENT_QUESTION_WINDOW = 8
_DAILY_COUNT = 10


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
        "read_timeout": int(os.getenv("MYSQL_READ_TIMEOUT", "30")),
        "write_timeout": int(os.getenv("MYSQL_WRITE_TIMEOUT", "30")),
        "autocommit": False,
    }


def ear_mysql_enabled():
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


def _today_str():
    return date.today().isoformat()


def ensure_ear_schema():
    global _SCHEMA_CHECKED
    if _SCHEMA_CHECKED:
        return
    with _connection() as conn:
        with conn.cursor() as cur:
            placeholders = ",".join(["%s"] * len(_REQUIRED_TABLES))
            cur.execute(
                "SELECT table_name FROM information_schema.tables "
                "WHERE table_schema = DATABASE() AND table_name IN (" + placeholders + ")",
                _REQUIRED_TABLES,
            )
            existed = {
                str(r.get("table_name") or r.get("TABLE_NAME") or "")
                for r in (cur.fetchall() or [])
            }
    missing = [t for t in _REQUIRED_TABLES if t not in existed]
    if missing:
        raise RuntimeError(
            "ear schema missing tables: "
            + ", ".join(missing)
            + f". Please execute {_DDL_HINT_PATH} once during deployment."
        )
    _SCHEMA_CHECKED = True


def _normalize_mode(mode):
    m = str(mode or "").strip().upper()
    return m if m in EAR_MODES else "A"


def _normalize_option(opt):
    if not isinstance(opt, dict):
        return None
    key = str(opt.get("key") or "").strip().upper()
    label = str(opt.get("label") or "").strip()
    is_correct = bool(opt.get("is_correct"))
    if key not in ("A", "B", "C", "D") or not label:
        return None
    return {"key": key, "label": label, "is_correct": is_correct}


def _decode_options(raw):
    if isinstance(raw, (bytes, bytearray)):
        raw = raw.decode("utf-8")
    if isinstance(raw, str):
        arr = json.loads(raw)
    elif isinstance(raw, list):
        arr = raw
    else:
        arr = []
    out = []
    for x in arr:
        n = _normalize_option(x)
        if n:
            out.append(n)
    out.sort(key=lambda x: x["key"])
    return out


def _validate_seed_question(q):
    if not isinstance(q, dict):
        return None
    qid = str(q.get("id") or "").strip()
    mode = _normalize_mode(q.get("mode"))
    qtype = str(q.get("question_type") or "").strip()
    difficulty = str(q.get("difficulty") or "").strip()
    prompt_zh = str(q.get("prompt_zh") or "").strip()
    correct_option_key = str(q.get("correct_option_key") or "").strip().upper()
    options_raw = q.get("options")
    if (
        not qid
        or not qtype
        or not difficulty
        or not prompt_zh
        or correct_option_key not in ("A", "B", "C", "D")
        or not isinstance(options_raw, list)
        or len(options_raw) != 4
    ):
        return None
    options = []
    seen = set()
    correct_count = 0
    for opt in options_raw:
        n = _normalize_option(opt)
        if not n:
            return None
        if n["key"] in seen:
            return None
        seen.add(n["key"])
        if n["is_correct"]:
            correct_count += 1
        options.append(n)
    if seen != {"A", "B", "C", "D"} or correct_count != 1:
        return None
    key_map = {o["key"]: o for o in options}
    if not key_map.get(correct_option_key, {}).get("is_correct"):
        return None
    return {
        "id": qid,
        "mode": mode,
        "question_type": qtype,
        "difficulty": difficulty,
        "music_key": str(q.get("music_key") or "").strip() or None,
        "root": str(q.get("root") or "").strip() or None,
        "chord_symbol": str(q.get("chord_symbol") or "").strip() or None,
        "target_quality": str(q.get("target_quality") or "").strip() or None,
        "progression_id": str(q.get("progression_id") or "").strip() or None,
        "progression_roman": str(q.get("progression_roman") or "").strip() or None,
        "variant_id": str(q.get("variant_id") or "").strip() or None,
        "hint_zh": str(q.get("hint_zh") or "").strip() or None,
        "prompt_zh": prompt_zh,
        "audio_json": q.get("audio_ref") if isinstance(q.get("audio_ref"), dict) else {},
        "correct_option_key": correct_option_key,
        "options": options,
        "tags_json": q.get("tags") if isinstance(q.get("tags"), list) else [],
    }


def import_ear_seed(seed_file_path, *, version=None, status="active"):
    p = Path(seed_file_path)
    if not p.exists():
        raise FileNotFoundError(f"seed not found: {seed_file_path}")
    raw = json.loads(p.read_text(encoding="utf-8"))
    banks = raw.get("banks")
    if not isinstance(banks, dict):
        raise ValueError("seed banks missing")
    rows = []
    for mode in ("A", "B"):
        items = banks.get(mode)
        if not isinstance(items, list):
            continue
        for item in items:
            q = _validate_seed_question(item)
            if q:
                rows.append(q)
    if not rows:
        raise ValueError("no valid seed questions")
    seed_version = str(version or raw.get("version") or "ear_seed_v1")
    saved = 0
    with _connection() as conn:
        with conn.cursor() as cur:
            for q in rows:
                cur.execute(
                    "INSERT INTO ear_question ("
                    "id, mode, question_type, difficulty, music_key, root, chord_symbol, target_quality, "
                    "progression_id, progression_roman, variant_id, prompt_zh, hint_zh, audio_json, "
                    "correct_option_key, options_json, tags_json, status, version"
                    ") VALUES ("
                    "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s"
                    ") ON DUPLICATE KEY UPDATE "
                    "mode=VALUES(mode), question_type=VALUES(question_type), difficulty=VALUES(difficulty), "
                    "music_key=VALUES(music_key), root=VALUES(root), chord_symbol=VALUES(chord_symbol), "
                    "target_quality=VALUES(target_quality), progression_id=VALUES(progression_id), "
                    "progression_roman=VALUES(progression_roman), variant_id=VALUES(variant_id), "
                    "prompt_zh=VALUES(prompt_zh), hint_zh=VALUES(hint_zh), audio_json=VALUES(audio_json), "
                    "correct_option_key=VALUES(correct_option_key), options_json=VALUES(options_json), "
                    "tags_json=VALUES(tags_json), status=VALUES(status), version=VALUES(version), "
                    "updated_at=CURRENT_TIMESTAMP",
                    (
                        q["id"],
                        q["mode"],
                        q["question_type"],
                        q["difficulty"],
                        q["music_key"],
                        q["root"],
                        q["chord_symbol"],
                        q["target_quality"],
                        q["progression_id"],
                        q["progression_roman"],
                        q["variant_id"],
                        q["prompt_zh"],
                        q["hint_zh"],
                        json.dumps(q["audio_json"], ensure_ascii=False),
                        q["correct_option_key"],
                        json.dumps(q["options"], ensure_ascii=False),
                        json.dumps(q["tags_json"], ensure_ascii=False),
                        status,
                        seed_version,
                    ),
                )
                saved += 1
        conn.commit()
    return {"saved": saved, "version": seed_version}


def _recent_question_ids(cur, learner_id, mode, limit=_RECENT_QUESTION_WINDOW):
    cur.execute(
        "SELECT ai.question_id FROM ear_attempt_item ai "
        "JOIN ear_attempt atp ON atp.id=ai.attempt_id "
        "WHERE atp.learner_id=%s AND atp.mode=%s "
        "ORDER BY ai.id DESC LIMIT %s",
        (learner_id, mode, int(limit)),
    )
    return [str(r.get("question_id") or "") for r in (cur.fetchall() or []) if r.get("question_id")]


def _answered_question_ids(cur, attempt_id):
    cur.execute(
        "SELECT question_id FROM ear_attempt_item WHERE attempt_id=%s ORDER BY id ASC",
        (int(attempt_id),),
    )
    return [str(r.get("question_id") or "") for r in (cur.fetchall() or []) if r.get("question_id")]


def _pick_question_row(cur, learner_id, mode):
    recent = _recent_question_ids(cur, learner_id, mode)
    rows = []
    if recent:
        cur.execute(
            "SELECT id, mode, question_type, difficulty, prompt_zh, hint_zh, audio_json, options_json, "
            "chord_symbol, music_key, progression_roman "
            "FROM ear_question WHERE status='active' AND mode=%s AND id NOT IN ("
            + ",".join(["%s"] * len(recent))
            + ")",
            tuple([mode] + recent),
        )
        rows = cur.fetchall() or []
    if not rows:
        cur.execute(
            "SELECT id, mode, question_type, difficulty, prompt_zh, hint_zh, audio_json, options_json, "
            "chord_symbol, music_key, progression_roman "
            "FROM ear_question WHERE status='active' AND mode=%s",
            (mode,),
        )
        rows = cur.fetchall() or []
    if not rows:
        raise ValueError(f"no active ear questions for mode {mode}")
    return random.choice(rows)


def _pick_c_question_row(cur, attempt_id, learner_id, daily_set_id):
    qids = []
    cur.execute(
        "SELECT question_ids_json FROM ear_daily_set WHERE id=%s LIMIT 1",
        (int(daily_set_id),),
    )
    row = cur.fetchone()
    if row:
        raw = row.get("question_ids_json")
        if isinstance(raw, (bytes, bytearray)):
            raw = raw.decode("utf-8")
        arr = json.loads(raw) if isinstance(raw, str) else raw
        if isinstance(arr, list):
            qids = [str(x) for x in arr if str(x)]
    answered = set(_answered_question_ids(cur, attempt_id))
    remain = [x for x in qids if x not in answered]
    if not remain:
        return None
    cur.execute(
        "SELECT id, mode, question_type, difficulty, prompt_zh, hint_zh, audio_json, options_json, "
        "chord_symbol, music_key, progression_roman "
        "FROM ear_question WHERE status='active' AND id=%s LIMIT 1",
        (remain[0],),
    )
    return cur.fetchone()


def _to_public_question(row):
    options = _decode_options(row.get("options_json"))
    sym = row.get("chord_symbol")
    mk = row.get("music_key")
    pr = row.get("progression_roman")
    out = {
        "question_id": row["id"],
        "mode": row.get("mode"),
        "question_type": row.get("question_type"),
        "difficulty": row.get("difficulty"),
        "prompt_zh": row.get("prompt_zh"),
        "hint_zh": row.get("hint_zh"),
        "audio_ref": _decode_json_obj(row.get("audio_json")),
        "options": [{"key": o["key"], "label": o["label"]} for o in options],
    }
    if sym:
        out["chord_symbol"] = str(sym).strip()
    if mk:
        out["music_key"] = str(mk).strip()
    if pr:
        out["progression_roman"] = str(pr).strip()
    return out


def _decode_json_obj(raw):
    if isinstance(raw, (bytes, bytearray)):
        raw = raw.decode("utf-8")
    if isinstance(raw, str):
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        return obj if isinstance(obj, dict) else {}
    return raw if isinstance(raw, dict) else {}


def _build_daily_set_question_ids(cur, learner_id):
    # 6 from mistake book (new/reviewing)
    cur.execute(
        "SELECT question_id FROM ear_mistake_book "
        "WHERE learner_id=%s AND status IN ('new','reviewing') "
        "ORDER BY last_wrong_at DESC, wrong_count DESC LIMIT 6",
        (learner_id,),
    )
    picked = [str(r["question_id"]) for r in (cur.fetchall() or []) if r.get("question_id")]

    # 2 from weak mode
    weak_mode = "A"
    cur.execute(
        "SELECT q.mode AS mode, SUM(ai.is_correct) AS right_count, COUNT(*) AS total_count "
        "FROM ear_attempt_item ai "
        "JOIN ear_attempt atp ON atp.id=ai.attempt_id "
        "JOIN ear_question q ON q.id=ai.question_id "
        "WHERE atp.learner_id=%s AND atp.mode IN ('A','B') "
        "GROUP BY q.mode",
        (learner_id,),
    )
    rows = cur.fetchall() or []
    if rows:
        acc = []
        for r in rows:
            total = int(r.get("total_count") or 0)
            right = int(r.get("right_count") or 0)
            if total > 0:
                acc.append((r.get("mode") or "A", right / total))
        if acc:
            acc.sort(key=lambda x: x[1])
            weak_mode = acc[0][0]
    weak_need = 2
    if weak_need > 0:
        cur.execute(
            "SELECT id FROM ear_question WHERE status='active' AND mode=%s "
            + ("AND id NOT IN (" + ",".join(["%s"] * len(picked)) + ") " if picked else "")
            + "ORDER BY RAND() LIMIT %s",
            tuple(([weak_mode] + picked + [weak_need]) if picked else [weak_mode, weak_need]),
        )
        picked += [str(r["id"]) for r in (cur.fetchall() or []) if r.get("id")]

    # retention random fill
    remain = _DAILY_COUNT - len(picked)
    if remain > 0:
        cur.execute(
            "SELECT id FROM ear_question WHERE status='active' AND mode IN ('A','B') "
            + ("AND id NOT IN (" + ",".join(["%s"] * len(picked)) + ") " if picked else "")
            + "ORDER BY RAND() LIMIT %s",
            tuple((picked + [remain]) if picked else [remain]),
        )
        picked += [str(r["id"]) for r in (cur.fetchall() or []) if r.get("id")]

    return picked[:_DAILY_COUNT]


def generate_or_get_daily_set(learner_id, day_date=None, force_regenerate=False):
    learner_id = (learner_id or "").strip()
    if not learner_id:
        raise ValueError("learner_id required")
    day_s = str(day_date or _today_str())
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, question_ids_json FROM ear_daily_set WHERE learner_id=%s AND day_date=%s LIMIT 1",
                (learner_id, day_s),
            )
            row = cur.fetchone()
            if row and not force_regenerate:
                qids = json.loads(row.get("question_ids_json") or "[]")
                return {"daily_set_id": int(row["id"]), "day_date": day_s, "question_ids": qids}
            qids = _build_daily_set_question_ids(cur, learner_id)
            qids_json = json.dumps(qids, ensure_ascii=False)
            if row:
                cur.execute(
                    "UPDATE ear_daily_set SET question_ids_json=%s, updated_at=CURRENT_TIMESTAMP "
                    "WHERE id=%s",
                    (qids_json, int(row["id"])),
                )
                dsid = int(row["id"])
            else:
                cur.execute(
                    "INSERT INTO ear_daily_set (learner_id, day_date, question_ids_json) VALUES (%s,%s,%s)",
                    (learner_id, day_s, qids_json),
                )
                dsid = int(cur.lastrowid)
        conn.commit()
    return {"daily_set_id": dsid, "day_date": day_s, "question_ids": qids}


def create_ear_attempt(learner_id, mode, *, daily_set_id=None):
    learner_id = (learner_id or "").strip()
    if not learner_id:
        raise ValueError("learner_id required")
    m = _normalize_mode(mode)
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO ear_attempt (learner_id, mode, daily_set_id) VALUES (%s,%s,%s)",
                (learner_id, m, daily_set_id),
            )
            aid = int(cur.lastrowid)
        conn.commit()
    return {"attempt_id": aid, "mode": m}


def get_next_ear_question(attempt_id):
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, learner_id, mode, ended_at, daily_set_id FROM ear_attempt WHERE id=%s LIMIT 1",
                (int(attempt_id),),
            )
            atp = cur.fetchone()
            if not atp:
                raise ValueError("attempt not found")
            if atp.get("ended_at") is not None:
                raise ValueError("attempt already ended")
            mode = atp.get("mode")
            if mode == "C":
                row = _pick_c_question_row(
                    cur, int(atp["id"]), atp["learner_id"], int(atp.get("daily_set_id") or 0)
                )
                if not row:
                    return None
                return _to_public_question(row)
            row = _pick_question_row(cur, atp["learner_id"], mode)
            return _to_public_question(row)


def _update_mistake_book(cur, learner_id, question_id, is_correct):
    cur.execute(
        "SELECT learner_id, question_id, wrong_count, right_streak, status "
        "FROM ear_mistake_book WHERE learner_id=%s AND question_id=%s LIMIT 1",
        (learner_id, question_id),
    )
    row = cur.fetchone()
    now_expr = "CURRENT_TIMESTAMP"
    if not row:
        if is_correct:
            return
        cur.execute(
            "INSERT INTO ear_mistake_book "
            "(learner_id, question_id, wrong_count, right_streak, status, last_wrong_at) "
            "VALUES (%s,%s,1,0,'new'," + now_expr + ")",
            (learner_id, question_id),
        )
        return
    wrong_count = int(row.get("wrong_count") or 0)
    right_streak = int(row.get("right_streak") or 0)
    if is_correct:
        right_streak += 1
        status = "mastered" if right_streak >= 3 else "reviewing"
        cur.execute(
            "UPDATE ear_mistake_book SET right_streak=%s, status=%s, last_right_at="
            + now_expr
            + ", updated_at="
            + now_expr
            + " WHERE learner_id=%s AND question_id=%s",
            (right_streak, status, learner_id, question_id),
        )
    else:
        wrong_count += 1
        status = "reviewing" if wrong_count > 1 else "new"
        cur.execute(
            "UPDATE ear_mistake_book SET wrong_count=%s, right_streak=0, status=%s, last_wrong_at="
            + now_expr
            + ", updated_at="
            + now_expr
            + " WHERE learner_id=%s AND question_id=%s",
            (wrong_count, status, learner_id, question_id),
        )


def answer_ear_question(attempt_id, question_id, selected_option_key):
    skey = str(selected_option_key or "").strip().upper()
    if skey not in ("A", "B", "C", "D"):
        raise ValueError("selected_option_key invalid")
    qid = str(question_id or "").strip()
    if not qid:
        raise ValueError("question_id required")
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, learner_id, ended_at FROM ear_attempt WHERE id=%s LIMIT 1",
                (int(attempt_id),),
            )
            atp = cur.fetchone()
            if not atp:
                raise ValueError("attempt not found")
            if atp.get("ended_at") is not None:
                raise ValueError("attempt already ended")
            cur.execute(
                "SELECT id, mode, question_type, prompt_zh, hint_zh, correct_option_key, options_json, "
                "chord_symbol, music_key, progression_roman "
                "FROM ear_question WHERE id=%s LIMIT 1",
                (qid,),
            )
            qrow = cur.fetchone()
            if not qrow:
                raise ValueError("question not found")
            correct_key = str(qrow.get("correct_option_key") or "").strip().upper()
            is_correct = 1 if skey == correct_key else 0
            options = _decode_options(qrow.get("options_json"))
            key_map = {o["key"]: o for o in options}
            correct_label = key_map.get(correct_key, {}).get("label", "")

            cur.execute(
                "INSERT INTO ear_attempt_item (attempt_id, question_id, selected_option_key, is_correct) "
                "VALUES (%s,%s,%s,%s)",
                (int(attempt_id), qid, skey, is_correct),
            )
            cur.execute(
                "UPDATE ear_attempt SET total_answered=total_answered+1, "
                "total_correct=total_correct+%s, updated_at=CURRENT_TIMESTAMP WHERE id=%s",
                (is_correct, int(attempt_id)),
            )
            _update_mistake_book(cur, atp["learner_id"], qid, bool(is_correct))
        conn.commit()
    sym = qrow.get("chord_symbol")
    mk = qrow.get("music_key")
    pr = qrow.get("progression_roman")
    out = {
        "question_id": qid,
        "is_correct": bool(is_correct),
        "correct_option_key": correct_key,
        "correct_option_label": correct_label,
        "prompt_zh": qrow.get("prompt_zh"),
        "hint_zh": qrow.get("hint_zh"),
        "mode": qrow.get("mode"),
        "question_type": qrow.get("question_type"),
    }
    if sym:
        out["chord_symbol"] = str(sym).strip()
    if mk:
        out["music_key"] = str(mk).strip()
    if pr:
        out["progression_roman"] = str(pr).strip()
    return out


def finish_ear_attempt(attempt_id):
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE ear_attempt SET ended_at=IFNULL(ended_at,CURRENT_TIMESTAMP), "
                "updated_at=CURRENT_TIMESTAMP WHERE id=%s",
                (int(attempt_id),),
            )
            cur.execute(
                "SELECT id, learner_id, mode, started_at, ended_at, total_answered, total_correct "
                "FROM ear_attempt WHERE id=%s LIMIT 1",
                (int(attempt_id),),
            )
            atp = cur.fetchone()
            if not atp:
                raise ValueError("attempt not found")
            cur.execute(
                "SELECT q.mode AS mode, SUM(ai.is_correct) AS right_count, COUNT(*) AS total_count "
                "FROM ear_attempt_item ai JOIN ear_question q ON q.id=ai.question_id "
                "WHERE ai.attempt_id=%s GROUP BY q.mode ORDER BY q.mode ASC",
                (int(attempt_id),),
            )
            rows = cur.fetchall() or []
            cur.execute(
                "SELECT q.prompt_zh, q.question_type, q.correct_option_key, q.options_json "
                "FROM ear_attempt_item ai JOIN ear_question q ON q.id=ai.question_id "
                "WHERE ai.attempt_id=%s AND ai.is_correct=0 ORDER BY ai.id DESC LIMIT 30",
                (int(attempt_id),),
            )
            wrong_rows = cur.fetchall() or []
        conn.commit()
    by_mode = []
    for r in rows:
        total = int(r.get("total_count") or 0)
        right = int(r.get("right_count") or 0)
        by_mode.append(
            {
                "mode": r.get("mode") or "",
                "right_count": right,
                "total_count": total,
                "accuracy": (right / total) if total else 0.0,
            }
        )
    wrongs = []
    for r in wrong_rows:
        options = _decode_options(r.get("options_json"))
        key_map = {o["key"]: o for o in options}
        ckey = r.get("correct_option_key")
        wrongs.append(
            {
                "prompt_zh": r.get("prompt_zh") or "",
                "question_type": r.get("question_type") or "",
                "correct_option_key": ckey,
                "correct_option_label": key_map.get(ckey, {}).get("label", ""),
            }
        )
    total_answered = int(atp.get("total_answered") or 0)
    total_correct = int(atp.get("total_correct") or 0)
    return {
        "attempt_id": int(atp["id"]),
        "learner_id": atp["learner_id"],
        "mode": atp["mode"],
        "started_at": _to_timestr(atp.get("started_at")),
        "ended_at": _to_timestr(atp.get("ended_at")),
        "total_answered": total_answered,
        "total_correct": total_correct,
        "accuracy": (total_correct / total_answered) if total_answered else 0.0,
        "by_mode_stats": by_mode,
        "wrongs": wrongs,
    }


def get_ear_mistakes(learner_id, limit=50):
    learner_id = (learner_id or "").strip()
    if not learner_id:
        raise ValueError("learner_id required")
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT mb.question_id, mb.wrong_count, mb.right_streak, mb.status, mb.last_wrong_at, "
                "q.mode, q.question_type, q.prompt_zh "
                "FROM ear_mistake_book mb "
                "JOIN ear_question q ON q.id=mb.question_id "
                "WHERE mb.learner_id=%s ORDER BY mb.updated_at DESC LIMIT %s",
                (learner_id, int(limit)),
            )
            rows = cur.fetchall() or []
    out = []
    for r in rows:
        out.append(
            {
                "question_id": r.get("question_id"),
                "mode": r.get("mode"),
                "question_type": r.get("question_type"),
                "prompt_zh": r.get("prompt_zh"),
                "wrong_count": int(r.get("wrong_count") or 0),
                "right_streak": int(r.get("right_streak") or 0),
                "status": r.get("status"),
                "last_wrong_at": _to_timestr(r.get("last_wrong_at")),
            }
        )
    return out


def ear_health_counts():
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS c FROM ear_question WHERE status='active'")
            total = int((cur.fetchone() or {}).get("c") or 0)
            cur.execute(
                "SELECT mode, COUNT(*) AS c FROM ear_question WHERE status='active' GROUP BY mode"
            )
            rows = cur.fetchall() or []
    by_mode = {"A": 0, "B": 0, "C": 0}
    for r in rows:
        m = str(r.get("mode") or "")
        if m in by_mode:
            by_mode[m] = int(r.get("c") or 0)
    return {"active_total": total, "by_mode": by_mode}


def _to_timestr(v):
    if hasattr(v, "isoformat"):
        return v.isoformat(sep=" ", timespec="seconds")
    if isinstance(v, datetime):
        return v.isoformat(sep=" ", timespec="seconds")
    return str(v) if v is not None else None

