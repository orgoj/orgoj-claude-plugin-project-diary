const std = @import("std");
const builtin = @import("builtin");

/// Get home directory environment variable name for current platform
fn homeEnvVar() []const u8 {
    return if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
}

/// Environment variable value - can be literal, unset (null), or reference ($VAR)
pub const EnvValue = union(enum) {
    literal: []const u8,
    unset: void,
    reference: []const u8, // var name without $

    pub fn deinit(self: EnvValue, allocator: std.mem.Allocator) void {
        switch (self) {
            .literal => |v| allocator.free(v),
            .reference => |v| allocator.free(v),
            .unset => {},
        }
    }
};

/// Claude execution configuration override for specific commands
pub const ClaudeExecConfig = struct {
    cmd: ?[]const u8 = null,
    env: ?std.StringHashMap(EnvValue) = null,
    tmux: ?[]const u8 = null,

    pub fn deinit(self: *ClaudeExecConfig, allocator: std.mem.Allocator) void {
        if (self.cmd) |c| allocator.free(c);
        if (self.tmux) |t| allocator.free(t);
        if (self.env) |*e| {
            var it = e.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            e.deinit();
        }
    }
};

/// Override configurations for different command types
pub const ClaudeOverride = struct {
    reflect: ?ClaudeExecConfig = null,
    diary: ?ClaudeExecConfig = null,
    main: ?ClaudeExecConfig = null,

    pub fn deinit(self: *ClaudeOverride, allocator: std.mem.Allocator) void {
        if (self.reflect) |*r| r.deinit(allocator);
        if (self.diary) |*d| d.deinit(allocator);
        if (self.main) |*m| m.deinit(allocator);
    }
};

/// Claude execution configuration
pub const ClaudeConfig = struct {
    cmd: []const u8,
    env: std.StringHashMap(EnvValue),
    tmux: ?[]const u8 = null,
    override: ClaudeOverride = .{},

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !ClaudeConfig {
        return .{
            .allocator = allocator,
            .cmd = try allocator.dupe(u8, "claude"),
            .env = std.StringHashMap(EnvValue).init(allocator),
        };
    }

    pub fn deinit(self: *ClaudeConfig) void {
        self.allocator.free(self.cmd);

        var it = self.env.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.env.deinit();

        if (self.tmux) |t| self.allocator.free(t);
        self.override.deinit(self.allocator);
    }
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

pub const DebugConfig = struct {
    enabled: bool = false, // Master switch - must be true for any logging
    logOurHooks: bool = true, // Log our implemented hooks (SessionStart, PreCompact, etc.)
    logAllHooks: bool = false, // Log ALL hook events (catch-all for debugging)
};

pub const Config = struct {
    claude: ClaudeConfig,
    wrapper: WrapperConfig = .{},
    recovery: RecoveryConfig = .{},
    idleTime: IdleTimeConfig = .{},
    debug: DebugConfig = .{},

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Config {
        return .{
            .allocator = allocator,
            .claude = try ClaudeConfig.init(allocator),
        };
    }

    pub fn deinit(self: *Config) void {
        self.claude.deinit();
    }
};

/// Load configuration from home directory (~/.config/mopc/config.json)
pub fn loadHomeConfig(allocator: std.mem.Allocator) !Config {
    const home = std.process.getEnvVarOwned(allocator, homeEnvVar()) catch {
        return try Config.init(allocator);
    };
    defer allocator.free(home);

    const path = try std.fs.path.join(allocator, &.{ home, ".config", "mopc", "config.json" });
    defer allocator.free(path);

    return loadSingle(allocator, path);
}

/// Load configuration from project directory (.claude/diary/.config.json)
pub fn loadProjectConfig(allocator: std.mem.Allocator, project_dir: []const u8) !Config {
    const path = try std.fs.path.join(allocator, &.{ project_dir, ".claude", "diary", ".config.json" });
    defer allocator.free(path);

    return loadSingle(allocator, path);
}

/// Load configuration from a single JSON file.
/// Returns default config if file doesn't exist.
pub fn loadSingle(allocator: std.mem.Allocator, path: []const u8) !Config {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return try Config.init(allocator);
        }
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    return try parseConfig(allocator, content);
}

