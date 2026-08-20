#!/usr/bin/env bash
# Collect recent Obsidian notes for the status rollup.
#
# Usage: collect-notes.sh <vault-path> <since-days> [folder ...]
#
# Prints each matching note as a delimited block so the skill can read a whole
# window of notes in one shot instead of stat-ing and cat-ing them one by one.
# Folders default to "Daily" and "Notes" (relative to the vault root).

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: collect-notes.sh <vault-path> <since-days> [folder ...]" >&2
  exit 2
fi

VAULT="$1"; shift
SINCE_DAYS="$1"; shift

if [ ! -d "$VAULT" ]; then
  echo "error: vault not found: $VAULT" >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  FOLDERS=("$@")
else
  FOLDERS=("Daily" "Notes")
fi

# Cap per-note output so one runaway note can't flood the context window.
MAX_LINES="${STATUS_HELPER_MAX_LINES:-400}"

found_any=0

for folder in "${FOLDERS[@]}"; do
  dir="$VAULT/$folder"
  [ -d "$dir" ] || continue

  # -mtime -N is "modified within the last N days" — the window the caller asked for.
  while IFS= read -r note; do
    found_any=1
    rel="${note#"$VAULT"/}"
    mtime=$(date -r "$note" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
    echo "===== NOTE: $rel (modified $mtime) ====="
    head -n "$MAX_LINES" "$note"
    total=$(wc -l < "$note" | tr -d ' ')
    if [ "$total" -gt "$MAX_LINES" ]; then
      echo "... [truncated: $total lines total, showing first $MAX_LINES]"
    fi
    echo "===== END NOTE: $rel ====="
    echo
  done < <(find "$dir" -type f -name '*.md' -mtime "-${SINCE_DAYS}" -not -path '*/.obsidian/*' | sort)
done

if [ "$found_any" -eq 0 ]; then
  echo "(no notes modified in the last ${SINCE_DAYS} days under: ${FOLDERS[*]})"
fi
