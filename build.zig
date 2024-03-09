const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flac_dep = b.dependency("flac", .{
        .target = target,
        .optimize = optimize,
    });

    const module = b.addModule("mach-flac", .{
        .root_source_file = .{ .path = "src/lib.zig" },
    });
    module.linkLibrary(flac_dep.artifact("flac"));

    const main_test = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(main_test);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(main_test).step);
}
