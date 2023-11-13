const std = @import("std");
const builtin = @import("builtin");
const sysaudio = @import("mach_sysaudio");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("mach-flac", .{ .source_file = .{ .path = "src/lib.zig" } });

    const sysaudio_dep = b.dependency("mach_sysaudio", .{ .target = target, .optimize = optimize });

    const main_test = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    link(b, main_test);
    b.installArtifact(main_test);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(main_test).step);

    const example = b.addExecutable(.{
        .name = "example-play",
        .root_source_file = .{ .path = "examples/play.zig" },
        .target = target,
        .optimize = optimize,
    });
    example.addModule("mach-flac", module);
    example.addModule("mach-sysaudio", sysaudio_dep.module("mach-sysaudio"));
    link(b, example);
    sysaudio.link(b, example);
    b.installArtifact(example);

    const example_run_cmd = b.addRunArtifact(example);
    example_run_cmd.step.dependOn(b.getInstallStep());

    const example_run_step = b.step("run-example", "Run example");
    example_run_step.dependOn(&example_run_cmd.step);
}

pub fn link(b: *std.Build, step: *std.build.CompileStep) void {
    const libflac_dep = b.dependency("flac", .{ .target = step.target, .optimize = step.optimize });
    step.linkLibrary(libflac_dep.artifact("flac"));
}
