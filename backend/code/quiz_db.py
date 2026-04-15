# -*- coding: utf-8 -*-
import json
import os
import random
from contextlib import contextmanager
from pathlib import Path

import pymysql
from pymysql.cursors import DictCursor

DIFFICULTY_IDS = ("beginner", "intermediate", "advanced")
_SCHEMA_CHECKED = False
_REQUIRED_TABLES = ("quiz_question", "quiz_attempt", "quiz_attempt_answer")
_DDL_HINT_PATH = "backend/database/ddl/quiz_training_tables.sql"
_RECENT_QUESTION_WINDOW = 15


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


def quiz_mysql_enabled():
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


def ensure_quiz_schema():
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
            existed = {
                str(r.get("table_name") or r.get("TABLE_NAME") or "")
                for r in (cur.fetchall() or [])
            }
    missing = [name for name in _REQUIRED_TABLES if name not in existed]
    if missing:
        missing_text = ", ".join(missing)
        raise RuntimeError(
            f"quiz schema missing tables: {missing_text}. "
            f"Please execute {_DDL_HINT_PATH} once during upgrade/deployment."
        )
    _SCHEMA_CHECKED = True


def _normalize_difficulty(difficulty):
    d = (difficulty or "").strip().lower()
    return d if d in DIFFICULTY_IDS else "beginner"


def _normalize_option(opt):
    if not isinstance(opt, dict):
        return None
    key = str(opt.get("key") or "").strip().upper()
    fingering = str(opt.get("fingering") or "").strip()
    is_correct = bool(opt.get("is_correct"))
    if key not in ("A", "B", "C", "D") or not fingering:
        return None
    return {"key": key, "fingering": fingering, "is_correct": is_correct}


def _validate_seed_question(q):
    if not isinstance(q, dict):
        return None
    qid = str(q.get("id") or "").strip()
    difficulty = _normalize_difficulty(q.get("difficulty"))
    chord_symbol = str(q.get("chord_symbol") or "").strip()
    chord_quality = str(q.get("chord_quality") or "").strip()
    correct_option_key = str(q.get("correct_option_key") or "").strip().upper()
    opts = q.get("options")
    if (
        not qid
        or not chord_symbol
        or not chord_quality
        or correct_option_key not in ("A", "B", "C", "D")
        or not isinstance(opts, list)
        or len(opts) != 4
    ):
        return None
    options = []
    seen_keys = set()
    correct_count = 0
    for opt in opts:
        n = _normalize_option(opt)
        if not n:
            return None
        if n["key"] in seen_keys:
            return None
        seen_keys.add(n["key"])
        if n["is_correct"]:
            correct_count += 1
        options.append(n)
    if seen_keys != {"A", "B", "C", "D"}:
        return None
    if correct_count != 1:
        return None
    key_to_option = {o["key"]: o for o in options}
    if not key_to_option.get(correct_option_key, {}).get("is_correct"):
        return None
    return {
        "id": qid,
        "difficulty": difficulty,
        "chord_symbol": chord_symbol,
        "chord_quality": chord_quality,
        "correct_option_key": correct_option_key,
        "options": options,
    }


def import_quiz_seed(seed_file_path, *, version=None, status="active"):
    p = Path(seed_file_path)
    if not p.exists():
        raise FileNotFoundError(f"seed not found: {seed_file_path}")
    raw = json.loads(p.read_text(encoding="utf-8"))
    questions = raw.get("questions")
    if not isinstance(questions, list) or not questions:
        raise ValueError("seed questions missing")
    seed_version = str(version or raw.get("version") or "quiz_seed")
    saved = 0
    with _connection() as conn:
        with conn.cursor() as cur:
            for item in questions:
                q = _validate_seed_question(item)
                if not q:
                    continue
                cur.execute(
                    "INSERT INTO quiz_question "
                    "(id, difficulty, chord_symbol, chord_quality, correct_option_key, options_json, status, version) "
                    "VALUES (%s,%s,%s,%s,%s,%s,%s,%s) "
                    "ON DUPLICATE KEY UPDATE "
                    "difficulty=VALUES(difficulty), chord_symbol=VALUES(chord_symbol), "
                    "chord_quality=VALUES(chord_quality), correct_option_key=VALUES(correct_option_key), "
                    "options_json=VALUES(options_json), status=VALUES(status), version=VALUES(version), "
                    "updated_at=CURRENT_TIMESTAMP",
                    (
                        q["id"],
                        q["difficulty"],
                        q["chord_symbol"],
                        q["chord_quality"],
                        q["correct_option_key"],
                        json.dumps(q["options"], ensure_ascii=False),
                        status,
                        seed_version,
                    ),
                )
                saved += 1
        conn.commit()
    return {"saved": saved, "version": seed_version}


