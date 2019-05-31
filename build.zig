const builtin = @import("builtin");
const std = @import("std");

const mem = std.mem;

const Builder = std.build.Builder;
const RunStep = std.build.RunStep;
const LibExeObjStep = std.build.LibExeObjStep;

const folder = "src";
const tools = [][]const u8{
    "tm35-rand-learned-moves",
    "tm35-rand-wild",
    "tm35-rand-stats",
    "tm35-rand-starters",
    "tm35-rand-parties",
    "tm35-gen5",
    "tm35-gen4",
    "tm35-gen3",
};

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const os = osOptions(b);
    const arch = builtin.arch;
    const environ = builtin.Abi.none;

    var exes: [tools.len]*LibExeObjStep = undefined;
    inline for (tools) |tool, i| {
        const exe = b.addExecutable(tool, "src/" ++ tool ++ ".zig");
        exe.setBuildMode(mode);
        exe.setTarget(arch, os, environ);
        exe.setOutputDir("zig-cache/" ++ tool);
        b.default_step.dependOn(&exe.step);
        b.installArtifact(exe);
        
        exes[i] = exe;
    }

    const gzip_step = b.step("gzip", "Create a gzipped tar for each repos artifacts");
    const version = try b.exec([][]const u8{"git", "describe", "--always"});
    const tar_path = b.fmt(
        "{}/metronome-{}-{}-{}.tar",
        b.cache_root,
        @tagName(os),
        @tagName(arch),
        mem.trim(u8, version, "\n"), 
    );
    const tar_command = tar(b, tar_path, exes);
    const gzip_command = b.addSystemCommand([][]const u8{ "gzip", "-f", tar_path  });
    gzip_command.step.dependOn(&tar_command.step);
    gzip_step.dependOn(&gzip_command.step);
}

fn tar(b: *Builder, out_path: []const u8, deps: []const *LibExeObjStep) *RunStep {
    var argv = std.ArrayList([]const u8).init(b.allocator);
    argv.ensureCapacity(3 + deps.len) catch unreachable;

    argv.append("tar") catch unreachable;
    argv.append("-cf") catch unreachable;
    argv.append(out_path) catch unreachable;
    for (deps) |dep|
        argv.append(dep.getOutputPath()) catch unreachable;

    const step = b.addSystemCommand(argv.toSlice());
    for (deps) |dep|
        step.step.dependOn(&dep.step);

    return step;
}

fn osOptions(b: *Builder) builtin.Os {
    const os = b.option([]const u8, "target-os", "the os to target [native, linux, windows]") orelse "native";

    if (mem.eql(u8, "native", os))
        return builtin.os;
    if (mem.eql(u8, "linux", os))
        return builtin.Os.linux;
    if (mem.eql(u8, "windows", os))
        return builtin.Os.windows;

    std.debug.warn("{} is not a supported os. Using {}", os, builtin.os);
    return builtin.os;
}