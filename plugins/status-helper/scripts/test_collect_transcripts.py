#!/usr/bin/env python3
"""Tests for collect_transcripts.py. Run with: python3 -m unittest scripts.test_collect_transcripts -v"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(__file__))
import collect_transcripts as ct  # noqa: E402

SCRIPT = os.path.join(os.path.dirname(__file__), "collect_transcripts.py")


def ts(days_ago=0):
    return (datetime.now(timezone.utc) - timedelta(days=days_ago)).strftime(
        "%Y-%m-%dT%H:%M:%S.000Z"
    )


def write_session(dir_path, session_id, entries):
    os.makedirs(dir_path, exist_ok=True)
    path = os.path.join(dir_path, f"{session_id}.jsonl")
    with open(path, "w") as fh:
        for entry in entries:
            fh.write(json.dumps(entry) + "\n")
    return path


def user_entry(text, timestamp=None, cwd="/repo", branch="main", origin=None):
    return {
        "type": "user",
        "message": {"role": "user", "content": text},
        "timestamp": timestamp or ts(),
        "cwd": cwd,
        "gitBranch": branch,
        "origin": origin or {"kind": "human"},
    }


def assistant_entry(text_blocks, timestamp=None):
    content = []
    for block in text_blocks:
        if block.get("type") == "text":
            content.append({"type": "text", "text": block["text"]})
        else:
            content.append(block)
    return {
        "type": "assistant",
        "message": {"role": "assistant", "content": content},
        "timestamp": timestamp or ts(),
    }


class HelperFunctionTests(unittest.TestCase):
    def test_is_human_user_text_accepts_plain_string(self):
        self.assertTrue(ct.is_human_user_text(user_entry("hello")))

    def test_is_human_user_text_rejects_non_user_type(self):
        self.assertFalse(ct.is_human_user_text(assistant_entry([{"type": "text", "text": "x"}])))

    def test_is_human_user_text_rejects_array_content(self):
        entry = {
            "type": "user",
            "message": {"content": [{"type": "tool_result", "content": "x"}]},
        }
        self.assertFalse(ct.is_human_user_text(entry))

    def test_is_human_user_text_rejects_non_human_origin(self):
        entry = user_entry("auto-generated", origin={"kind": "task-notification"})
        self.assertFalse(ct.is_human_user_text(entry))

    def test_is_human_user_text_rejects_leading_tag(self):
        entry = user_entry("<system-reminder>stuff</system-reminder>")
        self.assertFalse(ct.is_human_user_text(entry))

    def test_is_human_user_text_rejects_leading_whitespace_then_tag(self):
        entry = user_entry("   \n<command-name>/model</command-name>")
        self.assertFalse(ct.is_human_user_text(entry))

    def test_is_human_user_text_accepts_text_mentioning_tag_midstring(self):
        entry = user_entry("can you look at <Foo> in the code")
        self.assertTrue(ct.is_human_user_text(entry))

    def test_assistant_text_joins_text_blocks_only(self):
        entry = assistant_entry(
            [
                {"type": "thinking", "thinking": "internal"},
                {"type": "text", "text": "first"},
                {"type": "tool_use", "name": "Bash", "input": {}},
                {"type": "text", "text": "second"},
            ]
        )
        self.assertEqual(ct.assistant_text(entry), "first\n\nsecond")

    def test_assistant_text_empty_when_no_text_blocks(self):
        entry = assistant_entry([{"type": "tool_use", "name": "Bash", "input": {}}])
        self.assertEqual(ct.assistant_text(entry), "")

    def test_matches_cwd_no_prefixes_matches_everything(self):
        self.assertTrue(ct.matches_cwd(user_entry("x", cwd="/anywhere"), []))

    def test_matches_cwd_prefix_match(self):
        entry = user_entry("x", cwd="/Users/me/Code/repos/foo/sub")
        self.assertTrue(ct.matches_cwd(entry, ["/Users/me/Code/repos/foo"]))

    def test_matches_cwd_prefix_no_match(self):
        entry = user_entry("x", cwd="/Users/me/personal/project")
        self.assertFalse(ct.matches_cwd(entry, ["/Users/me/Code/repos"]))


class RenderSessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def test_render_includes_user_and_assistant(self):
        path = write_session(
            self.tmp.name,
            "session-1",
            [
                user_entry("do the thing", cwd="/repo", branch="main"),
                assistant_entry([{"type": "text", "text": "done"}]),
            ],
        )
        cutoff = ts(7)
        out = ct.render_session(path, cutoff, [], 400)
        self.assertIsNotNone(out)
        self.assertIn("SESSION: session-1", out)
        self.assertIn("USER", out)
        self.assertIn("do the thing", out)
        self.assertIn("cwd=/repo", out)
        self.assertIn("branch=main", out)
        self.assertIn("ASSISTANT", out)
        self.assertIn("done", out)
        self.assertIn("END SESSION: session-1", out)

    def test_render_excludes_entries_before_cutoff(self):
        path = write_session(
            self.tmp.name,
            "session-2",
            [user_entry("too old", timestamp=ts(30))],
        )
        cutoff = ts(7)
        out = ct.render_session(path, cutoff, [], 400)
        self.assertIsNone(out)

    def test_render_filters_by_cwd_prefix(self):
        path = write_session(
            self.tmp.name,
            "session-3",
            [
                user_entry("work item", cwd="/Users/me/Code/repos/work"),
                user_entry("personal item", cwd="/Users/me/personal"),
            ],
        )
        cutoff = ts(7)
        out = ct.render_session(path, cutoff, ["/Users/me/Code/repos"], 400)
        self.assertIn("work item", out)
        self.assertNotIn("personal item", out)

    def test_render_returns_none_when_nothing_matches_prefix(self):
        path = write_session(
            self.tmp.name,
            "session-4",
            [user_entry("personal item", cwd="/Users/me/personal")],
        )
        cutoff = ts(7)
        out = ct.render_session(path, cutoff, ["/Users/me/Code/repos"], 400)
        self.assertIsNone(out)

    def test_render_drops_tool_noise(self):
        entries = [
            user_entry("<system-reminder>noise</system-reminder>"),
            assistant_entry([{"type": "thinking", "thinking": "internal reasoning"}]),
            assistant_entry(
                [{"type": "tool_use", "name": "Bash", "input": {"command": "ls"}}]
            ),
        ]
        path = write_session(self.tmp.name, "session-5", entries)
        cutoff = ts(7)
        out = ct.render_session(path, cutoff, [], 400)
        self.assertIsNone(out)

    def test_render_truncates_long_sessions(self):
        entries = [user_entry(f"message {i}") for i in range(10)]
        path = write_session(self.tmp.name, "session-6", entries)
        cutoff = ts(7)
        out = ct.render_session(path, cutoff, [], 5)
        self.assertIn("truncated", out)
        self.assertIn("message 0", out)

    def test_render_handles_malformed_json_line(self):
        path = os.path.join(self.tmp.name, "session-7.jsonl")
        with open(path, "w") as fh:
            fh.write("not valid json\n")
            fh.write(json.dumps(user_entry("valid entry")) + "\n")
        cutoff = ts(7)
        out = ct.render_session(path, cutoff, [], 400)
        self.assertIsNotNone(out)
        self.assertIn("valid entry", out)


class CliTests(unittest.TestCase):
    def run_cli(self, *args, env=None):
        full_env = os.environ.copy()
        if env:
            full_env.update(env)
        return subprocess.run(
            [sys.executable, SCRIPT, *args], capture_output=True, text=True, env=full_env
        )

    def test_bad_args_usage(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)

    def test_non_numeric_since_days(self):
        result = self.run_cli("not-a-number")
        self.assertEqual(result.returncode, 2)
        self.assertIn("since-days must be a number", result.stderr)

    def test_missing_projects_dir(self):
        with tempfile.TemporaryDirectory() as fake_home:
            env = {"HOME": fake_home}
            result = self.run_cli("7", env=env)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no transcripts directory found", result.stderr)

    def test_end_to_end_with_fake_home(self):
        with tempfile.TemporaryDirectory() as fake_home:
            projects_dir = os.path.join(fake_home, ".claude", "projects", "-repo-foo")
            write_session(
                projects_dir,
                "abc123",
                [
                    user_entry("implement the widget", cwd="/repo/foo"),
                    assistant_entry([{"type": "text", "text": "Implemented the widget."}]),
                ],
            )
            env = {"HOME": fake_home}
            result = self.run_cli("7", env=env)
        self.assertEqual(result.returncode, 0)
        self.assertIn("implement the widget", result.stdout)
        self.assertIn("Implemented the widget.", result.stdout)

    def test_no_activity_message(self):
        with tempfile.TemporaryDirectory() as fake_home:
            os.makedirs(os.path.join(fake_home, ".claude", "projects"))
            env = {"HOME": fake_home}
            result = self.run_cli("7", env=env)
        self.assertEqual(result.returncode, 0)
        self.assertIn("no transcript activity", result.stdout)


if __name__ == "__main__":
    unittest.main()
