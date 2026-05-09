from __future__ import annotations

import hmac
import os

APP_TOKEN_ENV = "CHORD_ONNX_APP_TOKEN"


def configured_app_token() -> str:
    return os.getenv(APP_TOKEN_ENV, "").strip()


def app_token_matches(actual: str | None, expected: str | None = None) -> bool:
    expected_token = (configured_app_token() if expected is None else expected).strip()
    actual_token = (actual or "").strip()
    if not expected_token or not actual_token:
        return False
    return hmac.compare_digest(actual_token, expected_token)


def app_token_status(actual: str | None = None) -> str:
    if not configured_app_token():
        return "missing_config"
    return "ok" if app_token_matches(actual) else "unauthorized"
