const std = @import("std");
const config = @import("../shared/config.zig");

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    // Get project directory from args or use cwd
    const project_dir = if (args.len > 0) args[0] else ".";

    try stdout.print("Testing config cascade for project: {s}\n\n", .{project_dir});

    // Load cascaded config
    var cfg = try config.loadCascadedConfig(allocator, project_dir);
    defer cfg.deinit();

    // Print config values
    try stdout.print("Loaded configuration:\n", .{});
    try stdout.print("====================\n\n", .{});

    try stdout.print("Claude:\n", .{});
    try stdout.print("  cmd: {s}\n", .{cfg.claude.cmd});
    if (cfg.claude.tmux) |t| {
        try stdout.print("  tmux: {s}\n", .{t});
    }
    try stdout.print("  env vars: {d}\n", .{cfg.claude.env.count()});

    try stdout.print("\nWrapper:\n", .{});
    try stdout.print("  autoDiary: {}\n", .{cfg.wrapper.autoDiary});
    try stdout.print("  autoReflect: {}\n", .{cfg.wrapper.autoReflect});
    try stdout.print("  askBeforeDiary: {}\n", .{cfg.wrapper.askBeforeDiary});
    try stdout.print("  askBeforeReflect: {}\n", .{cfg.wrapper.askBeforeReflect});
    try stdout.print("  minSessionSize: {d} KB\n", .{cfg.wrapper.minSessionSize});
    try stdout.print("  minDiaryCount: {d}\n", .{cfg.wrapper.minDiaryCount});

    try stdout.print("\nRecovery:\n", .{});
    try stdout.print("  minActivity: {d}\n", .{cfg.recovery.minActivity});
    try stdout.print("  limits.userPrompts: {d}\n", .{cfg.recovery.limits.userPrompts});
    try stdout.print("  limits.promptLength: {d}\n", .{cfg.recovery.limits.promptLength});
    try stdout.print("  limits.toolCalls: {d}\n", .{cfg.recovery.limits.toolCalls});
    try stdout.print("  limits.lastMessageLength: {d}\n", .{cfg.recovery.limits.lastMessageLength});
    try stdout.print("  limits.errors: {d}\n", .{cfg.recovery.limits.errors});

    try stdout.print("\nIdle Time:\n", .{});
    try stdout.print("  enabled: {}\n", .{cfg.idleTime.enabled});
    try stdout.print("  thresholdMinutes: {d}\n", .{cfg.idleTime.thresholdMinutes});

    try stdout.print("\n", .{});
}
