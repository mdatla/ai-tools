#!/usr/bin/env bash
# Librarian Stop Hook (macOS/Linux)
# Phase 1: Syncs auto-memory → .scratch.md
# Phase 2: Routes scratch entries → library files via [TAG: path, type: file]

# --- Logging (set to false to disable) ---
LIBRARIAN_LOG_ENABLED=true
LIBRARIAN_LOG_FILE="$HOME/.claude/librarian.log"

log() {
  if [ "$LIBRARIAN_LOG_ENABLED" = true ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [write] $1" >> "$LIBRARIAN_LOG_FILE"
  fi
}

set -uo pipefail

INPUT=$(cat)
log "Hook fired"

# Extract cwd from JSON
PROJECT_DIR=$(echo "$INPUT" | grep -o '"cwd":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$PROJECT_DIR" ]; then
  log "No cwd found, skipping"
  exit 0
fi
log "Project: $PROJECT_DIR"

MEMORY_LIB="$PROJECT_DIR/_memory_library"

if [ ! -d "$MEMORY_LIB" ]; then
  log "No _memory_library/, skipping"
  exit 0
fi

SCRATCH="$MEMORY_LIB/.scratch.md"

# --- Phase 1: Sync auto-memory to scratch ---

ENCODED_PATH=$(echo "$PROJECT_DIR" | sed 's|[/.]|-|g')
AUTO_MEMORY_DIR="$HOME/.claude/projects/${ENCODED_PATH}/memory"

if [ -d "$AUTO_MEMORY_DIR" ]; then
  log "Phase 1: Scanning $AUTO_MEMORY_DIR"
  RECENT_FILES=$(find "$AUTO_MEMORY_DIR" -name "*.md" -not -name "MEMORY.md" -mmin -120 2>/dev/null || true)

  for mem_file in $RECENT_FILES; do
    # Parse YAML frontmatter
    MEM_NAME=""
    MEM_TYPE=""
    IN_FRONTMATTER=false
    BODY=""
    PAST_FRONTMATTER=false
    FRONTMATTER_DASHES=0

    while IFS= read -r line; do
      if [ "$line" = "---" ]; then
        FRONTMATTER_DASHES=$((FRONTMATTER_DASHES + 1))
        if [ "$FRONTMATTER_DASHES" -eq 1 ]; then
          IN_FRONTMATTER=true
          continue
        elif [ "$FRONTMATTER_DASHES" -eq 2 ]; then
          IN_FRONTMATTER=false
          PAST_FRONTMATTER=true
          continue
        fi
      fi
      if [ "$IN_FRONTMATTER" = true ]; then
        case "$line" in
          name:*) MEM_NAME=$(echo "$line" | sed 's/^name:[[:space:]]*//');;
          type:*) MEM_TYPE=$(echo "$line" | sed 's/^type:[[:space:]]*//');;
        esac
      elif [ "$PAST_FRONTMATTER" = true ] && [ -n "$line" ]; then
        if [ -z "$BODY" ]; then
          BODY="$line"
        fi
      fi
    done < "$mem_file"

    # Skip user-type memories
    if [ "$MEM_TYPE" = "user" ]; then
      continue
    fi
    if [ -z "$MEM_NAME" ]; then
      continue
    fi

    # Dedup: check scratch and all library files
    ALREADY_EXISTS=false
    if [ -f "$SCRATCH" ]; then
      grep -qF "$MEM_NAME" "$SCRATCH" 2>/dev/null && ALREADY_EXISTS=true
    fi
    if [ "$ALREADY_EXISTS" = false ]; then
      while IFS= read -r check_file; do
        if [ "$(basename "$check_file")" != ".scratch.md" ]; then
          grep -qF "$MEM_NAME" "$check_file" 2>/dev/null && ALREADY_EXISTS=true && break
        fi
      done < <(find "$MEMORY_LIB" -name "*.md" -type f 2>/dev/null)
    fi
    if [ "$ALREADY_EXISTS" = true ]; then
      continue
    fi

    # Map auto-memory type to library file type
    LIBRARY_TYPE="patterns"
    case "$MEM_TYPE" in
      feedback) LIBRARY_TYPE="patterns";;
      project)  LIBRARY_TYPE="product";;
      reference) LIBRARY_TYPE="tech";;
    esac

    log "Phase 1: Synced '${MEM_NAME}' (${MEM_TYPE} -> ${LIBRARY_TYPE})"
    {
      echo "## [TAG: global, type: ${LIBRARY_TYPE}]"
      echo "- ${MEM_NAME}: ${BODY}"
      echo ""
    } >> "$SCRATCH"
  done
fi

# --- Phase 2: Process scratch entries ---

if [ ! -f "$SCRATCH" ] || [ ! -s "$SCRATCH" ]; then
  log "Phase 2: Scratch empty"
  exit 0
fi

log "Phase 2: Processing scratch"
TODAY=$(date +%Y-%m-%d)
UNPROCESSED_FILE=$(mktemp)
CURRENT_CONTENT_FILE=$(mktemp)
trap 'rm -f "$UNPROCESSED_FILE" "$CURRENT_CONTENT_FILE"' EXIT

