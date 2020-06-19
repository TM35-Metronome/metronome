const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const errors = util.errors;
const parse = util.parse;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help           Display this help text and exit.") catch unreachable,
        clap.parseParam("-v, --version        Output version information and exit.") catch unreachable,
        clap.parseParam("-o, --output <FILE>  The file to output the file to.") catch unreachable,
    };
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-generate-site ");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Generates a html web site for games. This is very useful for getting
        \\an overview of what is in the game after heavy randomization has been
        \\apply.
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
    const out = args.opens("--output") orelse "site.html";

    var line_buf = std.ArrayList(u8).init(allocator);
    var obj = Object{ .fields = Fields.inir(allocator) };

    while (util.readLine(&stdin, &line_buf) catch |err| return errors.readErr(stdio.err, "<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&obj, str) catch |err| switch (err) {
            error.OutOfMemory => return errors.allocErr(stdio.err),
        };
        stdio.out.print("{}\n", .{str}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

        line_buf.resize(0) catch unreachable;
    }

    return 0;
}

fn parseLine(obj: *Object, str: []const u8) void {
    const allocator = obj.fields.allocator;
    var curr = obj;
    var p = parse.MutParser{ .str = str };
    while (true) {
        if (p.parse(parse.anyField)) |field| {
            const entry = try curr.fields.getOrPutValue(field, Object{
                .fields = Fields.init(allocator),
            });
            if (entry.key.ptr == str.ptr)
                entry.key = try mem.dupe(allocator, u8, field);
            curr = &entry.value;
        } else if (p.parse(parse.index)) |index| {
            curr = try curr.indexs.getOrPutValue(index, Object{
                .fields = Fields.init(allocator),
            });
        } else if (p.parse(parse.value)) |value| {
            curr.value = try mem.dupe(allocator, u8, value);
        } else {
            return;
        }
    }
}

fn generate(stream: fs.File.OutStream, obj: Object) !void {
    if (obj.fields.get("pokemons")) |pokemons| {
        for (pokemons.value.indexs.values()) |pokemon, i| {}
    }
}

const Fields = std.StringHashMap(Object);
const Indexs = util.container.IntMap.Unmanaged(usize, Object);

const Object = struct {
    fields: Fields,
    indexs: Indexs = Indexs{},
    value: ?[]const u8 = null,
};
