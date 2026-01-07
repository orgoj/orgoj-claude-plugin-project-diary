#!/usr/bin/env bash
# Project Diary Hook Script
# Handles: pre-compact, session-end, session-start

set -e

# Check jq dependency
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed" >&2
  exit 1
fi

# Parse arguments
PROJECT_ROOT=""
HOOK_EVENT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --project-dir)
      PROJECT_ROOT="$2"
      shift 2
      ;;
    pre-compact|session-end|session-start)
      HOOK_EVENT="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Read JSON from stdin
HOOK_DATA=$(cat 2>/dev/null || true)

# Parse JSON fields using jq
SESSION_ID=$(echo "$HOOK_DATA" | jq -r '.session_id // empty')
SOURCE=$(echo "$HOOK_DATA" | jq -r '.source // empty')  # For SessionStart: startup|resume|clear|compact

# Fallback for PROJECT_ROOT
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(pwd)"
fi

# Fallback for SESSION_ID (generate random if empty)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(head -c 6 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 6)
fi

# Diary directory (project-local)
DIARY_DIR="${PROJECT_ROOT}/.claude/diary"

# Generate filename: YYYY-MM-DD-HH-MM-SESSIONID.md
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
FILENAME="${TIMESTAMP}-${SESSION_ID}.md"
FILEPATH="${DIARY_DIR}/${FILENAME}"

# Get script directory for finding mopc binary
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$HOOK_EVENT" in
  "pre-compact"|"session-end")
    # Call mopc recovery with hook data via stdin
    # Try to find mopc binary relative to hook script
    MOPC_BIN="${SCRIPT_DIR}/../zig-out/bin/mopc"

    if [ ! -f "$MOPC_BIN" ]; then
      # Fallback: try global installation
      MOPC_BIN="mopc"
      if ! command -v mopc &>/dev/null; then
        echo "Error: mopc binary not found at ${SCRIPT_DIR}/../zig-out/bin/mopc" >&2
        echo "Please run 'zig build' to build the project" >&2
        exit 1
      fi
    fi

    # Pass hook data via stdin to mopc recovery command
    echo "$HOOK_DATA" | "$MOPC_BIN" recovery
    ;;

  "session-start")
    # Build context string with XML tags for clear parsing
    CONTEXT="<session-info>
SESSION_ID: ${SESSION_ID}
PROJECT: ${PROJECT_ROOT}
</session-info>"

    # Load recovery context only after compact
    RECOVERY_DIR="${DIARY_DIR}/recovery"
    if [ "$SOURCE" = "compact" ]; then
      if [ -d "$RECOVERY_DIR" ] && [ -n "$SESSION_ID" ]; then
        # Get newest recovery file for this session (sorted by name desc = newest timestamp first)
        RECOVERY_FILE=$(find "$RECOVERY_DIR" -maxdepth 1 -name "*-${SESSION_ID}.md" -type f 2>/dev/null | sort -r | head -1)
        if [ -n "$RECOVERY_FILE" ] && [ -f "$RECOVERY_FILE" ]; then
          RECOVERY_CONTENT=$(cat "$RECOVERY_FILE")
          CONTEXT="${CONTEXT}

<recovery-context>
Previous session recovery:

${RECOVERY_CONTENT}
</recovery-context>"
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
