#!/usr/bin/env python3
"""Tests for collect_notes.py. Run with: python3 -m unittest scripts.test_collect_notes -v"""

import io
import os
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(__file__))
import collect_notes  # noqa: E402

SCRIPT = os.path.join(os.path.dirname(__file__), "collect_notes.py")


def touch(path, content="hello\n", age_days=0):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(content)
    if age_days:
        old = time.time() - age_days * 86400
        os.utime(path, (old, old))


class CollectNotesLibTests(unittest.TestCase):
    """Exercise the library function directly for precise assertions."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.vault = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def run_collect(self, since_days, folders):
        buf = io.StringIO()
        with redirect_stdout(buf):
            collect_notes.collect(self.vault, since_days, folders)
        return buf.getvalue()

    def test_recent_note_included(self):
        touch(os.path.join(self.vault, "Daily", "2026-01-01.md"), "did the thing\n")
        out = self.run_collect(7, ["Daily"])
        self.assertIn("NOTE: Daily/2026-01-01.md", out)
        self.assertIn("did the thing", out)
        self.assertIn("END NOTE: Daily/2026-01-01.md", out)

    def test_old_note_excluded(self):
        touch(os.path.join(self.vault, "Daily", "old.md"), "ancient\n", age_days=30)
        out = self.run_collect(7, ["Daily"])
        self.assertNotIn("ancient", out)
        self.assertIn("no notes modified", out)

    def test_non_markdown_excluded(self):
        touch(os.path.join(self.vault, "Daily", "note.md"), "keep me\n")
        touch(os.path.join(self.vault, "Daily", "image.png"), "binary-ish\n")
        out = self.run_collect(7, ["Daily"])
        self.assertIn("keep me", out)
        self.assertNotIn("image.png", out)

    def test_obsidian_dir_excluded(self):
        touch(os.path.join(self.vault, "Daily", ".obsidian", "config.md"), "should not appear\n")
        touch(os.path.join(self.vault, "Daily", "real.md"), "should appear\n")
        out = self.run_collect(7, ["Daily"])
        self.assertNotIn("should not appear", out)
        self.assertIn("should appear", out)

    def test_missing_folder_skipped_silently(self):
        # "Notes" doesn't exist at all -- should not error, just find nothing.
        out = self.run_collect(7, ["Notes"])
        self.assertIn("no notes modified", out)

    def test_multiple_folders(self):
        touch(os.path.join(self.vault, "Daily", "a.md"), "from daily\n")
        touch(os.path.join(self.vault, "Notes", "b.md"), "from notes\n")
        out = self.run_collect(7, ["Daily", "Notes"])
        self.assertIn("from daily", out)
        self.assertIn("from notes", out)

    def test_truncation(self):
        content = "\n".join(f"line {i}" for i in range(10)) + "\n"
        touch(os.path.join(self.vault, "Notes", "long.md"), content)
        os.environ["STATUS_HELPER_MAX_LINES"] = "3"
        try:
            out = self.run_collect(7, ["Notes"])
        finally:
            del os.environ["STATUS_HELPER_MAX_LINES"]
        self.assertIn("line 0", out)
        self.assertIn("line 2", out)
        self.assertNotIn("line 3", out)
        self.assertIn("truncated: 10 lines total, showing first 3", out)

    def test_nested_subfolders_included(self):
        touch(os.path.join(self.vault, "Daily", "2026", "08", "deep.md"), "nested content\n")
        out = self.run_collect(7, ["Daily"])
        self.assertIn("nested content", out)
        self.assertIn(os.path.join("Daily", "2026", "08", "deep.md"), out)

    def test_tricky_filename_with_ampersand_and_parens(self):
        touch(os.path.join(self.vault, "Notes", "weird & name (1).md"), "tricky filename content\n")
        out = self.run_collect(7, ["Notes"])
        self.assertIn("tricky filename content", out)
        self.assertIn("weird & name (1).md", out)

    def test_empty_file(self):
        touch(os.path.join(self.vault, "Notes", "empty.md"), "")
        out = self.run_collect(7, ["Notes"])
        self.assertIn("NOTE: Notes/empty.md", out)
        self.assertIn("END NOTE: Notes/empty.md", out)


class CollectNotesCliTests(unittest.TestCase):
    """Exercise the actual CLI entry point via subprocess."""

    def run_cli(self, *args):
        return subprocess.run(
            [sys.executable, SCRIPT, *args], capture_output=True, text=True
        )

    def test_missing_vault_errors(self):
        result = self.run_cli("/definitely/not/a/real/vault", "7")
        self.assertEqual(result.returncode, 1)
        self.assertIn("vault not found", result.stderr)

    def test_bad_args_usage(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)

    def test_non_numeric_since_days(self):
        with tempfile.TemporaryDirectory() as vault:
            result = self.run_cli(vault, "not-a-number")
        self.assertEqual(result.returncode, 2)
        self.assertIn("since-days must be a number", result.stderr)

    def test_default_folders_used_when_none_given(self):
        with tempfile.TemporaryDirectory() as vault:
            touch(os.path.join(vault, "Daily", "d.md"), "daily default\n")
            touch(os.path.join(vault, "Notes", "n.md"), "notes default\n")
            result = self.run_cli(vault, "7")
        self.assertEqual(result.returncode, 0)
        self.assertIn("daily default", result.stdout)
        self.assertIn("notes default", result.stdout)

    def test_success_exit_code(self):
        with tempfile.TemporaryDirectory() as vault:
            touch(os.path.join(vault, "Daily", "d.md"))
            result = self.run_cli(vault, "7", "Daily")
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
