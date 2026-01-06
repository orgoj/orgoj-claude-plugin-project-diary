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
    // Parse stdin data to pass project directory
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, stdin_data, .{}) catch |err| {
        std.debug.print("Error: Failed to parse JSON input: {any}\n", .{err});
        return error.InvalidInput;
    };
    defer parsed.deinit();

    // Create a modified JSON with project directory context
    var json_obj = parsed.value.object;

    // Ensure project_dir is in the JSON data (as cwd if not present)
    if (json_obj.get("cwd") == null) {
        // We need to add cwd, but we can't modify the parsed object
        // So we'll reconstruct the JSON with cwd added
        var new_json = std.ArrayList(u8).init(allocator);
        defer new_json.deinit();

        // Simple JSON manipulation: add cwd field
        // Find the last } and insert before it
        const trimmed = std.mem.trim(u8, stdin_data, " \t\r\n");
        if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '}') {
            // Insert cwd before the closing brace
            const without_brace = trimmed[0 .. trimmed.len - 1];
            try new_json.appendSlice(without_brace);

            // Add comma if not empty object
            if (!std.mem.endsWith(u8, std.mem.trim(u8, without_brace, " \t\r\n"), "{")) {
                try new_json.append(',');
            }

            try new_json.writer().print("\"cwd\":\"{s}\"}}", .{project_dir});

            // Write modified JSON to a temporary buffer and call recovery
            // Actually, we'll use stdin redirection by creating a pipe
            // But simpler: we can just create a new stdin-like input

            // For now, let's just call recovery.run with empty args
            // The recovery module will read from the actual stdin which we control here

            // Create a temporary file with the modified JSON
            const tmp_dir = std.fs.cwd();
            const tmp_name = try std.fmt.allocPrint(allocator, ".recovery-input-{d}.json", .{std.time.milliTimestamp()});
            defer allocator.free(tmp_name);

            {
                const tmp_file = try tmp_dir.createFile(tmp_name, .{});
                defer tmp_file.close();
                try tmp_file.writeAll(new_json.items);
            }
            defer tmp_dir.deleteFile(tmp_name) catch {};

            // Redirect stdin temporarily by spawning ourselves
            // Actually, this is getting complex. Let's use a simpler approach:
            // Just call the recovery module's run function directly with a custom stdin

            // Get path to current executable
            const exe_path = try std.fs.selfExePathAlloc(allocator);
            defer allocator.free(exe_path);

            // Create argv with executable path
            const argv = [_][]const u8{ exe_path, "recovery" };

            // The simplest approach: use a pipe
            var child = std.process.Child.init(&argv, allocator);
            child.stdin_behavior = .Pipe;
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;

            try child.spawn();

            if (child.stdin) |stdin_pipe| {
                try stdin_pipe.writeAll(new_json.items);
                stdin_pipe.close();
                child.stdin = null;
            }

            const term = try child.wait();
            switch (term) {
                .Exited => |code| {
                    if (code != 0) {
                        return error.RecoveryFailed;
                    }
                },
                else => return error.RecoveryFailed,
            }
        }
    } else {
        // cwd already present, just spawn recovery with original stdin
        const exe_path = try std.fs.selfExePathAlloc(allocator);
        defer allocator.free(exe_path);

        const argv = [_][]const u8{ exe_path, "recovery" };

        var child = std.process.Child.init(&argv, allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        try child.spawn();

        if (child.stdin) |stdin_pipe| {
            try stdin_pipe.writeAll(stdin_data);
            stdin_pipe.close();
            child.stdin = null;
        }

        const term = try child.wait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    return error.RecoveryFailed;
                }
            },
            else => return error.RecoveryFailed,
        }
    }
}
