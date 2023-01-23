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

const clap_pkg = Pkg{ .name = "clap", .source = .{ .path = "lib/zig-clap/clap.zig" } };
const crc_pkg = Pkg{ .name = "crc", .source = .{ .path = "lib/zig-crc/crc.zig" } };
const folders_pkg = Pkg{ .name = "folders", .source = .{ .path = "lib/known-folders/known-folders.zig" } };
const ston_pkg = Pkg{ .name = "ston", .source = .{ .path = "lib/ston/ston.zig" } };

const util_pkg = Pkg{
    .name = "util",
    .source = .{ .path = "src/common/util.zig" },
    .dependencies = &[_]Pkg{ clap_pkg, folders_pkg },
};

const format_pkg = Pkg{
    .name = "format",
    .source = .{ .path = "src/core/format.zig" },
    .dependencies = &[_]Pkg{ ston_pkg, util_pkg },
};

const pkgs = [_]Pkg{
    clap_pkg,
    crc_pkg,
    folders_pkg,
    format_pkg,
    ston_pkg,
    util_pkg,
};

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseFast);
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const strip = b.option(bool, "strip", "") orelse false;
    const options = BuildProgramOptions{
        .strip = strip,
        .target = target,
        .mode = mode,
    };

    const test_step = b.step("test", "Run all tests");
    testIt(b, test_step, "src/test.zig", options);

    for (core_exes) |name|
        _ = buildProgram(b, name, b.fmt("src/core/{s}.zig", .{name}), options);
    for (randomizer_exes) |name|
        _ = buildProgram(b, name, b.fmt("src/randomizers/{s}.zig", .{name}), options);
    for (other_exes) |name|
        _ = buildProgram(b, name, b.fmt("src/other/{s}.zig", .{name}), options);

    for (gui_exes) |tool| {
        const source = b.fmt("src/gui/{s}.zig", .{tool});
        const exe = buildProgram(b, tool, source, .{
            .strip = strip,
            .target = target,
            .mode = mode,
            .single_threaded = false,
        });

        buildAndLinkMd4c(exe);
        buildAndLinkNativeFileDialog(exe, target);
        buildAndLinkWebview(exe, target);
        exe.linkLibC();
        exe.linkLibCpp();
        exe.linkSystemLibrary("m");
    }
}

fn buildAndLinkWebview(exe: *LibExeObjStep, target: std.zig.CrossTarget) void {
    exe.addIncludePath("lib/webview");
    exe.addCSourceFile("lib/webview/webview.cc", &.{"-std=c++17"});
    switch (target.getOsTag()) {
        .windows => {
            exe.addIncludePath("lib/webview-c/ms.webview2/include");
            exe.linkSystemLibrary("advapi32");
            exe.linkSystemLibrary("shlwapi");
            exe.linkSystemLibrary("version");
        },
        .linux => {
            exe.linkSystemLibrary("webkit2gtk-4.0");
        },
        else => unreachable, // TODO: More os support
    }
}

fn buildAndLinkMd4c(exe: *LibExeObjStep) void {
    exe.addCSourceFiles(&.{
        "lib/md4c/src/entity.c",
        "lib/md4c/src/md4c.c",
        "lib/md4c/src/md4c-html.c",
    }, &.{});
    exe.addIncludePath("lib/md4c/src");
}

fn buildAndLinkNativeFileDialog(exe: *LibExeObjStep, target: std.zig.CrossTarget) void {
    exe.addCSourceFile("lib/nativefiledialog/src/nfd_common.c", &.{});
    exe.addIncludePath("lib/nativefiledialog/src/include");
    switch (target.getOsTag()) {
        .windows => {
            exe.addCSourceFile("lib/nativefiledialog/src/nfd_win.cpp", &.{});
            exe.linkSystemLibrary("uuid");
        },
        .linux => {
            exe.addCSourceFile("lib/nativefiledialog/src/nfd_zenity.c", &.{});
            exe.linkSystemLibrary("webkit2gtk-4.0");
        },
        else => unreachable, // TODO: More os support
    }
}

const BuildProgramOptions = struct {
    install: bool = true,
    strip: bool = false,
    single_threaded: bool = true,
    mode: std.builtin.Mode = .Debug,
    target: Target,
};

fn buildProgram(
    b: *Builder,
    name: []const u8,
    src: []const u8,
    opt: BuildProgramOptions,
) *LibExeObjStep {
    const step = b.step(name, b.fmt("Build and install {s}", .{name}));
    const exe = b.addExecutable(name, src);
    for (pkgs) |pkg|
        exe.addPackage(pkg);

    if (opt.install)
        step.dependOn(&b.addInstallArtifact(exe).step);

    exe.setTarget(opt.target);
    exe.setBuildMode(opt.mode);
    exe.single_threaded = opt.single_threaded;
    exe.strip = opt.strip;
    step.dependOn(&exe.step);
    b.default_step.dependOn(step);

    return exe;
}

fn testIt(
    b: *Builder,
    parent_step: *Step,
    src: []const u8,
    opt: BuildProgramOptions,
) void {
    const exe = b.addTest(src);
    for (pkgs) |pkg|
        exe.addPackage(pkg);

    exe.setTarget(opt.target);
    exe.setBuildMode(opt.mode);
    exe.single_threaded = opt.single_threaded;
    exe.strip = opt.strip;
    parent_step.dependOn(&exe.step);
}
