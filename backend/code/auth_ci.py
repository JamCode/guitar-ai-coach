# -*- coding: utf-8 -*-
"""CI 专用登录：签发测试用户 JWT（默认关闭，需共享密钥）。"""
import hmac
import os
import re

from auth_db import apple_auth_mysql_enabled, upsert_user_by_apple_sub
from auth_jwt import issue_access_token


def _truthy_env(name):
    return str(os.getenv(name, "")).strip().lower() in ("1", "true", "yes", "on")


def _ci_enabled():
    return _truthy_env("CI_AUTH_ENABLED")


def _ci_secret():
    return (os.getenv("CI_AUTH_SECRET") or "").strip()


def _sanitize_ci_user_key(raw):
    key = str(raw or "").strip().lower()
    if not key:
        return "default"
    key = re.sub(r"[^a-z0-9._-]+", "-", key)
    key = re.sub(r"-{2,}", "-", key).strip("-.")
    if not key:
        return "default"
    return key[:64]


def handle_auth_ci_login_post(body):
    """处理 `POST /auth/ci-login`，返回 (status_code, payload)。"""
    if not _ci_enabled():
        return (404, {"error": "not_found"})
    if not isinstance(body, dict):
        return (400, {"error": "invalid_json", "detail": "请求体须为 JSON 对象"})

    secret = _ci_secret()
    if not secret:
        return (503, {"error": "ci_auth_not_configured", "detail": "missing CI_AUTH_SECRET"})

    provided = str(body.get("ci_secret") or "").strip()
    if not provided:
        return (401, {"error": "missing_ci_secret"})
    if not hmac.compare_digest(provided, secret):
        return (401, {"error": "invalid_ci_secret"})

    if not apple_auth_mysql_enabled():
        return (503, {"error": "mysql_not_configured"})

    ci_user_key = _sanitize_ci_user_key(body.get("ci_user_key"))
    apple_sub = f"ci.test.{ci_user_key}"
    try:
        user_id = upsert_user_by_apple_sub(apple_sub)
        access = issue_access_token(user_id=user_id, apple_sub=apple_sub, ttl_seconds=3600)
    except ValueError as e:
        return (400, {"error": "bad_request", "detail": str(e)})
    except RuntimeError as e:
        return (503, {"error": "user_persist_failed", "detail": str(e)})

    return (
        200,
        {
            "access_token": access,
            "token_type": "Bearer",
            "expires_in": 3600,
            "ci_user_key": ci_user_key,
        },
    )