/// Merge two configs - project overrides home
pub fn mergeConfigs(allocator: std.mem.Allocator, home: Config, project: Config) !Config {
    var result = try Config.init(allocator);
    errdefer result.deinit();

    // Free the default claude config before replacing it
    result.claude.deinit();

    // Merge claude config
    result.claude = try mergeClaudeConfig(allocator, home.claude, project.claude);

    // Merge wrapper config field-by-field
    result.wrapper = mergeWrapperConfig(home.wrapper, project.wrapper);

    // Merge recovery config field-by-field
    result.recovery = mergeRecoveryConfig(home.recovery, project.recovery);

    // Merge idle time config field-by-field
    result.idleTime = mergeIdleTimeConfig(home.idleTime, project.idleTime);

    return result;
}

/// Merge two WrapperConfig structs - uses non-default values from project, otherwise home
fn mergeWrapperConfig(home: WrapperConfig, project: WrapperConfig) WrapperConfig {
    const defaults = WrapperConfig{};
    return .{
        .autoDiary = if (project.autoDiary != defaults.autoDiary) project.autoDiary else home.autoDiary,
        .autoReflect = if (project.autoReflect != defaults.autoReflect) project.autoReflect else home.autoReflect,
        .askBeforeDiary = if (project.askBeforeDiary != defaults.askBeforeDiary) project.askBeforeDiary else home.askBeforeDiary,
        .askBeforeReflect = if (project.askBeforeReflect != defaults.askBeforeReflect) project.askBeforeReflect else home.askBeforeReflect,
        .minSessionSize = if (project.minSessionSize != defaults.minSessionSize) project.minSessionSize else home.minSessionSize,
        .minDiaryCount = if (project.minDiaryCount != defaults.minDiaryCount) project.minDiaryCount else home.minDiaryCount,
    };
}

/// Merge two RecoveryConfig structs - uses non-default values from project, otherwise home
fn mergeRecoveryConfig(home: RecoveryConfig, project: RecoveryConfig) RecoveryConfig {
    const defaults = RecoveryConfig{};
    return .{
        .minActivity = if (project.minActivity != defaults.minActivity) project.minActivity else home.minActivity,
        .limits = mergeRecoveryLimits(home.limits, project.limits),
    };
}

/// Merge two RecoveryLimits structs - uses non-default values from project, otherwise home
fn mergeRecoveryLimits(home: RecoveryLimits, project: RecoveryLimits) RecoveryLimits {
    const defaults = RecoveryLimits{};
    return .{
        .userPrompts = if (project.userPrompts != defaults.userPrompts) project.userPrompts else home.userPrompts,
        .promptLength = if (project.promptLength != defaults.promptLength) project.promptLength else home.promptLength,
        .toolCalls = if (project.toolCalls != defaults.toolCalls) project.toolCalls else home.toolCalls,
        .lastMessageLength = if (project.lastMessageLength != defaults.lastMessageLength) project.lastMessageLength else home.lastMessageLength,
        .errors = if (project.errors != defaults.errors) project.errors else home.errors,
    };
}

/// Merge two IdleTimeConfig structs - uses non-default values from project, otherwise home
fn mergeIdleTimeConfig(home: IdleTimeConfig, project: IdleTimeConfig) IdleTimeConfig {
    const defaults = IdleTimeConfig{};
    return .{
        .enabled = if (project.enabled != defaults.enabled) project.enabled else home.enabled,
        .thresholdMinutes = if (project.thresholdMinutes != defaults.thresholdMinutes) project.thresholdMinutes else home.thresholdMinutes,
    };
}