process_tag() {
  local tag_path="$1"
  local tag_type="$2"
  local content_file="$3"

  if [ -z "$tag_path" ] || [ -z "$tag_type" ] || [ ! -s "$content_file" ]; then
    return
  fi

  local target_dir
  if [ "$tag_path" = "global" ]; then
    target_dir="$MEMORY_LIB"
  else
    target_dir="$MEMORY_LIB/$tag_path"
  fi

  local target_file="$target_dir/${tag_type}.md"
  local learning_count
  learning_count=$(grep -c '^-' "$content_file" || true)

  mkdir -p "$target_dir"

  if [ ! -f "$target_file" ]; then
    log "Phase 2: Creating $target_file"
    echo "# ${tag_type}" > "$target_file"
  fi

  log "Phase 2: Routed $learning_count entries -> $target_file"
  {
    echo ""
    echo "## Session Learnings ($TODAY)"
    cat "$content_file"
  } >> "$target_file"
}

# Parse scratch entries
CURRENT_TAG_PATH=""
CURRENT_TAG_TYPE=""
while IFS= read -r line || [ -n "$line" ]; do
  if echo "$line" | grep -qE '^\#\#[[:space:]]*\[TAG:'; then
    # Process previous tag
    process_tag "$CURRENT_TAG_PATH" "$CURRENT_TAG_TYPE" "$CURRENT_CONTENT_FILE"

    # Parse new tag
    if echo "$line" | grep -q 'type:'; then
      CURRENT_TAG_PATH=$(echo "$line" | sed -E 's/^##[[:space:]]*\[TAG:[[:space:]]*([^,]+),.*/\1/' | sed 's/[[:space:]]*$//')
      CURRENT_TAG_TYPE=$(echo "$line" | sed -E 's/.*type:[[:space:]]*([^]]+)\].*/\1/' | sed 's/[[:space:]]*$//')
    else
      CURRENT_TAG_PATH=$(echo "$line" | sed -E 's/^##[[:space:]]*\[TAG:[[:space:]]*(.*)\][[:space:]]*/\1/')
      CURRENT_TAG_TYPE=""
    fi
    > "$CURRENT_CONTENT_FILE"
  elif [ -n "$CURRENT_TAG_PATH" ] && [ -n "$line" ]; then
    echo "$line" >> "$CURRENT_CONTENT_FILE"
  fi
done < "$SCRATCH"

# Process last tag
process_tag "$CURRENT_TAG_PATH" "$CURRENT_TAG_TYPE" "$CURRENT_CONTENT_FILE"

# Collect legacy (no type) entries back to scratch
> "$UNPROCESSED_FILE"
CURRENT_TAG_PATH=""
CURRENT_TAG_TYPE=""
CURRENT_LEGACY_CONTENT=""
while IFS= read -r line || [ -n "$line" ]; do
  if echo "$line" | grep -qE '^\#\#[[:space:]]*\[TAG:'; then
    if [ -n "$CURRENT_TAG_PATH" ] && [ -z "$CURRENT_TAG_TYPE" ] && [ -n "$CURRENT_LEGACY_CONTENT" ]; then
      echo "## [TAG: $CURRENT_TAG_PATH]" >> "$UNPROCESSED_FILE"
      echo "$CURRENT_LEGACY_CONTENT" >> "$UNPROCESSED_FILE"
      echo "" >> "$UNPROCESSED_FILE"
    fi
    if echo "$line" | grep -q 'type:'; then
      CURRENT_TAG_PATH=""
      CURRENT_TAG_TYPE="has_type"
      CURRENT_LEGACY_CONTENT=""
    else
      CURRENT_TAG_PATH=$(echo "$line" | sed -E 's/^##[[:space:]]*\[TAG:[[:space:]]*(.*)\][[:space:]]*/\1/')
      CURRENT_TAG_TYPE=""
      CURRENT_LEGACY_CONTENT=""
    fi
  elif [ -n "$CURRENT_TAG_PATH" ] && [ -z "$CURRENT_TAG_TYPE" ] && [ -n "$line" ]; then
    CURRENT_LEGACY_CONTENT="${CURRENT_LEGACY_CONTENT}
${line}"
  fi
done < "$SCRATCH"
if [ -n "$CURRENT_TAG_PATH" ] && [ -z "$CURRENT_TAG_TYPE" ] && [ -n "$CURRENT_LEGACY_CONTENT" ]; then
  echo "## [TAG: $CURRENT_TAG_PATH]" >> "$UNPROCESSED_FILE"
  echo "$CURRENT_LEGACY_CONTENT" >> "$UNPROCESSED_FILE"
  echo "" >> "$UNPROCESSED_FILE"
fi

if [ -s "$UNPROCESSED_FILE" ]; then
  cp "$UNPROCESSED_FILE" "$SCRATCH"
else
  > "$SCRATCH"
fi

log "Done"
exit 0
