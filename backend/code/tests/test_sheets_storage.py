# -*- coding: utf-8 -*-
import os
import tempfile
import unittest

from sheets_storage import absolute_path, ext_for_mime, relpath_for_page


class TestSheetsStorage(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        os.environ["SHEETS_STORAGE_ROOT"] = self._td.name

    def tearDown(self):
        self._td.cleanup()
        os.environ.pop("SHEETS_STORAGE_ROOT", None)

    def test_relpath_and_absolute_roundtrip(self):
        rel = relpath_for_page(7, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", 0, ".jpg")
        self.assertTrue(rel.startswith("7/"))
        full = absolute_path(rel)
        self.assertTrue(os.path.isabs(full))

    def test_traversal_rejected(self):
        with self.assertRaises(ValueError):
            absolute_path("../evil")

    def test_ext_for_mime(self):
        self.assertEqual(ext_for_mime("image/png"), ".png")


if __name__ == "__main__":
    unittest.main()
