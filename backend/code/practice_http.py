# -*- coding: utf-8 -*-
"""练习记录 HTTP：上报与列表（Bearer JWT）。"""
import json
import logging

from auth_db import apple_auth_mysql_enabled
from practice_db import list_sessions_for_user, upsert_session, validate_session_payload
from sheets_http import _bearer_user_id

LOGGER = logging.getLogger("guitar_ai_backend.practice")


def _read_json_body(event):
    raw = event.get("body", "")
    if not raw:
        return {}
    if event.get("isBase64Encoded"):
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def handle_practice_routes(event, _response):
    """若匹配练习路由则返回 handler 响应 dict，否则 None。"""
    method = (event.get("httpMethod") or "GET").upper()
    path = (event.get("path") or "/").strip() or "/"
    path_norm = path.rstrip("/") or "/"

    if method == "GET" and path_norm in ("/practice/sessions", "/api/practice/sessions"):
        uid, err = _bearer_user_id(event)
        if err:
            code, payload = err
            return _response(code, payload)
        if not apple_auth_mysql_enabled():
            return _response(503, {"error": "mysql_not_configured"})
        q = event.get("queryStringParameters") or {}
        limit_raw = q.get("limit") or "200"
        try:
            limit = int(str(limit_raw).strip() or "200")
        except ValueError:
            return _response(400, {"error": "invalid_limit"})
        try:
            sessions = list_sessions_for_user(uid, limit=limit)
            return _response(200, {"sessions": sessions})
        except Exception as e:
            LOGGER.exception("practice list")
            return _response(500, {"error": "practice_list_failed", "detail": str(e)})

    if method == "POST" and path_norm in ("/practice/sessions", "/api/practice/sessions"):
        uid, err = _bearer_user_id(event)
        if err:
            code, payload = err
            return _response(code, payload)
        if not apple_auth_mysql_enabled():
            return _response(503, {"error": "mysql_not_configured"})
        body = _read_json_body(event)
        if not isinstance(body, dict) or not body:
            return _response(400, {"error": "invalid_json"})
        try:
            row = validate_session_payload(body)
            upsert_session(uid, row)
            return _response(200, {"ok": True})
        except ValueError as e:
            return _response(400, {"error": "validation_error", "detail": str(e)})
        except Exception as e:
            LOGGER.exception("practice upsert")
            return _response(500, {"error": "practice_save_failed", "detail": str(e)})

    return None
