#!/usr/bin/env node
/**
 * Recovery Generator - Pure JavaScript transcript parser
 *
 * Parses Claude Code JSONL transcripts and generates session recovery markdown.
 * Used for context restoration after compact. Inspired by Continuous-Claude-v2.
 */

const fs = require('fs');
const path = require('path');

// ============================================================================
// Configuration
// ============================================================================

const DEFAULTS = {
  minActivity: 1,
  limits: {
    userPrompts: 5,
    promptLength: 150,
    toolCalls: 10,
    lastMessageLength: 500,
    errors: 5
  }
};

function findProjectRoot(startDir) {
  let dir = startDir;

  while (dir !== path.dirname(dir)) {
    if (fs.existsSync(path.join(dir, '.claude'))) {
      return dir;
    }
    dir = path.dirname(dir);
  }

  return startDir;
}

function loadConfig(projectRoot) {
  const configPath = path.join(projectRoot, '.claude', 'diary', '.config.json');

  if (!fs.existsSync(configPath)) {
    return DEFAULTS;
  }

  try {
    const userConfig = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
    const recovery = userConfig.recovery || {};

    return {
      minActivity: recovery.minActivity ?? DEFAULTS.minActivity,
      limits: { ...DEFAULTS.limits, ...recovery.limits }
    };
  } catch {
    return DEFAULTS;
  }
}

// ============================================================================
// Transcript Parsing
// ============================================================================

function parseTranscript(transcriptPath, limits = DEFAULTS.limits) {
  const summary = {
    lastTodos: [],
    recentToolCalls: [],
    lastAssistantMessage: '',
    filesModified: [],
    errorsEncountered: [],
    userPrompts: []
  };

  if (!fs.existsSync(transcriptPath)) {
    return summary;
  }

  const content = fs.readFileSync(transcriptPath, 'utf-8');
  const lines = content.split('\n').filter(line => line.trim());

  const allToolCalls = [];
  const modifiedFiles = new Set();
  const errors = [];
  let lastTodoState = [];
  let lastAssistant = '';
  const prompts = [];

  // Map tool_use_id to tool call for linking results
  const toolCallById = new Map();

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);

      // JSONL format: entry.type = "user"|"assistant", entry.message.role, entry.message.content
      const entryType = entry.type;
      const message = entry.message;

      if (!message) continue;

      // Extract user prompts
      // User messages have entry.type === "user" and message.content is string
      if (entryType === 'user' && message.role === 'user') {
        const content = message.content;
        // Skip tool results (content is array with type: "tool_result")
        if (typeof content === 'string') {
          const prompt = content.substring(0, limits.promptLength);
          if (prompt && !prompt.startsWith('<')) { // Skip system messages
            prompts.push(prompt);
          }
        }
      }

      // Extract assistant messages and tool calls
      // Assistant messages have entry.type === "assistant" and message.content is array
      if (entryType === 'assistant' && message.role === 'assistant') {
        const content = message.content;
        if (Array.isArray(content)) {
          for (const block of content) {
            // Text blocks - track last assistant text
            if (block.type === 'text' && typeof block.text === 'string') {
              lastAssistant = block.text;
            }

            // Tool use blocks
            if (block.type === 'tool_use') {
              const toolName = block.name;
              const toolInput = block.input || {};
              const toolId = block.id;

              const toolCall = {
                name: toolName,
                timestamp: entry.timestamp,
                input: toolInput,
                success: true,
                id: toolId
              };

              // Track by ID for linking results
              if (toolId) {
                toolCallById.set(toolId, toolCall);
              }

              // Check for TodoWrite to capture state
              if (toolName === 'TodoWrite') {
                if (toolInput && toolInput.todos) {
                  lastTodoState = toolInput.todos.map((t, idx) => ({
                    id: t.id || `todo-${idx}`,
                    content: t.content || '',
                    status: t.status || 'pending'
                  }));
                }
              }

              // Track file modifications from Edit/Write tools
              if (toolName === 'Edit' || toolName === 'Write') {
                const filePath = toolInput.file_path || toolInput.path;
                if (filePath && typeof filePath === 'string') {
                  modifiedFiles.add(filePath);
                }
              }

              // Track Bash commands (truncate for readability)
              if (toolName === 'Bash') {
                const command = toolInput.command;
                if (command) {
                  toolCall.input = { command: command.substring(0, 100) };
                }
              }

              allToolCalls.push(toolCall);
            }
          }
        }
      }

      // Extract tool results (come as user messages with array content)
      if (entryType === 'user' && message.role === 'user' && Array.isArray(message.content)) {
        for (const block of message.content) {
          if (block.type === 'tool_result') {
            const toolId = block.tool_use_id;
            const resultContent = block.content;

            // Link to original tool call
            const originalCall = toolId ? toolCallById.get(toolId) : null;

            // Check for errors in result
            if (Array.isArray(resultContent)) {
              for (const item of resultContent) {
                if (item.type === 'text' && typeof item.text === 'string') {
                  const text = item.text.toLowerCase();
                  if (text.includes('error') || text.includes('failed') || text.includes('exit code')) {
                    if (originalCall) {
                      originalCall.success = false;
                    }
                    const errorMsg = item.text.substring(0, 150);
                    errors.push(errorMsg);
                  }
                }
              }
            }
          }
        }
      }

      // Also check toolUseResult field (alternative location)
      if (entry.toolUseResult) {
        const results = Array.isArray(entry.toolUseResult) ? entry.toolUseResult : [entry.toolUseResult];
        for (const result of results) {
          if (result.type === 'text' && typeof result.text === 'string') {
            const text = result.text.toLowerCase();
            if (text.includes('error') || text.includes('failed')) {
              const errorMsg = result.text.substring(0, 150);
              errors.push(errorMsg);
            }
          }
        }
      }

    } catch {
      // Skip malformed JSON lines
      continue;
    }
  }

  summary.lastTodos = lastTodoState;
  summary.recentToolCalls = allToolCalls.slice(-limits.toolCalls);
  summary.lastAssistantMessage = lastAssistant.substring(0, limits.lastMessageLength);
  summary.filesModified = Array.from(modifiedFiles);
  summary.errorsEncountered = errors.slice(-limits.errors);
  summary.userPrompts = prompts.slice(-limits.userPrompts);

  // Quick Insights data
  summary.mainTask = prompts.length > 0 ? prompts[0] : 'No user prompts';
  summary.incompleteTodos = lastTodoState.filter(t => t.status === 'pending' || t.status === 'in_progress').length;
  summary.totalTodos = lastTodoState.length;

  return summary;
}

