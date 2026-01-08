const std = @import("std");
const paths = @import("../shared/paths.zig");
const config_mod = @import("../shared/config.zig");

const Color = struct {
    const reset = "\x1b[0m";
    const green = "\x1b[0;32m";
    const blue = "\x1b[0;34m";
    const yellow = "\x1b[1;33m";
};

const WrapperArgs = struct {
    min_session_size: ?u32 = null,
    min_diary_count: ?u32 = null,
    auto_diary: ?bool = null,
    auto_reflect: ?bool = null,
    claude_args: std.ArrayList([]const u8),
};

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Parse arguments
    var wrapper_args = try parseArgs(allocator, args);
    defer wrapper_args.claude_args.deinit();

    // Generate session ID
    const session_id = try generateSessionId(allocator);
    defer allocator.free(session_id);

    // Find project root
    const project_root = try findProjectRoot(allocator);
    defer allocator.free(project_root);

    // Load cascaded config (home → parent dirs → project)
    var config = try config_mod.loadCascadedConfig(allocator, project_root);
    defer config.deinit();

    // Merge config with CLI args
    var final_config = config.wrapper;
    if (wrapper_args.min_session_size) |size| final_config.minSessionSize = size;
    if (wrapper_args.min_diary_count) |count| final_config.minDiaryCount = count;
    if (wrapper_args.auto_diary) |auto| final_config.autoDiary = auto;
    if (wrapper_args.auto_reflect) |auto| final_config.autoReflect = auto;

    const stdout = std.io.getStdOut().writer();

    // Print header
    try stdout.print("{s}🚀 Claude Diary Wrapper{s}\n", .{ Color.blue, Color.reset });
    try stdout.print("{s}   Session ID: {s}{s}\n\n", .{ Color.blue, session_id, Color.reset });

    // Check for unprocessed diaries
    const diary_dir = try paths.getDiaryDir(allocator, project_root);
    defer allocator.free(diary_dir);
    const unprocessed_count = try countUnprocessedDiaries(diary_dir);

    if (unprocessed_count >= final_config.minDiaryCount) {
        try stdout.print("{s}📚 Found {d} unprocessed diary file(s) (min: {d}){s}\n", .{ Color.yellow, unprocessed_count, final_config.minDiaryCount, Color.reset });

        const run_reflect = if (final_config.autoReflect) blk: {
            try stdout.print("{s}🔄 Auto-running /reflect...{s}\n", .{ Color.green, Color.reset });
            break :blk true;
        } else if (final_config.askBeforeReflect) blk: {
            break :blk try promptUser("Run /reflect to process them? [y/N] ");
        } else false;

        if (run_reflect) {
            // Setup temp settings with reflect permissions
            const temp_settings = try setupTempSettings(allocator, project_root, .reflect);
            defer allocator.free(temp_settings);
            defer std.fs.cwd().deleteFile(temp_settings) catch {};

            var reflect_config = try config_mod.resolveClaudeConfig(allocator, config.claude, config.claude.override.reflect);
            defer reflect_config.deinit();
            try runClaude(allocator, reflect_config, &.{"/reflect"});
            try stdout.writeAll("\n");
        }
    } else if (unprocessed_count > 0) {
        try stdout.print("{s}📚 Found {d} unprocessed diary file(s) (min required: {d}, skipping reflect){s}\n\n", .{ Color.blue, unprocessed_count, final_config.minDiaryCount, Color.reset });
    }

    // Run main Claude session
    try stdout.print("{s}💬 Starting Claude Code session...{s}\n\n", .{ Color.green, Color.reset });

    var main_config = try config_mod.resolveClaudeConfig(allocator, config.claude, config.claude.override.main);
    defer main_config.deinit();

    var claude_args = std.ArrayList([]const u8).init(allocator);
    defer claude_args.deinit();
    try claude_args.appendSlice(&.{ "--session-id", session_id });
    try claude_args.appendSlice(wrapper_args.claude_args.items);

    try runClaude(allocator, main_config, claude_args.items);

    // Check session size and offer diary
    try stdout.print("\n{s}📝 Session ended{s}\n", .{ Color.blue, Color.reset });

    const session_size = try getSessionSize(allocator, project_root, session_id);
    try stdout.print("{s}   Transcript size: {d} KB (min: {d} KB){s}\n", .{ Color.blue, session_size, final_config.minSessionSize, Color.reset });

    if (session_size < final_config.minSessionSize) {
        try stdout.print("{s}⏩ Session too small, skipping diary{s}\n\n", .{ Color.yellow, Color.reset });
        try stdout.print("{s}✨ Done!{s}\n", .{ Color.green, Color.reset });
        return;
    }

    // Offer diary
    const run_diary = if (final_config.autoDiary) blk: {
        try stdout.print("{s}📝 Auto-running /diary...{s}\n", .{ Color.green, Color.reset });
        break :blk true;
    } else if (final_config.askBeforeDiary) blk: {
        break :blk try promptUser("Create diary for this session? [Y/n] ");
    } else false;

    if (run_diary) {
        try stdout.writeAll("\n");

        // Setup temp settings with diary permissions
        const temp_settings = try setupTempSettings(allocator, project_root, .diary);
        defer allocator.free(temp_settings);
        defer std.fs.cwd().deleteFile(temp_settings) catch {};

        var diary_config = try config_mod.resolveClaudeConfig(allocator, config.claude, config.claude.override.diary);
        defer diary_config.deinit();
        try runClaude(allocator, diary_config, &.{ "--resume", session_id, "/diary" });
    }

    try stdout.print("\n{s}✨ Done!{s}\n", .{ Color.green, Color.reset });
}

