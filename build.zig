const builtin = @import("builtin");
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

const randomizer_tools = [_][]const u8{
    "tm35-rand-starters",
    "tm35-rand-learned-moves",
    "tm35-rand-stats",
    "tm35-rand-wild",
    "tm35-rand-parties",
};

const gui_tools = [_][]const u8{
    "tm35-randomizer",
};

const lib_pkgs = [_][2][]const u8{
    [_][]const u8{ "clap", "lib/zig-clap/clap.zig" },
    [_][]const u8{ "fun", "lib/fun-with-zig/fun.zig" },
    [_][]const u8{ "crc", "lib/zig-crc/crc.zig" },
};

const src_pkgs = [_][2][]const u8{
    [_][]const u8{ "util", "src/common/util.zig" },
};

const pkgs = lib_pkgs ++ src_pkgs;

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseSafe);
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(null); // TODO: We don't actually support all targets. Provide the actual subset we do support
    const os = switch (target) {
        .Native => builtin.os,
        .Cross => |c| c.os,
    };

    const fmt_step = b.addFmt([_][]const u8{
        "build.zig",
        "src",
    });
    b.default_step.dependOn(&fmt_step.step);

    const test_step = b.step("test", "Run all tests");
    for (src_pkgs) |pkg| {
        const pkg_test = b.addTest(pkg[1]);
        test_step.dependOn(&pkg_test.step);
    }

    inline for (core_tools) |tool, i| {
        const source = "src/core/" ++ tool ++ ".zig";
        const exe_test = b.addTest(source);
        const exe = b.addExecutable(tool, source);
        for (pkgs) |pkg| {
            exe_test.addPackagePath(pkg[0], pkg[1]);
            exe.addPackagePath(pkg[0], pkg[1]);
        }

        exe.install();
        exe_test.setBuildMode(mode);
        exe.setBuildMode(mode);
        exe_test.single_threaded = true;
        exe.single_threaded = true;
        test_step.dependOn(&exe_test.step);
        b.default_step.dependOn(&exe.step);
    }

    inline for (randomizer_tools) |tool, i| {
        const source = "src/randomizers/" ++ tool ++ ".zig";
        const exe_test = b.addTest(source);
        const exe = b.addExecutable(tool, source);
        for (pkgs) |pkg| {
            exe_test.addPackagePath(pkg[0], pkg[1]);
            exe.addPackagePath(pkg[0], pkg[1]);
        }

        exe.install();
        exe_test.setBuildMode(mode);
        exe.setBuildMode(mode);
        exe_test.single_threaded = true;
        exe.single_threaded = true;
        test_step.dependOn(&exe_test.step);
        b.default_step.dependOn(&exe.step);
    }

    const lib_cflags = [_][]const u8{"-D_POSIX_C_SOURCE=200809L"};
    inline for (gui_tools) |tool, i| {
        const source = "src/gui/" ++ tool ++ ".zig";
        const exe_test = b.addTest(source);
        const exe = b.addExecutable(tool, source);
        for (pkgs) |pkg| {
            exe_test.addPackagePath(pkg[0], pkg[1]);
            exe.addPackagePath(pkg[0], pkg[1]);
        }

        switch (os) {
            .windows => {
                exe.addIncludeDir("lib/nuklear/demo/gdi");
                exe.addCSourceFile("src/gui/nuklear/gdi.c", lib_cflags);
                exe.addCSourceFile("lib/nativefiledialog/src/nfd_win.cpp", lib_cflags);
                exe.linkSystemLibrary("user32");
                exe.linkSystemLibrary("gdi32");
                exe.linkSystemLibrary("Msimg32");
            },
            .linux => {
                exe.addIncludeDir("lib/nuklear/demo/x11_xft");
                exe.addIncludeDir("/usr/include/freetype2");
                exe.addCSourceFile("src/gui/nuklear/x11.c", lib_cflags);
                exe.addCSourceFile("lib/nativefiledialog/src/nfd_zenity.c", lib_cflags);
                exe.linkSystemLibrary("X11");
                exe.linkSystemLibrary("Xft");
            },
            else => {}, // TODO: More os support
        }

        exe.addIncludeDir("lib/nativefiledialog/src/include");
        exe.addIncludeDir("lib/nuklear");
        exe.addIncludeDir("src/gui/nuklear");
        exe.addCSourceFile("src/gui/nuklear/impl.c", lib_cflags);
        exe.addCSourceFile("lib/nativefiledialog/src/nfd_common.c", lib_cflags);
        exe.linkSystemLibrary("c");
        exe.linkSystemLibrary("m");

        exe.install();
        exe_test.setBuildMode(mode);
        exe.setBuildMode(mode);
        exe_test.single_threaded = true;
        exe.single_threaded = true;
        test_step.dependOn(&exe_test.step);
        b.default_step.dependOn(&exe.step);
    }
}
