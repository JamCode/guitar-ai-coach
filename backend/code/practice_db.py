# -*- coding: utf-8 -*-
"""user_practice_sessions 的 MySQL 访问。"""
import re
from datetime import datetime

from mysql_crud_sample import get_connection

_SCHEMA_OK = False
_TABLE = "user_practice_sessions"
_UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)


def ensure_practice_schema():
    """确认 [user_practice_sessions] 已由 Flyway 创建。"""
    global _SCHEMA_OK
    if _SCHEMA_OK:
        return
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT table_name FROM information_schema.tables "
                "WHERE table_schema = DATABASE() AND table_name = %s",
                (_TABLE,),
            )
            row = cur.fetchone() or {}
            if str(row.get("table_name") or "") != _TABLE:
                raise RuntimeError(
                    f"missing table {_TABLE}. Run Flyway migration "
                    "backend/database/flyway/sql/V4__user_practice_sessions.sql"
                )
    _SCHEMA_OK = True


def _parse_dt(value, field_name):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field_name} 须为非空 ISO8601 字符串")
    raw = value.strip()
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(raw)
    except ValueError as e:
        raise ValueError(f"{field_name} 时间格式无效") from e
    if dt.tzinfo is not None:
        dt = dt.replace(tzinfo=None)
    return dt


def _clamp_str(s, max_len, field_name):
    t = str(s).strip() if s is not None else ""
    if not t:
        raise ValueError(f"{field_name} 不能为空")
    if len(t) > max_len:
        raise ValueError(f"{field_name} 过长（最多 {max_len} 字符）")
    return t


def _optional_str(s, max_len, field_name):
    if s is None:
        return None
    if not isinstance(s, str):
        s = str(s)
    t = s.strip()
    if not t:
        return None
    if len(t) > max_len:
        raise ValueError(f"{field_name} 过长（最多 {max_len} 字符）")
    return t


def validate_session_payload(body):
    """校验 App 上报的练习会话 JSON，返回写入数据库用的元组字段 dict。"""
    if not isinstance(body, dict):
        raise ValueError("请求体须为 JSON 对象")

    cid = body.get("id")
    if not isinstance(cid, str) or not _UUID_RE.match(cid.strip()):
        raise ValueError("id 须为合法 UUID 字符串")

    task_id = _clamp_str(body.get("taskId"), 64, "taskId")
    task_name = _clamp_str(body.get("taskName"), 255, "taskName")
    started_at = _parse_dt(body.get("startedAt"), "startedAt")
    ended_at = _parse_dt(body.get("endedAt"), "endedAt")

    ds = body.get("durationSeconds")
    if isinstance(ds, bool) or not isinstance(ds, (int, float)):
        raise ValueError("durationSeconds 须为数字")
    duration_seconds = int(ds)
    if duration_seconds < 0 or duration_seconds > 172800:
        raise ValueError("durationSeconds 超出允许范围")

    completed = body.get("completed")
    if not isinstance(completed, bool):
        raise ValueError("completed 须为布尔值")

    diff = body.get("difficulty")
    if isinstance(diff, bool) or not isinstance(diff, (int, float)):
        raise ValueError("difficulty 须为整数 1～5")
    difficulty = int(diff)
    if difficulty < 1 or difficulty > 5:
        raise ValueError("difficulty 须在 1～5 之间")

    note = _optional_str(body.get("note"), 8000, "note")
    progression_id = _optional_str(body.get("progressionId"), 128, "progressionId")
    music_key = _optional_str(body.get("musicKey"), 32, "musicKey")
    complexity = _optional_str(body.get("complexity"), 64, "complexity")

    if ended_at < started_at:
        raise ValueError("endedAt 不能早于 startedAt")

    return {
        "client_session_id": cid.strip(),
        "task_id": task_id,
        "task_name": task_name,
        "started_at": started_at,
        "ended_at": ended_at,
        "duration_seconds": duration_seconds,
        "completed": completed,
        "difficulty": difficulty,
        "note": note,
        "progression_id": progression_id,
        "music_key": music_key,
        "complexity": complexity,
    }


def upsert_session(user_id, row):
    """插入或更新一条练习记录（按 user_id + client_session_id 幂等）。"""
    ensure_practice_schema()
    uid = int(user_id)
    with get_connection() as conn:
        with conn.cursor() as cur:
            sql = (
                "INSERT INTO user_practice_sessions ("
                "user_id, client_session_id, task_id, task_name, "
                "started_at, ended_at, duration_seconds, completed, difficulty, note, "
                "progression_id, music_key, complexity"
                ") VALUES ("
                "%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s"
                ") ON DUPLICATE KEY UPDATE "
                "task_id=VALUES(task_id), task_name=VALUES(task_name), "
                "started_at=VALUES(started_at), ended_at=VALUES(ended_at), "
                "duration_seconds=VALUES(duration_seconds), completed=VALUES(completed), "
                "difficulty=VALUES(difficulty), note=VALUES(note), "
                "progression_id=VALUES(progression_id), music_key=VALUES(music_key), "
                "complexity=VALUES(complexity)"
            )
            cur.execute(
                sql,
                (
                    uid,
                    row["client_session_id"],
                    row["task_id"],
                    row["task_name"],
                    row["started_at"],
                    row["ended_at"],
                    row["duration_seconds"],
                    1 if row["completed"] else 0,
                    row["difficulty"],
                    row["note"],
                    row["progression_id"],
                    row["music_key"],
                    row["complexity"],
                ),
            )


def list_sessions_for_user(user_id, *, limit=200):
    """按结束时间倒序返回当前用户的练习记录（供 App 列表与统计）。"""
    ensure_practice_schema()
    uid = int(user_id)
    limit = max(1, min(int(limit), 500))
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT client_session_id, task_id, task_name, "
                "started_at, ended_at, duration_seconds, completed, difficulty, note, "
                "progression_id, music_key, complexity "
                "FROM user_practice_sessions WHERE user_id = %s "
                "ORDER BY ended_at DESC LIMIT %s",
                (uid, limit),
            )
            rows = list(cur.fetchall())
    out = []
    for r in rows:
        started = r["started_at"]
        ended = r["ended_at"]
        out.append(
            {
                "id": str(r["client_session_id"]),
                "taskId": str(r["task_id"]),
                "taskName": str(r["task_name"]),
                "startedAt": _format_iso_ms(started),
                "endedAt": _format_iso_ms(ended),
                "durationSeconds": int(r["duration_seconds"] or 0),
                "completed": bool(int(r["completed"] or 0)),
                "difficulty": int(r["difficulty"] or 3),
                "note": r["note"],
                "progressionId": r["progression_id"],
                "musicKey": r["music_key"],
                "complexity": r["complexity"],
            }
        )
    return out


def _format_iso_ms(dt):
    if dt is None:
        return ""
    if isinstance(dt, datetime):
        return dt.isoformat(timespec="milliseconds")
    return str(dt)
