const std = @import("std");

const mem = std.mem;

const Builder = std.build.Builder;
const RunStep = std.build.RunStep;
const LibExeObjStep = std.build.LibExeObjStep;

const folder = "src";
const tools = [_][]const u8{
    "tm35-gen5-load",
    "tm35-rand-starters",
    "tm35-gen4-apply",
    "tm35-rand-learned-moves",
    "tm35-gen5-apply",
    "tm35-rand-stats",
    "tm35-rand-wild",
    "tm35-nds-extract",
    "tm35-gen3-offsets",
    "tm35-gen4-load",
    "tm35-gen3-load",
    "tm35-gen3-disassemble-scripts",
    "tm35-rand-parties",
    "tm35-gen3-apply",
};

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseSafe);
    const mode = b.standardReleaseOptions();

    const fmt_step = b.addFmt([_][]const u8{
        "build.zig",
        "src",
    });

    b.default_step.dependOn(&fmt_step.step);

    inline for (tools) |tool, i| {
        const exe = b.addExecutable(tool, "src/" ++ tool ++ ".zig");
        exe.addPackagePath("clap", "lib/zig-clap/clap.zig");
        exe.addPackagePath("fun", "lib/fun-with-zig/fun.zig");
        exe.addPackagePath("crc", "lib/zig-crc/crc.zig");
        exe.setBuildMode(mode);
        exe.install();
        b.default_step.dependOn(&exe.step);
    }
}
