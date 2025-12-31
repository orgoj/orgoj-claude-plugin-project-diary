#!/usr/bin/env bash
# Project Diary Hook Script
# Handles: pre-compact, session-end, session-start

set -e

# Check jq dependency
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed" >&2
  exit 1
fi

# Read JSON from stdin
HOOK_DATA=$(cat 2>/dev/null || true)

# Parse JSON fields using jq
SESSION_ID=$(echo "$HOOK_DATA" | jq -r '.session_id // empty')
CWD=$(echo "$HOOK_DATA" | jq -r '.cwd // empty')
SOURCE=$(echo "$HOOK_DATA" | jq -r '.source // empty')  # For SessionStart: startup|resume|clear|compact
HOOK_EVENT=$1  # pre-compact | session-end | session-start

# Fallback for CWD
if [ -z "$CWD" ]; then
  CWD="$(pwd)"
fi

# Fallback for SESSION_ID (generate random if empty)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(head -c 6 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 6)
fi

# Diary directory (project-local)
DIARY_DIR="${CWD}/.claude/diary"

# Generate filename: YYYY-MM-DD-HH-MM-SESSIONID.md
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
FILENAME="${TIMESTAMP}-${SESSION_ID}.md"
FILEPATH="${DIARY_DIR}/${FILENAME}"

case "$HOOK_EVENT" in
  "pre-compact"|"session-end")
    # Ensure diary directory exists
    mkdir -p "$DIARY_DIR"

    # Output command for Claude to execute
    # Hook outputs /diary with the target filename
    echo "/diary ${FILEPATH}"
    ;;

  "session-start")
    # Output session ID to context (Claude will see this)
    echo "<session-info>"
    echo "SESSION_ID: ${SESSION_ID}"
    echo "PROJECT: ${CWD}"
    echo "</session-info>"

    # Load diary context only after compact
    if [ "$SOURCE" = "compact" ]; then
      if [ -d "$DIARY_DIR" ] && [ -n "$SESSION_ID" ]; then
        DIARY_FILE=$(find "$DIARY_DIR" -maxdepth 1 -name "*-${SESSION_ID}.md" -type f 2>/dev/null | head -1)
        if [ -n "$DIARY_FILE" ] && [ -f "$DIARY_FILE" ]; then
          echo "<diary-context>"
          echo "Previous session diary:"
          echo ""
          cat "$DIARY_FILE"
          echo "</diary-context>"
        fi
      fi
    fi
    ;;
esac
