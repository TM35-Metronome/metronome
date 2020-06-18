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

const errors = util.errors;

const nds = rom.nds;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-a, --abort-on-first-warning  Abort execution on the first warning emitted.") catch unreachable,
        clap.parseParam("-h, --help                    Display this help text and exit.             ") catch unreachable,
        clap.parseParam("-o, --output <FILE>           Override destination path.                   ") catch unreachable,
        clap.parseParam("-r, --replace                 Replace output file if it already exists.    ") catch unreachable,
        clap.parseParam("-v, --version                 Output version information and exit.         ") catch unreachable,
        Param{ .takes_value = true },
    };
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-nds-extract ");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Reads a Nintendo DS rom and extract its file system into a folder.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

pub fn main() u8 {
    var stdio = util.getStdIo();
    defer stdio.err.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(&arena.allocator) catch
        return errors.allocErr(stdio.err.outStream());
    const res = main2(
        &arena.allocator,
        util.StdIo.In.InStream,
        util.StdIo.Out.OutStream,
        stdio.streams(),
        clap.args.OsIterator,
        &arg_iter,
    );

    stdio.out.flush() catch |err| return errors.writeErr(stdio.err.outStream(), "<stdout>", err);
    return res;
}

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime InStream: type,
    comptime OutStream: type,
    stdio: util.CustomStdIoStreams(InStream, OutStream),
    comptime ArgIterator: type,
    arg_iter: *ArgIterator,
) u8 {
    const cwd = fs.cwd();
    var stdin = io.bufferedInStream(stdio.in);
    var args = Clap.parse(allocator, ArgIterator, arg_iter) catch |err| {
        stdio.err.print("{}\n", .{err}) catch {};
        usage(stdio.err) catch {};
        return 1;
    };
    defer args.deinit();

    if (args.flag("--help")) {
        usage(stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.print("{}\n", .{program_version}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else {
        stdio.err.writeAll("No file provided\n") catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const out = args.option("--output") orelse blk: {
        const res = fmt.allocPrint(allocator, "{}.output", .{path.basename(file_name)});
        break :blk res catch return errors.allocErr(stdio.err);
    };

    var rom_file = fs.cwd().openFile(file_name, .{}) catch |err| return errors.openErr(stdio.err, file_name, err);
    defer rom_file.close();
    var nds_rom = nds.Rom.fromFile(rom_file, allocator) catch |err| return errors.readErr(stdio.err, file_name, err);

    cwd.makePath(out) catch |err| return errors.makePathErr(stdio.err, out, err);

    // All dir instances should actually be `const`, but `Dir.close` takes mutable pointer, so we can't
    // actually do that...
    var out_dir = cwd.openDir(out, .{}) catch |err| return errors.openErr(stdio.err, out, err);
    defer out_dir.close();

    out_dir.makeDir("arm9_overlays") catch |err| return errors.makePathErr(stdio.err, "arm9_overlays", err);
    out_dir.makeDir("arm7_overlays") catch |err| return errors.makePathErr(stdio.err, "arm7_overlays", err);
    out_dir.makeDir("root") catch |err| return errors.makePathErr(stdio.err, "root", err);

    var arm9_overlays_dir = out_dir.openDir("arm9_overlays", .{}) catch |err| return errors.openErr(stdio.err, "arm9_overlays", err);
    defer arm9_overlays_dir.close();
    var arm7_overlays_dir = out_dir.openDir("arm7_overlays", .{}) catch |err| return errors.openErr(stdio.err, "arm7_overlays", err);
    defer arm7_overlays_dir.close();
    var root_dir = out_dir.openDir("root", .{}) catch |err| return errors.openErr(stdio.err, "root", err);
    defer root_dir.close();

    out_dir.writeFile("arm9", nds_rom.arm9()) catch |err| return errors.writeErr(stdio.err, "arm9", err);
    out_dir.writeFile("arm7", nds_rom.arm7()) catch |err| return errors.writeErr(stdio.err, "arm7", err);
    out_dir.writeFile("banner", mem.asBytes(nds_rom.banner())) catch |err| return errors.writeErr(stdio.err, "banner", err);
    out_dir.writeFile("nitro_footer", nds_rom.nitroFooter()) catch |err| return errors.writeErr(stdio.err, "nitro_footer", err);

    const file_system = nds_rom.fileSystem();
    writeOverlays(arm9_overlays_dir, file_system, nds_rom.arm9OverlayTable()) catch |err| return errors.writeErr(stdio.err, "arm9 overlays", err);
    writeOverlays(arm7_overlays_dir, file_system, nds_rom.arm7OverlayTable()) catch |err| return errors.writeErr(stdio.err, "arm7 overlays", err);

    writeFs(root_dir, file_system, nds.fs.root) catch |err| return errors.writeErr(stdio.err, "root file system", err);
    return 0;
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

fn writeOverlays(dir: fs.Dir, file_system: nds.fs.Fs, overlays: []const nds.Overlay) !void {
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;

    for (overlays) |*overlay, i| {
        try dir.writeFile(fmt.bufPrint(&buf, "overlay{}", .{i}) catch unreachable, mem.asBytes(overlay));
        try dir.writeFile(fmt.bufPrint(&buf, "file{}", .{i}) catch unreachable, file_system.fileData(.{ .i = overlay.file_id.value() }));
    }
}
