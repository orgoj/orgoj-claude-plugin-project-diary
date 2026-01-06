const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        std.debug.print("mopc v0.1.0 - Master of Prompts\n", .{});
        return;
    }

    if (std.mem.eql(u8, command, "wrapper")) {
        const wrapper = @import("commands/wrapper.zig");
        try wrapper.run(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "hook")) {
        const hook = @import("commands/hook.zig");
        try hook.run(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "tracker")) {
        const tracker = @import("commands/tracker.zig");
        try tracker.run(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "recovery")) {
        const recovery = @import("commands/recovery.zig");
        try recovery.run(allocator, args[2..]);
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{command});
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
        \\  mopc --version
        \\
    );
}
