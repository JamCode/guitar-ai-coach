# -*- coding: utf-8 -*-
"""Sign in with Apple：校验 [identity_token]（ES256 + JWKS），落库并签发本站 JWT。"""
import hashlib
import logging
import os
import time
import urllib.error

import jwt
from jwt import PyJWKClient

from auth_db import apple_auth_mysql_enabled, upsert_user_by_apple_sub
from auth_jwt import issue_access_token

LOGGER = logging.getLogger("guitar_ai_backend.auth_apple")

APPLE_ISSUER = "https://appleid.apple.com"
# Apple 官方 JWKS 地址（用于校验 identity_token 的签名）。
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
_JWKS_CLIENT = None
_JWKS_CLIENT_AT = 0.0
_JWKS_TTL = 300.0


def _expected_audience():
    return (os.getenv("APPLE_IOS_AUD") or "com.hanwang.guitarhelper").strip()


def _get_jwks_client():
    """缓存 [PyJWKClient] 实例，减少对 Apple JWKS 的冷启动请求。"""
    global _JWKS_CLIENT, _JWKS_CLIENT_AT
    now = time.monotonic()
    if _JWKS_CLIENT is None or (now - _JWKS_CLIENT_AT) > _JWKS_TTL:
        _JWKS_CLIENT = PyJWKClient(APPLE_JWKS_URL, cache_keys=True)
        _JWKS_CLIENT_AT = now
    return _JWKS_CLIENT


def _verify_apple_identity_token(identity_token, raw_nonce=None):
    """校验 Apple [identity_token]，返回解码后的 claims（dict）。"""
    token = (identity_token or "").strip()
    if not token:
        raise ValueError("identity_token 不能为空")
    jwks = _get_jwks_client()
    signing_key = jwks.get_signing_key_from_jwt(token)
    aud = _expected_audience()
    claims = jwt.decode(
        token,
        signing_key.key,
        algorithms=["ES256"],
        audience=aud,
        issuer=APPLE_ISSUER,
        options={"require": ["exp", "iat", "sub"]},
    )
    if raw_nonce is not None:
        raw = str(raw_nonce).strip()
        if not raw:
            raise ValueError("nonce 不能为空字符串")
        expected = hashlib.sha256(raw.encode("utf-8")).hexdigest()
        got = str(claims.get("nonce") or "")
        if got != expected:
            raise ValueError("nonce 不匹配")
    return claims


def handle_auth_apple_post(body):
    """处理 `POST /auth/apple` 的 JSON 体，返回 (status_code, payload)。

    请求字段：
    - identity_token（必填）：Apple 返回的 identityToken JWT
    - nonce（可选）：原始 nonce；若提供则须与 token 内 nonce（SHA256 十六进制）一致
    """
    if not isinstance(body, dict):
        return (400, {"error": "invalid_json", "detail": "请求体须为 JSON 对象"})

    if not apple_auth_mysql_enabled():
        return (
            503,
            {
                "error": "mysql_not_configured",
                "hint": "设置 MYSQL_HOST、MYSQL_USER、MYSQL_PASSWORD、MYSQL_DATABASE",
            },
        )

    identity_token = body.get("identity_token") or body.get("identityToken")
    if not isinstance(identity_token, str) or not identity_token.strip():
        return (400, {"error": "missing_identity_token"})

    raw_nonce = body.get("nonce")
    if raw_nonce is not None and not isinstance(raw_nonce, str):
        return (400, {"error": "invalid_nonce_type"})

    try:
        claims = _verify_apple_identity_token(
            identity_token,
            raw_nonce=raw_nonce if isinstance(raw_nonce, str) else None,
        )
    except ValueError as e:
        return (401, {"error": "invalid_token", "detail": str(e)})
    except jwt.PyJWTError as e:
        LOGGER.info("Apple JWT verify failed: %s", e)
        return (401, {"error": "invalid_token", "detail": str(e)})
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        LOGGER.warning("JWKS fetch error: %s", e)
        return (503, {"error": "jwks_unavailable", "detail": str(e)})

    apple_sub = str(claims.get("sub") or "").strip()
    if not apple_sub:
        return (401, {"error": "invalid_token", "detail": "missing sub"})

    try:
        user_id = upsert_user_by_apple_sub(apple_sub)
        access = issue_access_token(user_id=user_id, apple_sub=apple_sub)
    except RuntimeError as e:
        LOGGER.exception("auth apple persistence failed")
        return (503, {"error": "user_persist_failed", "detail": str(e)})
    except ValueError as e:
        return (400, {"error": "bad_request", "detail": str(e)})

    ttl = int(os.getenv("AUTH_JWT_TTL_SECONDS", str(7 * 24 * 3600)))
    ttl = max(300, min(ttl, 365 * 24 * 3600))
    return (
        200,
        {
            "access_token": access,
            "token_type": "Bearer",
            "expires_in": ttl,
        },
    )


def handle_auth_health_get():
    """`GET /auth/health`：MySQL 与 apple_users 表是否就绪。返回 (status_code, payload)。"""
    if not apple_auth_mysql_enabled():
        return (503, {"ok": False, "mysql": False, "apple_users": False})
    try:
        from auth_db import ensure_apple_auth_schema

        ensure_apple_auth_schema()
        return (
            200,
            {"ok": True, "mysql": True, "apple_users": True, "aud": _expected_audience()},
        )
    except Exception as e:
        return (
            503,
            {"ok": False, "mysql": True, "apple_users": False, "detail": str(e)},
        )