/// Merge two ClaudeConfig structs - project overrides home
fn mergeClaudeConfig(allocator: std.mem.Allocator, home: ClaudeConfig, project: ClaudeConfig) !ClaudeConfig {
    var result = try ClaudeConfig.init(allocator);
    errdefer result.deinit();

    // Use project cmd if different from default, otherwise use home
    allocator.free(result.cmd); // Free the default value first
    if (!std.mem.eql(u8, project.cmd, "claude")) {
        result.cmd = try allocator.dupe(u8, project.cmd);
    } else if (!std.mem.eql(u8, home.cmd, "claude")) {
        result.cmd = try allocator.dupe(u8, home.cmd);
    } else {
        result.cmd = try allocator.dupe(u8, "claude");
    }

    // Merge env: start with home, override with project
    var home_it = home.env.iterator();
    while (home_it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        const value = try dupeEnvValue(allocator, entry.value_ptr.*);
        try result.env.put(key, value);
    }

    var proj_it = project.env.iterator();
    while (proj_it.next()) |entry| {
        // If key exists, free old value first
        if (result.env.get(entry.key_ptr.*)) |old_val| {
            old_val.deinit(allocator);
        }
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        const value = try dupeEnvValue(allocator, entry.value_ptr.*);
        try result.env.put(key, value);
    }

    // Use project tmux if set, otherwise home
    if (project.tmux) |t| {
        result.tmux = try allocator.dupe(u8, t);
    } else if (home.tmux) |t| {
        result.tmux = try allocator.dupe(u8, t);
    }

    // Merge overrides
    result.override = try mergeClaudeOverride(allocator, home.override, project.override);

    return result;
}

fn mergeClaudeOverride(allocator: std.mem.Allocator, home: ClaudeOverride, project: ClaudeOverride) !ClaudeOverride {
    var result: ClaudeOverride = .{};

    if (project.reflect) |pr| {
        result.reflect = if (home.reflect) |hr|
            try mergeClaudeExecConfig(allocator, hr, pr)
        else
            try dupeClaudeExecConfig(allocator, pr);
    } else if (home.reflect) |hr| {
        result.reflect = try dupeClaudeExecConfig(allocator, hr);
    }

    if (project.diary) |pd| {
        result.diary = if (home.diary) |hd|
            try mergeClaudeExecConfig(allocator, hd, pd)
        else
            try dupeClaudeExecConfig(allocator, pd);
    } else if (home.diary) |hd| {
        result.diary = try dupeClaudeExecConfig(allocator, hd);
    }

    if (project.main) |pm| {
        result.main = if (home.main) |hm|
            try mergeClaudeExecConfig(allocator, hm, pm)
        else
            try dupeClaudeExecConfig(allocator, pm);
    } else if (home.main) |hm| {
        result.main = try dupeClaudeExecConfig(allocator, hm);
    }

    return result;
}

fn mergeClaudeExecConfig(allocator: std.mem.Allocator, base: ClaudeExecConfig, override: ClaudeExecConfig) !ClaudeExecConfig {
    var result: ClaudeExecConfig = .{};

    result.cmd = if (override.cmd) |c|
        try allocator.dupe(u8, c)
    else if (base.cmd) |c|
        try allocator.dupe(u8, c)
    else
        null;

    result.tmux = if (override.tmux) |t|
        try allocator.dupe(u8, t)
    else if (base.tmux) |t|
        try allocator.dupe(u8, t)
    else
        null;

    // Merge env
    if (base.env != null or override.env != null) {
        var env_map = std.StringHashMap(EnvValue).init(allocator);

        if (base.env) |be| {
            var it = be.iterator();
            while (it.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const value = try dupeEnvValue(allocator, entry.value_ptr.*);
                try env_map.put(key, value);
            }
        }

        if (override.env) |oe| {
            var it = oe.iterator();
            while (it.next()) |entry| {
                if (env_map.get(entry.key_ptr.*)) |old_val| {
                    old_val.deinit(allocator);
                }
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const value = try dupeEnvValue(allocator, entry.value_ptr.*);
                try env_map.put(key, value);
            }
        }

        result.env = env_map;
    }

    return result;
}

fn dupeClaudeExecConfig(allocator: std.mem.Allocator, config: ClaudeExecConfig) !ClaudeExecConfig {
    var result: ClaudeExecConfig = .{};

    if (config.cmd) |c| result.cmd = try allocator.dupe(u8, c);
    if (config.tmux) |t| result.tmux = try allocator.dupe(u8, t);

    if (config.env) |e| {
        var env_map = std.StringHashMap(EnvValue).init(allocator);
        var it = e.iterator();
        while (it.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const value = try dupeEnvValue(allocator, entry.value_ptr.*);
            try env_map.put(key, value);
        }
        result.env = env_map;
    }

    return result;
}

