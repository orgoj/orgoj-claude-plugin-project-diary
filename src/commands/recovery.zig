const std = @import("std");
const config_mod = @import("../shared/config.zig");
const paths = @import("../shared/paths.zig");

// ============================================================================
// Data Structures
// ============================================================================

const Todo = struct {
    content: []const u8,
    status: []const u8,
};

const ToolCall = struct {
    name: []const u8,
    success: bool,
    detail: []const u8, // truncated input info (command, file_path)
};

const Summary = struct {
    user_prompts: std.ArrayList([]const u8),
    tool_calls: std.ArrayList(ToolCall),
    files_modified: std.StringHashMap(void),
    errors: std.ArrayList([]const u8),
    todos: std.ArrayList(Todo),
    last_assistant_message: []const u8,
    main_task: []const u8,

    fn init(allocator: std.mem.Allocator) Summary {
        return .{
            .user_prompts = std.ArrayList([]const u8).init(allocator),
            .tool_calls = std.ArrayList(ToolCall).init(allocator),
            .files_modified = std.StringHashMap(void).init(allocator),
            .errors = std.ArrayList([]const u8).init(allocator),
            .todos = std.ArrayList(Todo).init(allocator),
            .last_assistant_message = "",
            .main_task = "",
        };
    }

    fn deinit(self: *Summary) void {
        for (self.user_prompts.items) |prompt| {
            self.user_prompts.allocator.free(prompt);
        }
        self.user_prompts.deinit();

        for (self.tool_calls.items) |tool_call| {
            self.tool_calls.allocator.free(tool_call.name);
            self.tool_calls.allocator.free(tool_call.detail);
        }
        self.tool_calls.deinit();

        var it = self.files_modified.keyIterator();
        while (it.next()) |key| {
            self.files_modified.allocator.free(key.*);
        }
        self.files_modified.deinit();

        for (self.errors.items) |err| {
            self.errors.allocator.free(err);
        }
        self.errors.deinit();

        for (self.todos.items) |todo| {
            self.todos.allocator.free(todo.content);
            self.todos.allocator.free(todo.status);
        }
        self.todos.deinit();

        if (self.last_assistant_message.len > 0) {
            self.user_prompts.allocator.free(self.last_assistant_message);
        }
        if (self.main_task.len > 0) {
            self.user_prompts.allocator.free(self.main_task);
        }
    }
};

// ============================================================================
// Transcript Parsing
// ============================================================================

