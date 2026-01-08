const std = @import("std");
const config_mod = @import("../shared/config.zig");
const debug_mod = @import("../shared/debug.zig");

/// Catch-all hook handler for debugging
/// Logs ALL hook events when debug.logAllHooks is enabled
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const start_time = std.time.milliTimestamp();

    // Parse arguments
    var project_dir: ?[]const u8 = null;
    var hook_name: []const u8 = "unknown";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--project-dir")) {
            if (i + 1 >= args.len) {
                return error.InvalidArgument;
            }
            project_dir = args[i + 1];
            i += 1;
        } else if (i == 0) {
            // First non-option argument is the hook name
            hook_name = arg;
        }
    }

    // Read stdin (hook context)
    const stdin = std.io.getStdIn();
    const stdin_data = try stdin.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stdin_data);

    // Determine project directory
    const proj_dir = project_dir orelse blk: {
        // Try to get from stdin JSON
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, stdin_data, .{}) catch break :blk ".";
        defer parsed.deinit();
        if (parsed.value.object.get("cwd")) |cwd| {
            break :blk cwd.string;
        }
        break :blk ".";
    };

    // Load config
    var config = config_mod.loadCascadedConfig(allocator, proj_dir) catch blk: {
        break :blk try config_mod.Config.init(allocator);
    };
    defer config.deinit();

    // Only log if debug.logAllHooks is enabled
    if (!debug_mod.shouldLogAllHooks(config)) {
        // Not logging, just return success (empty output)
        return;
    }

    // Extract session_id from stdin
    var session_id: []const u8 = "unknown";
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, stdin_data, .{}) catch null;
    if (parsed) |p| {
        defer p.deinit();
        if (p.value.object.get("session_id")) |sid| {
            session_id = sid.string;
        }
    }

    // Log the hook call
    const end_time = std.time.milliTimestamp();
    const duration: u64 = @intCast(end_time - start_time);

    var entry = try debug_mod.createEntry(
        allocator,
        hook_name,
        session_id,
        stdin_data,
        args,
        "", // No output for catch-all
        duration,
        null, // No error
    );
    defer entry.deinit();

    try debug_mod.logHook(allocator, proj_dir, entry);

    // Return empty JSON response (hook succeeded silently)
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("{}\n");
}
