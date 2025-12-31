# Project Diary Plugin

A Claude Code plugin for project-local session diaries with reflection to CLAUDE.md.

## Features

- **Project-local storage**: Diary entries stored in `./.claude/diary/` (not global)
- **Session ID tracking**: Multiple Claude sessions can run without conflicts
- **Automatic diary**: Hooks trigger `/diary` on PreCompact and SessionEnd
- **Context restoration**: After compact, previous diary content is loaded
- **Intelligent reflection**: `/reflect` analyzes patterns and updates CLAUDE.md

## Installation

```bash
# Add marketplace
/plugin marketplace add /path/to/orgoj-claude-plugin-project-diary

# Install plugin
/plugin install project-diary@project-diary

# Restart Claude Code
```

## Usage

### /diary [FILEPATH]

Create a diary entry from the current session.

```bash
# Manual diary (auto-generates filename)
/diary

# With specific filepath (used by hooks)
/diary ./.claude/diary/2025-12-31-14-30-abc123.md
```

**Diary location**: `./.claude/diary/YYYY-MM-DD-HH-MM-SESSIONID.md`

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

## How It Works

### Hooks

| Event | Action |
|-------|--------|
| SessionStart | Outputs session ID to context (`<session-info>`) |
| SessionStart (after compact) | Also loads previous diary into context |
| PreCompact | Creates diary entry before context compaction |
| SessionEnd | Creates diary entry when session ends |

### Data Flow

```
SessionStart → outputs SESSION_ID to context
PreCompact/SessionEnd → hook outputs "/diary FILEPATH" → Claude creates diary
SessionStart (compact) → hook also outputs diary content → Claude has context
Manual /diary → uses SESSION_ID from context (or generates random)
```

### Pattern Recognition

`/reflect` identifies:
- **Strong patterns** (3+ occurrences) → Added to CLAUDE.md
- **Emerging patterns** (2 occurrences) → Added to CLAUDE.md
- **One-off observations** → Noted but not added

## Directory Structure

```
your-project/
├── .claude/
│   └── diary/
│       ├── 2025-12-31-14-30-abc123.md    # Session diaries
│       ├── 2025-12-31-16-45-def456.md
│       ├── processed.log                  # Tracks analyzed entries
│       └── reflections/
│           └── 2025-12-reflection-1.md    # Reflection documents
└── CLAUDE.md                              # Updated by /reflect
```

## Requirements

- Claude Code CLI
- `jq` (for JSON parsing in hooks)

## Credits

Inspired by [claude-diary](https://github.com/rlancemartin/claude-diary) by rlancemartin.

Key differences:
- Project-local instead of global storage
- Session ID in filenames for multi-session support
- Simplified `/reflect` for single project focus
- Plugin format (just install, no manual setup)

## License

MIT
