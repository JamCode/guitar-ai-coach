# -*- coding: utf-8 -*-
"""Apple 登录用户表：依赖 MySQL，与 [mysql_crud_sample] 相同连接配置。"""
import os

import pymysql
from pymysql.cursors import DictCursor

from mysql_crud_sample import get_connection

_SCHEMA_OK = False

_APPLE_USERS_TABLE = "apple_users"


def apple_auth_mysql_enabled():
    host = (os.getenv("MYSQL_HOST") or "").strip()
    user = (os.getenv("MYSQL_USER") or "").strip()
    db = (os.getenv("MYSQL_DATABASE") or "").strip()
    return bool(host and user and db)


def ensure_apple_auth_schema():
    """确认 [apple_users] 已由 Flyway 创建；未创建则抛错提示执行迁移。"""
    global _SCHEMA_OK
    if _SCHEMA_OK:
        return
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT table_name FROM information_schema.tables "
                "WHERE table_schema = DATABASE() AND table_name = %s",
                (_APPLE_USERS_TABLE,),
            )
            row = cur.fetchone() or {}
            if str(row.get("table_name") or "") != _APPLE_USERS_TABLE:
                raise RuntimeError(
                    "missing table apple_users. Apply Flyway migration "
                    "backend/database/flyway/sql/V2__add_apple_users.sql "
                    "via `flyway migrate`."
                )
    _SCHEMA_OK = True


def upsert_user_by_apple_sub(apple_sub):
    """按 Apple [sub] 插入或更新 [last_login_at]，返回内部 [id]。"""
    apple_sub = str(apple_sub or "").strip()
    if not apple_sub:
        raise ValueError("apple_sub 不能为空")
    ensure_apple_auth_schema()
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO apple_users (apple_sub, last_login_at) VALUES (%s, NOW()) "
                "ON DUPLICATE KEY UPDATE last_login_at = NOW(), updated_at = NOW()",
                (apple_sub,),
            )
            conn.commit()
            cur.execute(
                "SELECT id FROM apple_users WHERE apple_sub = %s LIMIT 1",
                (apple_sub,),
            )
            row = cur.fetchone()
            if not row or row.get("id") is None:
                raise RuntimeError("apple_users upsert failed")
            return int(row["id"])
