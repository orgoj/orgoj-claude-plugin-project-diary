const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Detect command from argv[0] (symlink name) if called via symlink
    const exe_name = std.fs.path.basename(args[0]);
    const implied_command: ?[]const u8 = if (std.mem.eql(u8, exe_name, "claude-diary"))
        "wrapper"
    else if (std.mem.eql(u8, exe_name, "diary-hook.sh"))
        "hook"
    else if (std.mem.eql(u8, exe_name, "time-tracker.sh"))
        "tracker"
    else
        null;

    // If command implied by symlink, insert it into args
    const command = if (implied_command) |cmd|
        cmd
    else if (args.len >= 2)
        args[1]
    else
        null;

    if (command == null) {
        try printUsage();
        return;
    }

    const cmd = command.?;

    // If command was implied, use all args starting from index 1
    // If command was explicit, use args starting from index 2
    const cmd_args = if (implied_command != null) args[1..] else args[2..];

    // Handle --version flag
    if (args.len >= 2 and (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "-v"))) {
        std.debug.print("mopc v0.1.0 - Master of Prompts\n", .{});
        return;
    }

    if (std.mem.eql(u8, cmd, "wrapper")) {
        const wrapper = @import("commands/wrapper.zig");
        try wrapper.run(allocator, cmd_args);
    } else if (std.mem.eql(u8, cmd, "hook")) {
        const hook = @import("commands/hook.zig");
        try hook.run(allocator, cmd_args);
    } else if (std.mem.eql(u8, cmd, "tracker")) {
        const tracker = @import("commands/tracker.zig");
        try tracker.run(allocator, cmd_args);
    } else if (std.mem.eql(u8, cmd, "recovery")) {
        const recovery = @import("commands/recovery.zig");
        try recovery.run(allocator, cmd_args);
    } else if (std.mem.eql(u8, cmd, "test-config")) {
        const test_config = @import("commands/test-config.zig");
        try test_config.run(allocator, cmd_args);
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{cmd});
        try printUsage();
        std.process.exit(1);
    }
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\mopc - Master of Prompts
        \\
        \\Usage:
        \\  mopc wrapper [OPTIONS] -- [AI_CLI_OPTIONS]
        \\  mopc hook [session-start|pre-compact|session-end] [OPTIONS]
        \\  mopc tracker [stop|prompt] [OPTIONS]
        \\  mopc recovery [OPTIONS]
        \\  mopc test-config [PROJECT_DIR]
        \\  mopc --version
        \\
    );
}
