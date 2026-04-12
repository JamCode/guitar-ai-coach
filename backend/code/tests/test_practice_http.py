# -*- coding: utf-8 -*-
import unittest
from unittest.mock import patch

from practice_http import handle_practice_routes


def _resp(code, payload):
    return {"status": code, "body": payload}


class TestPracticeHttp(unittest.TestCase):
    def test_get_list_401(self):
        with patch(
            "practice_http._bearer_user_id",
            return_value=(None, (401, {"error": "missing_bearer_token"})),
        ):
            out = handle_practice_routes(
                {"httpMethod": "GET", "path": "/api/practice/sessions"},
                _resp,
            )
        self.assertEqual(out["status"], 401)

    def test_get_list_503_no_mysql(self):
        with patch("practice_http._bearer_user_id", return_value=(7, None)):
            with patch("practice_http.apple_auth_mysql_enabled", return_value=False):
                out = handle_practice_routes(
                    {"httpMethod": "GET", "path": "/api/practice/sessions"},
                    _resp,
                )
        self.assertEqual(out["status"], 503)

    def test_get_list_ok(self):
        fake_rows = [
            {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "taskId": "a",
                "taskName": "A",
                "startedAt": "2026-04-09T10:00:00.000",
                "endedAt": "2026-04-09T10:01:00.000",
                "durationSeconds": 60,
                "completed": True,
                "difficulty": 3,
                "note": None,
                "progressionId": None,
                "musicKey": None,
                "complexity": None,
            }
        ]
        with patch("practice_http._bearer_user_id", return_value=(7, None)):
            with patch("practice_http.apple_auth_mysql_enabled", return_value=True):
                with patch(
                    "practice_http.list_sessions_for_user",
                    return_value=fake_rows,
                ):
                    out = handle_practice_routes(
                        {
                            "httpMethod": "GET",
                            "path": "/api/practice/sessions",
                            "queryStringParameters": {"limit": "10"},
                        },
                        _resp,
                    )
        self.assertEqual(out["status"], 200)
        self.assertEqual(len(out["body"]["sessions"]), 1)

    def test_post_invalid_json(self):
        with patch("practice_http._bearer_user_id", return_value=(7, None)):
            with patch("practice_http.apple_auth_mysql_enabled", return_value=True):
                out = handle_practice_routes(
                    {
                        "httpMethod": "POST",
                        "path": "/api/practice/sessions",
                        "body": "",
                    },
                    _resp,
                )
        self.assertEqual(out["status"], 400)

    def test_post_ok(self):
        body = (
            '{"id":"550e8400-e29b-41d4-a716-446655440000",'
            '"taskId":"x","taskName":"X",'
            '"startedAt":"2026-04-09T10:00:00.000",'
            '"endedAt":"2026-04-09T10:01:00.000",'
            '"durationSeconds":60,"completed":true,"difficulty":3}'
        )
        with patch("practice_http._bearer_user_id", return_value=(7, None)):
            with patch("practice_http.apple_auth_mysql_enabled", return_value=True):
                with patch("practice_http.upsert_session") as up:
                    out = handle_practice_routes(
                        {
                            "httpMethod": "POST",
                            "path": "/api/practice/sessions",
                            "body": body,
                            "isBase64Encoded": False,
                        },
                        _resp,
                    )
        self.assertEqual(out["status"], 200)
        self.assertTrue(out["body"].get("ok"))
        up.assert_called_once()


if __name__ == "__main__":
    unittest.main()
