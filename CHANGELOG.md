# Changelog

All notable changes to this project will be documented in this file.

## [1.14.0] - 2026-01-08

### Changed
- **Wrapper permissions now path-scoped** - improved security and reduced permission prompts
  - Main session: No auto-permissions (user confirms each action as needed)
  - `/reflect`: Restricted to `CLAUDE.md` and `.claude/diary/**` only
  - `/diary`: Restricted to `.claude/diary/*.md` only
- Removed global `allowedTools` from wrapper temp settings
- Temp settings now created per-command with specific path-based permissions

### Security
- **Reduced permission scope** - wrapper commands can only write to their designated directories
- Main session requires explicit user approval for all file operations

### Fixed
- **CRITICAL: Debug logging feature now works** - config parsing was missing
  - `parseConfig()` now reads "debug" section from JSON files
  - `mergeConfigs()` now properly merges debug settings in config cascade
  - Previously: `mopc debug enable` saved config but hooks never loaded it
  - Now: Debug logging works when enabled, config cascade functions correctly
- **Version sync**: plugin.json updated to match main.zig (1.14.0)
- **Improved error messages** in recovery.zig with better context for debugging
  - JSON parse errors now show input source (stdin/hook) and length
  - Missing field errors now list available fields

### Documentation
- **Fixed CLAUDE.md architecture diagram** - now matches actual implementation
  - Removed references to non-existent bash wrapper scripts
  - Shows actual symlink structure: `bin/mopc` and `hooks/mopc` → `zig-out/bin/mopc`
  - Documents `hooks/session-start.js` (Node.js requirement)
- **Clarified Node.js dependency** in README and CLAUDE.md
  - SessionStart hook requires Node.js runtime (provided by Claude Code)
  - Compatible with Bun as Node.js replacement
  - Updated "zero dependencies" claim to "minimal dependencies"
- **Fixed diary-config.md** - corrected reference from `recovery-generator.js` to `mopc recovery`

### Technical Details
```json
// /reflect permissions
{
  "permissions": {
    "Write(CLAUDE.md)": "allow",
    "Write(.claude/diary/reflections/*.md)": "allow",
    "Write(.claude/diary/processed/*.md)": "allow",
    "Bash(mv .claude/diary/*.md .claude/diary/processed/*)": "allow",
    "Bash(mkdir -p .claude/diary/*)": "allow"
  }
}

// /diary permissions
{
  "permissions": {
    "Write(.claude/diary/*.md)": "allow",
    "Bash(mkdir -p .claude/diary)": "allow"
  }
}
```

## [1.13.0] - 2026-01-08

### Added
- **Two-level debug logging system** for comprehensive hook debugging
- **Debug CLI commands**: `mopc debug enable/disable/view/clear`
- **Level 1 logging (debug.logOurHooks)**: Logs our implemented hooks (SessionStart, PreCompact, SessionEnd, Stop, UserPromptSubmit)
  - Captures: timestamp, stdin, argv, environment, output, duration, errors
  - Integrated into hook.zig and tracker.zig
- **Level 2 logging (debug.logAllHooks)**: Catch-all handler for ALL Claude Code hook events
  - Logs: PostToolUse, PreToolUse, PreAssistantMessage, PostAssistantMessage
  - Plus all our hooks for complete system visibility
- **JSONL log format** at `.claude/diary/debug/hooks.jsonl`
- **Debug module** (src/shared/debug.zig): HookLogEntry struct and JSONL logger
- **Catch-all hook handler** (src/commands/debug_hook.zig): Logs all system hooks when enabled
- **Config cascade support** for debug settings (home → workspace → project)
- Debug settings default to **disabled** (opt-in for privacy)

### Usage
```bash
mopc debug enable --our-hooks     # Log our hooks only
mopc debug enable --all-hooks     # Log everything (complete debugging)
mopc debug view --tail 100        # View last 100 log entries
mopc debug disable                # Turn off logging
mopc debug clear                  # Clear log file
```

## [1.12.0] - 2026-01-06

### Added
- **Wrapper script (`bin/claude-diary`)** - automatic diary management for Claude sessions
- Session ID generation and continuity using `--session-id` and `--resume` flags
- Auto-detect unprocessed diaries on start → offers/auto `/reflect` in separate session
- Auto-prompt for `/diary` at session end → runs in same session (maintains full context)
- **Minimum session size check** - skips diary prompt for tiny sessions (default: 2 KB)
- **Minimum diary count check** - skips reflect prompt when too few diaries (default: 1)
- **Wrapper CLI options** - `--min-session-size`, `--min-diary-count`, `--auto-diary`, `--auto-reflect`
- **Argument separator (`--`)** - clean separation of wrapper and Claude options
- Wrapper config settings: `autoDiary`, `autoReflect`, `askBeforeDiary`, `askBeforeReflect`, `minSessionSize`, `minDiaryCount`
- Permission management via temporary `.claude/settings.local.json`
- Pass-through support for all Claude CLI arguments

### Changed
- `/diary-config` now includes wrapper settings section
- Documentation updated with wrapper usage examples and configuration

### Fixed
- **Wrapper now checks only diary files for `/reflect`** - recovery files are excluded
- Recovery system is separate from diary/reflect workflow

## [1.11.0] - 2026-01-05

### Fixed
- **Idle time detection now enabled by default** - previously required explicit config
- Changed `idleTime.enabled` default from `false` to `true`
- Feature now works out-of-the-box without requiring `/diary-config`
- Can be disabled by setting `idleTime.enabled: false` in config
- Gracefully handles missing config file (no silent failures)

