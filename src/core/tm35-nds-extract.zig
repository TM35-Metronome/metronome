const clap = @import("clap");
const std = @import("std");

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

const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);

const Clap = clap.ComptimeClap(clap.Help, params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

const params = [_]Param{
    clap.parseParam("-h, --help           Display this help text and exit.    ") catch unreachable,
    clap.parseParam("-o, --output <FILE>  Override destination path.          ") catch unreachable,
    clap.parseParam("-v, --version        Output version information and exit.") catch unreachable,
    Param{ .takes_value = true },
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-nds-extract [-hv] [-o <FILE>] <FILE>
        \\Reads a Nintendo DS rom and extract its file system into a folder.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    const stdout_file = io.getStdOut() catch |err| return errPrint("Could not aquire stdout: {}", err);
    const stderr_file = io.getStdErr() catch |err| return errPrint("Could not aquire stderr: {}", err);

    const stdout = &BufOutStream.init(&stdout_file.outStream().stream);
    const stderr = &stderr_file.outStream().stream;

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        debug.warn("{}\n", err);
        usage(stderr) catch |err2| return failedWriteError("<stderr>", err2);
        return 1;
    };

    if (args.flag("--help")) {
        usage(&stdout.stream) catch |err| return failedWriteError("<stdout>", err);
        stdout.flush() catch |err| return failedWriteError("<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdout.stream.print("{}\n", program_version) catch |err| return failedWriteError("<stdout>", err);
        stdout.flush() catch |err| return failedWriteError("<stdout>", err);
        return 0;
    }

    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else {
        debug.warn("No file provided\n");
        usage(stderr) catch |err| return failedWriteError("<stderr>", err);
        return 1;
    };

    const out = args.option("--output") orelse blk: {
        const res = fmt.allocPrint(allocator, "{}.output", path.basename(file_name));
        break :blk res catch return allocFailed();
    };

    var rom_file = fs.File.openRead(file_name) catch |err| return errPrint("Unable to open '{}': {}\n", file_name, err);
    defer rom_file.close();
    var nds_rom = nds.Rom.fromFile(rom_file, allocator) catch |err| return errPrint("Failed to read nds rom: {}\n", err);

    const arm9_file = path.join(allocator, [_][]const u8{ out, "arm9" }) catch return allocFailed();
    const arm7_file = path.join(allocator, [_][]const u8{ out, "arm7" }) catch return allocFailed();
    const banner_file = path.join(allocator, [_][]const u8{ out, "banner" }) catch return allocFailed();
    const nitro_footer_file = path.join(allocator, [_][]const u8{ out, "nitro_footer" }) catch return allocFailed();
    const arm9_overlay_folder = path.join(allocator, [_][]const u8{ out, "arm9_overlays" }) catch return allocFailed();
    const arm7_overlay_folder = path.join(allocator, [_][]const u8{ out, "arm7_overlays" }) catch return allocFailed();
    const root_folder = path.join(allocator, [_][]const u8{ out, "root" }) catch return allocFailed();

    fs.makePath(allocator, out) catch |err| return failedToMakePath(out, err);
    io.writeFile(arm9_file, nds_rom.arm9) catch |err| return failedWriteError(arm9_file, err);
    io.writeFile(arm7_file, nds_rom.arm7) catch |err| return failedWriteError(arm7_file, err);
    io.writeFile(banner_file, mem.toBytes(nds_rom.banner)) catch |err| return failedWriteError(banner_file, err);

    if (nds_rom.hasNitroFooter())
        io.writeFile(nitro_footer_file, mem.toBytes(nds_rom.nitro_footer)) catch |err| return failedWriteError(nitro_footer_file, err);

    fs.makePath(allocator, arm9_overlay_folder) catch |err| return failedToMakePath(arm9_overlay_folder, err);
    fs.makePath(allocator, arm7_overlay_folder) catch |err| return failedToMakePath(arm7_overlay_folder, err);
    writeOverlays(allocator, arm9_overlay_folder, nds_rom.arm9_overlay_table, nds_rom.arm9_overlay_files) catch |err| return errPrint("Failed to write arm9 overlays: {}", err);
    writeOverlays(allocator, arm7_overlay_folder, nds_rom.arm7_overlay_table, nds_rom.arm7_overlay_files) catch |err| return errPrint("Failed to write arm7 overlays: {}", err);

    fs.makePath(allocator, root_folder) catch |err| return failedToMakePath(root_folder, err);
    writeFs(allocator, nds.fs.Nitro, root_folder, nds_rom.root) catch |err| return errPrint("Failed to write root file system: {}", err);
    return 0;
}

fn allocFailed() u8 {
    debug.warn("Allocation failed\n");
    return 1;
}

fn failedWriteError(file: []const u8, err: anyerror) u8 {
    debug.warn("Failed to write data to '{}': {}\n", file, err);
    return 1;
}

fn failedToMakePath(path_str: []const u8, err: anyerror) u8 {
    debug.warn("Failed to make path '{}': {}\n", path_str, err);
    return 1;
}

fn errPrint(comptime format_str: []const u8, args: ...) u8 {
    debug.warn(format_str, args);
    return 1;
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
            const node_path = try path.join(allocator, [_][]const u8{ state.path, node.name });
            switch (node.kind) {
                Fs.Node.Kind.File => |f| {
                    defer allocator.free(node_path);
                    const Tag = @TagType(nds.fs.Nitro.File);
                    switch (Fs) {
                        nds.fs.Nitro => switch (f.*) {
                            Tag.Binary => |bin| try io.writeFile(node_path, bin.data),
                            Tag.Narc => |narc| {
                                try fs.makePath(allocator, node_path);
                                try writeFs(allocator, nds.fs.Narc, node_path, narc);
                            },
                        },
                        nds.fs.Narc => try io.writeFile(node_path, f.data),
                        else => comptime unreachable,
                    }
                },
                Fs.Node.Kind.Folder => |f| {
                    try fs.makePath(allocator, node_path);
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

    const overlay_folder_path = try path.join(allocator, [_][]const u8{ folder, "overlay" });
    for (overlays) |overlay, i| {
        const overlay_path = try fmt.allocPrint(allocator, "{}{}", overlay_folder_path, i);
        try io.writeFile(overlay_path, mem.toBytes(overlay));
    }

    const file_folder_path = try path.join(allocator, [_][]const u8{ folder, "file" });
    for (files) |file, i| {
        const file_path = try fmt.allocPrint(allocator, "{}{}", file_folder_path, i);
        try io.writeFile(file_path, file);
    }
}
