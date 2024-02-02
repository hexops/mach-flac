const std = @import("std");
const builtin = @import("builtin");
const sysaudio = @import("mach_sysaudio");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sysaudio_dep = b.dependency("mach_sysaudio", .{
        .target = target,
        .optimize = optimize,
    });
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
    sysaudio.addPaths(&main_test.root_module);
    b.installArtifact(main_test);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(main_test).step);

    const example = b.addExecutable(.{
        .name = "example-play",
        .root_source_file = .{ .path = "examples/play.zig" },
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("mach-flac", module);
    example.root_module.addImport("mach-sysaudio", sysaudio_dep.module("mach-sysaudio"));
    sysaudio.addPaths(&example.root_module);
    b.installArtifact(example);

    const example_run_cmd = b.addRunArtifact(example);
    example_run_cmd.step.dependOn(b.getInstallStep());

    const example_run_step = b.step("run-example", "Run example");
    example_run_step.dependOn(&example_run_cmd.step);
}