/// Run Claude with the specified configuration
fn runClaude(
    allocator: std.mem.Allocator,
    claude_config: config_mod.ClaudeConfig,
    extra_args: []const []const u8,
) !void {
    const builtin = @import("builtin");

    // Build command
    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append(claude_config.cmd);
    try cmd_args.append("code");
    try cmd_args.appendSlice(extra_args);

    // Build environment map (cross-platform)
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();

    // Platform-specific environment handling
    if (builtin.target.os.tag == .windows) {
        // On Windows, only set configured variables (child inherits rest)
        // std.process.getEnvMap uses posix.getenv which doesn't work on Windows
        var env_it = claude_config.env.iterator();
        while (env_it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            switch (value) {
                .literal => |v| {
                    try env_map.put(key, v);
                },
                .reference => |_| {
                    // Skip references on Windows (can't easily get current env)
                },
                .unset => {
                    // Skip unset on Windows (can't modify inherited env)
                },
            }
        }
    } else {
        // On Unix-like systems, copy current environment and apply changes
        var current_env = try std.process.getEnvMap(allocator);
        defer current_env.deinit();

        // Copy current environment
        var curr_it = current_env.hash_map.iterator();
        while (curr_it.next()) |entry| {
            try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Apply config environment variables
        var env_it = claude_config.env.iterator();
        while (env_it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            switch (value) {
                .literal => |v| {
                    try env_map.put(key, v);
                },
                .reference => |ref| {
                    // Resolve environment variable reference
                    if (current_env.get(ref)) |resolved| {
                        try env_map.put(key, resolved);
                    }
                },
                .unset => {
                    // Remove the variable
                    _ = env_map.remove(key);
                },
            }
        }
    }

    // Run in tmux if configured
    if (claude_config.tmux) |tmux_session| {
        try runInTmux(allocator, tmux_session, cmd_args.items, env_map);
    } else {
        try runCommand(allocator, cmd_args.items, env_map);
    }
}

/// Run command in tmux session
fn runInTmux(
    allocator: std.mem.Allocator,
    session_name: []const u8,
    command: []const []const u8,
    env_map: std.process.EnvMap,
) !void {
    // Check if tmux is available
    const tmux_check = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "which", "tmux" },
    }) catch {
        std.debug.print("Warning: tmux not found, running command directly\n", .{});
        return runCommand(allocator, command, env_map);
    };
    defer allocator.free(tmux_check.stdout);
    defer allocator.free(tmux_check.stderr);

    if (tmux_check.term.Exited != 0) {
        std.debug.print("Warning: tmux not found, running command directly\n", .{});
        return runCommand(allocator, command, env_map);
    }

    // Build tmux command
    var tmux_cmd = std.ArrayList([]const u8).init(allocator);
    defer tmux_cmd.deinit();

    // Check if session exists
    const session_check = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "tmux", "has-session", "-t", session_name },
    }) catch null;

    const session_exists = if (session_check) |check| blk: {
        defer allocator.free(check.stdout);
        defer allocator.free(check.stderr);
        break :blk check.term.Exited == 0;
    } else false;

    // Build command string for tmux
    var cmd_string = std.ArrayList(u8).init(allocator);
    defer cmd_string.deinit();

    // Add environment variables to command
    var env_it = env_map.hash_map.iterator();
    while (env_it.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        try cmd_string.appendSlice(key);
        try cmd_string.append('=');
        try cmd_string.append('"');
        try cmd_string.appendSlice(value);
        try cmd_string.appendSlice("\" ");
    }

    // Add command
    for (command, 0..) |arg, i| {
        if (i > 0) try cmd_string.append(' ');
        // Quote arguments with spaces
        if (std.mem.indexOf(u8, arg, " ") != null) {
            try cmd_string.append('"');
            try cmd_string.appendSlice(arg);
            try cmd_string.append('"');
        } else {
            try cmd_string.appendSlice(arg);
        }
    }

    if (session_exists) {
        // Attach to existing session
        try tmux_cmd.appendSlice(&.{ "tmux", "attach-session", "-t", session_name });
    } else {
        // Create new session
        try tmux_cmd.appendSlice(&.{ "tmux", "new-session", "-s", session_name, cmd_string.items });
    }

    // Run tmux command
    var child = std.process.Child.init(tmux_cmd.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.process.exit(code);
            }
        },
        else => {
            std.process.exit(1);
        },
    }
}

