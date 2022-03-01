const std = @import("std");

const mem = std.mem;

const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const Pkg = std.build.Pkg;
const RunStep = std.build.RunStep;
const Step = std.build.Step;
const Target = std.zig.CrossTarget;

const core_exes = [_][]const u8{
    "tm35-apply",
    "tm35-disassemble-scripts",
    "tm35-gen3-offsets",
    "tm35-identify",
    "tm35-load",
    "tm35-nds-extract",
};

const randomizer_exes = [_][]const u8{
    "tm35-rand-pokemons",
    "tm35-rand-machines",
    "tm35-rand-names",
    "tm35-rand-trainers",
    "tm35-rand-pokeball-items",
    "tm35-rand-starters",
    "tm35-rand-static",
    "tm35-rand-wild",
    "tm35-random-stones",
};

const other_exes = [_][]const u8{
    "tm35-generate-site",
    "tm35-misc",
    "tm35-noop",
    "tm35-no-trade-evolutions",
};

const gui_exes = [_][]const u8{
    "tm35-randomizer",
};

const clap_pkg = Pkg{ .name = "clap", .path = .{ .path = "lib/zig-clap/clap.zig" } };
const crc_pkg = Pkg{ .name = "crc", .path = .{ .path = "lib/zig-crc/crc.zig" } };
const folders_pkg = Pkg{ .name = "folders", .path = .{ .path = "lib/known-folders/known-folders.zig" } };
const ston_pkg = Pkg{ .name = "ston", .path = .{ .path = "lib/ston/ston.zig" } };
const ziter_pkg = Pkg{ .name = "ziter", .path = .{ .path = "lib/ziter/ziter.zig" } };

const util_pkg = Pkg{
    .name = "util",
    .path = .{ .path = "src/common/util.zig" },
    .dependencies = &[_]Pkg{
        clap_pkg,
        folders_pkg,
    },
};

const format_pkg = Pkg{
    .name = "format",
    .path = .{ .path = "src/core/format.zig" },
    .dependencies = &[_]Pkg{
        ston_pkg,
        util_pkg,
    },
};

const pkgs = [_]Pkg{
    clap_pkg,
    crc_pkg,
    folders_pkg,
    format_pkg,
    ston_pkg,
    util_pkg,
    ziter_pkg,
};

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseFast);
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const strip = b.option(bool, "strip", "") orelse false;

    const test_step = b.step("test", "Run all tests");
    testIt(b, test_step, mode, "src/test.zig");

    const options = BuildProgramOptions{ .strip = strip, .target = target, .mode = mode };
    for (core_exes) |name|
        _ = buildProgram(b, name, b.fmt("src/core/{s}.zig", .{name}), options);
    for (randomizer_exes) |name|
        _ = buildProgram(b, name, b.fmt("src/randomizers/{s}.zig", .{name}), options);
    for (other_exes) |name|
        _ = buildProgram(b, name, b.fmt("src/other/{s}.zig", .{name}), options);

    const lib_cflags = &[_][]const u8{
        "-D_POSIX_C_SOURCE=200809L",
        "-fno-sanitize=undefined", // Nuklear trips the undefined sanitizer https://github.com/Immediate-Mode-UI/Nuklear/issues/94
    };
    for (gui_exes) |tool| {
        const source = b.fmt("src/gui/{s}.zig", .{tool});
        const exe = buildProgram(b, tool, source, options);

        switch (target.getOsTag()) {
            .windows => {
                exe.addIncludeDir("lib/nuklear/demo/gdi");
                exe.addCSourceFile("src/gui/nuklear/gdi.c", lib_cflags);
                exe.addCSourceFile("lib/nativefiledialog/src/nfd_win.cpp", lib_cflags);
                exe.linkSystemLibrary("user32");
                exe.linkSystemLibrary("gdi32");
                exe.linkSystemLibrary("uuid");
                exe.linkSystemLibrary("msimg32");
            },
            .linux => {
                exe.addIncludeDir("lib/nuklear/demo/x11_xft");
                exe.addSystemIncludeDir("/usr/include/freetype2");
                exe.addSystemIncludeDir("/usr/include/");

                exe.addLibPath("/usr/lib/");
                exe.addLibPath("/usr/lib/x86_64-linux-gnu");
                exe.linkSystemLibrary("fontconfig");
                exe.linkSystemLibrary("freetype");
                exe.linkSystemLibrary("X11");
                exe.linkSystemLibrary("xcb");
                exe.linkSystemLibrary("Xft");
                exe.linkSystemLibrary("xrender");

                exe.addCSourceFile("src/gui/nuklear/x11.c", lib_cflags);
                exe.addCSourceFile("lib/nativefiledialog/src/nfd_zenity.c", lib_cflags);
            },
            else => unreachable, // TODO: More os support
        }

        exe.addIncludeDir("lib/nativefiledialog/src/include");
        exe.addIncludeDir("lib/nuklear");
        exe.addIncludeDir("src/gui/nuklear");
        exe.addCSourceFile("src/gui/nuklear/impl.c", lib_cflags);
        exe.addCSourceFile("lib/nativefiledialog/src/nfd_common.c", lib_cflags);
        exe.linkLibC();
        exe.linkSystemLibrary("m");
    }
}

const BuildProgramOptions = struct {
    install: bool = true,
    strip: bool = false,
    mode: std.builtin.Mode = .Debug,
    target: Target,
};

fn buildProgram(
    b: *Builder,
    name: []const u8,
    src: []const u8,
    opt: BuildProgramOptions,
) *LibExeObjStep {
    const step = b.step(name, "");
    const exe = b.addExecutable(name, src);
    for (pkgs) |pkg|
        exe.addPackage(pkg);

    if (opt.install)
        step.dependOn(&b.addInstallArtifact(exe).step);

    exe.setTarget(opt.target);
    exe.setBuildMode(opt.mode);
    exe.single_threaded = true;
    exe.strip = opt.strip;
    step.dependOn(&exe.step);
    b.default_step.dependOn(step);

    return exe;
}

fn testIt(b: *Builder, parent_step: *Step, mode: std.builtin.Mode, src: []const u8) void {
    const exe_test = b.addTest(src);
    for (pkgs) |pkg|
        exe_test.addPackage(pkg);

    exe_test.setBuildMode(mode);
    exe_test.single_threaded = true;
    parent_step.dependOn(&exe_test.step);
}
