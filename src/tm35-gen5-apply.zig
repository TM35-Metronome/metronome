const clap = @import("zig-clap");
const common = @import("tm35-common");
const format = @import("tm35-format");
const fun = @import("fun-with-zig");
const gen5 = @import("gen5-types.zig");
const nds = @import("tm35-nds");
const offsets = @import("gen5-offsets.zig");
const std = @import("std");

const bits = fun.bits;
const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const os = std.os;
const path = os.path;
const slice = fun.generic.slice;

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu64 = fun.platform.lu64;
const lu128 = fun.platform.lu128;

const BufInStream = io.BufferedInStream(os.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(os.File.OutStream.Error);
const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = []Param{
    Param.flag(
        "abort execution on the first warning emitted",
        Names.long("abort-on-first-warning"),
    ),
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
        \\Usage: tm35-gen5-apply [OPTION]... FILE
        \\Reads the tm35 format from stdin and applies it to a generation 5 Pokemon rom.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() !void {
    const unbuf_stdin = &(try std.io.getStdIn()).inStream().stream;
    var buf_stdin = BufInStream.init(unbuf_stdin);

    const stderr = &(try std.io.getStdErr()).outStream().stream;
    const stdout = &(try std.io.getStdOut()).outStream().stream;
    const stdin = &buf_stdin.stream;

    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    var arena = heap.ArenaAllocator.init(&direct_allocator.allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

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
        debug.warn("No file provided");
        return try usage(stderr);
    };

    const abort_on_first_warning = args.flag("--abort-on-first-warning");
    const out = args.option("--output") orelse blk: {
        break :blk try fmt.allocPrint(allocator, "{}.modified", path.basename(file_name));
    };

    var rom = blk: {
        var file = os.File.openRead(file_name) catch |err| {
            debug.warn("Couldn't open {}.\n", file_name);
            return err;
        };
        defer file.close();

        break :blk try nds.Rom.fromFile(file, allocator);
    };

    const game = try gen5.Game.fromRom(rom);

    var line: usize = 1;
    var line_buf = try std.Buffer.initSize(allocator, 0);

    while (stdin.readUntilDelimiterBuffer(&line_buf, '\n', 10000)) : (line += 1) {
        apply(rom, game, line, mem.trimRight(u8, line_buf.toSlice(), "\r\n")) catch |err| {
            warning(line, 1, "{}\n", @errorName(err));
            if (abort_on_first_warning)
                return err;
        };
        line_buf.shrink(0);
    } else |err| switch (err) {
        error.EndOfStream => {
            const str = mem.trim(u8, line_buf.toSlice(), " \t");
            if (str.len != 0)
                warning(line, 1, "none empty last line\n");
        },
        else => return err,
    }

    var out_file = os.File.openWrite(out) catch |err| {
        debug.warn("Couldn't open {}\n", out);
        return err;
    };
    defer out_file.close();
    try rom.writeToFile(out_file);
}

fn apply(rom: nds.Rom, game: gen5.Game, line: usize, str: []const u8) !void {
    var parser = format.StrParser.init(str);

    return error.Err;
}

fn warning(line: usize, col: usize, comptime f: []const u8, a: ...) void {
    debug.warn("(stdin):{}:{}: warning: ", line, col);
    debug.warn(f, a);
}

fn stringToBool(str: []const u8) ?bool {
    if (mem.eql(u8, "true", str))
        return true;
    if (mem.eql(u8, "false", str))
        return false;

    return null;
}

fn nodeAsFile(node: nds.fs.Narc.Node) !*nds.fs.Narc.File {
    switch (node.kind) {
        nds.fs.Narc.Node.Kind.File => |file| return file,
        nds.fs.Narc.Node.Kind.Folder => return error.NotFile,
    }
}

fn nodeAsType(comptime T: type, node: nds.fs.Narc.Node) !*T {
    const file = try nodeAsFile(node);
    const data = slice.bytesToSliceTrim(T, file.data);
    return slice.at(data, 0) catch error.FileToSmall;
}
