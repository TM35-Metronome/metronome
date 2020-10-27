const builtin = @import("builtin");
const std = @import("std");

const mem = std.mem;

const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const Pkg = std.build.Pkg;
const RunStep = std.build.RunStep;
const Step = std.build.Step;
const Target = std.build.Target;

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
    "tm35-identify",
    "tm35-load",
    "tm35-nds-extract",
};

const randomizer_exes = [_][]const u8{
    "tm35-rand-learned-moves",
    "tm35-rand-machines",
    "tm35-rand-parties",
    "tm35-rand-pokeball-items",
    "tm35-rand-starters",
    "tm35-rand-static",
    "tm35-rand-stats",
    "tm35-rand-wild",
    "tm35-random-stones",
};

const other_exes = [_][]const u8{
    "tm35-generate-site",
    "tm35-misc",
    "tm35-no-trade-evolutions",
};

const gui_exes = [_][]const u8{
    "tm35-randomizer",
};

const clap_pkg = Pkg{
    .name = "clap",
    .path = lib_folder ++ "/zig-clap/clap.zig",
};
const crc_pkg = Pkg{
    .name = "crc",
    .path = lib_folder ++ "/zig-crc/crc.zig",
};
const mecha_pkg = Pkg{
    .name = "mecha",
    .path = lib_folder ++ "/mecha/mecha.zig",
};

const util_pkg = Pkg{
    .name = "util",
    .path = src_folder ++ "/common/util.zig",

    // Why is this field no const? I have to do
    // this awful hack because of it...
    .dependencies = &struct {
        var dep = [2]Pkg{
            clap_pkg,
            mecha_pkg,
        };
    }.dep,
};

