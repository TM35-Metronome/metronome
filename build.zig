const builtin = @import("builtin");
const std = @import("std");

const Builder = std.build.Builder;
const Mode = builtin.Mode;

pub fn build(b: *Builder) void {
    const test_all_step = b.step("test", "Run all tests in all modes.");
    inline for ([]Mode{ Mode.Debug, Mode.ReleaseFast, Mode.ReleaseSafe, Mode.ReleaseSmall }) |test_mode| {
        const mode_str = comptime modeToString(test_mode);

        const t = b.addTest("src/index.zig");
        t.addPackagePath("bench", "lib/zig-bench/src/index.zig");
        t.addPackagePath("fun", "lib/fun-with-zig/index.zig");
        t.setBuildMode(test_mode);
        t.setNamePrefix(mode_str ++ " ");

        const test_step = b.step("test-" ++ mode_str, "Run all tests in " ++ mode_str ++ ".");
        test_step.dependOn(&t.step);
        test_all_step.dependOn(test_step);
    }

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
