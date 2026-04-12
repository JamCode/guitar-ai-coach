# -*- coding: utf-8 -*-
import unittest

from sheets_http import _parse_multipart


class TestMultipart(unittest.TestCase):
    def test_parse_display_name_and_pages(self):
        boundary = "----abc123"
        body = (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="display_name"\r\n\r\n'
            "我的歌\r\n"
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="page"; filename="a.jpg"\r\n'
            "Content-Type: image/jpeg\r\n\r\n"
        ).encode("utf-8")
        body += b"\xff\xd8\xff\r\n"
        body += f"--{boundary}--\r\n".encode("ascii")
        ct = f"multipart/form-data; boundary={boundary}"
        name, files = _parse_multipart(body, ct)
        self.assertEqual(name, "我的歌")
        self.assertEqual(len(files), 1)
        self.assertEqual(files[0][1], "image/jpeg")
        self.assertEqual(files[0][2], b"\xff\xd8\xff")


if __name__ == "__main__":
    unittest.main()
