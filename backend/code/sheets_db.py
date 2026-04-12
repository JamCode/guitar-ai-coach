# -*- coding: utf-8 -*-
"""user_sheets / user_sheet_pages 的 MySQL 访问。"""
import uuid

from mysql_crud_sample import get_connection

_SCHEMA_OK = False


def ensure_sheets_schema():
    global _SCHEMA_OK
    if _SCHEMA_OK:
        return
    with get_connection() as conn:
        with conn.cursor() as cur:
            for table in ("user_sheets", "user_sheet_pages"):
                cur.execute(
                    "SELECT table_name FROM information_schema.tables "
                    "WHERE table_schema = DATABASE() AND table_name = %s",
                    (table,),
                )
                row = cur.fetchone() or {}
                if str(row.get("table_name") or "") != table:
                    raise RuntimeError(
                        f"missing table {table}. Run Flyway migration "
                        "backend/database/flyway/sql/V3__user_sheets.sql"
                    )
    _SCHEMA_OK = True


def list_sheets_for_user(user_id, *, limit=100):
    ensure_sheets_schema()
    limit = max(1, min(int(limit), 200))
    uid = int(user_id)
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT public_id, display_name, page_count, "
                "UNIX_TIMESTAMP(created_at) * 1000 AS created_at_ms "
                "FROM user_sheets WHERE user_id = %s "
                "ORDER BY updated_at DESC LIMIT %s",
                (uid, limit),
            )
            return list(cur.fetchall())


def get_sheet_by_public_id(user_id, public_id):
    ensure_sheets_schema()
    uid = int(user_id)
    pid = str(public_id).strip()
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, public_id, display_name, page_count, user_id "
                "FROM user_sheets WHERE public_id = %s LIMIT 1",
                (pid,),
            )
            row = cur.fetchone()
            if not row:
                return None
            if int(row["user_id"]) != uid:
                return None
            return row


def get_page_row(sheet_internal_id, page_index):
    ensure_sheets_schema()
    sid = int(sheet_internal_id)
    p = int(page_index)
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT storage_relpath, mime_type FROM user_sheet_pages "
                "WHERE sheet_id = %s AND page_index = %s LIMIT 1",
                (sid, p),
            )
            return cur.fetchone()


def insert_sheet_with_pages(user_id, display_name, pages_meta, public_id=None):
    """[pages_meta]: [(relpath, mime, byte_size), ...] 按页序。

    @param public_id: 若传入须为合法 UUID 字符串，与磁盘目录一致；否则自动生成。
    """
    ensure_sheets_schema()
    if not pages_meta:
        raise ValueError("至少一页")
    uid = int(user_id)
    name = (display_name or "").strip()
    if not name:
        raise ValueError("display_name 不能为空")
    public_id = str(public_id).strip() if public_id else str(uuid.uuid4())
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO user_sheets (user_id, public_id, display_name, page_count) "
                "VALUES (%s, %s, %s, %s)",
                (uid, public_id, name, len(pages_meta)),
            )
            sheet_id = cur.lastrowid
            for i, (relpath, mime, size) in enumerate(pages_meta):
                cur.execute(
                    "INSERT INTO user_sheet_pages "
                    "(sheet_id, page_index, storage_relpath, mime_type, byte_size) "
                    "VALUES (%s, %s, %s, %s, %s)",
                    (sheet_id, i, relpath, mime, int(size)),
                )
            conn.commit()
    return public_id


def delete_sheet_by_public_id(user_id, public_id):
    """返回 (internal_id, public_id) 若删除成功，否则 None。"""
    row = get_sheet_by_public_id(user_id, public_id)
    if not row:
        return None
    internal_id = int(row["id"])
    pid = row["public_id"]
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM user_sheets WHERE id = %s AND user_id = %s", (internal_id, int(user_id)))
            conn.commit()
    return internal_id, pid
