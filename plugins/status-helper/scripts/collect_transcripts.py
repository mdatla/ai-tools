#!/usr/bin/env python3
"""Collect recent Claude Code transcript activity for the status rollup.

Usage: collect_transcripts.py <since-days> [cwd-prefix ...]

Scans ~/.claude/projects/*/*.jsonl (session transcripts). For each line
within the lookback window, prints human-typed prompts and the assistant's
final text (never thinking blocks, tool_use, or raw tool_result output --
that's noise for this purpose). If one or more cwd-prefix args are given,
only sessions whose recorded cwd starts with one of them are included --
use this to scope to work repos and exclude personal projects.
"""

import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

DEFAULT_MAX_LINES = 400
LEADING_TAG_RE = re.compile(r"^\s*<")


def iso_cutoff(since_days: float) -> str:
    cutoff = datetime.now(timezone.utc) - timedelta(days=since_days)
    return cutoff.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def is_human_user_text(entry: dict) -> bool:
    if entry.get("type") != "user":
        return False
    message = entry.get("message") or {}
    content = message.get("content")
    if not isinstance(content, str):
        return False
    origin = entry.get("origin") or {}
    if origin.get("kind", "human") != "human":
        return False
    if LEADING_TAG_RE.match(content):
        return False
    return True


def assistant_text(entry: dict) -> str:
    if entry.get("type") != "assistant":
        return ""
    message = entry.get("message") or {}
    content = message.get("content")
    if not isinstance(content, list):
        return ""
    parts = [
        block.get("text", "")
        for block in content
        if isinstance(block, dict) and block.get("type") == "text"
    ]
    return "\n\n".join(p for p in parts if p)


def matches_cwd(entry: dict, prefixes) -> bool:
    if not prefixes:
        return True
    cwd = entry.get("cwd") or ""
    return any(cwd.startswith(p) for p in prefixes)


def render_session(path: str, cutoff: str, prefixes, max_lines: int) -> str | None:
    lines_out = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for raw_line in fh:
                raw_line = raw_line.strip()
                if not raw_line:
                    continue
                try:
                    entry = json.loads(raw_line)
                except json.JSONDecodeError:
                    continue

                timestamp = entry.get("timestamp")
                if not isinstance(timestamp, str) or timestamp < cutoff:
                    continue
                if not matches_cwd(entry, prefixes):
                    continue

                if is_human_user_text(entry):
                    message = entry["message"]
                    cwd = entry.get("cwd", "?")
                    branch = entry.get("gitBranch", "?")
                    lines_out.append(
                        f"USER [{timestamp}] cwd={cwd} branch={branch}:\n{message['content']}"
                    )
                else:
                    text = assistant_text(entry)
                    if text:
                        lines_out.append(f"ASSISTANT [{timestamp}]:\n{text}")
    except OSError:
        return None

    if not lines_out:
        return None

    session = os.path.basename(path)[: -len(".jsonl")] if path.endswith(".jsonl") else os.path.basename(path)

    body = "\n".join(lines_out)
    body_lines = body.split("\n")
    truncated_note = ""
    if len(body_lines) > max_lines:
        truncated_note = f"\n... [truncated: {len(body_lines)} lines total, showing first {max_lines}]"
        body = "\n".join(body_lines[:max_lines])

    return f"===== SESSION: {session} =====\n{body}{truncated_note}\n===== END SESSION: {session} =====\n"


def main(argv):
    if len(argv) < 1:
        print("usage: collect_transcripts.py <since-days> [cwd-prefix ...]", file=sys.stderr)
        return 2

    try:
        since_days = float(argv[0])
    except ValueError:
        print(f"error: since-days must be a number, got: {argv[0]}", file=sys.stderr)
        return 2

    prefixes = argv[1:]

    projects_dir = os.path.expanduser("~/.claude/projects")
    if not os.path.isdir(projects_dir):
        print(f"error: no transcripts directory found at {projects_dir}", file=sys.stderr)
        return 1

    max_lines = int(os.environ.get("STATUS_HELPER_MAX_LINES", DEFAULT_MAX_LINES))
    cutoff_iso = iso_cutoff(since_days)
    cutoff_mtime = (datetime.now(timezone.utc) - timedelta(days=since_days)).timestamp()

    jsonl_files = []
    for root, _dirs, files in os.walk(projects_dir):
        for name in files:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(root, name)
            try:
                if os.path.getmtime(path) >= cutoff_mtime:
                    jsonl_files.append(path)
            except OSError:
                continue
    jsonl_files.sort()

    found_any = False
    for path in jsonl_files:
        rendered = render_session(path, cutoff_iso, prefixes, max_lines)
        if rendered is None:
            continue
        found_any = True
        print(rendered)

    if not found_any:
        print(f"(no transcript activity in the last {since_days} days)")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