fn parseTranscript(
    allocator: std.mem.Allocator,
    transcript_path: []const u8,
    limits: config_mod.RecoveryLimits,
) !Summary {
    var summary = Summary.init(allocator);
    errdefer summary.deinit();

    // Read transcript file
    const file = std.fs.cwd().openFile(transcript_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return summary;
        }
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 100 * 1024 * 1024); // 100MB max
    defer allocator.free(content);

    // Map tool_use_id to index in tool_calls array
    var tool_call_map = std.StringHashMap(usize).init(allocator);
    defer {
        var it = tool_call_map.keyIterator();
        while (it.next()) |key| {
            allocator.free(key.*);
        }
        tool_call_map.deinit();
    }

    // Parse line by line
    var lines = std.mem.split(u8, content, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Parse JSON line
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            trimmed,
            .{ .ignore_unknown_fields = true },
        ) catch continue; // Skip malformed lines
        defer parsed.deinit();

        const entry = parsed.value.object;

        // Get entry type and message
        const entry_type = entry.get("type") orelse continue;
        const message_value = entry.get("message") orelse continue;
        const message = message_value.object;

        const role = message.get("role") orelse continue;
        const content_value = message.get("content") orelse continue;

        // USER MESSAGE - Extract prompts or tool results
        if (std.mem.eql(u8, entry_type.string, "user") and std.mem.eql(u8, role.string, "user")) {
            switch (content_value) {
                .string => |str| {
                    // User prompt
                    if (str.len > 0 and str[0] != '<') { // Skip system messages
                        const truncated = if (str.len > limits.promptLength)
                            str[0..limits.promptLength]
                        else
                            str;
                        const prompt = try allocator.dupe(u8, truncated);
                        try summary.user_prompts.append(prompt);

                        // Set main task from first prompt
                        if (summary.main_task.len == 0) {
                            summary.main_task = try allocator.dupe(u8, truncated);
                        }
                    }
                },
                .array => |arr| {
                    // Tool results - check for errors
                    for (arr.items) |item| {
                        if (item != .object) continue;
                        const block = item.object;

                        const block_type = block.get("type") orelse continue;
                        if (!std.mem.eql(u8, block_type.string, "tool_result")) continue;

                        // Get tool_use_id to link to original call
                        const tool_use_id = block.get("tool_use_id");
                        const result_content = block.get("content") orelse continue;

                        // Check for errors in result
                        if (result_content == .array) {
                            for (result_content.array.items) |result_item| {
                                if (result_item != .object) continue;
                                const result_obj = result_item.object;

                                const result_type = result_obj.get("type") orelse continue;
                                if (!std.mem.eql(u8, result_type.string, "text")) continue;

                                const text = result_obj.get("text") orelse continue;
                                const text_str = text.string;

                                // Check for error indicators
                                const lower = try std.ascii.allocLowerString(allocator, text_str);
                                defer allocator.free(lower);

                                if (std.mem.indexOf(u8, lower, "error") != null or
                                    std.mem.indexOf(u8, lower, "failed") != null or
                                    std.mem.indexOf(u8, lower, "exit code") != null)
                                {
                                    // Mark tool call as failed
                                    if (tool_use_id) |tid| {
                                        if (tool_call_map.get(tid.string)) |idx| {
                                            summary.tool_calls.items[idx].success = false;
                                        }
                                    }

                                    // Record error
                                    const truncated = if (text_str.len > 150)
                                        text_str[0..150]
                                    else
                                        text_str;
                                    const err_msg = try allocator.dupe(u8, truncated);
                                    try summary.errors.append(err_msg);
                                }
                            }
                        }
                    }
                },
                else => {},
            }
        }

        // ASSISTANT MESSAGE - Extract tool calls and text
        if (std.mem.eql(u8, entry_type.string, "assistant") and std.mem.eql(u8, role.string, "assistant")) {
            if (content_value != .array) continue;

            for (content_value.array.items) |item| {
                if (item != .object) continue;
                const block = item.object;

                const block_type = block.get("type") orelse continue;

                // Text block - track last assistant message
                if (std.mem.eql(u8, block_type.string, "text")) {
                    const text = block.get("text") orelse continue;
                    const text_str = text.string;

                    if (text_str.len > 0) {
                        if (summary.last_assistant_message.len > 0) {
                            allocator.free(summary.last_assistant_message);
                        }
                        const truncated = if (text_str.len > limits.lastMessageLength)
                            text_str[0..limits.lastMessageLength]
                        else
                            text_str;
                        summary.last_assistant_message = try allocator.dupe(u8, truncated);
                    }
                }

                // Tool use block
                if (std.mem.eql(u8, block_type.string, "tool_use")) {
                    const tool_name = block.get("name") orelse continue;
                    const tool_input = block.get("input");
                    const tool_id = block.get("id");

                    const name_str = tool_name.string;

                    // Extract detail based on tool type
                    var detail: []const u8 = "";
                    if (tool_input) |input| {
                        if (input == .object) {
                            const input_obj = input.object;

                            // Bash command
                            if (std.mem.eql(u8, name_str, "Bash")) {
                                if (input_obj.get("command")) |cmd| {
                                    const cmd_str = cmd.string;
                                    const truncated = if (cmd_str.len > 100)
                                        cmd_str[0..100]
                                    else
                                        cmd_str;
                                    detail = try allocator.dupe(u8, truncated);
                                }
                            }
                            // Edit/Write file path
                            else if (std.mem.eql(u8, name_str, "Edit") or std.mem.eql(u8, name_str, "Write")) {
                                if (input_obj.get("file_path")) |fp| {
                                    detail = try allocator.dupe(u8, fp.string);

                                    // Track modified file
                                    const file_path = try allocator.dupe(u8, fp.string);
                                    try summary.files_modified.put(file_path, {});
                                } else if (input_obj.get("path")) |p| {
                                    detail = try allocator.dupe(u8, p.string);

                                    const file_path = try allocator.dupe(u8, p.string);
                                    try summary.files_modified.put(file_path, {});
                                }
                            }
                            // TodoWrite - extract todos
                            else if (std.mem.eql(u8, name_str, "TodoWrite")) {
                                if (input_obj.get("todos")) |todos_value| {
                                    if (todos_value == .array) {
                                        // Clear previous todos
                                        for (summary.todos.items) |todo| {
                                            allocator.free(todo.content);
                                            allocator.free(todo.status);
                                        }
                                        summary.todos.clearRetainingCapacity();

                                        // Add new todos
                                        for (todos_value.array.items) |todo_item| {
                                            if (todo_item != .object) continue;
                                            const todo_obj = todo_item.object;

                                            const todo_content = todo_obj.get("content") orelse continue;
                                            const status = todo_obj.get("status") orelse continue;

                                            const todo = Todo{
                                                .content = try allocator.dupe(u8, todo_content.string),
                                                .status = try allocator.dupe(u8, status.string),
                                            };
                                            try summary.todos.append(todo);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Add tool call
                    const tool_call = ToolCall{
                        .name = try allocator.dupe(u8, name_str),
                        .success = true, // Assume success until proven otherwise
                        .detail = detail,
                    };
                    const idx = summary.tool_calls.items.len;
                    try summary.tool_calls.append(tool_call);

                    // Map tool ID to index
                    if (tool_id) |tid| {
                        const id_str = try allocator.dupe(u8, tid.string);
                        try tool_call_map.put(id_str, idx);
                    }
                }
            }
        }
    }

    // Set default main task if no prompts
    if (summary.main_task.len == 0) {
        summary.main_task = try allocator.dupe(u8, "No user prompts");
    }

    return summary;
}

// ============================================================================
// Recovery Generation
// ============================================================================

fn generateRecovery(
    allocator: std.mem.Allocator,
    summary: Summary,
    session_id: []const u8,
    trigger: []const u8,
    limits: config_mod.RecoveryLimits,
) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    const writer = output.writer();

    // Get current timestamp (ISO 8601 format)
    const timestamp = std.time.timestamp();
    const seconds: u64 = @intCast(timestamp);

    // YAML frontmatter
    try writer.print("---\n", .{});
    try writer.print("timestamp: {d}\n", .{seconds});
    try writer.print("session: {s}\n", .{session_id});
    try writer.print("trigger: {s}\n", .{trigger});
    try writer.print("---\n\n", .{});

    // Header
    try writer.print("# Session Recovery\n\n", .{});

    // Quick Insights
    try writer.print("## Quick Insights\n\n", .{});

    // Main Task
    const task_preview = if (summary.main_task.len > 80)
        summary.main_task[0..80]
    else
        summary.main_task;
    try writer.print("**Main Task**: {s}", .{task_preview});
    if (summary.main_task.len > 80) {
        try writer.print("...", .{});
    }
    try writer.print("\n\n", .{});

    // Status
    const total_todos = summary.todos.items.len;
    var incomplete_todos: usize = 0;
    for (summary.todos.items) |todo| {
        if (std.mem.eql(u8, todo.status, "pending") or std.mem.eql(u8, todo.status, "in_progress")) {
            incomplete_todos += 1;
        }
    }

    const status = if (total_todos == 0)
        "No Activity"
    else if (incomplete_todos > 0)
        "In Progress"
    else
        "Completed";
    try writer.print("**Status**: {s}\n\n", .{status});

    // Activity stats
    try writer.print("**Activity**: {d} prompts, {d} files, {d} todos\n\n", .{
        summary.user_prompts.items.len,
        summary.files_modified.count(),
        total_todos,
    });

    // Errors
    if (summary.errors.items.len > 0) {
        try writer.print("**Errors**: {d} encountered\n\n", .{summary.errors.items.len});
    }

    try writer.print("---\n\n", .{});

    // User Prompts
    try writer.print("## What Was Asked\n\n", .{});
    if (summary.user_prompts.items.len > 0) {
        // Show last N prompts
        const start_idx = if (summary.user_prompts.items.len > limits.userPrompts)
            summary.user_prompts.items.len - limits.userPrompts
        else
            0;

        for (summary.user_prompts.items[start_idx..]) |prompt| {
            try writer.print("- {s}", .{prompt});
            if (prompt.len >= limits.promptLength) {
                try writer.print("...", .{});
            }
            try writer.print("\n", .{});
        }
    } else {
        try writer.print("No user prompts captured.\n", .{});
    }
    try writer.print("\n", .{});

    // Task State (todos)
    try writer.print("## Task State\n\n", .{});
    if (summary.todos.items.len > 0) {
        var has_completed = false;
        var has_in_progress = false;
        var has_pending = false;

        // Check what we have
        for (summary.todos.items) |todo| {
            if (std.mem.eql(u8, todo.status, "completed")) has_completed = true;
            if (std.mem.eql(u8, todo.status, "in_progress")) has_in_progress = true;
            if (std.mem.eql(u8, todo.status, "pending")) has_pending = true;
        }

        // Completed
        if (has_completed) {
            try writer.print("**Completed:**\n", .{});
            for (summary.todos.items) |todo| {
                if (std.mem.eql(u8, todo.status, "completed")) {
                    try writer.print("- [x] {s}\n", .{todo.content});
                }
            }
            try writer.print("\n", .{});
        }

        // In Progress
        if (has_in_progress) {
            try writer.print("**In Progress:**\n", .{});
            for (summary.todos.items) |todo| {
                if (std.mem.eql(u8, todo.status, "in_progress")) {
                    try writer.print("- [>] {s}\n", .{todo.content});
                }
            }
            try writer.print("\n", .{});
        }

        // Pending
        if (has_pending) {
            try writer.print("**Pending:**\n", .{});
            for (summary.todos.items) |todo| {
                if (std.mem.eql(u8, todo.status, "pending")) {
                    try writer.print("- [ ] {s}\n", .{todo.content});
                }
            }
            try writer.print("\n", .{});
        }
    } else {
        try writer.print("No TodoWrite state captured.\n\n", .{});
    }

    // Files Modified
    try writer.print("## Files Modified\n\n", .{});
    if (summary.files_modified.count() > 0) {
        var it = summary.files_modified.keyIterator();
        while (it.next()) |key| {
            try writer.print("- {s}\n", .{key.*});
        }
    } else {
        try writer.print("No files modified.\n", .{});
    }
    try writer.print("\n", .{});

    // Recent Actions
    try writer.print("## Recent Actions\n\n", .{});
    if (summary.tool_calls.items.len > 0) {
        // Show last N tool calls
        const start_idx = if (summary.tool_calls.items.len > limits.toolCalls)
            summary.tool_calls.items.len - limits.toolCalls
        else
            0;

        for (summary.tool_calls.items[start_idx..]) |tc| {
            const status_str = if (tc.success) "OK" else "FAIL";
            try writer.print("- {s} [{s}]", .{ tc.name, status_str });
            if (tc.detail.len > 0) {
                if (std.mem.eql(u8, tc.name, "Bash")) {
                    try writer.print(" `{s}`", .{tc.detail});
                } else {
                    try writer.print(" {s}", .{tc.detail});
                }
            }
            try writer.print("\n", .{});
        }
    } else {
        try writer.print("No tool calls recorded.\n", .{});
    }
    try writer.print("\n", .{});

    // Errors
    if (summary.errors.items.len > 0) {
        try writer.print("## Errors\n\n", .{});

        // Show last N errors
        const start_idx = if (summary.errors.items.len > limits.errors)
            summary.errors.items.len - limits.errors
        else
            0;

        for (summary.errors.items[start_idx..]) |err| {
            try writer.print("```\n{s}\n```\n", .{err});
        }
        try writer.print("\n", .{});
    }

    // Last Context
    if (summary.last_assistant_message.len > 0) {
        try writer.print("## Last Context\n\n", .{});
        try writer.print("```\n{s}", .{summary.last_assistant_message});
        if (summary.last_assistant_message.len >= limits.lastMessageLength) {
            try writer.print("\n[... truncated]", .{});
        }
        try writer.print("\n```\n\n", .{});
    }

    return output.toOwnedSlice();
}

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args; // Recovery reads from stdin

    // Read JSON input from stdin
    const stdin = std.io.getStdIn();
    const json_input = try stdin.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(json_input);

    // Parse input JSON
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_input,
        .{ .ignore_unknown_fields = true },
    ) catch {
        std.debug.print("Error: Invalid JSON input\n", .{});
        return error.InvalidInput;
    };
    defer parsed.deinit();

    const input = parsed.value.object;

    // Extract required fields
    const transcript_path_value = input.get("transcript_path") orelse {
        std.debug.print("Error: No transcript_path in input\n", .{});
        return error.MissingField;
    };
    const transcript_path = transcript_path_value.string;

    const session_id = if (input.get("session_id")) |v| v.string else "unknown";
    const cwd = if (input.get("cwd")) |v| v.string else blk: {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fs.cwd().realpath(".", &buf);
        break :blk try allocator.dupe(u8, path);
    };
    defer if (input.get("cwd") == null) allocator.free(cwd);

    const trigger = if (input.get("trigger")) |v|
        v.string
    else if (input.get("hook_event_name")) |v|
        v.string
    else
        "manual";

    // Find project root (look for .claude directory)
    const project_root = try findProjectRoot(allocator, cwd);
    defer allocator.free(project_root);

    // Load config
    const config_path = try paths.getConfigPath(allocator, project_root);
    defer allocator.free(config_path);

    const config = config_mod.load(allocator, config_path) catch config_mod.Config{};

    // Parse transcript
    var summary = try parseTranscript(allocator, transcript_path, config.recovery.limits);
    defer summary.deinit();

    // Calculate activity score
    const activity = summary.user_prompts.items.len +
        summary.tool_calls.items.len +
        summary.files_modified.count() +
        summary.todos.items.len;

    // Check activity threshold
    if (activity < config.recovery.minActivity) {
        std.debug.print("Skipping recovery: activity {d} < minActivity {d}\n", .{
            activity,
            config.recovery.minActivity,
        });
        return;
    }

    // Generate recovery markdown
    const recovery_md = try generateRecovery(
        allocator,
        summary,
        session_id,
        trigger,
        config.recovery.limits,
    );
    defer allocator.free(recovery_md);

    // Create recovery directory
    const recovery_dir = try paths.getRecoveryDir(allocator, project_root);
    defer allocator.free(recovery_dir);

    try paths.ensureDirExists(recovery_dir);

    // Generate filename: YYYY-MM-DD-HH-MM-SESSIONID.md
    const timestamp = std.time.timestamp();
    const seconds: u64 = @intCast(timestamp);

    // Convert Unix timestamp to datetime
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = seconds };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const day_seconds = epoch_seconds.getDaySeconds();
    const hour = day_seconds.getHoursIntoDay();
    const minute = day_seconds.getMinutesIntoHour();

    const filename = try std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}-{d:0>2}-{d:0>2}-{s}.md",
        .{ year_day.year, month_day.month.numeric(), month_day.day_index + 1, hour, minute, session_id },
    );
    defer allocator.free(filename);

    const filepath = try std.fs.path.join(allocator, &.{ recovery_dir, filename });
    defer allocator.free(filepath);

    // Check if file exists (multiple compacts in same session)
    const file_exists = blk: {
        std.fs.cwd().access(filepath, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (file_exists) {
        // Append to existing file
        const file = try std.fs.cwd().openFile(filepath, .{ .mode = .read_write });
        defer file.close();

        // Seek to end
        try file.seekFromEnd(0);

        // Add separator
        const separator = "\n\n---\n\n# Session Continued\n\n";
        try file.writeAll(separator);

        // Remove frontmatter from new recovery
        const recovery_without_frontmatter = blk2: {
            const frontmatter_end = std.mem.indexOf(u8, recovery_md, "---\n\n") orelse {
                break :blk2 recovery_md;
            };
            const content_start = std.mem.indexOfPos(u8, recovery_md, frontmatter_end + 4, "---\n\n") orelse {
                break :blk2 recovery_md;
            };
            break :blk2 recovery_md[content_start + 5 ..];
        };

        try file.writeAll(recovery_without_frontmatter);

        std.debug.print("Recovery appended: {s}\n", .{filepath});
    } else {
        // Write new file
        const file = try std.fs.cwd().createFile(filepath, .{});
        defer file.close();

        try file.writeAll(recovery_md);

        std.debug.print("Recovery saved: {s}\n", .{filepath});
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn findProjectRoot(allocator: std.mem.Allocator, start_dir: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(path_buf[0..start_dir.len], start_dir);
    var path_len = start_dir.len;

    while (true) {
        // Check if .claude exists
        const claude_dir = try std.fs.path.join(allocator, &.{ path_buf[0..path_len], ".claude" });
        defer allocator.free(claude_dir);

        std.fs.cwd().access(claude_dir, .{}) catch {
            // .claude not found, go up one directory
            const parent = std.fs.path.dirname(path_buf[0..path_len]);
            if (parent == null or parent.?.len == path_len or parent.?.len == 0) {
                // Reached root, use start_dir
                return allocator.dupe(u8, start_dir);
            }
            @memcpy(path_buf[0..parent.?.len], parent.?);
            path_len = parent.?.len;
            continue;
        };

        // Found .claude directory
        return allocator.dupe(u8, path_buf[0..path_len]);
    }
}
