const std = @import("std");
const paths = @import("../shared/paths.zig");
const config_mod = @import("../shared/config.zig");
const debug_mod = @import("../shared/debug.zig");

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const start_time = std.time.milliTimestamp();
    // Parse arguments
    var project_dir: ?[]const u8 = null;
    var subcommand: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--project-dir")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --project-dir requires an argument\n", .{});
                return error.InvalidArgument;
            }
            project_dir = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "stop") or std.mem.eql(u8, args[i], "prompt")) {
            subcommand = args[i];
        }
    }

    if (project_dir == null) {
        std.debug.print("Error: --project-dir is required\n", .{});
        return error.MissingArgument;
    }

    if (subcommand == null) {
        std.debug.print("Error: subcommand (stop or prompt) is required\n", .{});
        return error.MissingArgument;
    }

    // Read stdin for JSON
    const stdin = std.io.getStdIn().reader();
    const input = stdin.readAllAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        // If stdin is empty or can't be read, exit silently
        if (err == error.EndOfStream) return;
        return err;
    };
    defer allocator.free(input);

    if (input.len == 0) return;

    // Parse JSON to get session_id
    const parsed = std.json.parseFromSlice(
        struct { session_id: []const u8 },
        allocator,
        input,
        .{ .ignore_unknown_fields = true },
    ) catch {
        // If JSON parsing fails, exit silently
        return;
    };
    defer parsed.deinit();

    const session_id = parsed.value.session_id;
    if (session_id.len == 0) return;

    // Get timestamp directory
    const timestamp_dir = try paths.getTimestampDir(allocator, project_dir.?);
    defer allocator.free(timestamp_dir);

    // Ensure directory exists
    try paths.ensureDirExists(timestamp_dir);

    // Build timestamp file path
    const timestamp_file = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}.txt",
        .{ timestamp_dir, session_id },
    );
    defer allocator.free(timestamp_file);

    // Load config to check debug status
    var config = config_mod.loadCascadedConfig(allocator, project_dir.?) catch blk: {
        break :blk try config_mod.Config.init(allocator);
    };
    defer config.deinit();

    // Capture output for debug logging
    var output_buf = std.ArrayList(u8).init(allocator);
    defer output_buf.deinit();

    var error_msg: ?[]const u8 = null;
    defer if (error_msg) |e| allocator.free(e);

    // Execute tracker command
    const result = runTrackerInternal(allocator, &output_buf, subcommand.?, timestamp_file, &config) catch |err| blk: {
        const err_str = try std.fmt.allocPrint(allocator, "{}", .{err});
        error_msg = err_str;
        break :blk err;
    };

    // Write output to stdout
    if (output_buf.items.len > 0) {
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(output_buf.items);
    }

    // Log if debug enabled
    if (debug_mod.shouldLogOurHooks(config)) {
        const end_time = std.time.milliTimestamp();
        const duration: u64 = @intCast(end_time - start_time);

        var entry = try debug_mod.createEntry(
            allocator,
            subcommand.?,
            session_id,
            input,
            args,
            output_buf.items,
            duration,
            error_msg,
        );
        defer entry.deinit();

        debug_mod.logHook(allocator, project_dir.?, entry) catch {};
    }

    return result;
}

fn runTrackerInternal(
    allocator: std.mem.Allocator,
    output_buf: *std.ArrayList(u8),
    subcommand: []const u8,
    timestamp_file: []const u8,
    config: *const config_mod.Config,
) !void {
    if (std.mem.eql(u8, subcommand, "stop")) {
        try handleStop(timestamp_file);
    } else if (std.mem.eql(u8, subcommand, "prompt")) {
        try handlePromptInternal(allocator, output_buf, timestamp_file, config);
    }
}

fn handleStop(timestamp_file: []const u8) !void {
    const now = std.time.timestamp();

    const file = try std.fs.cwd().createFile(timestamp_file, .{});
    defer file.close();

    var buf: [32]u8 = undefined;
    const timestamp_str = try std.fmt.bufPrint(&buf, "{d}\n", .{now});
    try file.writeAll(timestamp_str);
}

fn handlePromptInternal(
    allocator: std.mem.Allocator,
    output_buf: *std.ArrayList(u8),
    timestamp_file: []const u8,
    config: *const config_mod.Config,
) !void {
    // Check if idle time detection is enabled
    if (!config.idleTime.enabled) {
        return;
    }

    // Read last timestamp
    const file = std.fs.cwd().openFile(timestamp_file, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return; // No timestamp file yet, exit silently
        }
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, &std.ascii.whitespace);
    const last_timestamp = std.fmt.parseInt(i64, trimmed, 10) catch {
        return; // Invalid timestamp, exit silently
    };

    // Calculate elapsed time
    const now = std.time.timestamp();
    const elapsed_seconds = now - last_timestamp;
    const elapsed_minutes = @divTrunc(elapsed_seconds, 60);

    // Check threshold
    if (elapsed_minutes >= config.idleTime.thresholdMinutes) {
        const writer = output_buf.writer();

        // Create message
        const message = try std.fmt.allocPrint(
            allocator,
            "Uplynulo {d} minut od poslední odpovědi. Zvažte ověření aktuálního stavu.",
            .{elapsed_minutes},
        );
        defer allocator.free(message);

        // Create the output structure matching the shell script format
        const Output = struct {
            hookSpecificOutput: struct {
                hookEventName: []const u8,
                additionalContext: []const u8,
            },
        };

        const output = Output{
            .hookSpecificOutput = .{
                .hookEventName = "UserPromptSubmit",
                .additionalContext = message,
            },
        };

        // Serialize to JSON
        try std.json.stringify(output, .{}, writer);
        try writer.writeByte('\n');
    }
}