// ============================================================================
// Recovery Generation
// ============================================================================

function generateRecovery(summary, sessionId, trigger, limits = DEFAULTS.limits) {
  const timestamp = new Date().toISOString();
  const lines = [];

  // YAML frontmatter
  lines.push('---');
  lines.push(`date: ${timestamp}`);
  lines.push(`session: ${sessionId}`);
  lines.push(`trigger: ${trigger}`);
  lines.push('---');
  lines.push('');

  // Header
  lines.push('# Session Recovery');
  lines.push('');

  // Quick Insights
  lines.push('## Quick Insights');
  lines.push('');

  // Main Task
  const taskPreview = summary.mainTask.length > 80
    ? summary.mainTask.substring(0, 80) + '...'
    : summary.mainTask;
  lines.push(`**Main Task**: ${taskPreview}`);
  lines.push('');

  // Status
  let status = 'No Activity';
  if (summary.totalTodos > 0) {
    status = summary.incompleteTodos > 0 ? 'In Progress' : 'Completed';
  }
  lines.push(`**Status**: ${status}`);
  lines.push('');

  // Activity stats
  lines.push(`**Activity**: ${summary.userPrompts.length} prompts, ` +
             `${summary.filesModified.length} files, ` +
             `${summary.totalTodos} todos`);
  lines.push('');

  // Errors
  if (summary.errorsEncountered.length > 0) {
    lines.push(`**Errors**: ${summary.errorsEncountered.length} encountered`);
    lines.push('');
  }

  lines.push('---');
  lines.push('');

  // User Prompts (what was asked)
  lines.push('## What Was Asked');
  lines.push('');
  if (summary.userPrompts.length > 0) {
    summary.userPrompts.forEach(p => {
      const truncated = p.length > 150 ? p.substring(0, 150) + '...' : p;
      lines.push(`- ${truncated}`);
    });
  } else {
    lines.push('No user prompts captured.');
  }
  lines.push('');

  // Task State (TodoWrite)
  lines.push('## Task State');
  lines.push('');
  if (summary.lastTodos.length > 0) {
    const inProgress = summary.lastTodos.filter(t => t.status === 'in_progress');
    const pending = summary.lastTodos.filter(t => t.status === 'pending');
    const completed = summary.lastTodos.filter(t => t.status === 'completed');

    if (completed.length > 0) {
      lines.push('**Completed:**');
      completed.forEach(t => lines.push(`- [x] ${t.content}`));
      lines.push('');
    }
    if (inProgress.length > 0) {
      lines.push('**In Progress:**');
      inProgress.forEach(t => lines.push(`- [>] ${t.content}`));
      lines.push('');
    }
    if (pending.length > 0) {
      lines.push('**Pending:**');
      pending.forEach(t => lines.push(`- [ ] ${t.content}`));
      lines.push('');
    }
  } else {
    lines.push('No TodoWrite state captured.');
    lines.push('');
  }

  // Files Modified
  lines.push('## Files Modified');
  lines.push('');
  if (summary.filesModified.length > 0) {
    summary.filesModified.forEach(f => lines.push(`- ${f}`));
  } else {
    lines.push('No files modified.');
  }
  lines.push('');

  // Recent Actions
  lines.push('## Recent Actions');
  lines.push('');
  if (summary.recentToolCalls.length > 0) {
    summary.recentToolCalls.forEach(tc => {
      const status = tc.success ? 'OK' : 'FAIL';
      let detail = '';
      if (tc.input) {
        if (tc.input.command) {
          detail = ` \`${tc.input.command}\``;
        } else if (tc.input.file_path) {
          detail = ` ${tc.input.file_path}`;
        }
      }
      lines.push(`- ${tc.name} [${status}]${detail}`);
    });
  } else {
    lines.push('No tool calls recorded.');
  }
  lines.push('');

  // Errors
  if (summary.errorsEncountered.length > 0) {
    lines.push('## Errors');
    lines.push('');
    summary.errorsEncountered.forEach(e => {
      lines.push('```');
      lines.push(e);
      lines.push('```');
    });
    lines.push('');
  }

  // Last Context
  if (summary.lastAssistantMessage) {
    lines.push('## Last Context');
    lines.push('');
    lines.push('```');
    lines.push(summary.lastAssistantMessage);
    if (summary.lastAssistantMessage.length >= limits.lastMessageLength) {
      lines.push('[... truncated]');
    }
    lines.push('```');
    lines.push('');
  }

  return lines.join('\n');
}

