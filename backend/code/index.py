# -*- coding: utf-8 -*-
import json
import os
import urllib.error
import urllib.request

from mysql_crud_sample import handle_mysql_http


DASHSCOPE_ENDPOINT = os.getenv(
    "DASHSCOPE_ENDPOINT",
    "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
)
DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY", "")
DASHSCOPE_MODEL = os.getenv("DASHSCOPE_MODEL", "qwen3.5-plus")
DASHSCOPE_TIMEOUT_SECONDS = int(os.getenv("DASHSCOPE_TIMEOUT_SECONDS", "90"))


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json; charset=utf-8"},
        "isBase64Encoded": False,
        "body": json.dumps(payload, ensure_ascii=False),
    }


def _extract_body(event):
    raw_body = event.get("body", "")
    if not raw_body:
        return {}
    if event.get("isBase64Encoded"):
        return {}
    try:
        return json.loads(raw_body)
    except json.JSONDecodeError:
        return {}


def _normalize_event(event):
    if isinstance(event, (bytes, bytearray)):
        event = event.decode("utf-8", errors="ignore")
    if isinstance(event, str):
        try:
            event = json.loads(event) if event else {}
        except json.JSONDecodeError:
            event = {}
    if not isinstance(event, dict):
        return {}
    return event


def _is_mysql_demo_request(event):
    ctx = event.get("requestContext") or {}
    http = ctx.get("http") or {}
    path = (http.get("path") or event.get("path") or "").strip() or "/"
    if "/mysql/items" in path:
        return True
    body = _extract_body(event)
    if isinstance(body, dict) and body.get("mysql_op"):
        return True
    return False


def _call_dashscope(prompt):
    if "compatible-mode" in DASHSCOPE_ENDPOINT:
        payload = {
            "model": DASHSCOPE_MODEL,
            "messages": [{"role": "user", "content": prompt}],
        }
    else:
        payload = {
            "model": DASHSCOPE_MODEL,
            "input": {"messages": [{"role": "user", "content": prompt}]},
        }
    req = urllib.request.Request(
        DASHSCOPE_ENDPOINT,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {DASHSCOPE_API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=DASHSCOPE_TIMEOUT_SECONDS) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw)


def handler(event, context):
    event = _normalize_event(event)

    if _is_mysql_demo_request(event):
        out = handle_mysql_http(event, _extract_body)
        return _response(out["statusCode"], out["payload"])

    if not DASHSCOPE_API_KEY:
        return _response(
            500,
            {
                "error": "Missing DASHSCOPE_API_KEY",
                "message": "Set DASHSCOPE_API_KEY in serverless environment variables.",
            },
        )

    method = (
        event.get("httpMethod")
        or event.get("requestContext", {}).get("http", {}).get("method")
        or "GET"
    ).upper()
    if method == "GET":
        return _response(
            200,
            {
                "message": "DashScope serverless endpoint is running.",
                "usage": {
                    "method": "POST",
                    "body": {"prompt": "Write a short guitar practice plan."},
                },
                "model": DASHSCOPE_MODEL,
            },
        )

    body = _extract_body(event)
    prompt = (body.get("prompt") or "").strip()
    if not prompt:
        return _response(400, {"error": "Missing required field: prompt"})

    try:
        result = _call_dashscope(prompt)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="ignore")
        return _response(
            e.code,
            {"error": "DashScope HTTP error", "status": e.code, "detail": detail},
        )
    except urllib.error.URLError as e:
        return _response(502, {"error": "DashScope network error", "detail": str(e)})
    except Exception as e:
        return _response(500, {"error": "Unexpected error", "detail": str(e)})

    text = (
        result.get("output", {}).get("text")
        or result.get("output", {})
        .get("choices", [{}])[0]
        .get("message", {})
        .get("content", "")
    )
    return _response(
        200,
        {
            "prompt": prompt,
            "reply": text,
            "model": DASHSCOPE_MODEL,
            "raw": result,
        },
    )
