const std = @import("std");
const builtin = @import("builtin");
const sysaudio = @import("mach_sysaudio");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("mach-flac", .{ .source_file = .{ .path = "src/lib.zig" } });
    _ = target;
    _ = optimize;
    _ = module;

    // TODO(build-system): Zig package manager currently can't handle transitive deps like this, so we need to use
    // these explicitly here:
    // const libflac_dep = b.dependency("flac", .{ .target = target, .optimize = optimize });

    // const main_test = b.addTest(.{
    //     .root_source_file = .{ .path = "src/lib.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });
    // main_test.linkLibrary(libflac_dep.artifact("flac"));
    // b.installArtifact(main_test);

    const test_step = b.step("test", "Run library tests");
    _ = test_step;
    // test_step.dependOn(&b.addRunArtifact(main_test).step);

    // const example = b.addExecutable(.{
    //     .name = "example-play",
    //     .root_source_file = .{ .path = "examples/play.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });
    // example.addModule("flac", module);
    // example.addModule("sysaudio", sysaudio.module(b, optimize, target));
    // example.linkLibrary(libflac_dep.artifact("flac"));
    // sysaudio.link(b, example, .{});
    // b.installArtifact(example);

    // const example_run_cmd = b.addRunArtifact(example);
    // example_run_cmd.step.dependOn(b.getInstallStep());

    // const example_run_step = b.step("run-example", "Run example");
    // example_run_step.dependOn(&example_run_cmd.step);
}
