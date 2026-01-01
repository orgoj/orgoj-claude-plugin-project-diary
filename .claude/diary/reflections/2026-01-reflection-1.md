# Reflection: Last 5 Entries

**Generated**: 2026-01-01 12:30
**Entries Analyzed**: 5
**Date Range**: 2026-01-01-01-04 to 2026-01-01-12-15

## Summary

These diary entries document the development of the project-diary plugin itself. Key themes include: clarifying the conceptual distinction between auto-generated "recovery" files and manual "diary" entries, fixing bugs in JSONL transcript parsing, and adding new features (Mistakes/Lessons sections, bump-version command).

A recurring challenge is correctly distinguishing between plugin distribution files (`commands/`) and project-local development tools (`.claude/commands/`). Users expect version bumps and CHANGELOG updates to happen atomically with feature commits, not as separate commits.

## Patterns Identified

### Strong Patterns (3+ occurrences)

1. **Version + CHANGELOG before commit** (4/5 entries)
   - Observation: Every feature/fix commit must include version bump and CHANGELOG update in same commit
   - CLAUDE.md rule: `- version: bump + CHANGELOG update must be in same commit as feature`

2. **Conventional commits** (4/5 entries)
   - Observation: User consistently uses feat:, fix:, chore: prefixes
   - Already documented implicitly; strengthen

3. **README must reflect current state** (3/5 entries)
   - Observation: When features change, README must document actual behavior, not just version numbers
   - CLAUDE.md rule: `- README: update feature documentation when behavior changes, not just versions`

### Emerging Patterns (2 occurrences)

1. **Plugin vs project-local commands** (2/5 entries)
   - Observation: `commands/` = distributed with plugin; `.claude/commands/` = local dev workflow
   - CLAUDE.md rule: `- commands: dev workflow tools go in .claude/commands/, plugin features go in commands/`

2. **Check skill descriptions before invoking** (2/5 entries)
   - Observation: Wrong skill choice wastes time; read descriptions carefully
   - CLAUDE.md rule: `- skills: read description carefully before invoking, match to actual task`

3. **Clear concept separation** (2/5 entries)
   - Observation: Naming matters - "recovery" vs "diary" confusion was fixed; clear naming prevents confusion
   - One-off for this project, but worth noting

### Rule Violations Detected

None detected against existing CLAUDE.md rules.

## Proposed CLAUDE.md Updates

### New Section: User Preferences

```
## User Preferences

- version: bump + CHANGELOG update must be in same commit as feature
- README: update feature documentation when behavior changes, not just versions
- commands: dev workflow tools go in .claude/commands/, plugin features go in commands/
- skills: read description carefully before invoking, match to actual task
- commits: conventional format (feat:, fix:, chore:) with English messages
- push: wait for explicit user confirmation before pushing
```

## One-Off Observations

- Pure JavaScript preferred over TypeScript (no build step)
- Czech communication language
- `sort -r | head -1` pattern for newest file by timestamp in filename
- BREAKING changes must be marked in CHANGELOG
- User verifies changes in IDE during session

## Metadata

- Entries analyzed:
  - 2026-01-01-12-15-15f1ec75.md
  - 2026-01-01-10-59-23cb107d-b56b-496e-a5a3-7b05f316e19b.md
  - 2026-01-01-10-15-23cb107d-b56b-496e-a5a3-7b05f316e19b.md
  - 2026-01-01-09-24-b81454c7-129d-45c7-be19-28dd8bf1df7a.md
  - 2026-01-01-01-04-b81454c7-129d-45c7-be19-28dd8bf1df7a.md
