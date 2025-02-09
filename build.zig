pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    std.debug.assert(target.result.cpu.arch.endian() == .little);

    const exes = [_][]const u8{
        "src/metronome-cli.zig",
        // "src/core/tm35-disassemble-scripts.zig",
        // "src/core/tm35-gen3-offsets.zig",
        // "src/core/tm35-identify.zig",
        // "src/core/tm35-nds-extract.zig",
    };

    const test_step = b.step("test", "Run all tests");
    for (exes) |path| {
        const basename = std.fs.path.basename(path);
        const name = basename[0 .. basename.len - 4]; // Remove `.zig`
        const test_name = b.fmt("test-{s}", .{name});

        const step = b.step(name, b.fmt("Build and install {s}", .{name}));
        const exe_test_step = b.step(test_name, b.fmt("Test {s}", .{name}));
        const exe = b.addExecutable(.{
            .name = name,
            .root_source_file = b.path(path),
            .optimize = optimize,
            .target = target,
        });
        const test_exe = b.addTest(.{
            .name = test_name,
            .root_source_file = b.path(path),
            .optimize = optimize,
            .target = target,
        });
        const run_test = b.addRunArtifact(test_exe);

        step.dependOn(&b.addInstallArtifact(exe, .{}).step);
        step.dependOn(&exe.step);
        b.default_step.dependOn(step);
        exe_test_step.dependOn(&run_test.step);
        test_step.dependOn(exe_test_step);
    }
}

const std = @import("std");
