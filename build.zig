const builtin = @import("builtin");
const std = @import("std");

const mem = std.mem;

const Step = std.build.Step;
const Builder = std.build.Builder;
const RunStep = std.build.RunStep;
const LibExeObjStep = std.build.LibExeObjStep;

const src_folder = "src";
const lib_folder = "lib";
const tools_folder = "tools";

const tool_exes = [_][]const u8{
    "asm-macros-to-zig-struct",
};

const core_exes = [_][]const u8{
    "tm35-apply",
    "tm35-disassemble-scripts",
    "tm35-gen3-offsets",
    "tm35-load",
    "tm35-nds-extract",
};

const randomizer_exes = [_][]const u8{
    "tm35-rand-starters",
    "tm35-rand-learned-moves",
    "tm35-rand-stats",
    "tm35-rand-wild",
    "tm35-rand-parties",
};

const gui_exes = [_][]const u8{
    "tm35-randomizer",
};

const lib_pkgs = [_][2][]const u8{
    [_][]const u8{ "clap", lib_folder ++ "/zig-clap/clap.zig" },
    [_][]const u8{ "fun", lib_folder ++ "/fun-with-zig/fun.zig" },
    [_][]const u8{ "crc", lib_folder ++ "/zig-crc/crc.zig" },
};

const src_pkgs = [_][2][]const u8{
    [_][]const u8{ "util", src_folder ++ "/common/util.zig" },
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
        src_folder,
        tools_folder,
    });
    b.default_step.dependOn(&fmt_step.step);

    const test_step = b.step("test", "Run all tests");
    for (src_pkgs) |pkg| {
        const pkg_test = b.addTest(pkg[1]);
        test_step.dependOn(&pkg_test.step);
    }

    inline for (tool_exes) |name, i|
        buildAndInstallCmdlineProgram(b, test_step, false, mode, name, tools_folder ++ "/" ++ name ++ ".zig");
    inline for (core_exes) |name, i|
        buildAndInstallCmdlineProgram(b, test_step, true, mode, name, src_folder ++ "/core/" ++ name ++ ".zig");
    inline for (randomizer_exes) |name, i|
        buildAndInstallCmdlineProgram(b, test_step, true, mode, name, src_folder ++ "/randomizers/" ++ name ++ ".zig");

    const lib_cflags = [_][]const u8{"-D_POSIX_C_SOURCE=200809L"};
    inline for (gui_exes) |tool, i| {
        const source = src_folder ++ "/gui/" ++ tool ++ ".zig";
        const exe_test = b.addTest(source);
        const exe = b.addExecutable(tool, source);
        for (pkgs) |pkg| {
            exe_test.addPackagePath(pkg[0], pkg[1]);
            exe.addPackagePath(pkg[0], pkg[1]);
        }

        switch (os) {
            .windows => {
                exe.addIncludeDir(lib_folder ++ "/nuklear/demo/gdi");
                exe.addCSourceFile(src_folder ++ "/gui/nuklear/gdi.c", lib_cflags);
                exe.addCSourceFile(lib_folder ++ "/nativefiledialog/src/nfd_win.cpp", lib_cflags);
                exe.linkSystemLibrary("user32");
                exe.linkSystemLibrary("gdi32");
                exe.linkSystemLibrary("Msimg32");
            },
            .linux => {
                exe.addIncludeDir(lib_folder ++ "/nuklear/demo/x11_xft");
                exe.addIncludeDir("/usr/include/freetype2");
                exe.addCSourceFile(src_folder ++ "/gui/nuklear/x11.c", lib_cflags);
                exe.addCSourceFile(lib_folder ++ "/nativefiledialog/src/nfd_zenity.c", lib_cflags);
                exe.linkSystemLibrary("X11");
                exe.linkSystemLibrary("Xft");
            },
            else => {}, // TODO: More os support
        }

        exe.addIncludeDir(lib_folder ++ "/nativefiledialog/src/include");
        exe.addIncludeDir(lib_folder ++ "/nuklear");
        exe.addIncludeDir(src_folder ++ "/gui/nuklear");
        exe.addCSourceFile(src_folder ++ "/gui/nuklear/impl.c", lib_cflags);
        exe.addCSourceFile(lib_folder ++ "/nativefiledialog/src/nfd_common.c", lib_cflags);
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

fn buildAndInstallCmdlineProgram(b: *Builder, test_step: *Step, install: bool, mode: builtin.Mode, name: []const u8, src: []const u8) void {
    const exe_test = b.addTest(src);
    const exe = b.addExecutable(name, src);
    for (pkgs) |pkg| {
        exe_test.addPackagePath(pkg[0], pkg[1]);
        exe.addPackagePath(pkg[0], pkg[1]);
    }

    if (install)
        exe.install();
    exe_test.setBuildMode(mode);
    exe.setBuildMode(mode);
    exe_test.single_threaded = true;
    exe.single_threaded = true;
    test_step.dependOn(&exe_test.step);
    b.default_step.dependOn(&exe.step);
}
