const std = @import("std");
const paths = @import("../shared/paths.zig");
const config_mod = @import("../shared/config.zig");
const debug_mod = @import("../shared/debug.zig");

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try printUsage();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "enable")) {
        try handleEnable(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "disable")) {
        try handleDisable(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "view")) {
        try handleView(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "clear")) {
        try handleClear(allocator, args[1..]);
    } else {
        std.debug.print("Unknown debug subcommand: {s}\n\n", .{subcommand});
        try printUsage();
        std.process.exit(1);
    }
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\mopc debug - Debug logging control
        \\
        \\Usage:
        \\  mopc debug enable [--our-hooks|--all-hooks] [PROJECT_DIR]
        \\  mopc debug disable [PROJECT_DIR]
        \\  mopc debug view [--tail N] [PROJECT_DIR]
        \\  mopc debug clear [PROJECT_DIR]
        \\
        \\Subcommands:
        \\  enable     Enable debug logging
        \\             --our-hooks: Log only our implemented hooks (default)
        \\             --all-hooks: Log ALL hook events (catch-all)
        \\  disable    Disable all debug logging
        \\  view       View debug log (default: last 50 lines)
        \\  clear      Clear debug log file
        \\
        \\Examples:
        \\  mopc debug enable --our-hooks .
        \\  mopc debug enable --all-hooks /path/to/project
        \\  mopc debug view --tail 100
        \\  mopc debug disable
        \\
    );
}

fn getProjectDir(args: []const []const u8) []const u8 {
    for (args) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) {
            return arg;
        }
    }
    return "."; // Default to current directory
}

fn handleEnable(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const project_dir = getProjectDir(args);

    // Parse flags
    var our_hooks = true; // default
    var all_hooks = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--our-hooks")) {
            our_hooks = true;
            all_hooks = false;
        } else if (std.mem.eql(u8, arg, "--all-hooks")) {
            our_hooks = true;
            all_hooks = true;
        }
    }

    // Load config
    var config = config_mod.loadCascadedConfig(allocator, project_dir) catch blk: {
        break :blk try config_mod.Config.init(allocator);
    };
    defer config.deinit();

    // Update debug settings
    config.debug.enabled = true;
    config.debug.logOurHooks = our_hooks;
    config.debug.logAllHooks = all_hooks;

    // Save to project config
    const config_path = try paths.getConfigPath(allocator, project_dir);
    defer allocator.free(config_path);

    try saveDebugConfig(allocator, config_path, config.debug);

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("✅ Debug logging enabled\n");
    if (our_hooks) try stdout.writeAll("   Logging our hooks: YES\n");
    if (all_hooks) try stdout.writeAll("   Logging all hooks: YES\n");
    try stdout.print("   Log file: {s}/.claude/diary/debug/hooks.jsonl\n", .{project_dir});
}

fn handleDisable(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const project_dir = getProjectDir(args);

    // Load config
    var config = config_mod.loadCascadedConfig(allocator, project_dir) catch blk: {
        break :blk try config_mod.Config.init(allocator);
    };
    defer config.deinit();

    // Disable debug
    config.debug.enabled = false;

    // Save to project config
    const config_path = try paths.getConfigPath(allocator, project_dir);
    defer allocator.free(config_path);

    try saveDebugConfig(allocator, config_path, config.debug);

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("✅ Debug logging disabled\n");
}

fn handleView(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const project_dir = getProjectDir(args);

    // Parse --tail flag
    var tail_lines: usize = 50; // default
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--tail")) {
            if (i + 1 < args.len) {
                tail_lines = std.fmt.parseInt(usize, args[i + 1], 10) catch 50;
                i += 1;
            }
        }
    }

    const log_path = try debug_mod.getLogPath(allocator, project_dir);
    defer allocator.free(log_path);

    // Read log file
    const file = std.fs.cwd().openFile(log_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("No debug log found at: {s}\n", .{log_path});
            std.debug.print("Enable debug logging with: mopc debug enable\n", .{});
            return;
        }
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 100 * 1024 * 1024); // 100MB max
    defer allocator.free(content);

    // Split into lines
    var lines = std.mem.splitScalar(u8, content, '\n');
    var line_list = std.ArrayList([]const u8).init(allocator);
    defer line_list.deinit();

    while (lines.next()) |line| {
        if (line.len > 0) {
            try line_list.append(line);
        }
    }

    // Print last N lines
    const start_index = if (line_list.items.len > tail_lines)
        line_list.items.len - tail_lines
    else
        0;

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== Last {d} lines of {s} ===\n\n", .{ line_list.items.len - start_index, log_path });

    for (line_list.items[start_index..]) |line| {
        try stdout.print("{s}\n", .{line});
    }
}

fn handleClear(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const project_dir = getProjectDir(args);

    const log_path = try debug_mod.getLogPath(allocator, project_dir);
    defer allocator.free(log_path);

    // Delete log file
    std.fs.cwd().deleteFile(log_path) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("No debug log to clear.\n", .{});
            return;
        }
        return err;
    };

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("✅ Debug log cleared\n");
}

fn saveDebugConfig(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    debug_config: config_mod.DebugConfig,
) !void {
    // Ensure directory exists
    if (std.fs.path.dirname(config_path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }

    // Read existing config or create new
    var existing_json = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer existing_json.object.deinit();

    // Try to read existing config
    const existing_content = std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024) catch |err| blk: {
        if (err == error.FileNotFound) {
            break :blk null;
        }
        return err;
    };
    defer if (existing_content) |c| allocator.free(c);

    if (existing_content) |content| {
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch null;
        if (parsed) |p| {
            defer p.deinit();
            // Copy object entries
            var it = p.value.object.iterator();
            while (it.next()) |entry| {
                const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                try existing_json.object.put(key_copy, entry.value_ptr.*);
            }
        }
    }

    // Update debug section
    var debug_obj = std.json.ObjectMap.init(allocator);
    defer {
        // Clean up debug_obj keys
        var it = debug_obj.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        debug_obj.deinit();
    }

    const enabled_key = try allocator.dupe(u8, "enabled");
    try debug_obj.put(enabled_key, .{ .bool = debug_config.enabled });

    const log_our_key = try allocator.dupe(u8, "logOurHooks");
    try debug_obj.put(log_our_key, .{ .bool = debug_config.logOurHooks });

    const log_all_key = try allocator.dupe(u8, "logAllHooks");
    try debug_obj.put(log_all_key, .{ .bool = debug_config.logAllHooks });

    const debug_section_key = try allocator.dupe(u8, "debug");
    try existing_json.object.put(debug_section_key, .{ .object = debug_obj });

    // Write to file
    const file = try std.fs.cwd().createFile(config_path, .{});
    defer file.close();

    try std.json.stringify(existing_json, .{ .whitespace = .indent_2 }, file.writer());

    // Clean up existing_json keys
    var it = existing_json.object.iterator();
    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
    }
}
