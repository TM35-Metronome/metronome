const builtin = @import("builtin");
const std = @import("std");

const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exs = exes(b, b.build_root);
    for (exs) |exe| {
        exe.setBuildMode(mode);
        b.default_step.dependOn(&exe.step);
        b.installArtifact(exe);
    }
}

pub fn exes(b: *Builder, path: []const u8) [4]*LibExeObjStep {
    var res: [4]*LibExeObjStep = undefined;
    for ([][]const u8{
        "tm35-gen3-load",
        "tm35-gen3-apply",
        "tm35-gen3-offsets",
        "tm35-gen3-disassemble-scripts",
    }) |exe_name, i| {
        const exe = b.addExecutable(exe_name, b.fmt("{}/src/{}.zig", path, exe_name));
        exe.addPackagePath("fun-with-zig", b.fmt("{}/lib/fun-with-zig/index.zig", path));
        exe.addPackagePath("tm35-common", b.fmt("{}/lib/tm35-common/index.zig", path));
        exe.addPackagePath("tm35-format", b.fmt("{}/lib/tm35-format/src/index.zig", path));
        exe.addPackagePath("zig-clap", b.fmt("{}/lib/zig-clap/index.zig", path));
        res[i] = exe;
    }

    return res;
}
