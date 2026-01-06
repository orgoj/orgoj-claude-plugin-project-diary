const std = @import("std");

pub const Config = struct {
    wrapper: WrapperConfig = .{},
    recovery: RecoveryConfig = .{},
    idleTime: IdleTimeConfig = .{},
};

pub const WrapperConfig = struct {
    autoDiary: bool = false,
    autoReflect: bool = false,
    askBeforeDiary: bool = true,
    askBeforeReflect: bool = true,
    minSessionSize: u32 = 2,
    minDiaryCount: u32 = 1,
};

pub const RecoveryConfig = struct {
    minActivity: u32 = 1,
    limits: RecoveryLimits = .{},
};

pub const RecoveryLimits = struct {
    userPrompts: u32 = 5,
    promptLength: u32 = 150,
    toolCalls: u32 = 10,
    lastMessageLength: u32 = 500,
    errors: u32 = 5,
};

pub const IdleTimeConfig = struct {
    enabled: bool = true,
    thresholdMinutes: u32 = 5,
};

/// Load configuration from a JSON file.
/// Returns default config if file doesn't exist.
/// Caller owns the returned config but not any string data (uses parseFromSlice).
pub fn load(allocator: std.mem.Allocator, path: []const u8) !Config {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return Config{};
        }
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(Config, allocator, content, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return parsed.value;
}
