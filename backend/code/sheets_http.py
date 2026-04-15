# -*- coding: utf-8 -*-
"""用户曲谱 HTTP：列表、multipart 上传、按页下载（Bearer JWT）、删除。"""
import logging
import os
import re
import uuid

import jwt

from auth_db import apple_auth_mysql_enabled
from auth_jwt import decode_access_token
from sheets_db import (
    delete_sheet_by_public_id,
    get_page_row,
    get_sheet_by_public_id,
    insert_sheet_with_pages,
    list_sheets_for_user,
)
from sheets_storage import (
    absolute_path,
    ext_for_mime,
    relpath_for_page,
    remove_sheet_directory,
    sheets_root_dir,
)

LOGGER = logging.getLogger("guitar_ai_backend.sheets")

_ALLOWED_MIME = frozenset({"image/jpeg", "image/jpg", "image/png", "image/webp"})
_MAX_PAGES = int(os.getenv("SHEETS_MAX_PAGES", "30"))
_MAX_PAGE_BYTES = int(os.getenv("SHEETS_MAX_PAGE_BYTES", str(15 * 1024 * 1024)))


def _bearer_user_id(event):
    """从 [event]headers 解析 Bearer JWT，返回 int user_id；失败返回 (status, payload) 或 None."""
    headers = event.get("headers") or {}
    if not isinstance(headers, dict):
        headers = {}
    auth = ""
    for k, v in headers.items():
        if str(k).lower() == "authorization":
            auth = str(v or "").strip()
            break
    if not auth.lower().startswith("bearer "):
        return None, (401, {"error": "missing_bearer_token"})
    token = auth[7:].strip()
    if not token:
        return None, (401, {"error": "missing_bearer_token"})
    try:
        claims = decode_access_token(token)
        uid = int(str(claims.get("sub") or "0"))
        if uid <= 0:
            raise ValueError("bad sub")
        return uid, None
    except jwt.PyJWTError as e:
        LOGGER.info("sheets auth failed: %s", e)
        return None, (401, {"error": "invalid_token"})
    except (TypeError, ValueError) as e:
        return None, (401, {"error": "invalid_token", "detail": str(e)})


def _parse_multipart(body: bytes, content_type: str):
    """解析 multipart/form-data，返回 (display_name, [(filename, mime, bytes), ...])。"""
    if not content_type or "multipart/form-data" not in content_type.lower():
        raise ValueError("需要 multipart/form-data")
    m = re.search(r"boundary=([^;\s]+)", content_type, re.I)
    if not m:
        raise ValueError("缺少 boundary")
    boundary = m.group(1).strip().strip('"')
    bdelim = b"--" + boundary.encode("ascii")
    display_name = ""
    files = []
    segments = body.split(bdelim)
    for seg in segments:
        seg = seg.strip()
        if not seg or seg == b"--":
            continue
        if seg.startswith(b"\r\n"):
            seg = seg[2:]
        elif seg.startswith(b"\n"):
            seg = seg[1:]
        header_end = seg.find(b"\r\n\r\n")
        if header_end < 0:
            header_end = seg.find(b"\n\n")
            if header_end < 0:
                continue
            headers_blob = seg[:header_end].decode("latin-1", errors="replace")
            payload = seg[header_end + 2 :]
        else:
            headers_blob = seg[:header_end].decode("latin-1", errors="replace")
            payload = seg[header_end + 4 :]
        if payload.endswith(b"\r\n"):
            payload = payload[:-2]
        elif payload.endswith(b"\n"):
            payload = payload[:-1]
        disp = ""
        ctype = "application/octet-stream"
        for line in headers_blob.split("\r\n"):
            if ":" not in line:
                continue
            k, v = line.split(":", 1)
            kl = k.strip().lower()
            vl = v.strip()
            if kl == "content-disposition":
                disp = vl
            elif kl == "content-type":
                ctype = vl.split(";")[0].strip().lower()
        name_m = re.search(r'name="([^"]+)"', disp, re.I)
        if not name_m:
            continue
        field_name = name_m.group(1)
        if field_name == "display_name":
            display_name = payload.decode("utf-8", errors="replace").strip()
            continue
        if field_name != "page":
            continue
        fn_m = re.search(r'filename="([^"]*)"', disp, re.I)
        filename = fn_m.group(1) if fn_m else "page.bin"
        files.append((filename, ctype, payload))
    return display_name, files


