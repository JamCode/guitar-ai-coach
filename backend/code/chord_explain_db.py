# -*- coding: utf-8 -*-
"""
和弦 explain 缓存：MySQL 读写。环境变量与 mysql_crud_sample 一致。
表结构须事先在库中执行 DDL：backend/database/ddl/chord_explain_cache.sql
"""
import json
import os
from contextlib import contextmanager

import pymysql
from pymysql.cursors import DictCursor


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
    }


def mysql_chord_cache_enabled():
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


def fetch_cached_explain(symbol, music_key, level):
    """
    返回 explain 字段对应的 dict，未命中或出错返回 None。
    """
    if not mysql_chord_cache_enabled():
        return None
    try:
        with _connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT explain_json FROM chord_explain_cache "
                    "WHERE symbol = %s AND music_key = %s AND level = %s LIMIT 1",
                    (symbol, music_key, level),
                )
                row = cur.fetchone()
        if not row:
            return None
        raw = row.get("explain_json")
        if raw is None:
            return None
        if isinstance(raw, (dict, list)):
            return raw if isinstance(raw, dict) else None
        if isinstance(raw, (bytes, bytearray)):
            raw = raw.decode("utf-8")
        if isinstance(raw, str):
            return json.loads(raw)
        return None
    except Exception:
        return None


def save_chord_explain(symbol, music_key, level, explain_dict):
    """写入或覆盖缓存（同一 symbol/key/level 时更新）；失败静默。"""
    if not mysql_chord_cache_enabled():
        return
    try:
        payload = json.dumps(explain_dict, ensure_ascii=False)
        with _connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO chord_explain_cache (symbol, music_key, level, explain_json) "
                    "VALUES (%s, %s, %s, %s) "
                    "ON DUPLICATE KEY UPDATE explain_json = VALUES(explain_json), "
                    "updated_at = CURRENT_TIMESTAMP",
                    (symbol, music_key, level, payload),
                )
            conn.commit()
    except Exception:
        pass
