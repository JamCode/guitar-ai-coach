# -*- coding: utf-8 -*-
import unittest
from unittest.mock import patch

import auth_db


class _FakeCursor:
    def __init__(self, row):
        self._row = row

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def execute(self, _sql, _args):
        return None

    def fetchone(self):
        return self._row


class _FakeConn:
    def __init__(self, row):
        self._row = row

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def cursor(self):
        return _FakeCursor(self._row)


class TestAuthDbSchemaCheck(unittest.TestCase):
    def test_accepts_uppercase_table_name_column(self):
        auth_db._SCHEMA_OK = False
        with patch("auth_db.get_connection", return_value=_FakeConn({"TABLE_NAME": "apple_users"})):
            auth_db.ensure_apple_auth_schema()
        self.assertTrue(auth_db._SCHEMA_OK)


if __name__ == "__main__":
    unittest.main()
