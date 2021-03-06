const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const rom = @import("rom.zig");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const os = std.os;

const path = fs.path;

const nds = rom.nds;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help           Display this help text and exit.    ") catch unreachable,
        clap.parseParam("-o, --output <FILE>  Override destination path.          ") catch unreachable,
        clap.parseParam("-v, --version        Output version information and exit.") catch unreachable,
        clap.parseParam("<ROM>") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-nds-extract ");
    try clap.usage(writer, &params);
    try writer.writeAll(
        \\
        \\Reads a Nintendo DS rom and extract its file system into a folder.
        \\
        \\Options:
        \\
    );
    try clap.help(writer, &params);
}

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) anyerror!void {
    const cwd = fs.cwd();
    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else return error.MissingFile;

    const out = args.option("--output") orelse blk: {
        break :blk try fmt.allocPrint(allocator, "{s}.output", .{path.basename(file_name)});
    };

    const rom_file = try cwd.openFile(file_name, .{});
    defer rom_file.close();
    var nds_rom = try nds.Rom.fromFile(rom_file, allocator);

    try cwd.makePath(out);

    // All dir instances should actually be `const`, but `Dir.close` takes mutable pointer, so we can't
    // actually do that...
    var out_dir = try cwd.openDir(out, .{});
    defer out_dir.close();

    try out_dir.makeDir("arm9_overlays");
    try out_dir.makeDir("arm7_overlays");
    try out_dir.makeDir("root");

    var arm9_overlays_dir = try out_dir.openDir("arm9_overlays", .{});
    defer arm9_overlays_dir.close();
    var arm7_overlays_dir = try out_dir.openDir("arm7_overlays", .{});
    defer arm7_overlays_dir.close();
    var root_dir = try out_dir.openDir("root", .{});
    defer root_dir.close();

    try out_dir.writeFile("arm9", nds_rom.arm9());
    try out_dir.writeFile("arm9_decoded", try nds_rom.getDecodedArm9(allocator));
    try out_dir.writeFile("arm7", nds_rom.arm7());
    try out_dir.writeFile("nitro_footer", nds_rom.nitroFooter());
    if (nds_rom.banner()) |banner|
        try out_dir.writeFile("banner", mem.asBytes(banner));

    const file_system = nds_rom.fileSystem();
    try writeOverlays(arm9_overlays_dir, file_system, nds_rom.arm9OverlayTable(), allocator);
    try writeOverlays(arm7_overlays_dir, file_system, nds_rom.arm7OverlayTable(), allocator);

    try writeFs(root_dir, file_system, nds.fs.root);
}

fn writeFs(dir: fs.Dir, file_system: nds.fs.Fs, folder: nds.fs.Dir) anyerror!void {
    var it = file_system.iterate(folder);
    while (it.next()) |entry| {
        switch (entry.handle) {
            .file => |file| try dir.writeFile(entry.name, file_system.fileData(file)),
            .dir => |sub_folder| {
                try dir.makeDir(entry.name);
                var sub_dir = try dir.openDir(entry.name, .{});
                defer sub_dir.close();

                try writeFs(sub_dir, file_system, sub_folder);
            },
        }
    }
}

fn writeOverlays(dir: fs.Dir, file_system: nds.fs.Fs, overlays: []const nds.Overlay, allocator: *mem.Allocator) !void {
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;

    for (overlays) |*overlay, i| {
        try dir.writeFile(fmt.bufPrint(&buf, "overlay{}", .{i}) catch unreachable, mem.asBytes(overlay));

        const data = file_system.fileData(.{ .i = overlay.file_id.value() });
        if (nds.blz.decode(data, allocator)) |d| {
            std.log.info("Decompressed overlay {}", .{i});
            try dir.writeFile(fmt.bufPrint(&buf, "file{}", .{i}) catch unreachable, d);
        } else |_| {
            try dir.writeFile(fmt.bufPrint(&buf, "file{}", .{i}) catch unreachable, data);
        }
    }
}