## [1.10.0] - 2026-01-05

### Added
- **Idle time detection** - tracks time between Stop hooks and UserPromptSubmit
- Automatic notification when user returns after extended idle period
- Helps Claude understand context switches and time gaps
- Configurable via `/diary-config` with `idleTime.enabled` and `idleTime.thresholdMinutes`
- Example: After 20 minute break, Claude receives "Uplynulo 20 minut od poslední odpovědi" note

### Changed
- All hook commands now use `--project-dir` argument instead of cwd from hook input
- Ensures correct project root detection regardless of current working directory
- Updated `diary-hook.sh`, `time-tracker.sh` to accept `--project-dir` argument

### Fixed
- Timestamp storage uses simple text format (epoch seconds) instead of JSON
- KISS principle: just `date +%s > file` instead of complex JSON parsing
- Timestamps stored in `.claude/diary/timestamps/{SESSION_ID}.txt`

## [1.9.0] - 2026-01-02

### Changed
- Reflection filename format now uses full timestamp: `YYYY-MM-DD-HH-MM-reflection-N.md`
- Prevents filename collisions when running multiple reflections per day
- Previous format `YYYY-MM-reflection-N.md` could overwrite earlier reflections

### Fixed
- Replaced `mkdir -p` with directory existence checks in all commands
- Commands now check directory existence with Glob/Read tools before creating
- Eliminates unnecessary confirmation prompts for directory creation
- Affected commands: `/diary`, `/diary-config`, `/reflect`

## [1.8.0] - 2026-01-01

### Added
- **Quick Insights** section at the start of recovery files for rapid context understanding
- Displays main task, status (In Progress/Completed), activity stats, and error count
- Helps Claude quickly grasp session state after context compaction without reading entire recovery

## [1.7.0] - 2026-01-01

### Added
- `/diary-config` command for interactive configuration of recovery settings
- Configurable recovery limits via `.claude/diary/.config.json`
- `minActivity` threshold to skip empty/minimal sessions (default: 1)
- Configurable limits for: userPrompts, promptLength, toolCalls, lastMessageLength, errors
- `findProjectRoot()` to correctly locate config regardless of cwd

### Changed
- Recovery generator now reads config from project root, not cwd
- All hardcoded limits replaced with configurable values

## [1.6.0] - 2026-01-01

### Changed
- **BREAKING**: Replaced `processed.log` with `processed/` directory
- Processed diary entries are now moved to `.claude/diary/processed/` after reflection
- Simplified tracking: unprocessed = `diary/*.md`, processed = `diary/processed/*.md`

### Added
- `include all processed` parameter to re-analyze all processed entries
- `include processed PATTERN` parameter to re-analyze matching processed entries

### Removed
- `processed.log` file no longer used
- `reprocess FILENAME` parameter (just move file back to diary/ manually)
- `include processed` without argument (use `include all processed` instead)

## [1.5.0] - 2026-01-01

### Added
- `/diary` now includes "Mistakes & Corrections" section for honest error tracking
- `/diary` now includes "Lessons Learned" section with technical/process lessons
- New subsection "To Remember for CLAUDE.md" for capturing insights to persist

## [1.4.0] - 2026-01-01

### Changed
- **BREAKING**: Separated auto-generated context recovery from manual diary
- Renamed `diary-generator.js` to `recovery-generator.js`
- Recovery files now stored in `.claude/diary/recovery/` (was `.claude/diary/`)
- SessionStart loads `<recovery-context>` instead of `<diary-context>`

### Added
- `/reflect include recovery` parameter to optionally analyze recovery files
- Clear documentation distinguishing recovery (auto) vs diary (manual)

### Migration
- Existing `.claude/diary/*.md` files created by hooks will not be moved automatically
- New recovery files will be created in `.claude/diary/recovery/`

## [1.3.2] - 2026-01-01

### Fixed
- SessionStart after compact now loads newest diary (was loading first alphabetically)
- Added `sort -r` to get most recent diary file when multiple exist for same session

## [1.3.1] - 2026-01-01

### Fixed
- Transcript parser now correctly matches JSONL structure
- User prompts extracted from `entry.type === "user"` with `entry.message.content`
- Tool calls extracted from `entry.message.content[].type === "tool_use"`
- Previously diary was empty because parser looked for wrong field names

## [1.3.0] - 2026-01-01

### Added
- `diary-generator.js` - Pure JavaScript transcript parser
- Auto-generated diary from transcript JSONL (no Claude API call needed)
- Diary includes: user prompts, task state, files modified, tool calls, errors

### Changed
- PreCompact/SessionEnd hooks now parse transcript directly instead of calling `/diary`
- Diary generation is instant (no LLM call required)

### Dependencies
- Added Node.js requirement for transcript parsing

## [1.2.0] - 2025-12-31

### Fixed
- SessionStart hook now uses JSON `hookSpecificOutput.additionalContext` format
- Session ID properly appears in Claude's context

## [1.1.0] - 2025-12-31

### Added
- SessionStart hook outputs session ID to context
- Context restoration after compact (loads previous diary)

### Fixed
- Marketplace name collision resolved
- GitHub repo path for marketplace add

## [1.0.0] - 2025-12-31

### Added
- Initial release
- `/diary` command for manual diary creation
- `/reflect` command for pattern analysis
- Project-local diary storage in `.claude/diary/`
- Session ID tracking in filenames
- PreCompact, SessionEnd, SessionStart hooks
