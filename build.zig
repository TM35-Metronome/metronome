const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("tm35-nds-extract", "src/main.zig");
    exe.setBuildMode(mode);
    exe.addPackagePath("tm35-nds", "lib/tm35-nds/src/index.zig");
    exe.addPackagePath("zig-clap", "lib/zig-clap/index.zig");
    exe.linkSystemLibrary("c");
    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
