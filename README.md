# Project Diary Plugin

A Claude Code plugin for project-local session diaries with reflection to CLAUDE.md.

## Features

- **Project-local storage**: Diary entries stored in `./.claude/diary/` (not global)
- **Session ID tracking**: Multiple Claude sessions can run without conflicts
- **Automatic recovery**: PreCompact/SessionEnd hooks parse transcript and generate recovery files
- **Context restoration**: After compact, previous recovery content is loaded into context
- **Idle time detection**: Notifies Claude when significant time passed between responses
- **Wrapper script**: `bin/claude-diary` for automatic diary/reflect at session start/end
- **Manual diary**: `/diary` command for structured session documentation
- **Intelligent reflection**: `/reflect` analyzes patterns and updates CLAUDE.md
- **Configurable recovery**: `/diary-config` to customize recovery limits and skip empty sessions

## Installation

```bash
# Add marketplace
/plugin marketplace add orgoj/orgoj-claude-plugin-project-diary

# Install plugin
/plugin install project-diary@orgoj-project-diary

# Restart Claude Code
```

## Usage

### Wrapper Script (Recommended)

Use `bin/claude-diary` wrapper for automatic diary management:

```bash
# Start Claude with automatic diary prompts
bin/claude-diary

# Pass arguments to Claude CLI
bin/claude-diary --model sonnet "fix the bug"
```

**What it does:**
1. **On start**: Checks for unprocessed diaries → offers/auto `/reflect`
2. **During**: Runs normal Claude session with generated session ID
3. **On end**: Offers/auto `/diary` in same session (maintains context)

**Configuration** (via `/diary-config`):
```json
{
  "wrapper": {
    "autoDiary": false,        // Auto-run /diary without asking
    "autoReflect": false,      // Auto-run /reflect without asking
    "askBeforeDiary": true,    // Show prompt before /diary
    "askBeforeReflect": true   // Show prompt before /reflect
  }
}
```

### Direct Claude CLI

Run Claude normally and use commands manually:

```bash
claude code
# Use /diary and /reflect manually
```

### /diary [FILEPATH]

Create a diary entry from the current session.

```bash
# Manual diary (auto-generates filename)
/diary

# With specific filepath (used by hooks)
/diary ./.claude/diary/2025-12-31-14-30-abc123.md
```

**Diary location**: `./.claude/diary/YYYY-MM-DD-HH-MM-SESSIONID.md`

**Diary sections**:
- Task Summary, Work Done, Design Decisions
- Challenges & Solutions
- **Mistakes & Corrections** - what went wrong, where user corrected Claude
- **Lessons Learned** - technical/process insights to remember
- User Preferences, Code Patterns, Notes

### /reflect [PARAMS]

Analyze diary entries and update CLAUDE.md.

```bash
# Default: last 10 unprocessed entries
/reflect

# Last N entries
/reflect last 20 entries

# Date range
/reflect from 2025-01-01 to 2025-01-31

# Last N days
/reflect last 7 days

# Filter by keyword
/reflect related to React

# Combine filters
/reflect last 5 entries related to testing

# Include already processed entries
/reflect include processed

# Reprocess specific entry
/reflect reprocess 2025-01-01-10-30-abc123.md
```

### /diary-config

Configure recovery generator and idle time detection settings interactively.

```bash
/diary-config
```

Creates `.claude/diary/.config.json` with settings for:
- **Recovery settings**: minActivity, data limits (prompts, tool calls, errors, etc.)
- **Idle time detection**: Enable/disable, threshold in minutes
- **Wrapper settings**: Auto-modes and prompts for `bin/claude-diary`

## How It Works

### Hooks

| Event | Action |
|-------|--------|
| SessionStart | Outputs session ID to context (`<session-info>`) |
| SessionStart (after compact) | Also loads previous recovery into context (`<recovery-context>`) |
| PreCompact | Creates recovery file before context compaction |
| SessionEnd | Creates recovery file when session ends |
| Stop | Saves timestamp for idle time detection |
| UserPromptSubmit | Checks idle time and injects notification if threshold exceeded |

