---
description: Analyze diary entries to identify patterns and update CLAUDE.md
---

# Reflect on Diary Entries

Analyze diary entries from `./.claude/diary/` to identify patterns and update `./CLAUDE.md`.

## Parameters

**$ARGUMENTS**: {{ arguments }}

Parse the following from `$ARGUMENTS`:

| Parameter | Example | Description |
|-----------|---------|-------------|
| `last N entries` | `last 5 entries` | Analyze N most recent entries (default: 10) |
| `from YYYY-MM-DD to YYYY-MM-DD` | `from 2025-01-01 to 2025-01-31` | Date range filter |
| `last N days` | `last 7 days` | Entries from last N days |
| `related to KEYWORD` | `related to testing` | Filter by keyword in content |
| `include recovery` | `include recovery` | Include auto-generated recovery files from `recovery/` |
| `include all processed` | `include all processed` | Include all entries from `processed/` |
| `include processed PATTERN` | `include processed 2025-01*` | Include matching entries from `processed/` |

**Examples:**
```
/reflect                              # Last 10 unprocessed manual diary entries
/reflect last 20 entries              # Last 20 unprocessed entries
/reflect from 2025-01-01 to 2025-01-15
/reflect last 7 days
/reflect related to React
/reflect last 5 entries related to testing
/reflect include recovery             # Include auto-generated recovery files
/reflect include all processed        # Include all already-analyzed entries
/reflect include processed 2025-01*   # Include specific processed entries
```

## Steps

### Step 1: List diary entries

**Default** (unprocessed manual diary entries only):
```bash
ls -1 ./.claude/diary/*.md 2>/dev/null | sort -r
```

**With `include recovery`**:
```bash
ls -1 ./.claude/diary/*.md ./.claude/diary/recovery/*.md 2>/dev/null | sort -r
```

**With `include all processed`**:
```bash
ls -1 ./.claude/diary/*.md ./.claude/diary/processed/*.md 2>/dev/null | sort -r
```

**With `include processed PATTERN`**:
```bash
ls -1 ./.claude/diary/*.md ./.claude/diary/processed/PATTERN 2>/dev/null | sort -r
```

Note: Unprocessed entries are in `.claude/diary/`. Processed entries are in `.claude/diary/processed/`. Recovery files are in `.claude/diary/recovery/`.

### Step 2: Filter entries

Apply filters from `$ARGUMENTS`:
1. **Entry count**: Take N most recent
2. **Date range**: Filter by filename date prefix (YYYY-MM-DD)
3. **Days filter**: Calculate date threshold
4. **Keyword filter**: grep for keyword in file content

### Step 3: Read and analyze entries

For each filtered entry:
1. Read the file content
2. Extract sections: Task Summary, Design Decisions, User Preferences, Challenges, Patterns
3. Build a list of observations

### Step 4: Pattern recognition

Identify patterns across entries:
- **2+ occurrences** = emerging pattern
- **3+ occurrences** = strong pattern
- **1 occurrence** = one-off (note but don't add to CLAUDE.md)

Categories to analyze:
1. **User Preferences** - Commits, PRs, testing, code style
2. **Design Decisions That Worked** - Successful approaches
3. **Anti-Patterns** - Things that failed or needed rework
4. **Code Patterns** - Technical patterns worth standardizing

### Step 5: Check existing CLAUDE.md

Read `./CLAUDE.md` to:
- Avoid duplicate rules
- Detect if diary entries show violations of existing rules (HIGH PRIORITY)
- Understand existing structure/sections

### Step 6: Generate reflection document

Check if `.claude/diary/reflections/` exists using Glob, then create directory only if needed:
```bash
mkdir ./.claude/diary/reflections
```

Save to `./.claude/diary/reflections/YYYY-MM-DD-HH-MM-reflection-N.md`:

```markdown
# Reflection: [Date Range or "Last N Entries"]

**Generated**: YYYY-MM-DD HH:MM
**Entries Analyzed**: [count]
**Date Range**: [first] to [last]

## Summary
[2-3 paragraphs of key insights]

## Patterns Identified

### Strong Patterns (3+ occurrences)
1. **Pattern Name** (X/Y entries)
   - Observation: ...
   - CLAUDE.md rule: `- [actionable rule]`

### Emerging Patterns (2 occurrences)
1. **Pattern Name** (2/Y entries)
   - Observation: ...
   - CLAUDE.md rule: `- [actionable rule]`

### Rule Violations Detected
[If existing CLAUDE.md rules were violated in diary entries]
- Rule: ...
- Violation: ...
- Action: Strengthen rule

## Proposed CLAUDE.md Updates

### [Section Name]
```
- [Succinct actionable rule 1]
- [Succinct actionable rule 2]
```

## One-Off Observations
[Single occurrences - not patterns yet]

## Metadata
- Entries analyzed: [list]
```

### Step 7: Update CLAUDE.md

1. **Strengthen violated rules** (edit existing rules to be more explicit)
2. **Add new rules** (append to appropriate sections)
3. **Keep rules succinct**: One line, imperative tone, no verbose explanations

**Good rule format:**
```markdown
- git commits: use conventional format (feat:, fix:, refactor:)
- testing: always run tests before committing
- React: prefer functional components with hooks
```

**Bad rule format:**
```markdown
- When creating git commits, you should always use the conventional
  commit format which includes prefixes...
```

### Step 8: Move processed entries

Move analyzed diary entries (not recovery files) to `processed/`:
```bash
mkdir ./.claude/diary/processed
mv ./.claude/diary/FILENAME ./.claude/diary/processed/
```

Note: Recovery files stay in `recovery/` - they have separate cleanup.

### Step 9: Summary

Report to user:
- How many entries analyzed
- Patterns found (strong vs emerging)
- Rules added/strengthened in CLAUDE.md
- Reflection file location

## Error Handling

- No diary entries in `.claude/diary/`: Inform user, suggest running `/diary` first
- No unprocessed entries: Inform user, suggest `include all processed` to re-analyze
- Fewer than 3 entries: Proceed but note low confidence
- CLAUDE.md doesn't exist: Create it with new rules
- `processed/` doesn't exist: Create it when first moving entries
