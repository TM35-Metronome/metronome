const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const strip = b.option(bool, "strip", "") orelse false;

    const clap_module = b.createModule(.{
        .source_file = .{ .path = "lib/zig-clap/clap.zig" },
    });
    const crc_module = b.createModule(.{
        .source_file = .{ .path = "lib/zig-crc/crc.zig" },
    });
    const folders_module = b.createModule(.{
        .source_file = .{ .path = "lib/known-folders/known-folders.zig" },
    });
    const ston_module = b.createModule(.{
        .source_file = .{ .path = "lib/ston/ston.zig" },
    });
    const util_module = b.createModule(.{
        .source_file = .{ .path = "src/util.zig" },
        .dependencies = &.{
            .{ .name = "clap", .module = clap_module },
            .{ .name = "folders", .module = folders_module },
        },
    });
    const core_module = b.createModule(.{
        .source_file = .{ .path = "src/core.zig" },
        .dependencies = &.{
            .{ .name = "ston", .module = ston_module },
            .{ .name = "util", .module = util_module },
            .{ .name = "crc", .module = crc_module },
        },
    });

    const modules = [_]std.Build.ModuleDependency{
        .{ .name = "clap", .module = clap_module },
        .{ .name = "core", .module = core_module },
        .{ .name = "folders", .module = folders_module },
        .{ .name = "ston", .module = ston_module },
        .{ .name = "util", .module = util_module },
    };

    const exes = [_][]const u8{
        "src/core/tm35-apply.zig",
        "src/core/tm35-disassemble-scripts.zig",
        "src/core/tm35-gen3-offsets.zig",
        "src/core/tm35-identify.zig",
        "src/core/tm35-load.zig",
        "src/core/tm35-nds-extract.zig",

        "src/randomizers/tm35-rand-machines.zig",
        "src/randomizers/tm35-rand-names.zig",
        "src/randomizers/tm35-random-stones.zig",
        "src/randomizers/tm35-rand-pokeball-items.zig",
        "src/randomizers/tm35-rand-pokemons.zig",
        "src/randomizers/tm35-rand-starters.zig",
        "src/randomizers/tm35-rand-static.zig",
        "src/randomizers/tm35-rand-trainers.zig",
        "src/randomizers/tm35-rand-wild.zig",

        "src/other/tm35-generate-site.zig",
        "src/other/tm35-misc.zig",
        "src/other/tm35-noop.zig",
        "src/other/tm35-no-trade-evolutions.zig",

        "src/gui/tm35-randomizer.zig",
    };
    for (exes) |path| {
        const basename = std.fs.path.basename(path);
        const name = basename[0 .. basename.len - 4]; // Remove `.zig`

        const step = b.step(name, b.fmt("Build and install {s}", .{name}));
        const exe = b.addExecutable(.{
            .name = name,
            .root_source_file = .{ .path = path },
            .optimize = optimize,
            .target = target,
        });
        exe.strip = strip;

        for (modules) |module|
            exe.addModule(module.name, module.module);

        step.dependOn(&b.addInstallArtifact(exe).step);
        step.dependOn(&exe.step);
        b.default_step.dependOn(step);

        if (std.mem.startsWith(u8, path, "src/gui/")) {
            buildAndLinkMd4c(exe);
            buildAndLinkNativeFileDialog(exe, target);
            buildAndLinkWebview(exe, target);
            exe.linkLibC();
            exe.linkLibCpp();
            exe.linkSystemLibrary("m");
        }
    }

    const test_step = b.step("test", "Run all tests");
    const test_util = b.addTest(.{
        .name = "test",
        .root_source_file = .{ .path = "src/util.zig" },
        .optimize = optimize,
        .target = target,
    });
    const test_exes = b.addTest(.{
        .name = "test",
        .root_source_file = .{ .path = "src/test.zig" },
        .optimize = optimize,
        .target = target,
    });
    for (modules) |module|
        test_exes.addModule(module.name, module.module);

    test_step.dependOn(&test_util.step);
    test_step.dependOn(&test_exes.step);
}

fn buildAndLinkWebview(exe: *std.Build.CompileStep, target: std.zig.CrossTarget) void {
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

fn buildAndLinkMd4c(exe: *std.Build.CompileStep) void {
    exe.addCSourceFiles(&.{
        "lib/md4c/src/entity.c",
        "lib/md4c/src/md4c.c",
        "lib/md4c/src/md4c-html.c",
    }, &.{});
    exe.addIncludePath("lib/md4c/src");
}

fn buildAndLinkNativeFileDialog(exe: *std.Build.CompileStep, target: std.zig.CrossTarget) void {
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
