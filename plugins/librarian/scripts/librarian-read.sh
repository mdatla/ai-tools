#!/usr/bin/env bash
# Librarian Pre-Tool Hook (macOS/Linux)
# Walks up _memory_library/ from the target file, injects context into Claude.

# --- Logging (set to false to disable) ---
LIBRARIAN_LOG_ENABLED=true
LIBRARIAN_LOG_FILE="$HOME/.claude/librarian.log"

log() {
  if [ "$LIBRARIAN_LOG_ENABLED" = true ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [read] $1" >> "$LIBRARIAN_LOG_FILE"
  fi
}

set -uo pipefail

INPUT=$(cat)
log "Hook fired"

# Extract file_path — grep the JSON string value
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$FILE_PATH" ]; then
  # UserPromptSubmit — always inject tagging reminder if library exists
  if [ -n "${LIBRARIAN_PATH:-}" ] && [ -d "$LIBRARIAN_PATH" ]; then
    log "No file_path (prompt hook), injecting tagging reminder"
    REMINDER="Tag learnings to $LIBRARIAN_PATH/.scratch.md as: ## [TAG: path, type: file] + bullets. Capture WHY not WHAT — gotchas, non-obvious constraints, decisions and their rationale, surprising behavior, things you'd want to know next time. Include a short summary of what was done."
    ESCAPED_REMINDER=$(printf '%s' "$REMINDER" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    printf '{"systemMessage":"Librarian active","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$ESCAPED_REMINDER"
  fi
  exit 0
fi
log "File: $FILE_PATH"

# Find the memory library: try LIBRARIAN_PATH first, then walk up from file
MEMORY_LIB=""
PROJECT_DIR=""

if [ -n "${LIBRARIAN_PATH:-}" ] && [ -d "$LIBRARIAN_PATH" ]; then
  MEMORY_LIB="$LIBRARIAN_PATH"
  PROJECT_DIR="${LIBRARIAN_PATH%/_memory_library}"
  if [ "$PROJECT_DIR" = "$LIBRARIAN_PATH" ]; then
    # LIBRARIAN_PATH doesn't end with /_memory_library, use parent
    PROJECT_DIR=$(dirname "$LIBRARIAN_PATH")
  fi
  log "Using configured LIBRARIAN_PATH: $MEMORY_LIB"
else
  # Fall back: walk up from the file's directory
  FILE_DIR=$(dirname "$FILE_PATH")
  SEARCH_DIR="$FILE_DIR"
  while true; do
    if [ -d "$SEARCH_DIR/_memory_library" ]; then
      PROJECT_DIR="$SEARCH_DIR"
      MEMORY_LIB="$SEARCH_DIR/_memory_library"
      break
    fi
    PARENT=$(dirname "$SEARCH_DIR")
    if [ "$PARENT" = "$SEARCH_DIR" ]; then
      break
    fi
    SEARCH_DIR="$PARENT"
  done
fi

if [ -z "$MEMORY_LIB" ]; then
  log "No memory library found"
  exit 0
fi

# Compute relative path
REL_PATH="${FILE_PATH#"$PROJECT_DIR"/}"
if [ "$REL_PATH" = "$FILE_PATH" ]; then
  exit 0
fi

REL_DIR=$(dirname "$REL_PATH")

# Collect .md files walking up the tree
CONTEXT=""
FILES_LIST=""
CURRENT_DIR="$REL_DIR"
VISITED_ROOT=false

while true; do
  if [ "$CURRENT_DIR" = "." ]; then
    MIRROR_DIR="$MEMORY_LIB"
    DISPLAY_PREFIX="global"
    VISITED_ROOT=true
  else
    MIRROR_DIR="$MEMORY_LIB/$CURRENT_DIR"
    DISPLAY_PREFIX="$CURRENT_DIR"
  fi

  if [ -d "$MIRROR_DIR" ]; then
    for md_file in "$MIRROR_DIR"/*.md; do
      if [ -f "$md_file" ]; then
        BASENAME=$(basename "$md_file")
        if [ "$BASENAME" = ".scratch.md" ]; then
          continue
        fi
        CONTEXT="$CONTEXT
--- [$DISPLAY_PREFIX/$BASENAME] ---
$(cat "$md_file")
"
        if [ -n "$FILES_LIST" ]; then
          FILES_LIST="$FILES_LIST, $DISPLAY_PREFIX/$BASENAME"
        else
          FILES_LIST="$DISPLAY_PREFIX/$BASENAME"
        fi
      fi
    done
  fi

  if [ "$CURRENT_DIR" = "." ]; then
    break
  fi
  PARENT_DIR=$(dirname "$CURRENT_DIR")
  if [ "$PARENT_DIR" = "$CURRENT_DIR" ]; then
    break
  fi
  CURRENT_DIR="$PARENT_DIR"
done

# Read root if walk-up didn't reach it
if [ "$VISITED_ROOT" = false ]; then
  for md_file in "$MEMORY_LIB"/*.md; do
    if [ -f "$md_file" ]; then
      BASENAME=$(basename "$md_file")
      if [ "$BASENAME" = ".scratch.md" ]; then
        continue
      fi
      CONTEXT="$CONTEXT
--- [global/$BASENAME] ---
$(cat "$md_file")
"
      if [ -n "$FILES_LIST" ]; then
        FILES_LIST="$FILES_LIST, global/$BASENAME"
      else
        FILES_LIST="global/$BASENAME"
      fi
    fi
  done
fi

# Output JSON with additionalContext
if [ -n "$CONTEXT" ]; then
  MD_COUNT=$(echo "$CONTEXT" | grep -c '^\-\-\-' || true)
  log "Injecting $MD_COUNT files for $REL_PATH: $FILES_LIST"

  FULL_CONTEXT="[Librarian] Context for $REL_PATH (files: $FILES_LIST):
$CONTEXT"
  # Escape for JSON: backslashes, quotes, newlines, tabs
  ESCAPED=$(printf '%s' "$FULL_CONTEXT" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
  printf '{"systemMessage":"Librarian injected context","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"%s"}}\n' "$ESCAPED"
fi

exit 0
