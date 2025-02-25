pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    std.debug.assert(target.result.cpu.arch.endian() == .little);

    const exe = b.addExecutable(.{
        .name = "metronome",
        .root_source_file = b.path("src/metronome-cli.zig"),
        .optimize = optimize,
        .target = target,
    });
    b.installArtifact(exe);

    const test_exe = b.addTest(.{
        .name = "metronome-test",
        .root_source_file = b.path("src/metronome-cli.zig"),
        .optimize = optimize,
        .target = target,
    });
    const run_test_exe = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test_exe.step);
}

const std = @import("std");
