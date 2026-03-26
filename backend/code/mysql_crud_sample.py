# -*- coding: utf-8 -*-
"""
阿里云 RDS MySQL / PolarDB MySQL 兼容实例的增删改查样例。

连接说明（函数计算 FC）：
- 公网访问：RDS 控制台的「数据安全性 → 白名单」需放行 FC 出口 IP，或先 0.0.0.0/0 做联调（生产请收紧）。
- 同 VPC：优先用 RDS 内网地址，低延迟且不必暴露公网；需在 s.yaml 为函数配置 VPC。

环境变量（与 s.yaml 中 environmentVariables 对应）：
  MYSQL_HOST      实例连接地址（外网或内网）
  MYSQL_PORT      端口，默认 3306
  MYSQL_USER      用户名
  MYSQL_PASSWORD  密码
  MYSQL_DATABASE  数据库名（需事先在 RDS 上创建）
"""
import os
import re
from contextlib import contextmanager

import pymysql
from pymysql.cursors import DictCursor

_DDL = """
CREATE TABLE IF NOT EXISTS demo_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  title VARCHAR(255) NOT NULL,
  content TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
"""


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


@contextmanager
def get_connection():
    cfg = _config()
    if not cfg or not cfg["user"] or not cfg["database"]:
        raise RuntimeError(
            "MySQL 未配置：请设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE"
        )
    conn = pymysql.connect(**cfg)
    try:
        yield conn
    finally:
        conn.close()


def ensure_schema():
    """创建演示表（幂等）。"""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(_DDL)
        conn.commit()


def list_items(limit=50):
    limit = max(1, min(int(limit), 200))
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT id, title, content, created_at, updated_at FROM demo_items "
                f"ORDER BY id DESC LIMIT {int(limit)}"
            )
            return list(cur.fetchall())


def get_item(item_id):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, title, content, created_at, updated_at FROM demo_items WHERE id = %s",
                (int(item_id),),
            )
            return cur.fetchone()


def create_item(title, content=None):
    title = (title or "").strip()
    if not title:
        raise ValueError("title 不能为空")
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO demo_items (title, content) VALUES (%s, %s)",
                (title, content),
            )
            conn.commit()
            return cur.lastrowid


def update_item(item_id, title=None, content=None):
    fields = []
    args = []
    if title is not None:
        fields.append("title = %s")
        args.append(title.strip() if isinstance(title, str) else title)
    if content is not None:
        fields.append("content = %s")
        args.append(content)
    if not fields:
        raise ValueError("至少需要提供 title 或 content 之一")
    args.append(int(item_id))
    sql = "UPDATE demo_items SET " + ", ".join(fields) + " WHERE id = %s"
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            conn.commit()
            return cur.rowcount


def delete_item(item_id):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM demo_items WHERE id = %s", (int(item_id),))
            conn.commit()
            return cur.rowcount


def _serialize_row(row):
    if not row:
        return row
    out = dict(row)
    for k, v in list(out.items()):
        if hasattr(v, "isoformat"):
            out[k] = v.isoformat(sep=" ", timespec="seconds")
    return out


