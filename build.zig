const builtin = @import("builtin");
const std = @import("std");

const Builder = std.build.Builder;
const Mode = builtin.Mode;

pub fn build(b: *Builder) void {
    const test_all_step = b.step("test", "Run all tests in all modes.");
    inline for ([_]Mode{ Mode.Debug, Mode.ReleaseFast, Mode.ReleaseSafe, Mode.ReleaseSmall }) |test_mode| {
        const mode_str = comptime modeToString(test_mode);

        const t = b.addTest("src/test.zig");
        t.addPackagePath("bench", "lib/zig-bench/bench.zig");
        t.addPackagePath("fun", "lib/fun-with-zig/fun.zig");
        t.addPackagePath("crc", "lib/zig-crc/crc.zig");
        t.setBuildMode(test_mode);
        t.setNamePrefix(mode_str ++ " ");

        const test_step = b.step("test-" ++ mode_str, "Run all tests in " ++ mode_str ++ ".");
        test_step.dependOn(&t.step);
        test_all_step.dependOn(test_step);
    }

    const fmt_step = b.addFmt([_][]const u8{
        "build.zig",
        "src",
    });
    b.default_step.dependOn(&fmt_step.step);
    b.default_step.dependOn(test_all_step);
}

fn modeToString(mode: Mode) []const u8 {
    return switch (mode) {
        Mode.Debug => "debug",
        Mode.ReleaseFast => "release-fast",
        Mode.ReleaseSafe => "release-safe",
        Mode.ReleaseSmall => "release-small",
    };
}
