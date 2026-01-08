const std = @import("std");
const config_mod = @import("config.zig");
const paths = @import("paths.zig");

/// Log entry for hook execution
pub const HookLogEntry = struct {
    timestamp: []const u8,
    hook: []const u8,
    session_id: []const u8,
    stdin: []const u8,
    argv: []const []const u8,
    env: std.StringHashMap([]const u8),
    output: []const u8,
    duration_ms: u64,
    error_msg: ?[]const u8,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *HookLogEntry) void {
        self.allocator.free(self.timestamp);
        self.allocator.free(self.hook);
        self.allocator.free(self.session_id);
        self.allocator.free(self.stdin);
        for (self.argv) |arg| self.allocator.free(arg);
        self.allocator.free(self.argv);

        var it = self.env.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.env.deinit();

        self.allocator.free(self.output);
        if (self.error_msg) |err| self.allocator.free(err);
    }
};

/// Check if debug logging is enabled
pub fn isEnabled(config: config_mod.Config) bool {
    return config.debug.enabled;
}

/// Check if our hooks should be logged
pub fn shouldLogOurHooks(config: config_mod.Config) bool {
    return config.debug.enabled and config.debug.logOurHooks;
}

/// Check if all hooks should be logged
pub fn shouldLogAllHooks(config: config_mod.Config) bool {
    return config.debug.enabled and config.debug.logAllHooks;
}

/// Get debug log file path
pub fn getLogPath(allocator: std.mem.Allocator, project_dir: []const u8) ![]const u8 {
    const debug_dir = try std.fs.path.join(allocator, &.{ project_dir, ".claude", "diary", "debug" });
    defer allocator.free(debug_dir);

    // Ensure directory exists
    std.fs.cwd().makePath(debug_dir) catch {};

    return try std.fs.path.join(allocator, &.{ debug_dir, "hooks.jsonl" });
}

/// Log a hook execution
pub fn logHook(
    allocator: std.mem.Allocator,
    project_dir: []const u8,
    entry: HookLogEntry,
) !void {
    const log_path = try getLogPath(allocator, project_dir);
    defer allocator.free(log_path);

    // Open file in append mode
    const file = try std.fs.cwd().openFile(log_path, .{
        .mode = .write_only,
    });
    defer file.close();

    try file.seekFromEnd(0);

    // Build JSON object
    var json_buf = std.ArrayList(u8).init(allocator);
    defer json_buf.deinit();

    const writer = json_buf.writer();

    try writer.writeAll("{");

    // timestamp
    try writer.writeAll("\"timestamp\":\"");
    try writer.writeAll(entry.timestamp);
    try writer.writeAll("\",");

    // hook
    try writer.writeAll("\"hook\":\"");
    try writer.writeAll(entry.hook);
    try writer.writeAll("\",");

    // session_id
    try writer.writeAll("\"session_id\":\"");
    try writer.writeAll(entry.session_id);
    try writer.writeAll("\",");

    // stdin
    try writer.writeAll("\"stdin\":");
    try std.json.stringify(entry.stdin, .{}, writer);
    try writer.writeAll(",");

    // argv
    try writer.writeAll("\"argv\":");
    try std.json.stringify(entry.argv, .{}, writer);
    try writer.writeAll(",");

    // env
    try writer.writeAll("\"env\":{");
    var env_it = entry.env.iterator();
    var first_env = true;
    while (env_it.next()) |env_entry| {
        if (!first_env) try writer.writeAll(",");
        first_env = false;
        try std.json.stringify(env_entry.key_ptr.*, .{}, writer);
        try writer.writeAll(":");
        try std.json.stringify(env_entry.value_ptr.*, .{}, writer);
    }
    try writer.writeAll("},");

    // output
    try writer.writeAll("\"output\":");
    try std.json.stringify(entry.output, .{}, writer);
    try writer.writeAll(",");

    // duration_ms
    try writer.print("\"duration_ms\":{d},", .{entry.duration_ms});

    // error_msg
    try writer.writeAll("\"error\":");
    if (entry.error_msg) |err| {
        try std.json.stringify(err, .{}, writer);
    } else {
        try writer.writeAll("null");
    }

    try writer.writeAll("}\n");

    // Write to file
    try file.writeAll(json_buf.items);
}

/// Create a hook log entry from execution context
pub fn createEntry(
    allocator: std.mem.Allocator,
    hook_name: []const u8,
    session_id: []const u8,
    stdin_data: []const u8,
    argv: []const []const u8,
    output: []const u8,
    duration_ms: u64,
    error_msg: ?[]const u8,
) !HookLogEntry {
    // Get current timestamp
    const timestamp_ms = std.time.milliTimestamp();
    const timestamp_sec: i64 = @divFloor(timestamp_ms, 1000);

    var timestamp_buf: [64]u8 = undefined;
    const timestamp_str = try std.fmt.bufPrint(&timestamp_buf, "{d}", .{timestamp_sec});

    // Copy all strings
    const hook_copy = try allocator.dupe(u8, hook_name);
    const session_copy = try allocator.dupe(u8, session_id);
    const stdin_copy = try allocator.dupe(u8, stdin_data);
    const output_copy = try allocator.dupe(u8, output);
    const timestamp_copy = try allocator.dupe(u8, timestamp_str);

    const error_copy = if (error_msg) |err| try allocator.dupe(u8, err) else null;

    // Copy argv
    const argv_copy = try allocator.alloc([]const u8, argv.len);
    for (argv, 0..) |arg, i| {
        argv_copy[i] = try allocator.dupe(u8, arg);
    }

    // Get environment variables
    var env_map = std.StringHashMap([]const u8).init(allocator);

    // Add relevant env vars
    const env_vars = [_][]const u8{
        "CLAUDE_PROJECT_DIR",
        "CLAUDE_PLUGIN_ROOT",
        "CLAUDE_SESSION_ID",
        "CLAUDE_CODE_REMOTE",
    };

    for (env_vars) |var_name| {
        if (std.process.getEnvVarOwned(allocator, var_name)) |value| {
            const key = try allocator.dupe(u8, var_name);
            try env_map.put(key, value);
        } else |_| {}
    }

    return HookLogEntry{
        .allocator = allocator,
        .timestamp = timestamp_copy,
        .hook = hook_copy,
        .session_id = session_copy,
        .stdin = stdin_copy,
        .argv = argv_copy,
        .env = env_map,
        .output = output_copy,
        .duration_ms = duration_ms,
        .error_msg = error_copy,
    };
}
