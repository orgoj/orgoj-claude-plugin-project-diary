# Changelog

All notable changes to this project will be documented in this file.

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
