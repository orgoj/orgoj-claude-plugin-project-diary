const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Single executable with all commands
    const exe = b.addExecutable(.{
        .name = "mopc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // Run command (for development)
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run mopc");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_step = b.step("test", "Run all tests");

    // Test main
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_main_tests = b.addRunArtifact(main_tests);
    test_step.dependOn(&run_main_tests.step);

    // Test shared modules (will be added as they are created)
    const shared_modules = [_][]const u8{ "config", "paths" };
    inline for (shared_modules) |mod| {
        const mod_test = b.addTest(.{
            .root_source_file = b.path(b.fmt("src/shared/{s}.zig", .{mod})),
            .target = target,
            .optimize = optimize,
        });
        const run_mod_test = b.addRunArtifact(mod_test);
        test_step.dependOn(&run_mod_test.step);
    }
}
