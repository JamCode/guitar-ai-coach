# -*- coding: utf-8 -*-
import os
import unittest
from unittest.mock import patch

import jwt

from auth_apple import APPLE_JWKS_URL, handle_auth_apple_post


class TestAuthAppleHandler(unittest.TestCase):
    def test_jwks_url_uses_official_keys_endpoint(self):
        self.assertEqual(APPLE_JWKS_URL, "https://appleid.apple.com/auth/keys")

    def setUp(self):
        self._prev_secret = os.environ.get("AUTH_JWT_SECRET")
        os.environ["AUTH_JWT_SECRET"] = "unit-test-secret-at-least-16-chars"

    def tearDown(self):
        if self._prev_secret is None:
            os.environ.pop("AUTH_JWT_SECRET", None)
        else:
            os.environ["AUTH_JWT_SECRET"] = self._prev_secret

    def test_missing_mysql_returns_503(self):
        with patch("auth_apple.apple_auth_mysql_enabled", return_value=False):
            code, payload = handle_auth_apple_post({"identity_token": "x"})
        self.assertEqual(code, 503)
        self.assertIn("mysql", payload.get("error", ""))

    def test_success_returns_token(self):
        with patch("auth_apple.apple_auth_mysql_enabled", return_value=True):
            with patch("auth_apple.upsert_user_by_apple_sub", return_value=7):
                with patch(
                    "auth_apple._verify_apple_identity_token",
                    return_value={"sub": "apple.sub.1"},
                ):
                    code, payload = handle_auth_apple_post({"identity_token": "dummy.jwt"})
        self.assertEqual(code, 200)
        self.assertIn("access_token", payload)
        claims = jwt.decode(
            payload["access_token"],
            os.environ["AUTH_JWT_SECRET"],
            algorithms=["HS256"],
        )
        self.assertEqual(claims["sub"], "7")

    def test_missing_identity_token_400(self):
        with patch("auth_apple.apple_auth_mysql_enabled", return_value=True):
            code, _ = handle_auth_apple_post({})
        self.assertEqual(code, 400)


if __name__ == "__main__":
    unittest.main()
