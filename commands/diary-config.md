---
description: Configure recovery generator settings interactively
---

# Configure Diary Recovery Settings

Create or update `.claude/diary/.config.json` with recovery settings.

## Current Defaults

| Setting | Default | Description |
|---------|---------|-------------|
| minActivity | 1 | Minimum activity score to generate recovery |
| userPrompts | 5 | Number of recent prompts to save |
| promptLength | 150 | Max characters per prompt |
| toolCalls | 10 | Number of recent tool calls to save |
| lastMessageLength | 500 | Max characters for last assistant message |
| errors | 5 | Number of recent errors to save |

Activity score = prompts + toolCalls + filesModified + todos

## Steps

1. **Check existing config**: Read `.claude/diary/.config.json` if it exists

2. **Ask all questions at once** using AskUserQuestion tool with these questions:

   - **minActivity**: What minimum activity level to generate recovery?
     - 1 (Recommended) - any activity saves
     - 2 - skip very short sessions
     - 0 - always save (even empty)

   - **userPrompts**: How many recent prompts to save?
     - 5 (Recommended)
     - 3
     - 10

   - **promptLength**: Max characters per prompt?
     - 150 (Recommended)
     - 100
     - 300

   - **toolCalls**: How many recent tool calls to save?
     - 10 (Recommended)
     - 5
     - 20

   - **lastMessageLength**: Max chars for last context?
     - 500 (Recommended)
     - 300
     - 1000

   - **errors**: How many recent errors to save?
     - 5 (Recommended)
     - 3
     - 10

3. **Write config file**:
   Check if `.claude/diary/` exists using Glob, then create directory only if needed:
   ```bash
   mkdir .claude/diary
   ```

   Write `.claude/diary/.config.json`:
   ```json
   {
     "recovery": {
       "minActivity": [selected value],
       "limits": {
         "userPrompts": [selected value],
         "promptLength": [selected value],
         "toolCalls": [selected value],
         "lastMessageLength": [selected value],
         "errors": [selected value]
       }
     }
   }
   ```

4. **Confirm**: Display saved config summary

## Notes

- If user selects "Other", ask for custom numeric value
- Config affects `recovery-generator.js` hook behavior
- Sessions with activity below minActivity won't generate recovery files