/// Run command directly (no tmux)
fn runCommand(
    allocator: std.mem.Allocator,
    command: []const []const u8,
    env_map: std.process.EnvMap,
) !void {
    var child = std.process.Child.init(command, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.env_map = &env_map;

    const term = try child.spawnAndWait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.process.exit(code);
            }
        },
        else => {
            std.process.exit(1);
        },
    }
}

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !WrapperArgs {
    var result = WrapperArgs{
        .claude_args = std.ArrayList([]const u8).init(allocator),
    };

    var i: usize = 0;
    var parsing_wrapper = true;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (parsing_wrapper) {
            if (std.mem.eql(u8, arg, "--min-session-size")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                result.min_session_size = try std.fmt.parseInt(u32, args[i], 10);
            } else if (std.mem.eql(u8, arg, "--min-diary-count")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                result.min_diary_count = try std.fmt.parseInt(u32, args[i], 10);
            } else if (std.mem.eql(u8, arg, "--auto-diary")) {
                result.auto_diary = true;
            } else if (std.mem.eql(u8, arg, "--auto-reflect")) {
                result.auto_reflect = true;
            } else if (std.mem.eql(u8, arg, "--")) {
                parsing_wrapper = false;
            } else {
                // Not a wrapper arg, stop parsing wrapper options
                parsing_wrapper = false;
                try result.claude_args.append(arg);
            }
        } else {
            try result.claude_args.append(arg);
        }
    }

    return result;
}

fn generateSessionId(allocator: std.mem.Allocator) ![]u8 {
    const charset = "abcdefghijklmnopqrstuvwxyz0123456789";
    const session_id = try allocator.alloc(u8, 8);

    var random = std.crypto.random;
    for (session_id) |*c| {
        c.* = charset[random.intRangeAtMost(usize, 0, charset.len - 1)];
    }

    return session_id;
}

