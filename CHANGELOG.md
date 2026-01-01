# Changelog

All notable changes to this project will be documented in this file.

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