fn dupeEnvValue(allocator: std.mem.Allocator, value: EnvValue) !EnvValue {
    return switch (value) {
        .literal => |v| .{ .literal = try allocator.dupe(u8, v) },
        .reference => |v| .{ .reference = try allocator.dupe(u8, v) },
        .unset => .{ .unset = {} },
    };
}

/// Resolve ClaudeConfig by applying override
pub fn resolveClaudeConfig(allocator: std.mem.Allocator, base: ClaudeConfig, override_config: ?ClaudeExecConfig) !ClaudeConfig {
    if (override_config == null) {
        // Return a copy of base
        var result = try ClaudeConfig.init(allocator);
        allocator.free(result.cmd);
        result.cmd = try allocator.dupe(u8, base.cmd);

        var it = base.env.iterator();
        while (it.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const value = try dupeEnvValue(allocator, entry.value_ptr.*);
            try result.env.put(key, value);
        }

        if (base.tmux) |t| result.tmux = try allocator.dupe(u8, t);

        return result;
    }

    const override = override_config.?;
    var result = try ClaudeConfig.init(allocator);

    // Override cmd
    allocator.free(result.cmd); // Free the default value first
    result.cmd = if (override.cmd) |c|
        try allocator.dupe(u8, c)
    else
        try allocator.dupe(u8, base.cmd);

    // Merge env: start with base, override with override
    var base_it = base.env.iterator();
    while (base_it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        const value = try dupeEnvValue(allocator, entry.value_ptr.*);
        try result.env.put(key, value);
    }

    if (override.env) |oe| {
        var override_it = oe.iterator();
        while (override_it.next()) |entry| {
            if (result.env.get(entry.key_ptr.*)) |old_val| {
                old_val.deinit(allocator);
            }
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const value = try dupeEnvValue(allocator, entry.value_ptr.*);
            try result.env.put(key, value);
        }
    }

    // Override tmux
    result.tmux = if (override.tmux) |t|
        try allocator.dupe(u8, t)
    else if (base.tmux) |t|
        try allocator.dupe(u8, t)
    else
        null;

    return result;
}

/// Parse configuration from JSON content
fn parseConfig(allocator: std.mem.Allocator, content: []const u8) !Config {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    var config = try Config.init(allocator);
    errdefer config.deinit();

    const root = parsed.value.object;

    // Parse claude config
    if (root.get("claude")) |claude_val| {
        config.claude.deinit(); // Free the default config first
        config.claude = try parseClaudeConfig(allocator, claude_val);
    }

    // Parse wrapper config (backward compatible)
    if (root.get("wrapper")) |wrapper_val| {
        config.wrapper = try parseWrapperConfig(wrapper_val);
    }

    // Parse recovery config (backward compatible)
    if (root.get("recovery")) |recovery_val| {
        config.recovery = try parseRecoveryConfig(recovery_val);
    }

    // Parse idle time config (backward compatible)
    if (root.get("idleTime")) |idle_val| {
        config.idleTime = try parseIdleTimeConfig(idle_val);
    }

    return config;
}

fn parseClaudeConfig(allocator: std.mem.Allocator, value: std.json.Value) !ClaudeConfig {
    var config = try ClaudeConfig.init(allocator);
    errdefer config.deinit();

    const obj = value.object;

    if (obj.get("cmd")) |cmd_val| {
        if (cmd_val != .string) return error.InvalidJson;
        allocator.free(config.cmd); // Free the default value
        config.cmd = try allocator.dupe(u8, cmd_val.string);
    }

    if (obj.get("env")) |env_val| {
        if (env_val != .object) return error.InvalidJson;
        config.env = try parseEnvMap(allocator, env_val.object);
    }

    if (obj.get("tmux")) |tmux_val| {
        if (tmux_val == .string) {
            config.tmux = try allocator.dupe(u8, tmux_val.string);
        }
    }

    if (obj.get("override")) |override_val| {
        if (override_val != .object) return error.InvalidJson;
        config.override = try parseClaudeOverride(allocator, override_val.object);
    }

    return config;
}

