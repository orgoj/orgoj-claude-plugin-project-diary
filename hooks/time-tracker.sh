#!/usr/bin/env bash
# Time Tracker Hook Script
# Tracks idle time between Stop hooks and UserPromptSubmit
# Handles: stop, prompt

set -e

# Parse arguments
PROJECT_ROOT=""
COMMAND=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --project-dir)
      PROJECT_ROOT="$2"
      shift 2
      ;;
    stop|prompt)
      COMMAND="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Read hook input
HOOK_DATA=$(cat 2>/dev/null || true)
SESSION_ID=$(echo "$HOOK_DATA" | jq -r '.session_id // empty')

if [ -z "$SESSION_ID" ]; then
  exit 0
fi

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(pwd)"
fi

TIMESTAMP_DIR="${PROJECT_ROOT}/.claude/diary/timestamps"
mkdir -p "$TIMESTAMP_DIR"

case "$COMMAND" in
  "stop")
    date +%s > "${TIMESTAMP_DIR}/${SESSION_ID}.txt"
    ;;

  "prompt")
    CONFIG_FILE="${PROJECT_ROOT}/.claude/diary/.config.json"
    if [ ! -f "$CONFIG_FILE" ]; then
      exit 0
    fi

    ENABLED=$(jq -r '.idleTime.enabled // false' "$CONFIG_FILE")
    if [ "$ENABLED" != "true" ]; then
      exit 0
    fi

    THRESHOLD=$(jq -r '.idleTime.thresholdMinutes // 5' "$CONFIG_FILE")

    TIMESTAMP_FILE="${TIMESTAMP_DIR}/${SESSION_ID}.txt"
    if [ ! -f "$TIMESTAMP_FILE" ]; then
      exit 0
    fi

    LAST_STOP=$(cat "$TIMESTAMP_FILE")
    NOW=$(date +%s)
    DIFF=$((NOW - LAST_STOP))
    MINUTES=$((DIFF / 60))

    if [ $MINUTES -ge $THRESHOLD ]; then
      MESSAGE="Uplynulo ${MINUTES} minut od poslední odpovědi. Zvažte ověření aktuálního stavu."
      jq -n --arg msg "$MESSAGE" '{
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: $msg
        }
      }'
    fi
    ;;
esac