const pkgs = [_]Pkg{
    clap_pkg,
    crc_pkg,
    mecha_pkg,
    util_pkg,
};

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseFast);
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{
        .whitelist = &[_]Target{
            Target.parse(.{ .arch_os_abi = "x86_64-linux-gnu" }) catch unreachable,
            Target.parse(.{ .arch_os_abi = "x86_64-windows-gnu" }) catch unreachable,
        },
    });

    const skip_release = b.option(bool, "skip-release", "Main test suite skips release builds") orelse false;

    // Zig fmt doesn't work on windows, so let's just skip it
    if (builtin.os.tag != .windows) {
        const fmt_step = b.addFmt(&[_][]const u8{
            "build.zig",
            src_folder,
            tools_folder,
        });
        b.default_step.dependOn(&fmt_step.step);
    }

    const modes_to_test: []const builtin.Mode = if (skip_release)
        &[_]builtin.Mode{.Debug}
    else
        &[_]builtin.Mode{ .Debug, .ReleaseFast, .ReleaseSafe, .ReleaseSmall };

    const test_step = b.step("test", "Run all tests");
    const build_all_step = b.step("build-all", "Build all programs");
    const build_cli_step = b.step("build-cli", "Build cli programs");
    const build_gui_step = b.step("build-gui", "Build gui programs");
    const build_tools_step = b.step("build-tools", "Build development tools");
    const build_core_step = b.step("build-core", "Build core programs (tm35-load, tm35-store)");
    const build_randomizers_step = b.step("build-randomizers", "Build randomizers");
    b.default_step.dependOn(build_all_step);
    build_all_step.dependOn(build_cli_step);
    build_all_step.dependOn(build_gui_step);
    build_cli_step.dependOn(build_tools_step);
    build_cli_step.dependOn(build_core_step);
    build_cli_step.dependOn(build_randomizers_step);

    for (modes_to_test) |test_mode| {
        const util_test = b.addTest(util_pkg.path);
        for (pkgs) |pkg|
            util_test.addPackage(pkg);
        util_test.setNamePrefix(b.fmt("{}-", .{@tagName(mode)}));
        test_step.dependOn(&util_test.step);

        for (tool_exes) |name|
            testCmdlineProgram(b, test_step, test_mode, b.fmt("{}/{}.zig", .{ tools_folder, name }));
        for (core_exes) |name|
            testCmdlineProgram(b, test_step, test_mode, b.fmt("{}/core/{}.zig", .{ src_folder, name }));
        for (randomizer_exes) |name|
            testCmdlineProgram(b, test_step, test_mode, b.fmt("{}/randomizers/{}.zig", .{ src_folder, name }));
        for (other_exes) |name|
            testCmdlineProgram(b, test_step, test_mode, b.fmt("{}/other/{}.zig", .{ src_folder, name }));

        for (gui_exes) |tool, i| {
            const source = b.fmt("{}/gui/{}.zig", .{ src_folder, tool });
            const exe_test = b.addTest(source);
            for (pkgs) |pkg|
                exe_test.addPackage(pkg);

            exe_test.setNamePrefix(b.fmt("{}-", .{@tagName(mode)}));
            exe_test.setBuildMode(test_mode);
            exe_test.single_threaded = true;
            test_step.dependOn(&exe_test.step);
        }
    }

    for (tool_exes) |name, i|
        buildAndInstallCmdlineProgram(b, build_tools_step, false, target, mode, name, b.fmt("{}/{}.zig", .{ tools_folder, name }));
    for (core_exes) |name, i|
        buildAndInstallCmdlineProgram(b, build_core_step, true, target, mode, name, b.fmt("{}/core/{}.zig", .{ src_folder, name }));
    for (randomizer_exes) |name, i|
        buildAndInstallCmdlineProgram(b, build_randomizers_step, true, target, mode, name, b.fmt("{}/randomizers/{}.zig", .{ src_folder, name }));
    for (other_exes) |name, i|
        buildAndInstallCmdlineProgram(b, build_randomizers_step, true, target, mode, name, b.fmt("{}/other/{}.zig", .{ src_folder, name }));

    const lib_cflags = &[_][]const u8{
        "-D_POSIX_C_SOURCE=200809L",
        "-fno-sanitize=undefined", // Nuklear trips the undefined sanitizer https://github.com/Immediate-Mode-UI/Nuklear/issues/94
    };
    for (gui_exes) |tool, i| {
        const source = b.fmt("{}/gui/{}.zig", .{ src_folder, tool });
        const exe = b.addExecutable(tool, source);
        for (pkgs) |pkg|
            exe.addPackage(pkg);

        switch (target.getOsTag()) {
            .windows => {
                exe.addIncludeDir(b.fmt("{}/nuklear/demo/gdi", .{lib_folder}));
                exe.addCSourceFile(b.fmt("{}/gui/nuklear/gdi.c", .{src_folder}), lib_cflags);
                exe.addCSourceFile(b.fmt("{}/nativefiledialog/src/nfd_win.cpp", .{lib_folder}), lib_cflags);
                exe.linkSystemLibrary("user32");
                exe.linkSystemLibrary("gdi32");
                exe.linkSystemLibrary("Msimg32");
            },
            .linux => {
                exe.addIncludeDir(b.fmt("{}/nuklear/demo/x11_xft", .{lib_folder}));
                exe.addIncludeDir("/usr/include/freetype2");
                exe.addIncludeDir("/usr/include/");
                exe.addCSourceFile(b.fmt("{}/gui/nuklear/x11.c", .{src_folder}), lib_cflags);
                exe.addCSourceFile(b.fmt("{}/nativefiledialog/src/nfd_zenity.c", .{lib_folder}), lib_cflags);
                exe.linkSystemLibrary("X11");
                exe.linkSystemLibrary("Xft");
            },
            else => unreachable, // TODO: More os support
        }

        exe.addIncludeDir(b.fmt("{}/nativefiledialog/src/include", .{lib_folder}));
        exe.addIncludeDir(b.fmt("{}/nuklear", .{lib_folder}));
        exe.addIncludeDir(b.fmt("{}/gui/nuklear", .{src_folder}));
        exe.addCSourceFile(b.fmt("{}/gui/nuklear/impl.c", .{src_folder}), lib_cflags);
        exe.addCSourceFile(b.fmt("{}/nativefiledialog/src/nfd_common.c", .{lib_folder}), lib_cflags);
        exe.linkSystemLibrary("c");
        exe.linkSystemLibrary("m");

        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.single_threaded = true;
        build_gui_step.dependOn(&b.addInstallArtifact(exe).step);
    }
}

fn buildAndInstallCmdlineProgram(
    b: *Builder,
    parent_step: *Step,
    install: bool,
    target: Target,
    mode: builtin.Mode,
    name: []const u8,
    src: []const u8,
) void {
    const exe = b.addExecutable(name, src);
    for (pkgs) |pkg|
        exe.addPackage(pkg);

    if (install)
        parent_step.dependOn(&b.addInstallArtifact(exe).step);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.single_threaded = true;
    parent_step.dependOn(&exe.step);
}

fn testCmdlineProgram(b: *Builder, parent_step: *Step, mode: builtin.Mode, src: []const u8) void {
    const exe_test = b.addTest(src);
    for (pkgs) |pkg|
        exe_test.addPackage(pkg);

    exe_test.setNamePrefix(b.fmt("{}-", .{@tagName(mode)}));
    exe_test.setBuildMode(mode);
    exe_test.single_threaded = true;
    parent_step.dependOn(&exe_test.step);
}
