import os
import unittest

from chord_auth import APP_TOKEN_ENV, app_token_matches, configured_app_token


class AppTokenAuthTests(unittest.TestCase):
    def setUp(self):
        self._prev = os.environ.get(APP_TOKEN_ENV)

    def tearDown(self):
        if self._prev is None:
            os.environ.pop(APP_TOKEN_ENV, None)
        else:
            os.environ[APP_TOKEN_ENV] = self._prev

    def test_verify_app_token_rejects_when_not_configured(self):
        os.environ.pop(APP_TOKEN_ENV, None)

        self.assertEqual(configured_app_token(), "")
        self.assertFalse(app_token_matches("anything"))

    def test_verify_app_token_rejects_missing_or_wrong_token(self):
        os.environ[APP_TOKEN_ENV] = "expected-token"

        for token in ("", "wrong-token"):
            self.assertFalse(app_token_matches(token))

    def test_verify_app_token_accepts_matching_token(self):
        os.environ[APP_TOKEN_ENV] = "expected-token"

        self.assertTrue(app_token_matches("expected-token"))


if __name__ == "__main__":
    unittest.main()