def handle_mysql_http(event, extract_body_fn):
    """
    与 FC HTTP 触发器配合：根据 path + method 执行 CRUD。
    若网关未传 path，可在 POST JSON 中使用 mysql_op: list|get|create|update|delete。
    """
    import json

    cfg = _config()
    if not cfg:
        return {
            "statusCode": 503,
            "payload": {
                "error": "MySQL 未配置",
                "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
            },
        }

    ctx = event.get("requestContext") or {}
    http = ctx.get("http") or {}
    path = (http.get("path") or event.get("path") or "").strip() or "/"
    method = (
        http.get("method") or event.get("httpMethod") or "GET"
    ).upper()

    body = extract_body_fn(event) if callable(extract_body_fn) else {}
    if not isinstance(body, dict):
        body = {}

    # 无 path 时的备用：POST { "mysql_op": "list", ... }
    op = body.get("mysql_op")
    item_id = body.get("id")

    m = re.search(r"/mysql/items/(\d+)/?$", path) or re.search(
        r"/mysql/items/(\d+)$", path
    )
    path_id = int(m.group(1)) if m else None

    try:
        ensure_schema()
    except Exception as e:
        return {
            "statusCode": 500,
            "payload": {"error": "MySQL 连接或建表失败", "detail": str(e)},
        }

    try:
        # GET .../mysql/items — 列表（或 POST {"mysql_op":"list"}，适配未透传 path 的网关）
        if path.rstrip("/").endswith("/mysql/items") and method == "GET":
            rows = list_items()
            return {
                "statusCode": 200,
                "payload": {"items": [_serialize_row(r) for r in rows]},
            }
        if method == "POST" and op == "list":
            rows = list_items()
            return {
                "statusCode": 200,
                "payload": {"items": [_serialize_row(r) for r in rows]},
            }

        # GET .../mysql/items/:id — 单条
        if method == "GET" and path_id is not None:
            row = get_item(path_id)
            if not row:
                return {"statusCode": 404, "payload": {"error": "未找到记录"}}
            return {"statusCode": 200, "payload": {"item": _serialize_row(row)}}

        if op == "get" and method in ("GET", "POST"):
            rid = int(item_id) if item_id is not None else None
            if rid is None:
                return {"statusCode": 400, "payload": {"error": "get 需要 id"}}
            row = get_item(rid)
            if not row:
                return {"statusCode": 404, "payload": {"error": "未找到记录"}}
            return {"statusCode": 200, "payload": {"item": _serialize_row(row)}}

        # POST .../mysql/items — 新建（排除同路径下的 mysql_op 分流）
        _mysql_ops = frozenset(("list", "get", "update", "delete"))
        if method == "POST" and (
            op == "create"
            or (
                path.rstrip("/").endswith("/mysql/items")
                and (op is None or op not in _mysql_ops)
            )
        ):
            title = (body.get("title") or "").strip()
            content = body.get("content")
            new_id = create_item(title, content)
            return {
                "statusCode": 201,
                "payload": {"id": new_id, "message": "已创建"},
            }

        # PUT/PATCH ... 或 POST mysql_op=update
        if method in ("PUT", "PATCH") or op == "update":
            rid = path_id if path_id is not None else int(item_id) if item_id is not None else None
            if rid is None:
                return {"statusCode": 400, "payload": {"error": "更新需要 id"}}
            n = update_item(rid, title=body.get("title"), content=body.get("content"))
            if n == 0:
                return {"statusCode": 404, "payload": {"error": "未找到记录"}}
            return {"statusCode": 200, "payload": {"message": "已更新", "id": rid}}

        # DELETE .../mysql/items/:id
        if method == "DELETE" and path_id is not None:
            n = delete_item(path_id)
            if n == 0:
                return {"statusCode": 404, "payload": {"error": "未找到记录"}}
            return {"statusCode": 200, "payload": {"message": "已删除", "id": path_id}}

        if op == "delete":
            rid = int(item_id) if item_id is not None else None
            if rid is None:
                return {"statusCode": 400, "payload": {"error": "delete 需要 id"}}
            n = delete_item(rid)
            if n == 0:
                return {"statusCode": 404, "payload": {"error": "未找到记录"}}
            return {"statusCode": 200, "payload": {"message": "已删除", "id": rid}}

        return {
            "statusCode": 400,
            "payload": {
                "error": "未知的 MySQL 样例路由",
                "path": path,
                "method": method,
                "hint": {
                    "list": "GET .../mysql/items 或 POST {\"mysql_op\":\"list\"}",
                    "get": "GET .../mysql/items/1 或 POST {\"mysql_op\":\"get\",\"id\":1}",
                    "create": "POST .../mysql/items {\"title\":\"x\",\"content\":\"y\"}",
                    "update": "PUT + body {\"id\":1,\"title\":\"x\"} 或 POST mysql_op=update",
                    "delete": "DELETE .../mysql/items/1 或 POST {\"mysql_op\":\"delete\",\"id\":1}",
                },
            },
        }
    except ValueError as e:
        return {"statusCode": 400, "payload": {"error": str(e)}}
    except Exception as e:
        return {"statusCode": 500, "payload": {"error": "MySQL 操作失败", "detail": str(e)}}


if __name__ == "__main__":
    # 本地：export MYSQL_* 后 python mysql_crud_sample.py
    ensure_schema()
    i = create_item("样例标题", "阿里云 MySQL 测试")
    print("created id=", i)
    print("list=", list_items(5))
