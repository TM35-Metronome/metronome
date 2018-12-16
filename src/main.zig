const std = @import("std");
const nds = @import("tm35-nds");
const clap = @import("zig-clap");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const os = std.os;
const path = os.path;

const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = []Param{
    Param.flag(
        "display this help text and exit",
        Names.both("help"),
    ),
    Param.option(
        "override destination path",
        Names.both("output"),
    ),
    Param.positional(""),
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-nds-extract [OPTION]... FILE
        \\Reads a Nintendo DS rom and extract its files into a folder.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() !void {
    const stderr = &(try std.io.getStdErr()).outStream().stream;
    const stdout = &(try std.io.getStdOut()).outStream().stream;

    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    var arena = heap.ArenaAllocator.init(&direct_allocator.allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(allocator);
    const iter = &arg_iter.iter;
    _ = iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator.Error, iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const file_name = if (args.positionals().len > 0) args.positionals()[0] else {
        try usage(stderr);
        return error.NoFileProvided;
    };

    const out = args.option("--output") orelse blk: {
        break :blk try fmt.allocPrint(allocator, "{}.output", path.basename(file_name));
    };

    var rom_file = try os.File.openRead(file_name);
    defer rom_file.close();
    var rom = try nds.Rom.fromFile(rom_file, allocator);

    try os.makePath(allocator, out);
    try write(try path.join(allocator, out, "arm9"), rom.arm9);
    try write(try path.join(allocator, out, "arm7"), rom.arm7);
    try write(try path.join(allocator, out, "banner"), mem.toBytes(rom.banner));

    if (rom.hasNitroFooter())
        try write(try path.join(allocator, out, "nitro_footer"), mem.toBytes(rom.nitro_footer));

    const arm9_overlay_folder = try path.join(allocator, out, "arm9_overlays");
    const arm7_overlay_folder = try path.join(allocator, out, "arm7_overlays");
    try os.makePath(allocator, arm9_overlay_folder);
    try os.makePath(allocator, arm7_overlay_folder);
    try writeOverlays(allocator, arm9_overlay_folder, rom.arm9_overlay_table, rom.arm9_overlay_files);
    try writeOverlays(allocator, arm7_overlay_folder, rom.arm7_overlay_table, rom.arm7_overlay_files);

    const root_folder = try path.join(allocator, out, "root");
    try os.makePath(allocator, root_folder);
    try writeFs(allocator, nds.fs.Nitro, root_folder, rom.root);
}

fn writeFs(allocator: *mem.Allocator, comptime Fs: type, p: []const u8, folder: *Fs) !void {
    const State = struct {
        path: []const u8,
        folder: *Fs,
    };

    var stack = std.ArrayList(State).init(allocator);
    defer stack.deinit();

    try stack.append(State{
        .path = try mem.dupe(allocator, u8, p),
        .folder = folder,
    });

    while (stack.popOrNull()) |state| {
        defer allocator.free(state.path);

        for (state.folder.nodes.toSliceConst()) |node| {
            const node_path = try path.join(allocator, state.path, node.name);
            switch (node.kind) {
                Fs.Node.Kind.File => |f| {
                    defer allocator.free(node_path);
                    const Tag = @TagType(nds.fs.Nitro.File);
                    switch (Fs) {
                        nds.fs.Nitro => switch (f.*) {
                            Tag.Binary => |bin| {
                                var file = try os.File.openWrite(node_path);
                                defer file.close();
                                try file.write(bin.data);
                            },
                            Tag.Narc => |narc| {
                                try os.makePath(allocator, node_path);
                                try writeFs(allocator, nds.fs.Narc, node_path, narc);
                            },
                        },
                        nds.fs.Narc => {
                            var file = try os.File.openWrite(node_path);
                            defer file.close();
                            try file.write(f.data);
                        },
                        else => comptime unreachable,
                    }
                },
                Fs.Node.Kind.Folder => |f| {
                    try os.makePath(allocator, node_path);
                    try stack.append(State{
                        .path = node_path,
                        .folder = f,
                    });
                },
            }
        }
    }
}

fn writeOverlays(child_allocator: *mem.Allocator, folder: []const u8, overlays: []const nds.Overlay, files: []const []const u8) !void {
    var arena = heap.ArenaAllocator.init(child_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const overlay_folder_path = try path.join(allocator, folder, "overlay");
    for (overlays) |overlay, i| {
        const overlay_path = try fmt.allocPrint(allocator, "{}{}", overlay_folder_path, i);
        try write(overlay_path, mem.toBytes(overlay));
    }

    const file_folder_path = try path.join(allocator, folder, "file");
    for (files) |file, i| {
        const file_path = try fmt.allocPrint(allocator, "{}{}", file_folder_path, i);
        try write(file_path, file);
    }
}

fn write(file_path: []const u8, data: []const u8) !void {
    var file = try os.File.openWrite(file_path);
    defer file.close();
    try file.write(data);
}
