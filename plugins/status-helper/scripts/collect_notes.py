#!/usr/bin/env python3
"""Collect recent Obsidian notes for the status rollup.

Usage: collect_notes.py <vault-path> <since-days> [folder ...]

Prints each matching note as a delimited block so the skill can read a whole
window of notes in one shot instead of stat-ing and cat-ing them one by one.
Folders default to "Daily" and "Notes" (relative to the vault root).
"""

import os
import sys
import time

DEFAULT_FOLDERS = ("Daily", "Notes")
DEFAULT_MAX_LINES = 400


def collect(vault: str, since_days: float, folders):
    max_lines = int(os.environ.get("STATUS_HELPER_MAX_LINES", DEFAULT_MAX_LINES))
    cutoff = time.time() - since_days * 86400
    found_any = False

    for folder in folders:
        folder_dir = os.path.join(vault, folder)
        if not os.path.isdir(folder_dir):
            continue

        notes = []
        for root, dirs, files in os.walk(folder_dir):
            # Mirror the shell version's `-not -path '*/.obsidian/*'` exclusion.
            dirs[:] = [d for d in dirs if d != ".obsidian"]
            for name in files:
                if not name.endswith(".md"):
                    continue
                path = os.path.join(root, name)
                try:
                    mtime = os.path.getmtime(path)
                except OSError:
                    continue
                if mtime >= cutoff:
                    notes.append((path, mtime))

        notes.sort(key=lambda item: item[0])

        for path, mtime in notes:
            found_any = True
            rel = os.path.relpath(path, vault)
            mtime_str = time.strftime("%Y-%m-%d %H:%M", time.localtime(mtime))
            print(f"===== NOTE: {rel} (modified {mtime_str}) =====")
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    lines = fh.readlines()
            except OSError as exc:
                print(f"[error reading file: {exc}]")
                lines = []
            for line in lines[:max_lines]:
                print(line, end="" if line.endswith("\n") else "\n")
            if len(lines) > max_lines:
                print(f"... [truncated: {len(lines)} lines total, showing first {max_lines}]")
            print(f"===== END NOTE: {rel} =====")
            print()

    if not found_any:
        folder_list = " ".join(folders)
        print(f"(no notes modified in the last {since_days} days under: {folder_list})")


def main(argv):
    if len(argv) < 2:
        print("usage: collect_notes.py <vault-path> <since-days> [folder ...]", file=sys.stderr)
        return 2

    vault = argv[0]
    try:
        since_days = float(argv[1])
    except ValueError:
        print(f"error: since-days must be a number, got: {argv[1]}", file=sys.stderr)
        return 2

    folders = argv[2:] if len(argv) > 2 else list(DEFAULT_FOLDERS)

    if not os.path.isdir(vault):
        print(f"error: vault not found: {vault}", file=sys.stderr)
        return 1

    collect(vault, since_days, folders)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
