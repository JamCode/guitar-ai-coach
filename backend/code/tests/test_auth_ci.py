# -*- coding: utf-8 -*-
import os
import unittest
from unittest.mock import patch

import jwt

from auth_ci import handle_auth_ci_login_post, handle_auth_test_login_post


class TestAuthCiLogin(unittest.TestCase):
    def setUp(self):
        self._prev_ci_enabled = os.environ.get("CI_AUTH_ENABLED")
        self._prev_ci_secret = os.environ.get("CI_AUTH_SECRET")
        self._prev_test_auth_enabled = os.environ.get("TEST_AUTH_ENABLED")
        self._prev_jwt_secret = os.environ.get("AUTH_JWT_SECRET")
        os.environ["AUTH_JWT_SECRET"] = "unit-test-secret-at-least-16-chars"

    def tearDown(self):
        if self._prev_ci_enabled is None:
            os.environ.pop("CI_AUTH_ENABLED", None)
        else:
            os.environ["CI_AUTH_ENABLED"] = self._prev_ci_enabled
        if self._prev_ci_secret is None:
            os.environ.pop("CI_AUTH_SECRET", None)
        else:
            os.environ["CI_AUTH_SECRET"] = self._prev_ci_secret
        if self._prev_test_auth_enabled is None:
            os.environ.pop("TEST_AUTH_ENABLED", None)
        else:
            os.environ["TEST_AUTH_ENABLED"] = self._prev_test_auth_enabled
        if self._prev_jwt_secret is None:
            os.environ.pop("AUTH_JWT_SECRET", None)
        else:
            os.environ["AUTH_JWT_SECRET"] = self._prev_jwt_secret

    def test_ci_disabled_returns_404(self):
        os.environ.pop("CI_AUTH_ENABLED", None)
        code, _ = handle_auth_ci_login_post({"ci_secret": "x"})
        self.assertEqual(code, 404)

    def test_missing_secret_returns_401(self):
        os.environ["CI_AUTH_ENABLED"] = "true"
        os.environ["CI_AUTH_SECRET"] = "abc"
        code, _ = handle_auth_ci_login_post({})
        self.assertEqual(code, 401)

    def test_wrong_secret_returns_401(self):
        os.environ["CI_AUTH_ENABLED"] = "true"
        os.environ["CI_AUTH_SECRET"] = "abc"
        code, _ = handle_auth_ci_login_post({"ci_secret": "wrong"})
        self.assertEqual(code, 401)

    def test_success_returns_token(self):
        os.environ["CI_AUTH_ENABLED"] = "true"
        os.environ["CI_AUTH_SECRET"] = "abc"
        with patch("auth_ci.apple_auth_mysql_enabled", return_value=True):
            with patch("auth_ci.upsert_user_by_apple_sub", return_value=88):
                code, payload = handle_auth_ci_login_post(
                    {"ci_secret": "abc", "ci_user_key": "github-actions"}
                )
        self.assertEqual(code, 200)
        self.assertIn("access_token", payload)
        self.assertEqual(payload.get("ci_user_key"), "github-actions")
        claims = jwt.decode(
            payload["access_token"],
            os.environ["AUTH_JWT_SECRET"],
            algorithms=["HS256"],
        )
        self.assertEqual(claims["sub"], "88")

    def test_test_login_disabled_returns_404(self):
        os.environ.pop("TEST_AUTH_ENABLED", None)
        code, _ = handle_auth_test_login_post({})
        self.assertEqual(code, 404)

    def test_test_login_success_returns_token(self):
        os.environ["TEST_AUTH_ENABLED"] = "true"
        with patch("auth_ci.apple_auth_mysql_enabled", return_value=True):
            with patch("auth_ci.upsert_user_by_apple_sub", return_value=99):
                code, payload = handle_auth_test_login_post({"test_user_key": "mobile-user"})
        self.assertEqual(code, 200)
        self.assertIn("access_token", payload)
        self.assertEqual(payload.get("test_user_key"), "mobile-user")
        claims = jwt.decode(
            payload["access_token"],
            os.environ["AUTH_JWT_SECRET"],
            algorithms=["HS256"],
        )
        self.assertEqual(claims["sub"], "99")


if __name__ == "__main__":
    unittest.main()