fn parseEnvMap(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !std.StringHashMap(EnvValue) {
    var map = std.StringHashMap(EnvValue).init(allocator);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        map.deinit();
    }

    var it = obj.iterator();
    while (it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(key);

        const value: EnvValue = switch (entry.value_ptr.*) {
            .null => .{ .unset = {} },
            .string => |s| blk: {
                if (s.len > 0 and s[0] == '$') {
                    // Reference - strip the $
                    break :blk .{ .reference = try allocator.dupe(u8, s[1..]) };
                } else {
                    break :blk .{ .literal = try allocator.dupe(u8, s) };
                }
            },
            else => return error.InvalidJson,
        };

        try map.put(key, value);
    }

    return map;
}

fn parseClaudeOverride(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !ClaudeOverride {
    var override: ClaudeOverride = .{};
    errdefer override.deinit(allocator);

    if (obj.get("reflect")) |val| {
        if (val != .object) return error.InvalidJson;
        override.reflect = try parseClaudeExecConfig(allocator, val.object);
    }

    if (obj.get("diary")) |val| {
        if (val != .object) return error.InvalidJson;
        override.diary = try parseClaudeExecConfig(allocator, val.object);
    }

    if (obj.get("main")) |val| {
        if (val != .object) return error.InvalidJson;
        override.main = try parseClaudeExecConfig(allocator, val.object);
    }

    return override;
}

fn parseClaudeExecConfig(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !ClaudeExecConfig {
    var config: ClaudeExecConfig = .{};
    errdefer config.deinit(allocator);

    if (obj.get("cmd")) |val| {
        if (val != .string) return error.InvalidJson;
        config.cmd = try allocator.dupe(u8, val.string);
    }

    if (obj.get("env")) |val| {
        if (val != .object) return error.InvalidJson;
        config.env = try parseEnvMap(allocator, val.object);
    }

    if (obj.get("tmux")) |val| {
        if (val == .string) {
            config.tmux = try allocator.dupe(u8, val.string);
        }
    }

    return config;
}

fn parseWrapperConfig(value: std.json.Value) !WrapperConfig {
    var config: WrapperConfig = .{};
    const obj = value.object;

    if (obj.get("autoDiary")) |v| {
        if (v != .bool) return error.InvalidJson;
        config.autoDiary = v.bool;
    }
    if (obj.get("autoReflect")) |v| {
        if (v != .bool) return error.InvalidJson;
        config.autoReflect = v.bool;
    }
    if (obj.get("askBeforeDiary")) |v| {
        if (v != .bool) return error.InvalidJson;
        config.askBeforeDiary = v.bool;
    }
    if (obj.get("askBeforeReflect")) |v| {
        if (v != .bool) return error.InvalidJson;
        config.askBeforeReflect = v.bool;
    }
    if (obj.get("minSessionSize")) |v| {
        if (v != .integer) return error.InvalidJson;
        config.minSessionSize = @intCast(v.integer);
    }
    if (obj.get("minDiaryCount")) |v| {
        if (v != .integer) return error.InvalidJson;
        config.minDiaryCount = @intCast(v.integer);
    }

    return config;
}

fn parseRecoveryConfig(value: std.json.Value) !RecoveryConfig {
    var config: RecoveryConfig = .{};
    const obj = value.object;

    if (obj.get("minActivity")) |v| {
        if (v != .integer) return error.InvalidJson;
        config.minActivity = @intCast(v.integer);
    }
    if (obj.get("limits")) |v| {
        if (v != .object) return error.InvalidJson;
        config.limits = try parseRecoveryLimits(v);
    }

    return config;
}

fn parseRecoveryLimits(value: std.json.Value) !RecoveryLimits {
    var limits: RecoveryLimits = .{};
    const obj = value.object;

    if (obj.get("userPrompts")) |v| {
        if (v != .integer) return error.InvalidJson;
        limits.userPrompts = @intCast(v.integer);
    }
    if (obj.get("promptLength")) |v| {
        if (v != .integer) return error.InvalidJson;
        limits.promptLength = @intCast(v.integer);
    }
    if (obj.get("toolCalls")) |v| {
        if (v != .integer) return error.InvalidJson;
        limits.toolCalls = @intCast(v.integer);
    }
    if (obj.get("lastMessageLength")) |v| {
        if (v != .integer) return error.InvalidJson;
        limits.lastMessageLength = @intCast(v.integer);
    }
    if (obj.get("errors")) |v| {
        if (v != .integer) return error.InvalidJson;
        limits.errors = @intCast(v.integer);
    }

    return limits;
}

fn parseIdleTimeConfig(value: std.json.Value) !IdleTimeConfig {
    var config: IdleTimeConfig = .{};
    const obj = value.object;

    if (obj.get("enabled")) |v| {
        if (v != .bool) return error.InvalidJson;
        config.enabled = v.bool;
    }
    if (obj.get("thresholdMinutes")) |v| {
        if (v != .integer) return error.InvalidJson;
        config.thresholdMinutes = @intCast(v.integer);
    }

    return config;
}

/// Find all .mopc-config.json files between home and project directory.
/// Returns paths in top-down order (from home toward project).
fn findParentConfigs(allocator: std.mem.Allocator, project_dir: []const u8) ![][]const u8 {
    const home = std.process.getEnvVarOwned(allocator, homeEnvVar()) catch {
        return &[_][]const u8{};
    };
    defer allocator.free(home);

    var paths = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (paths.items) |p| allocator.free(p);
        paths.deinit();
    }

    // Resolve project_dir to absolute path
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const abs_project = std.fs.cwd().realpath(project_dir, &path_buf) catch project_dir;

    // Start from project_dir's parent (not project_dir itself)
    var current = std.fs.path.dirname(abs_project) orelse return paths.toOwnedSlice();

    while (true) {
        // If we reached home, stop (don't check home for .mopc-config.json)
        if (std.mem.eql(u8, current, home)) break;

        // If current is shorter than home, we've gone too far up
        if (current.len < home.len) {
            // Check if we're actually above home (not a sibling path)
            const is_above = !std.mem.startsWith(u8, home, current);
            if (is_above) break;
        }

        // Check for .mopc-config.json in current directory
        const config_path = try std.fs.path.join(allocator, &.{ current, ".mopc-config.json" });
        errdefer allocator.free(config_path);

        // Try to access the file
        std.fs.cwd().access(config_path, .{}) catch {
            allocator.free(config_path);

            // Move to parent
            current = std.fs.path.dirname(current) orelse break;
            continue;
        };

        // File exists, add to list
        try paths.append(config_path);

        // Move to parent
        current = std.fs.path.dirname(current) orelse break;
    }

    // Reverse to get top-down order (from home toward project)
    std.mem.reverse([]const u8, paths.items);

    return paths.toOwnedSlice();
}

/// Load configuration with cascade: home -> parent dirs -> project
/// Config files are merged in order, with later configs overriding earlier ones.
pub fn loadCascadedConfig(allocator: std.mem.Allocator, project_dir: []const u8) !Config {
    // 1. Load home config (or default if not found)
    var config = loadHomeConfig(allocator) catch |err| blk: {
        if (err == error.FileNotFound) {
            break :blk try Config.init(allocator);
        }
        return err;
    };
    errdefer config.deinit();

    // 2. Find and merge parent configs (.mopc-config.json files)
    const parent_configs = try findParentConfigs(allocator, project_dir);
    defer {
        for (parent_configs) |p| allocator.free(p);
        allocator.free(parent_configs);
    }

    for (parent_configs) |config_path| {
        var parent_config = loadSingle(allocator, config_path) catch |err| {
            // Skip unreadable or unparseable files, continue with others
            if (err == error.FileNotFound or
                err == error.AccessDenied or
                err == error.InvalidJson)
            {
                continue;
            }
            return err;
        };
        defer parent_config.deinit();

        const merged = try mergeConfigs(allocator, config, parent_config);
        config.deinit();
        config = merged;
    }

    // 3. Load and merge project config
    var project_config = loadProjectConfig(allocator, project_dir) catch |err| {
        // If project config not found or invalid, return current config
        if (err == error.FileNotFound or err == error.InvalidJson) {
            return config;
        }
        return err;
    };
    defer project_config.deinit();

    const final = try mergeConfigs(allocator, config, project_config);
    config.deinit();

    return final;
}

/// Legacy function for backward compatibility - loads single config file
pub fn load(allocator: std.mem.Allocator, path: []const u8) !Config {
    return loadSingle(allocator, path);
}
