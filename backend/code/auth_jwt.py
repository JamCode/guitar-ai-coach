# -*- coding: utf-8 -*-
"""签发与解析面向 App 的短期访问 JWT（HS256）。"""
import os
import time

import jwt


def _secret():
    s = (os.getenv("AUTH_JWT_SECRET") or "").strip()
    if not s:
        raise RuntimeError("AUTH_JWT_SECRET 未配置：无法签发访问令牌")
    return s


def issue_access_token(*, user_id, apple_sub, ttl_seconds=None):
    """为已认证的 apple_users.id 签发 JWT。

    @param user_id: 内部用户主键
    @param apple_sub: Apple 的 sub，写入自定义声明便于审计
    @param ttl_seconds: 有效期秒数；默认 7 天，可由环境变量 AUTH_JWT_TTL_SECONDS 覆盖
    @returns: 编码后的 JWT 字符串
    """
    ttl = ttl_seconds
    if ttl is None:
        ttl = int(os.getenv("AUTH_JWT_TTL_SECONDS", str(7 * 24 * 3600)))
    ttl = max(300, min(int(ttl), 365 * 24 * 3600))
    now = int(time.time())
    payload = {
        "sub": str(int(user_id)),
        "apple_sub": str(apple_sub or ""),
        "iat": now,
        "exp": now + ttl,
    }
    return jwt.encode(payload, _secret(), algorithm="HS256")


def decode_access_token(token):
    """校验并解析访问 JWT；失败抛出 [jwt.PyJWTError] 子类。"""
    return jwt.decode(
        (token or "").strip(),
        _secret(),
        algorithms=["HS256"],
        options={"require": ["exp", "iat", "sub"]},
    )
