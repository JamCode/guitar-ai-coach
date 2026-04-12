# -*- coding: utf-8 -*-
import unittest

from practice_db import validate_session_payload


class TestPracticeValidate(unittest.TestCase):
    def _valid_body(self):
        return {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "taskId": "chord-switch",
            "taskName": "和弦切换",
            "startedAt": "2026-04-09T10:00:00.000",
            "endedAt": "2026-04-09T10:05:00.000",
            "durationSeconds": 300,
            "completed": True,
            "difficulty": 3,
        }

    def test_ok(self):
        row = validate_session_payload(self._valid_body())
        self.assertEqual(row["client_session_id"], "550e8400-e29b-41d4-a716-446655440000")
        self.assertEqual(row["task_id"], "chord-switch")
        self.assertTrue(row["completed"])

    def test_duration_as_float_accepted(self):
        b = self._valid_body()
        b["durationSeconds"] = 120.0
        row = validate_session_payload(b)
        self.assertEqual(row["duration_seconds"], 120)

    def test_bad_uuid(self):
        b = self._valid_body()
        b["id"] = "not-a-uuid"
        with self.assertRaises(ValueError):
            validate_session_payload(b)

    def test_ended_before_started(self):
        b = self._valid_body()
        b["endedAt"] = "2026-04-09T09:00:00.000"
        with self.assertRaises(ValueError):
            validate_session_payload(b)


if __name__ == "__main__":
    unittest.main()
