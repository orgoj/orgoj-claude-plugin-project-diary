const std = @import("std");

/// Recovery command - stub implementation that delegates to Node.js
///
/// This is a temporary implementation that calls hooks/recovery-generator.js
/// to parse JSONL transcripts and generate recovery markdown files.
///
/// TODO: Rewrite JSONL parsing in pure Zig for performance and no Node.js dependency
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args; // Currently unused - recovery reads from stdin

    // Read JSON from stdin
    const stdin = std.io.getStdIn();
    const json_input = try stdin.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(json_input);

    // Find project root to locate hooks/recovery-generator.js
    const project_root = try findProjectRoot(allocator);
    defer allocator.free(project_root);

    // Build path to recovery-generator.js
    const script_path = try std.fs.path.join(
        allocator,
        &.{ project_root, "hooks", "recovery-generator.js" },
    );
    defer allocator.free(script_path);

    // Verify script exists
    std.fs.cwd().access(script_path, .{}) catch |err| {
        std.debug.print("Error: Cannot find recovery-generator.js at {s}\n", .{script_path});
        return err;
    };

    // Spawn node process
    var child = std.process.Child.init(&.{ "node", script_path }, allocator);

    // Pipe stdin to child
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();

    // Write JSON to child's stdin
    if (child.stdin) |stdin_pipe| {
        try stdin_pipe.writeAll(json_input);
        stdin_pipe.close();
        child.stdin = null;
    }

    // Wait for child to complete
    const term = try child.wait();

    // Exit with same code as child
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.process.exit(@intCast(code));
            }
        },
        .Signal => |sig| {
            std.debug.print("recovery-generator.js terminated by signal {d}\n", .{sig});
            std.process.exit(1);
        },
        .Stopped => |sig| {
            std.debug.print("recovery-generator.js stopped by signal {d}\n", .{sig});
            std.process.exit(1);
        },
        .Unknown => |code| {
            std.debug.print("recovery-generator.js exited with unknown code {d}\n", .{code});
            std.process.exit(1);
        },
    }
}

/// Find project root by looking for .claude directory
fn findProjectRoot(allocator: std.mem.Allocator) ![]u8 {
    var dir = std.fs.cwd();

    // Try current directory first
    const current_path = try dir.realpathAlloc(allocator, ".");
    defer allocator.free(current_path);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(path_buf[0..current_path.len], current_path);
    var path_len = current_path.len;

    while (true) {
        // Check if .claude exists in current path
        const claude_dir_path = try std.fs.path.join(
            allocator,
            &.{ path_buf[0..path_len], ".claude" },
        );
        defer allocator.free(claude_dir_path);

        std.fs.cwd().access(claude_dir_path, .{}) catch {
            // .claude not found, go up one directory
            const parent = std.fs.path.dirname(path_buf[0..path_len]);
            if (parent == null or parent.?.len == path_len) {
                // Reached root, use current working directory
                return dir.realpathAlloc(allocator, ".");
            }
            path_len = parent.?.len;
            continue;
        };

        // Found .claude directory
        return allocator.dupe(u8, path_buf[0..path_len]);
    }
}
