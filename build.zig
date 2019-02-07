const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    inline for ([][]const u8{
        "tm35-gen3-load",
        "tm35-gen3-apply",
        "tm35-gen3-offsets",
    }) |exe_name| {
        const exe = b.addExecutable(exe_name, "src/" ++ exe_name ++ ".zig");
        exe.setBuildMode(mode);
        exe.addPackagePath("fun-with-zig", "lib/fun-with-zig/index.zig");
        exe.addPackagePath("tm35-common", "lib/tm35-common/index.zig");
        exe.addPackagePath("tm35-format", "lib/tm35-format/src/index.zig");
        exe.addPackagePath("zig-clap", "lib/zig-clap/index.zig");
        b.default_step.dependOn(&exe.step);
        b.installArtifact(exe);
    }
}
