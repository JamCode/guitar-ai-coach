# -*- coding: utf-8 -*-
import os
import unittest

import jwt

from auth_jwt import decode_access_token, issue_access_token


class TestAuthJwt(unittest.TestCase):
    def setUp(self):
        self._prev = os.environ.get("AUTH_JWT_SECRET")
        os.environ["AUTH_JWT_SECRET"] = "unit-test-secret-at-least-16-chars"

    def tearDown(self):
        if self._prev is None:
            os.environ.pop("AUTH_JWT_SECRET", None)
        else:
            os.environ["AUTH_JWT_SECRET"] = self._prev

    def test_issue_and_decode_roundtrip(self):
        tok = issue_access_token(user_id=42, apple_sub="sub.x", ttl_seconds=600)
        self.assertIsInstance(tok, str)
        self.assertTrue(tok.count("."), 2)
        claims = decode_access_token(tok)
        self.assertEqual(claims["sub"], "42")
        self.assertEqual(claims["apple_sub"], "sub.x")

    def test_decode_rejects_tampered(self):
        tok = issue_access_token(user_id=1, apple_sub="a", ttl_seconds=600)
        parts = tok.split(".")
        parts[1] = jwt.utils.base64url_encode(b'{"sub":"99","iat":1,"exp":9999999999}').decode(
            "ascii"
        )
        bad = ".".join(parts)
        with self.assertRaises(jwt.PyJWTError):
            decode_access_token(bad)


if __name__ == "__main__":
    unittest.main()