fn findProjectRoot(allocator: std.mem.Allocator) ![]u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", &buf);

    var current = try allocator.dupe(u8, cwd);

    while (true) {
        const claude_dir = try std.fs.path.join(allocator, &.{ current, ".claude" });
        defer allocator.free(claude_dir);

        if (std.fs.cwd().access(claude_dir, .{})) {
            return current;
        } else |_| {
            // Try parent directory
            if (std.mem.eql(u8, current, "/")) {
                // Reached root without finding .claude, return original cwd
                return try allocator.dupe(u8, cwd);
            }

            const parent = std.fs.path.dirname(current) orelse "/";
            const new_current = try allocator.dupe(u8, parent);
            allocator.free(current);
            current = new_current;
        }
    }
}

const CommandType = enum { reflect, diary };

fn setupTempSettings(allocator: std.mem.Allocator, project_root: []const u8, command_type: CommandType) ![]u8 {
    const settings_path = try std.fs.path.join(allocator, &.{ project_root, ".claude", "settings.local.json" });

    const content = switch (command_type) {
        .reflect =>
            \\{
            \\  "permissions": {
            \\    "Write(CLAUDE.md)": "allow",
            \\    "Write(.claude/diary/reflections/*.md)": "allow",
            \\    "Write(.claude/diary/processed/*.md)": "allow",
            \\    "Bash(mv .claude/diary/*.md .claude/diary/processed/*)": "allow",
            \\    "Bash(mkdir -p .claude/diary/*)": "allow"
            \\  }
            \\}
            \\
        ,
        .diary =>
            \\{
            \\  "permissions": {
            \\    "Write(.claude/diary/*.md)": "allow",
            \\    "Bash(mkdir -p .claude/diary)": "allow"
            \\  }
            \\}
            \\
        ,
    };

    const file = try std.fs.cwd().createFile(settings_path, .{});
    defer file.close();
    try file.writeAll(content);

    return settings_path;
}

fn countUnprocessedDiaries(diary_dir: []const u8) !u32 {
    var dir = std.fs.cwd().openDir(diary_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return 0;
        return err;
    };
    defer dir.close();

    var count: u32 = 0;
    var iter = dir.iterate();

    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.endsWith(u8, entry.name, ".md")) {
            count += 1;
        }
    }

    return count;
}

fn getSessionSize(allocator: std.mem.Allocator, project_root: []const u8, session_id: []const u8) !u64 {
    // Build transcript path: ~/.claude/projects/{project_name}/{session_id}.jsonl
    const builtin = @import("builtin");
    const home_env = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
    const home = std.process.getEnvVarOwned(allocator, home_env) catch return 0;
    defer allocator.free(home);

    // Convert project_root to project_name (replace / with -)
    var project_name = std.ArrayList(u8).init(allocator);
    defer project_name.deinit();
    for (project_root) |c| {
        if (c == '/') {
            try project_name.append('-');
        } else {
            try project_name.append(c);
        }
    }

    const filename = try std.fmt.allocPrint(allocator, "{s}.jsonl", .{session_id});
    defer allocator.free(filename);

    const transcript_path = try std.fs.path.join(allocator, &.{
        home,
        ".claude",
        "projects",
        project_name.items,
        filename,
    });
    defer allocator.free(transcript_path);

    const file = std.fs.cwd().openFile(transcript_path, .{}) catch |err| {
        if (err == error.FileNotFound) return 0;
        return err;
    };
    defer file.close();

    const stat = try file.stat();
    return @intCast(stat.size / 1024); // Convert to KB
}

fn promptUser(prompt: []const u8) !bool {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll(prompt);

    var buf: [16]u8 = undefined;
    const input = (try stdin.readUntilDelimiterOrEof(&buf, '\n')) orelse "";

    if (input.len == 0) {
        // Default behavior depends on prompt
        if (std.mem.indexOf(u8, prompt, "[Y/n]") != null) {
            return true; // Default yes
        } else {
            return false; // Default no
        }
    }

    const first_char = std.ascii.toLower(input[0]);
    return first_char == 'y';
}
