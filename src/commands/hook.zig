const std = @import("std");
const paths = @import("../shared/paths.zig");

pub fn run(allocator: std.mem.Allocator, args: [][]const u8) !void {
    // Parse arguments
    var project_dir: ?[]const u8 = null;
    var subcommand: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--project-dir")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --project-dir requires a value\n", .{});
                return error.InvalidArgument;
            }
            project_dir = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "session-start") or
            std.mem.eql(u8, arg, "pre-compact") or
            std.mem.eql(u8, arg, "session-end"))
        {
            subcommand = arg;
        }
    }

    // Validate required arguments
    if (project_dir == null) {
        std.debug.print("Error: --project-dir is required\n", .{});
        return error.MissingArgument;
    }

    if (subcommand == null) {
        std.debug.print("Error: subcommand (session-start, pre-compact, or session-end) is required\n", .{});
        return error.MissingArgument;
    }

    // Read JSON from stdin
    const stdin = std.io.getStdIn();
    const stdin_data = try stdin.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(stdin_data);

    // Handle subcommands
    if (std.mem.eql(u8, subcommand.?, "session-start")) {
        // Parse JSON for session-start
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, stdin_data, .{});
        defer parsed.deinit();

        const json_obj = parsed.value.object;
        const session_id = if (json_obj.get("session_id")) |sid| sid.string else "";
        const source = if (json_obj.get("source")) |src| src.string else "";

        try handleSessionStart(allocator, project_dir.?, session_id, source);
    } else if (std.mem.eql(u8, subcommand.?, "pre-compact") or
        std.mem.eql(u8, subcommand.?, "session-end"))
    {
        try handleRecovery(allocator, project_dir.?, stdin_data);
    }
}

fn handleSessionStart(
    allocator: std.mem.Allocator,
    project_dir: []const u8,
    session_id: []const u8,
    source: []const u8,
) !void {
    const stdout = std.io.getStdOut().writer();

    // Build session info
    var context = std.ArrayList(u8).init(allocator);
    defer context.deinit();

    try context.writer().print(
        \\<session-info>
        \\SESSION_ID: {s}
        \\PROJECT: {s}
        \\</session-info>
    , .{
        session_id,
        project_dir,
    });

    // Load recovery context if source is "compact"
    if (std.mem.eql(u8, source, "compact") and session_id.len > 0) {
        const recovery_dir = try paths.getRecoveryDir(allocator, project_dir);
        defer allocator.free(recovery_dir);

        // Check if recovery directory exists and find recovery file
        var dir = std.fs.cwd().openDir(recovery_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                // No recovery directory, output without recovery context
                try outputSessionStartJson(allocator, stdout, context.items);
                return;
            }
            return err;
        };
        defer dir.close();

        // Find newest recovery file for this session
        var newest_name = std.ArrayList(u8).init(allocator);
        defer newest_name.deinit();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            // Check if filename ends with -{session_id}.md
            const suffix = try std.fmt.allocPrint(allocator, "-{s}.md", .{session_id});
            defer allocator.free(suffix);

            if (std.mem.endsWith(u8, entry.name, suffix)) {
                // Keep the newest (lexicographically last due to timestamp format)
                if (newest_name.items.len == 0 or std.mem.order(u8, entry.name, newest_name.items) == .gt) {
                    newest_name.clearRetainingCapacity();
                    try newest_name.appendSlice(entry.name);
                }
            }
        }

        // If recovery file found, read and append to context
        if (newest_name.items.len > 0) {
            const recovery_path = try std.fs.path.join(allocator, &.{ recovery_dir, newest_name.items });
            defer allocator.free(recovery_path);

            const recovery_content = std.fs.cwd().readFileAlloc(allocator, recovery_path, 10 * 1024 * 1024) catch |err| {
                if (err == error.FileNotFound) {
                    // File disappeared, output without recovery context
                    try outputSessionStartJson(allocator, stdout, context.items);
                    return;
                }
                return err;
            };
            defer allocator.free(recovery_content);

            // Append recovery context
            try context.writer().print(
                \\
                \\
                \\<recovery-context>
                \\Previous session recovery:
                \\
                \\{s}
                \\</recovery-context>
            , .{recovery_content});
        }
    }

    // Output JSON
    try outputSessionStartJson(allocator, stdout, context.items);
}

fn outputSessionStartJson(
    allocator: std.mem.Allocator,
    writer: anytype,
    context: []const u8,
) !void {
    // Escape the context string for JSON
    var escaped = std.ArrayList(u8).init(allocator);
    defer escaped.deinit();

    for (context) |c| {
        switch (c) {
            '"' => try escaped.appendSlice("\\\""),
            '\\' => try escaped.appendSlice("\\\\"),
            '\n' => try escaped.appendSlice("\\n"),
            '\r' => try escaped.appendSlice("\\r"),
            '\t' => try escaped.appendSlice("\\t"),
            else => try escaped.append(c),
        }
    }

    try writer.print(
        \\{{"hookSpecificOutput":{{"hookEventName":"SessionStart","additionalContext":"{s}"}}}}
        \\
    , .{escaped.items});
}

fn handleRecovery(
    allocator: std.mem.Allocator,
    project_dir: []const u8,
    stdin_data: []const u8,
) !void {
    // Path to recovery-generator.js in hooks directory
    const recovery_generator = try std.fs.path.join(allocator, &.{ project_dir, "hooks", "recovery-generator.js" });
    defer allocator.free(recovery_generator);

    // Spawn node process
    var child = std.process.Child.init(&.{ "node", recovery_generator }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();

    // Write stdin data to child
    if (child.stdin) |stdin_pipe| {
        try stdin_pipe.writeAll(stdin_data);
        stdin_pipe.close();
        child.stdin = null;
    }

    // Wait for completion
    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                return error.RecoveryGeneratorFailed;
            }
        },
        else => return error.RecoveryGeneratorFailed,
    }
}
