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

pub fn exes(b: *Builder, path: []const u8) [1]*LibExeObjStep {
    const exe = b.addExecutable("tm35-nds-extract", b.fmt("{}/src/main.zig", path));
    exe.addPackagePath("tm35-nds", b.fmt("{}/lib/tm35-nds/src/index.zig", path));
    exe.addPackagePath("zig-clap", b.fmt("{}/lib/zig-clap/clap.zig", path));
    return [_]*LibExeObjStep{exe};
}
