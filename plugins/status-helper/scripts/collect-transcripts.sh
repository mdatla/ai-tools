#!/usr/bin/env bash
# Collect recent Claude Code transcript activity for the status rollup.
#
# Usage: collect-transcripts.sh <since-days> [cwd-prefix ...]
#
# Scans ~/.claude/projects/*/*.jsonl (session transcripts). For each line
# within the lookback window, prints human-typed prompts and the assistant's
# final text (never thinking blocks, tool_use, or raw tool_result output —
# that's noise for this purpose). If one or more cwd-prefix args are given,
# only sessions whose recorded cwd starts with one of them are included —
# use this to scope to work repos and exclude personal projects.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: collect-transcripts.sh <since-days> [cwd-prefix ...]" >&2
  exit 2
fi

SINCE_DAYS="$1"; shift
PREFIXES=("$@")

PROJECTS_DIR="$HOME/.claude/projects"
if [ ! -d "$PROJECTS_DIR" ]; then
  echo "error: no transcripts directory found at $PROJECTS_DIR" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "error: jq is required but not found on PATH" >&2; exit 1; }

# ISO8601 cutoff, since transcript timestamps are UTC ISO8601 strings that
# sort correctly as text.
if date -v-1d >/dev/null 2>&1; then
  CUTOFF=$(date -u -v-"${SINCE_DAYS}"d "+%Y-%m-%dT%H:%M:%S.000Z")
else
  CUTOFF=$(date -u -d "-${SINCE_DAYS} days" "+%Y-%m-%dT%H:%M:%S.000Z")
fi

MAX_LINES="${STATUS_HELPER_MAX_LINES:-400}"

# Build the jq cwd-prefix filter once, if any prefixes were given.
if [ "${#PREFIXES[@]}" -gt 0 ]; then
  PREFIX_JSON=$(printf '%s\n' "${PREFIXES[@]}" | jq -R . | jq -s .)
  CWD_FILTER='(.cwd // "") as $c | ($prefixes | any(. as $p | $c | startswith($p)))'
else
  PREFIX_JSON='[]'
  CWD_FILTER='true'
fi

found_any=0

while IFS= read -r file; do
  session=$(basename "$file" .jsonl)

  out=$(jq -r --arg cutoff "$CUTOFF" --argjson prefixes "$PREFIX_JSON" '
    select(.timestamp >= $cutoff) |
    select('"$CWD_FILTER"') |
    if .type == "user"
       and (.message.content | type) == "string"
       and ((.origin.kind // "human") == "human")
       and (.message.content | test("^\\s*<") | not)
    then
      "USER [\(.timestamp)] cwd=\(.cwd // "?") branch=\(.gitBranch // "?"):\n\(.message.content)"
    elif .type == "assistant" then
      (.message.content // [] | map(select(.type == "text") | .text) | join("\n\n")) as $t
      | if ($t | length) > 0 then "ASSISTANT [\(.timestamp)]:\n\($t)" else empty end
    else empty end
  ' "$file" 2>/dev/null || true)

  [ -z "$out" ] && continue

  found_any=1
  lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  echo "===== SESSION: $session ====="
  printf '%s\n' "$out" | head -n "$MAX_LINES"
  if [ "$lines" -gt "$MAX_LINES" ]; then
    echo "... [truncated: $lines lines total, showing first $MAX_LINES]"
  fi
  echo "===== END SESSION: $session ====="
  echo
done < <(find "$PROJECTS_DIR" -type f -name '*.jsonl' -mtime "-${SINCE_DAYS}" | sort)

if [ "$found_any" -eq 0 ]; then
  echo "(no transcript activity in the last ${SINCE_DAYS} days)"
fi
