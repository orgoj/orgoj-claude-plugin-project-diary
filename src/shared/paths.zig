const std = @import("std");

/// Returns the .claude/diary directory path
pub fn getDiaryDir(allocator: std.mem.Allocator, project_dir: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ project_dir, ".claude", "diary" });
}

/// Returns the .claude/diary/recovery directory path
pub fn getRecoveryDir(allocator: std.mem.Allocator, project_dir: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ project_dir, ".claude", "diary", "recovery" });
}

/// Returns the .claude/diary/timestamps directory path
pub fn getTimestampDir(allocator: std.mem.Allocator, project_dir: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ project_dir, ".claude", "diary", "timestamps" });
}

/// Returns the .claude/diary/processed directory path
pub fn getProcessedDir(allocator: std.mem.Allocator, project_dir: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ project_dir, ".claude", "diary", "processed" });
}

/// Returns the .claude/diary/reflections directory path
pub fn getReflectionsDir(allocator: std.mem.Allocator, project_dir: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ project_dir, ".claude", "diary", "reflections" });
}

/// Returns the .claude/diary/.config.json file path
pub fn getConfigPath(allocator: std.mem.Allocator, project_dir: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ project_dir, ".claude", "diary", ".config.json" });
}

/// Creates directory if it doesn't exist, handles PathAlreadyExists
/// Creates intermediate directories as needed
pub fn ensureDirExists(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
}
