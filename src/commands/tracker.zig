const std = @import("std");
const paths = @import("../shared/paths.zig");
const config_mod = @import("../shared/config.zig");

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
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

    if (std.mem.eql(u8, subcommand.?, "stop")) {
        try handleStop(timestamp_file);
    } else if (std.mem.eql(u8, subcommand.?, "prompt")) {
        try handlePrompt(allocator, project_dir.?, timestamp_file);
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

fn handlePrompt(allocator: std.mem.Allocator, project_dir: []const u8, timestamp_file: []const u8) !void {
    // Load config
    const config_path = try paths.getConfigPath(allocator, project_dir);
    defer allocator.free(config_path);

    var config = config_mod.load(allocator, config_path) catch |err| {
        // If config can't be loaded, use defaults
        if (err == error.FileNotFound) {
            var default_config = try config_mod.Config.init(allocator);
            defer default_config.deinit();
            return handlePromptWithConfig(allocator, timestamp_file, &default_config);
        }
        return err;
    };
    defer config.deinit();

    try handlePromptWithConfig(allocator, timestamp_file, &config);
}

fn handlePromptWithConfig(
    allocator: std.mem.Allocator,
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
        const stdout = std.io.getStdOut().writer();

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
        try std.json.stringify(output, .{}, stdout);
        try stdout.writeByte('\n');
    }
}
