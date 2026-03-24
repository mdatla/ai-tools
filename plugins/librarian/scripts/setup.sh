#!/usr/bin/env bash
# Librarian Setup Script (macOS/Linux)
# Detects OS and writes hook configuration to .claude/settings.local.json
# Uses $CLAUDE_PLUGIN_ROOT to locate hook scripts within the plugin.

set -euo pipefail

# When run from the plugin, CLAUDE_PLUGIN_ROOT is set automatically.
# When run manually, derive from script location.
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  CLAUDE_PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# Project dir: find the repo root (where .claude/ lives or should live)
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  PROJECT_DIR="$CLAUDE_PROJECT_DIR"
else
  PROJECT_DIR="$(pwd)"
fi

SETTINGS_FILE="$PROJECT_DIR/.claude/settings.local.json"
mkdir -p "$PROJECT_DIR/.claude"

echo "Librarian Setup"
echo "==============="
echo "Project: $PROJECT_DIR"
echo "Plugin:  $CLAUDE_PLUGIN_ROOT"
echo "Platform: $(uname -s)"
echo ""

# Determine hook commands based on OS
OS="$(uname -s)"
case "$OS" in
  Darwin|Linux)
    READ_CMD="\${CLAUDE_PLUGIN_ROOT}/scripts/librarian-read.sh"
    WRITE_CMD="\${CLAUDE_PLUGIN_ROOT}/scripts/librarian-write.sh"
    echo "Detected macOS/Linux — using .sh scripts"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    READ_CMD="powershell -ExecutionPolicy Bypass -File \"\${CLAUDE_PLUGIN_ROOT}/scripts/librarian-read.ps1\""
    WRITE_CMD="powershell -ExecutionPolicy Bypass -File \"\${CLAUDE_PLUGIN_ROOT}/scripts/librarian-write.ps1\""
    echo "Detected Windows (Git Bash) — using .ps1 scripts"
    ;;
  *)
    echo "Unknown OS: $OS — defaulting to .sh scripts"
    READ_CMD="\${CLAUDE_PLUGIN_ROOT}/scripts/librarian-read.sh"
    WRITE_CMD="\${CLAUDE_PLUGIN_ROOT}/scripts/librarian-write.sh"
    ;;
esac

# Check for jq (required by hook scripts)
if ! command -v jq &> /dev/null; then
  echo ""
  echo "WARNING: jq is not installed. The hook scripts require jq for JSON parsing."
  echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
  echo ""
fi

# Read existing settings or start with empty object
if [ -f "$SETTINGS_FILE" ]; then
  EXISTING=$(cat "$SETTINGS_FILE")
  echo "Found existing settings.local.json — merging hooks"
else
  EXISTING='{}'
  echo "No existing settings.local.json — creating new"
fi

# Build hook config JSON
HOOK_CONFIG=$(cat <<HOOKEOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$READ_CMD",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$WRITE_CMD",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
HOOKEOF
)

# Deep merge: existing settings + hook config (hooks overwrite, rest preserved)
MERGED=$(echo "$EXISTING" | jq --argjson hooks "$(echo "$HOOK_CONFIG" | jq '.hooks')" '. * {hooks: $hooks}')

echo "$MERGED" | jq '.' > "$SETTINGS_FILE"

# Create _memory_library directory if it doesn't exist
if [ ! -d "$PROJECT_DIR/_memory_library" ]; then
  mkdir -p "$PROJECT_DIR/_memory_library"
  touch "$PROJECT_DIR/_memory_library/.scratch.md"
  echo "Created _memory_library/ directory"
fi

echo ""
echo "Hooks configured in: $SETTINGS_FILE"
echo ""
echo "Pre-tool hook (Edit|Write): $READ_CMD"
echo "Stop hook: $WRITE_CMD"
echo ""
echo "Setup complete! The Librarian is now active."
