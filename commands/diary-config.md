---
description: Configure recovery generator settings interactively
---

# Configure Diary Recovery Settings

Create or update `.claude/diary/.config.json` with recovery settings.

## Current Defaults

### Recovery Settings

| Setting | Default | Description |
|---------|---------|-------------|
| minActivity | 1 | Minimum activity score to generate recovery |
| userPrompts | 5 | Number of recent prompts to save |
| promptLength | 150 | Max characters per prompt |
| toolCalls | 10 | Number of recent tool calls to save |
| lastMessageLength | 500 | Max characters for last assistant message |
| errors | 5 | Number of recent errors to save |

Activity score = prompts + toolCalls + filesModified + todos

### Idle Time Detection Settings

| Setting | Default | Description |
|---------|---------|-------------|
| enabled | true | Enable idle time detection (default: enabled) |
| thresholdMinutes | 5 | Minutes of idle time before notification |

### Wrapper Settings (for bin/claude-diary)

| Setting | Default | Description |
|---------|---------|-------------|
| autoDiary | false | Auto-run /diary without asking |
| autoReflect | false | Auto-run /reflect without asking |
| askBeforeDiary | true | Prompt before running /diary |
| askBeforeReflect | true | Prompt before running /reflect |
| minSessionSize | 2 | Minimum session size (KB) to offer diary |

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

   - **idleTime.enabled**: Enable idle time detection?
     - true (Recommended) - enabled by default
     - false - disable time tracking

   - **idleTime.thresholdMinutes**: Idle threshold in minutes?
     - 5 (Recommended)
     - 10
     - 15

   - **wrapper.autoDiary**: Auto-run /diary without asking?
     - false (Recommended) - ask before running
     - true - always run

   - **wrapper.autoReflect**: Auto-run /reflect without asking?
     - false (Recommended) - ask before running
     - true - always run

   - **wrapper.askBeforeDiary**: Prompt before running /diary?
     - true (Recommended) - show prompt
     - false - skip prompt (respect autoDiary)

   - **wrapper.askBeforeReflect**: Prompt before running /reflect?
     - true (Recommended) - show prompt
     - false - skip prompt (respect autoReflect)

   - **wrapper.minSessionSize**: Minimum session size (KB)?
     - 2 (Recommended) - skip tiny sessions
     - 0 - always offer diary
     - 10 - only substantial sessions

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
     },
     "idleTime": {
       "enabled": [selected value],
       "thresholdMinutes": [selected value]
     },
     "wrapper": {
       "autoDiary": [selected value],
       "autoReflect": [selected value],
       "askBeforeDiary": [selected value],
       "askBeforeReflect": [selected value],
       "minSessionSize": [selected value]
     }
   }
   ```

4. **Confirm**: Display saved config summary

## Notes

- If user selects "Other", ask for custom numeric value
- Config affects `recovery-generator.js` hook behavior
- Sessions with activity below minActivity won't generate recovery files
- Idle time detection requires `idleTime.enabled: true` to function
- When enabled, tracks time between Stop hooks and notifies on new prompts if idle exceeds threshold
