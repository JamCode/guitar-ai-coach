# -*- coding: utf-8 -*-
"""曲谱页文件在同机磁盘上的根目录与路径规则。"""
import os
import re
import shutil

_SAFE_USER_ID = re.compile(r"^\d{1,20}$")
_SAFE_SHEET_PUBLIC_ID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.I,
)


def sheets_root_dir():
    """返回 [SHEETS_STORAGE_ROOT] 绝对路径；未配置则抛错。"""
    root = (os.getenv("SHEETS_STORAGE_ROOT") or "").strip()
    if not root:
        raise RuntimeError(
            "SHEETS_STORAGE_ROOT 未配置：请设置环境变量为可写绝对路径，例如 /var/lib/guitar-helper/sheets"
        )
    return os.path.abspath(os.path.expanduser(root))


def ensure_root_exists():
    """确保根目录存在。"""
    root = sheets_root_dir()
    os.makedirs(root, mode=0o750, exist_ok=True)
    return root


def sheet_dir(user_id, public_sheet_id):
    """某用户某谱在磁盘上的目录（绝对路径）。"""
    uid = str(int(user_id))
    sid = str(public_sheet_id).strip()
    if not _SAFE_USER_ID.match(uid) or not _SAFE_SHEET_PUBLIC_ID.match(sid):
        raise ValueError("invalid user_id or public_sheet_id for path")
    root = ensure_root_exists()
    return os.path.join(root, uid, sid)


def relpath_for_page(user_id, public_sheet_id, page_index, ext):
    """写入 DB 的相对路径（相对 SHEETS_STORAGE_ROOT）。"""
    uid = str(int(user_id))
    sid = str(public_sheet_id).strip()
    ext = (ext or ".bin").strip()
    if not ext.startswith("."):
        ext = "." + ext
    if not _SAFE_USER_ID.match(uid) or not _SAFE_SHEET_PUBLIC_ID.match(sid):
        raise ValueError("invalid path segment")
    return f"{uid}/{sid}/{int(page_index):04d}{ext}"


def absolute_path(relpath):
    """[relpath] 必须为此前生成的相对路径，防止穿越。"""
    root = sheets_root_dir()
    rel = str(relpath or "").strip().replace("\\", "/")
    if ".." in rel or rel.startswith("/"):
        raise ValueError("invalid relpath")
    full = os.path.normpath(os.path.join(root, rel))
    if not full.startswith(os.path.normpath(root) + os.sep):
        raise ValueError("path traversal")
    return full


def remove_sheet_directory(user_id, public_sheet_id):
    """删除整本谱的目录（若存在）。"""
    d = sheet_dir(user_id, public_sheet_id)
    if os.path.isdir(d):
        shutil.rmtree(d, ignore_errors=True)


def ext_for_mime(mime):
    m = (mime or "").strip().lower()
    if m in ("image/jpeg", "image/jpg"):
        return ".jpg"
    if m == "image/png":
        return ".png"
    if m == "image/webp":
        return ".webp"
    return ".bin"