def create_attempt(learner_id, difficulty, wrong_only=False):
    learner_id = (learner_id or "").strip()
    if not learner_id:
        raise ValueError("learner_id required")
    d = _normalize_difficulty(difficulty)
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO quiz_attempt (learner_id, difficulty, wrong_only) VALUES (%s, %s, %s)",
                (learner_id, d, 1 if wrong_only else 0),
            )
            aid = int(cur.lastrowid)
        conn.commit()
    return {"attempt_id": aid, "difficulty": d, "wrong_only": bool(wrong_only)}


def get_attempt(attempt_id):
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, learner_id, difficulty, wrong_only, started_at, ended_at, total_answered, total_correct "
                "FROM quiz_attempt WHERE id=%s LIMIT 1",
                (int(attempt_id),),
            )
            return cur.fetchone()


def _recent_chord_symbols(cur, learner_id, difficulty, limit=_RECENT_QUESTION_WINDOW):
    cur.execute(
        "SELECT qq.chord_symbol "
        "FROM quiz_attempt_answer qa "
        "JOIN quiz_attempt atp ON atp.id = qa.attempt_id "
        "JOIN quiz_question qq ON qq.id = qa.question_id "
        "WHERE atp.learner_id=%s AND atp.difficulty=%s "
        "ORDER BY qa.answered_at DESC, qa.id DESC "
        "LIMIT %s",
        (learner_id, difficulty, int(limit)),
    )
    rows = cur.fetchall() or []
    out = []
    for r in rows:
        sym = str(r.get("chord_symbol") or "").strip()
        if sym and sym not in out:
            out.append(sym)
    return out


def _wrong_question_ids(cur, learner_id, difficulty, limit=300):
    cur.execute(
        "SELECT DISTINCT qa.question_id "
        "FROM quiz_attempt_answer qa "
        "JOIN quiz_attempt atp ON atp.id = qa.attempt_id "
        "JOIN quiz_question qq ON qq.id = qa.question_id "
        "WHERE atp.learner_id=%s AND atp.difficulty=%s AND qa.is_correct=0 AND qq.status='active' "
        "ORDER BY qa.question_id ASC LIMIT %s",
        (learner_id, difficulty, int(limit)),
    )
    return [str(r["question_id"]) for r in (cur.fetchall() or []) if r.get("question_id")]


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
            n["is_correct"] = bool(n["is_correct"])
            out.append(n)
    out.sort(key=lambda x: x["key"])
    return out