// ============================================================================
// Main
// ============================================================================

function main() {
  // Read hook input from stdin
  let input = '';
  try {
    input = fs.readFileSync(0, 'utf-8');
  } catch {
    console.error('Failed to read stdin');
    process.exit(1);
  }

  let hookData;
  try {
    hookData = JSON.parse(input);
  } catch {
    console.error('Invalid JSON input');
    process.exit(1);
  }

  const transcriptPath = hookData.transcript_path;
  const sessionId = hookData.session_id || 'unknown';
  const cwd = hookData.cwd || process.cwd();
  const trigger = hookData.trigger || hookData.hook_event_name || 'manual';

  if (!transcriptPath) {
    console.error('No transcript_path in input');
    process.exit(1);
  }

  // Find project root and load config
  const projectRoot = findProjectRoot(cwd);
  const config = loadConfig(projectRoot);

  // Parse transcript
  const summary = parseTranscript(transcriptPath, config.limits);

  // Check activity threshold
  const activity = summary.userPrompts.length
                 + summary.recentToolCalls.length
                 + summary.filesModified.length
                 + summary.lastTodos.length;

  if (activity < config.minActivity) {
    console.log(`Skipping recovery: activity ${activity} < minActivity ${config.minActivity}`);
    process.exit(0);
  }

  // Generate recovery markdown
  const recovery = generateRecovery(summary, sessionId, trigger, config.limits);

  // Create recovery directory
  const recoveryDir = path.join(projectRoot, '.claude', 'diary', 'recovery');
  if (!fs.existsSync(recoveryDir)) {
    fs.mkdirSync(recoveryDir, { recursive: true });
  }

  // Generate filename
  const now = new Date();
  const timestamp = now.toISOString().slice(0, 16).replace('T', '-').replace(':', '-');
  const filename = `${timestamp}-${sessionId}.md`;
  const filepath = path.join(recoveryDir, filename);

  // Check if file exists (from previous compact in same session)
  // If so, append instead of overwrite
  if (fs.existsSync(filepath)) {
    const separator = '\n\n---\n\n# Session Continued\n\n';
    const existingContent = fs.readFileSync(filepath, 'utf-8');
    // Remove frontmatter from new recovery for append
    const recoveryWithoutFrontmatter = recovery.replace(/^---[\s\S]*?---\n\n/, '');
    fs.writeFileSync(filepath, existingContent + separator + recoveryWithoutFrontmatter);
  } else {
    fs.writeFileSync(filepath, recovery);
  }

  console.log(`Recovery saved: ${filepath}`);
}

main();