def handle_sheets_routes(event, _response, _response_binary):
    """若匹配曲谱路由则返回 dict（JSON）或 bytes 响应包；否则返回 None。

    @param _response: (status, dict) -> handler 用的 response dict
    @param _response_binary: (status, bytes, content_type) -> 二进制响应
    """
    method = (event.get("httpMethod") or "GET").upper()
    path = (event.get("path") or "/").strip() or "/"
    path_norm = path.rstrip("/") or "/"

    if method == "GET" and path_norm in ("/sheets", "/api/sheets"):
        uid, err = _bearer_user_id(event)
        if err:
            code, payload = err
            return _response(code, payload)
        if not apple_auth_mysql_enabled():
            return _response(
                503,
                {"error": "mysql_not_configured"},
            )
        try:
            rows = list_sheets_for_user(uid)
        except Exception as e:
            LOGGER.exception("list_sheets")
            return _response(500, {"error": "list_failed", "detail": str(e)})
        out = []
        for r in rows:
            out.append(
                {
                    "id": r["public_id"],
                    "display_name": r["display_name"],
                    "page_count": int(r["page_count"] or 0),
                    "added_at_ms": int(r["created_at_ms"] or 0),
                }
            )
        return _response(200, {"sheets": out})

    # GET .../sheets/{id}/pages/{n}
    if method == "GET":
        m_page = re.match(
            r"^/(?:api/)?sheets/([0-9a-fA-F-]{36})/pages/(\d+)/?$",
            path,
        )
        if m_page:
            public_id, page_s = m_page.group(1), m_page.group(2)
            page_index = int(page_s)
            uid, err = _bearer_user_id(event)
            if err:
                code, payload = err
                return _response(code, payload)
            if not apple_auth_mysql_enabled():
                return _response(503, {"error": "mysql_not_configured"})
            row = get_sheet_by_public_id(uid, public_id)
            if not row:
                return _response(404, {"error": "not_found"})
            prow = get_page_row(row["id"], page_index)
            if not prow:
                return _response(404, {"error": "page_not_found"})
            try:
                full = absolute_path(prow["storage_relpath"])
            except ValueError:
                return _response(500, {"error": "invalid_storage"})
            mime = str(prow["mime_type"] or "application/octet-stream")
            try:
                with open(full, "rb") as f:
                    data = f.read()
            except OSError as e:
                LOGGER.warning("read sheet page: %s", e)
                return _response(404, {"error": "file_missing"})
            return _response_binary(200, data, mime)

    # POST .../sheets  multipart
    if method == "POST" and path_norm in ("/sheets", "/api/sheets"):
        uid, err = _bearer_user_id(event)
        if err:
            code, payload = err
            return _response(code, payload)
        if not apple_auth_mysql_enabled():
            return _response(503, {"error": "mysql_not_configured"})
        ct = ""
        headers = event.get("headers") or {}
        for k, v in headers.items():
            if str(k).lower() == "content-type":
                ct = str(v or "")
                break
        raw = event.get("bodyRaw")
        if not isinstance(raw, (bytes, bytearray)):
            raw = (event.get("body") or "").encode("utf-8", errors="ignore")
        try:
            display_name, files = _parse_multipart(bytes(raw), ct)
        except ValueError as e:
            return _response(400, {"error": "bad_multipart", "detail": str(e)})
        if not display_name:
            return _response(400, {"error": "missing_display_name"})
        if not files:
            return _response(400, {"error": "no_pages"})
        if len(files) > _MAX_PAGES:
            return _response(400, {"error": "too_many_pages", "max": _MAX_PAGES})
        pages_meta = []
        try:
            sheets_root_dir()
        except RuntimeError as e:
            return _response(503, {"error": "storage_not_configured", "detail": str(e)})
        public_id = str(uuid.uuid4())
        user_id_int = int(uid)
        for i, (_fn, mime, blob) in enumerate(files):
            if mime not in _ALLOWED_MIME and mime != "image/jpg":
                return _response(400, {"error": "unsupported_mime", "mime": mime})
            if len(blob) > _MAX_PAGE_BYTES:
                return _response(
                    400,
                    {"error": "page_too_large", "max_bytes": _MAX_PAGE_BYTES},
                )
            ext = ext_for_mime(mime)
            rel = relpath_for_page(user_id_int, public_id, i, ext)
            full = absolute_path(rel)
            os.makedirs(os.path.dirname(full), mode=0o750, exist_ok=True)
            with open(full, "wb") as outf:
                outf.write(blob)
            pages_meta.append((rel, mime if mime != "image/jpg" else "image/jpeg", len(blob)))
        try:
            insert_sheet_with_pages(user_id_int, display_name, pages_meta, public_id=public_id)
        except Exception as e:
            LOGGER.exception("insert_sheet")
            remove_sheet_directory(user_id_int, public_id)
            return _response(500, {"error": "save_failed", "detail": str(e)})
        return _response(
            200,
            {"id": public_id, "display_name": display_name, "page_count": len(pages_meta)},
        )

    # DELETE .../sheets/{id}
    if method == "DELETE":
        m_del = re.match(r"^/(?:api/)?sheets/([0-9a-fA-F-]{36})/?$", path)
        if m_del:
            rest = m_del.group(1)
            uid, err = _bearer_user_id(event)
            if err:
                code, payload = err
                return _response(code, payload)
            if not apple_auth_mysql_enabled():
                return _response(503, {"error": "mysql_not_configured"})
            deleted = delete_sheet_by_public_id(uid, rest)
            if not deleted:
                return _response(404, {"error": "not_found"})
            _unused_internal_id, pid = deleted
            remove_sheet_directory(uid, pid)
            return _response(200, {"ok": True})

    return None
