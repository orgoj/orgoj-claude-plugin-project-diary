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

# Get script directory for calling diary-generator.js
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$HOOK_EVENT" in
  "pre-compact"|"session-end")
    # Check node dependency
    if ! command -v node &>/dev/null; then
      echo "Error: node is required but not installed" >&2
      exit 1
    fi

    # Call diary-generator.js with hook data via stdin
    echo "$HOOK_DATA" | node "${SCRIPT_DIR}/diary-generator.js"
    ;;

  "session-start")
    # Build context string with XML tags for clear parsing
    CONTEXT="<session-info>
SESSION_ID: ${SESSION_ID}
PROJECT: ${CWD}
</session-info>"

    # Load diary context only after compact
    if [ "$SOURCE" = "compact" ]; then
      if [ -d "$DIARY_DIR" ] && [ -n "$SESSION_ID" ]; then
        DIARY_FILE=$(find "$DIARY_DIR" -maxdepth 1 -name "*-${SESSION_ID}.md" -type f 2>/dev/null | head -1)
        if [ -n "$DIARY_FILE" ] && [ -f "$DIARY_FILE" ]; then
          DIARY_CONTENT=$(cat "$DIARY_FILE")
          CONTEXT="${CONTEXT}

<diary-context>
Previous session diary:

${DIARY_CONTENT}
</diary-context>"
        fi
      fi
    fi

    # Output JSON format for SessionStart hook using jq for proper escaping
    jq -n --arg ctx "$CONTEXT" '{
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: $ctx
      }
    }'
    ;;
esac