### Data Flow

```
SessionStart → outputs SESSION_ID to context
PreCompact/SessionEnd → hook parses transcript → generates recovery markdown
SessionStart (compact) → loads previous recovery into context
Manual /diary → Claude writes diary (uses SESSION_ID from context)
Stop → saves timestamp
UserPromptSubmit → checks idle time → injects notification if threshold exceeded
```

### Idle Time Detection

When enabled via `/diary-config`, the plugin tracks time between Claude's responses:

1. **Stop hook**: Saves current timestamp to `.claude/diary/timestamps/{SESSION_ID}.txt`
2. **User is idle**: User switches context, takes a break, etc.
3. **User returns**: Submits new prompt
4. **UserPromptSubmit hook**: Calculates `now - last_stop`
5. **If threshold exceeded**: Injects notification into context:
   ```
   Uplynulo X minut od poslední odpovědi. Zvažte ověření aktuálního stavu.
   ```

**Example scenario:**
- User asks "status?" → Claude responds
- User leaves for 20 minutes
- User returns and asks "status?" again
- Plugin injects: "Uplynulo 20 minut od poslední odpovědi..."
- Claude knows to re-check actual status instead of repeating old information

**Configuration:**
- `idleTime.enabled`: true (default) | false
- `idleTime.thresholdMinutes`: 5 (default) | 10 | 15

### Recovery vs Diary

| Type | Location | Generated by | Purpose |
|------|----------|--------------|---------|
| **Recovery** | `.claude/diary/recovery/` | Hooks (auto) | Context restoration after compact |
| **Diary** | `.claude/diary/` | `/diary` command (manual) | Structured session documentation |

### Recovery Content (auto-generated)

Extracted from transcript JSONL:
- **Quick Insights**: Main task, status, activity stats, error count (at top for rapid context)
- **What Was Asked**: User prompts
- **Task State**: TodoWrite status (completed/in-progress/pending)
- **Files Modified**: From Edit/Write tool calls
- **Recent Actions**: Last 10 tool calls with status
- **Errors**: Bash failures and errors
- **Last Context**: Last assistant message (truncated)

### Pattern Recognition

`/reflect` identifies:
- **Strong patterns** (3+ occurrences) → Added to CLAUDE.md
- **Emerging patterns** (2 occurrences) → Added to CLAUDE.md
- **One-off observations** → Noted but not added

## Directory Structure

```
your-project/
├── bin/
│   └── claude-diary                       # Wrapper script (optional)
├── .claude/
│   ├── settings.local.json                # Temp permissions (wrapper only)
│   └── diary/
│       ├── .config.json                   # Optional config (/diary-config)
│       ├── 2025-12-31-14-30-abc123.md     # Manual diary (/diary command)
│       ├── 2025-12-31-16-45-def456.md
│       ├── processed/                     # Analyzed entries (moved by /reflect)
│       │   └── 2025-12-31-14-30-abc123.md
│       ├── recovery/                      # Auto-generated (hooks)
│       │   ├── 2025-12-31-14-00-abc123.md
│       │   └── 2025-12-31-16-00-def456.md
│       ├── timestamps/                    # Idle time tracking (hooks)
│       │   └── abc123.txt                 # Epoch timestamp of last Stop
│       └── reflections/
│           └── 2025-12-31-14-30-reflection-1.md    # Reflection documents
└── CLAUDE.md                              # Updated by /reflect
```

## Requirements

- Claude Code CLI
- Node.js (for transcript parsing)
- `jq` (for JSON processing in hooks)

## Credits

Inspired by:
- [claude-diary](https://github.com/rlancemartin/claude-diary) by rlancemartin
- [Continuous-Claude-v2](https://github.com/parcadei/Continuous-Claude-v2) - transcript parsing approach

Key differences from claude-diary:
- Project-local instead of global storage
- Session ID in filenames for multi-session support
- Auto-generated diary from transcript (no Claude call needed)
- Plugin format (just install, no manual setup)

## License

MIT
