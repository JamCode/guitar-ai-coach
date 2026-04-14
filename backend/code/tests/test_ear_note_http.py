# -*- coding: utf-8 -*-
import json
import unittest

from index import handler


def _call(method, path, body=None):
    event = {
        "httpMethod": method,
        "path": path,
        "headers": {"Content-Type": "application/json"},
        "requestContext": {"http": {"method": method, "path": path}},
        "isBase64Encoded": False,
    }
    if body is not None:
        event["body"] = json.dumps(body, ensure_ascii=False)
    out = handler(event, None)
    payload = json.loads(out.get("body") or "{}")
    return int(out.get("statusCode") or 0), payload


class TestEarNoteHttp(unittest.TestCase):
    def test_start_mid_range_default(self):
        code, payload = _call(
            "POST",
            "/api/ear-note/session/start",
            {"mode": "single_note", "question_count": 3},
        )
        self.assertEqual(code, 200)
        config = payload.get("config") or {}
        self.assertEqual(config.get("pitch_range", {}).get("min_note"), "C4")
        self.assertEqual(config.get("pitch_range", {}).get("max_note"), "B4")

    def test_start_low_range_without_accidental(self):
        code, payload = _call(
            "POST",
            "/api/ear-note/session/start",
            {
                "mode": "single_note",
                "question_count": 5,
                "include_accidental": False,
                "pitch_range": "low",
            },
        )
        self.assertEqual(code, 200)
        notes = (payload.get("question") or {}).get("candidate_notes") or []
        self.assertTrue(notes)
        for note in notes:
            self.assertTrue(note.endswith("3"))
            self.assertNotIn("#", note)

    def test_start_custom_range(self):
        code, payload = _call(
            "POST",
            "/api/ear-note/session/start",
            {
                "mode": "multi_note",
                "question_count": 3,
                "notes_per_question": 3,
                "pitch_range": "D3-G3",
                "include_accidental": True,
            },
        )
        self.assertEqual(code, 200)
        config = payload.get("config") or {}
        self.assertEqual(config.get("pitch_range", {}).get("min_note"), "D3")
        self.assertEqual(config.get("pitch_range", {}).get("max_note"), "G3")


if __name__ == "__main__":
    unittest.main()