def get_next_question(attempt_id):
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, learner_id, difficulty, wrong_only, ended_at FROM quiz_attempt WHERE id=%s LIMIT 1",
                (int(attempt_id),),
            )
            attempt = cur.fetchone()
            if not attempt:
                raise ValueError("attempt not found")
            if attempt.get("ended_at") is not None:
                raise ValueError("attempt already ended")
            learner_id = attempt["learner_id"]
            difficulty = attempt["difficulty"]
            wrong_only = bool(attempt.get("wrong_only"))

            recent = _recent_chord_symbols(cur, learner_id, difficulty, limit=_RECENT_QUESTION_WINDOW)
            wrong_ids = _wrong_question_ids(cur, learner_id, difficulty) if wrong_only else []

            rows = []
            if wrong_only and wrong_ids:
                placeholders = ",".join(["%s"] * len(wrong_ids))
                not_in_recent = ""
                params = [difficulty] + wrong_ids
                if recent:
                    not_in_recent = " AND chord_symbol NOT IN (" + ",".join(["%s"] * len(recent)) + ")"
                    params += recent
                sql = (
                    "SELECT id, chord_symbol, chord_quality, options_json "
                    "FROM quiz_question WHERE status='active' AND difficulty=%s "
                    f"AND id IN ({placeholders}) {not_in_recent}"
                )
                cur.execute(sql, tuple(params))
                rows = cur.fetchall() or []
                if not rows and recent:
                    cur.execute(
                        "SELECT id, chord_symbol, chord_quality, options_json "
                        "FROM quiz_question WHERE status='active' AND difficulty=%s "
                        f"AND id IN ({placeholders})",
                        tuple([difficulty] + wrong_ids),
                    )
                    rows = cur.fetchall() or []
            elif not wrong_only:
                if recent:
                    cur.execute(
                        "SELECT id, chord_symbol, chord_quality, options_json "
                        "FROM quiz_question WHERE status='active' AND difficulty=%s "
                        "AND chord_symbol NOT IN (" + ",".join(["%s"] * len(recent)) + ")",
                        tuple([difficulty] + recent),
                    )
                    rows = cur.fetchall() or []
                if not rows:
                    cur.execute(
                        "SELECT id, chord_symbol, chord_quality, options_json "
                        "FROM quiz_question WHERE status='active' AND difficulty=%s",
                        (difficulty,),
                    )
                    rows = cur.fetchall() or []
            # wrong_only but no wrong history fallback
            if wrong_only and not rows:
                if recent:
                    cur.execute(
                        "SELECT id, chord_symbol, chord_quality, options_json "
                        "FROM quiz_question WHERE status='active' AND difficulty=%s "
                        "AND chord_symbol NOT IN (" + ",".join(["%s"] * len(recent)) + ")",
                        tuple([difficulty] + recent),
                    )
                    rows = cur.fetchall() or []
                if not rows:
                    cur.execute(
                        "SELECT id, chord_symbol, chord_quality, options_json "
                        "FROM quiz_question WHERE status='active' AND difficulty=%s",
                        (difficulty,),
                    )
                    rows = cur.fetchall() or []
            if not rows:
                raise ValueError("no active questions")
            row = random.choice(rows)
            options = _decode_options(row.get("options_json"))
            # do not leak correctness in question payload
            safe_options = [{"key": o["key"], "fingering": o["fingering"]} for o in options]
            return {
                "question_id": row["id"],
                "chord_symbol": row["chord_symbol"],
                "chord_quality": row["chord_quality"],
                "options": safe_options,
                "recent_rule_window": _RECENT_QUESTION_WINDOW,
                "wrong_only": wrong_only,
            }


def answer_question(attempt_id, question_id, selected_option_key):
    skey = str(selected_option_key or "").strip().upper()
    if skey not in ("A", "B", "C", "D"):
        raise ValueError("selected_option_key invalid")
    qid = str(question_id or "").strip()
    if not qid:
        raise ValueError("question_id required")
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, ended_at FROM quiz_attempt WHERE id=%s LIMIT 1",
                (int(attempt_id),),
            )
            attempt = cur.fetchone()
            if not attempt:
                raise ValueError("attempt not found")
            if attempt.get("ended_at") is not None:
                raise ValueError("attempt already ended")

            cur.execute(
                "SELECT chord_symbol, chord_quality, correct_option_key, options_json FROM quiz_question WHERE id=%s LIMIT 1",
                (qid,),
            )
            qrow = cur.fetchone()
            if not qrow:
                raise ValueError("question not found")
            correct_key = str(qrow.get("correct_option_key") or "").strip().upper()
            is_correct = 1 if skey == correct_key else 0
            options = _decode_options(qrow.get("options_json"))
            key_map = {o["key"]: o for o in options}
            correct_fingering = key_map.get(correct_key, {}).get("fingering", "")

            cur.execute(
                "INSERT INTO quiz_attempt_answer (attempt_id, question_id, selected_option_key, is_correct) "
                "VALUES (%s, %s, %s, %s)",
                (int(attempt_id), qid, skey, is_correct),
            )
            cur.execute(
                "UPDATE quiz_attempt SET total_answered = total_answered + 1, "
                "total_correct = total_correct + %s, updated_at=CURRENT_TIMESTAMP "
                "WHERE id=%s",
                (is_correct, int(attempt_id)),
            )
        conn.commit()
    return {
        "question_id": qid,
        "is_correct": bool(is_correct),
        "correct_option_key": correct_key,
        "correct_fingering": correct_fingering,
        "chord_symbol": qrow["chord_symbol"],
        "chord_quality": qrow["chord_quality"],
    }


