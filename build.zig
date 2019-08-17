const std = @import("std");

const mem = std.mem;

const Builder = std.build.Builder;
const RunStep = std.build.RunStep;
const LibExeObjStep = std.build.LibExeObjStep;

const folder = "src";
const core_tools = [_][]const u8{
    "tm35-apply",
    "tm35-gen3-disassemble-scripts",
    "tm35-gen3-offsets",
    "tm35-load",
    "tm35-nds-extract",
};

const filter_tools = [_][]const u8{
    "tm35-rand-starters",
    "tm35-rand-learned-moves",
    "tm35-rand-stats",
    "tm35-rand-wild",
    "tm35-rand-parties",
};

const gui_tools = [_][]const u8{"tm35-randomizer"};

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseSafe);
    const mode = b.standardReleaseOptions();

    const fmt_step = b.addFmt([_][]const u8{
        "build.zig",
        "src",
    });

    b.default_step.dependOn(&fmt_step.step);

    inline for (core_tools) |tool, i| {
        const exe = b.addExecutable(tool, "src/core/" ++ tool ++ ".zig");
        exe.addPackagePath("clap", "lib/zig-clap/clap.zig");
        exe.addPackagePath("fun", "lib/fun-with-zig/fun.zig");
        exe.addPackagePath("crc", "lib/zig-crc/crc.zig");
        exe.addPackagePath("format", "src/common/parser.zig");
        exe.setBuildMode(mode);
        exe.install();
        b.default_step.dependOn(&exe.step);
    }

    inline for (filter_tools) |tool, i| {
        const exe = b.addExecutable(tool, "src/filter/" ++ tool ++ ".zig");
        exe.addPackagePath("clap", "lib/zig-clap/clap.zig");
        exe.addPackagePath("format", "src/common/parser.zig");
        exe.setBuildMode(mode);
        exe.install();
        b.default_step.dependOn(&exe.step);
    }

    const lib_cflags = [_][]const u8{ "-std=c89", "-D_POSIX_C_SOURCE=200809L" };
    inline for (gui_tools) |tool, i| {
        const exe = b.addExecutable(tool, "src/gui/" ++ tool ++ ".zig");
        exe.addPackagePath("clap", "lib/zig-clap/clap.zig");
        exe.addPackagePath("format", "src/common/parser.zig");
        exe.addIncludeDir("lib/nuklear");
        exe.addIncludeDir("lib/nuklear/demo/x11_xft");
        exe.addIncludeDir("src/gui/nuklear");
        exe.addIncludeDir("/usr/include/freetype2");
        exe.addCSourceFile("src/gui/nuklear/impl.c", lib_cflags);
        exe.addCSourceFile("src/gui/nuklear/x11.c", lib_cflags);
        exe.linkSystemLibrary("c");
        exe.linkSystemLibrary("m");
        exe.linkSystemLibrary("X11");
        exe.linkSystemLibrary("Xft");
        exe.setBuildMode(mode);
        exe.install();
        b.default_step.dependOn(&exe.step);
    }
}
