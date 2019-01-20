const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("tm35-rand-starters", "src/main.zig");
    exe.setBuildMode(mode);
    exe.addPackagePath("tm35-format", "lib/tm35-format/src/index.zig");
    exe.addPackagePath("zig-clap", "lib/zig-clap/index.zig");
    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
