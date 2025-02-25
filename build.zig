pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const rom_directory = b.option(
        []const u8,
        "rom-directory",
        "Path to directory containing rom files",
    );

    std.debug.assert(target.result.cpu.arch.endian() == .little);

    const exe = b.addExecutable(.{
        .name = "metronome",
        .root_source_file = b.path("src/metronome-cli.zig"),
        .optimize = optimize,
        .target = target,
    });
    b.installArtifact(exe);

    const test_options = b.addOptions();
    test_options.addOption(?[]const u8, "rom_directory", rom_directory);

    const test_exe = b.addTest(.{
        .name = "metronome-test",
        .root_source_file = b.path("src/metronome-cli.zig"),
        .optimize = optimize,
        .target = target,
    });
    test_exe.root_module.addOptions("build_options", test_options);

    const test_step = b.step("test", "Run unit tests");
    const run_test_exe = b.addRunArtifact(test_exe);
    test_step.dependOn(&run_test_exe.step);
}

const std = @import("std");
