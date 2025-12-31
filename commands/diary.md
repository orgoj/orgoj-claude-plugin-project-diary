---
description: Create a structured diary entry from the current session
---

# Create Diary Entry

You will create a structured diary entry documenting this session.

## Parameters

The command accepts an optional filepath parameter:
- `/diary` - Generate filename automatically: `./.claude/diary/YYYY-MM-DD-HH-MM-RANDOM.md`
- `/diary /path/to/file.md` - Use the specified filepath (from hook)

**$ARGUMENTS**: {{ arguments }}

## Filename Handling

1. If `$ARGUMENTS` contains a filepath (ends with `.md`), use that filepath exactly
2. If `$ARGUMENTS` is empty or doesn't contain a filepath:
   - Generate: `./.claude/diary/YYYY-MM-DD-HH-MM-$(head -c 6 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 6).md`
   - Create directory if needed: `mkdir -p ./.claude/diary`

## Approach: Context-First

Reflect on the conversation history in this session. You have access to:
- All user messages and requests
- Your responses and tool invocations
- Files you read, edited, or wrote
- Errors encountered and solutions applied
- Design decisions discussed
- User preferences expressed

## Diary Entry Template

Create a markdown file with this structure:

```markdown
# Session Diary

**Date**: YYYY-MM-DD HH:MM
**Session ID**: [from filename or generated]
**Project**: {{ cwd }}
**Git Branch**: [run: git branch --show-current]

## Task Summary
[2-3 sentences: What was the user trying to accomplish?]

## Work Done
- [Bullet list of accomplishments]
- Features implemented
- Bugs fixed
- Files modified

## Design Decisions
[Key technical decisions and WHY they were made]
- Decision 1: because...
- Decision 2: because...

## Challenges & Solutions
| Challenge | Solution |
|-----------|----------|
| Problem 1 | How it was solved |

## User Preferences Observed
[CRITICAL: Document ALL preferences - commits, testing, code style]

### Git & PR Preferences:
- [Commit message style, PR format]

### Code Quality Preferences:
- [Testing, linting, formatting]

### Technical Preferences:
- [Libraries, patterns, frameworks]

## Code Patterns Used
[Technical patterns worth remembering]

## Notes
[Any other observations]
```

## Steps

1. **Determine filepath**: Check `$ARGUMENTS` for provided path or generate new one
2. **Create directory**: `mkdir -p ./.claude/diary` if needed
3. **Gather context**: Review conversation history
4. **Get git branch**: Run `git branch --show-current 2>/dev/null || echo "unknown"`
5. **Write diary**: Use Write tool to save the diary entry
6. **Confirm**: Display the saved filepath

## Guidelines

- Be factual and specific (file paths, error messages, exact commands)
- Capture the "why" behind decisions
- Document ALL user preferences (especially commits, PRs, testing)
- Include failures as learning opportunities
- Keep it structured and scannable