def finish_attempt(attempt_id):
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE quiz_attempt SET ended_at=IFNULL(ended_at, CURRENT_TIMESTAMP), updated_at=CURRENT_TIMESTAMP "
                "WHERE id=%s",
                (int(attempt_id),),
            )
            cur.execute(
                "SELECT id, learner_id, difficulty, started_at, ended_at, total_answered, total_correct "
                "FROM quiz_attempt WHERE id=%s LIMIT 1",
                (int(attempt_id),),
            )
            attempt = cur.fetchone()
            if not attempt:
                raise ValueError("attempt not found")
            cur.execute(
                "SELECT qq.chord_quality AS chord_quality, SUM(qa.is_correct) AS right_count, COUNT(*) AS total_count "
                "FROM quiz_attempt_answer qa "
                "JOIN quiz_question qq ON qq.id = qa.question_id "
                "WHERE qa.attempt_id=%s "
                "GROUP BY qq.chord_quality ORDER BY qq.chord_quality ASC",
                (int(attempt_id),),
            )
            quality_rows = cur.fetchall() or []
            cur.execute(
                "SELECT qq.chord_symbol, qq.chord_quality, qq.correct_option_key, qq.options_json "
                "FROM quiz_attempt_answer qa "
                "JOIN quiz_question qq ON qq.id = qa.question_id "
                "WHERE qa.attempt_id=%s AND qa.is_correct=0 "
                "ORDER BY qa.id DESC LIMIT 30",
                (int(attempt_id),),
            )
            wrong_rows = cur.fetchall() or []
        conn.commit()
    quality_stats = []
    for row in quality_rows:
        total = int(row.get("total_count") or 0)
        right = int(row.get("right_count") or 0)
        quality_stats.append(
            {
                "chord_quality": row.get("chord_quality") or "",
                "right_count": right,
                "total_count": total,
                "accuracy": (right / total) if total else 0.0,
            }
        )
    wrongs = []
    for row in wrong_rows:
        options = _decode_options(row.get("options_json"))
        key_map = {o["key"]: o for o in options}
        correct_key = row.get("correct_option_key")
        wrongs.append(
            {
                "chord_symbol": row.get("chord_symbol") or "",
                "chord_quality": row.get("chord_quality") or "",
                "correct_option_key": correct_key,
                "correct_fingering": key_map.get(correct_key, {}).get("fingering", ""),
            }
        )
    total_answered = int(attempt.get("total_answered") or 0)
    total_correct = int(attempt.get("total_correct") or 0)
    accuracy = (total_correct / total_answered) if total_answered else 0.0
    return {
        "attempt_id": int(attempt["id"]),
        "learner_id": attempt["learner_id"],
        "difficulty": attempt["difficulty"],
        "started_at": _to_timestr(attempt.get("started_at")),
        "ended_at": _to_timestr(attempt.get("ended_at")),
        "total_answered": total_answered,
        "total_correct": total_correct,
        "accuracy": accuracy,
        "quality_stats": quality_stats,
        "wrongs": wrongs,
    }


def quiz_health_counts():
    with _connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS c FROM quiz_question WHERE status='active'")
            total = int((cur.fetchone() or {}).get("c") or 0)
            cur.execute(
                "SELECT difficulty, COUNT(*) AS c FROM quiz_question WHERE status='active' GROUP BY difficulty"
            )
            rows = cur.fetchall() or []
    by_diff = {"beginner": 0, "intermediate": 0, "advanced": 0}
    for r in rows:
        d = str(r.get("difficulty") or "")
        if d in by_diff:
            by_diff[d] = int(r.get("c") or 0)
    return {"active_total": total, "by_difficulty": by_diff}


def _to_timestr(v):
    if hasattr(v, "isoformat"):
        return v.isoformat(sep=" ", timespec="seconds")
    return str(v) if v is not None else None
