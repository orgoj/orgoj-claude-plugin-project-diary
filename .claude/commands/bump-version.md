---
description: Bump version, update CHANGELOG with changes since last version, update README if needed
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git tag:*), Bash(git show:*), Read, Edit
argument-hint: [patch|minor|major]
---

# Bump Version

Increase version number in all version files, update CHANGELOG with changes since last version.

## Parameters

**$ARGUMENTS**: {{ arguments }}

| Parameter | Default | Description |
|-----------|---------|-------------|
| `patch` | ✓ | Bump patch version (1.4.0 → 1.4.1) |
| `minor` | | Bump minor version (1.4.0 → 1.5.0) |
| `major` | | Bump major version (1.4.0 → 2.0.0) |

## Context

- Current plugin version: !`jq -r '.version' .claude-plugin/plugin.json 2>/dev/null || echo "unknown"`
- Git tags: !`git tag --sort=-v:refname | head -5 2>/dev/null || echo "no tags"`
- Last tag: !`git describe --tags --abbrev=0 2>/dev/null || echo "no tags"`
- Current branch: !`git branch --show-current`

## Steps

### Step 1: Determine current version

Read `.claude-plugin/plugin.json` to get current version.

### Step 2: Calculate new version

Parse `$ARGUMENTS` (default: `patch`):
- `patch`: X.Y.Z → X.Y.(Z+1)
- `minor`: X.Y.Z → X.(Y+1).0
- `major`: X.Y.Z → (X+1).0.0

### Step 3: Get changes since last version

Find changes since last git tag or last version in CHANGELOG:

```bash
# If tags exist
git log $(git describe --tags --abbrev=0)..HEAD --oneline

# If no tags, compare with previous CHANGELOG version
git log --oneline -20
```

Categorize changes by reading commit messages and git diff:
- **Added**: New features, commands, hooks
- **Changed**: Modified behavior, breaking changes
- **Fixed**: Bug fixes
- **Removed**: Removed features

### Step 4: Update version files

Update version in these files:
1. `.claude-plugin/plugin.json` - `"version": "X.Y.Z"`
2. `.claude-plugin/marketplace.json` - `"metadata": { "version": "X.Y.Z" }`

### Step 5: Update CHANGELOG.md

Prepend new version section after header:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- [new features]

### Changed
- [changes, breaking changes marked with **BREAKING**]

### Fixed
- [bug fixes]
```

Keep existing changelog entries below.

### Step 6: Update README.md

README must accurately describe the current state of the application. Review changes and update README accordingly:

1. **Feature documentation**: If new features were added, document them
2. **Command descriptions**: If command behavior changed, update usage examples
3. **Section descriptions**: If output format changed (e.g. new diary sections), update docs
4. **Installation/requirements**: If dependencies changed, update
5. **Version badges**: If present, update version numbers

Compare git diff with README content - any mismatch means README needs update.

### Step 7: Summary

Report:
- Previous version → New version
- Files updated
- CHANGELOG entries added
- Suggest: `git add -A && git commit -m "chore: bump version to X.Y.Z"`

## Guidelines

- Use conventional changelog format (Keep a Changelog)
- Mark breaking changes with **BREAKING**
- Be concise in changelog entries
- Don't include commit hashes in changelog
- Group related changes together
