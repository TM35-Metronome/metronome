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
const unicode = std.unicode;

const Utf8 = util.unicode.Utf8View;

const escape = util.escape;
const exit = util.exit;
const parse = util.parse;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help        Display this help text and exit.                                                                ") catch unreachable,
        clap.parseParam("    --hms         Also randomize hms (this may break your game).") catch unreachable,
        clap.parseParam("-s, --seed <INT>  The seed to use for random numbers. A random seed will be picked if this is not specified.      ") catch unreachable,
        clap.parseParam("-v, --version     Output version information and exit.                                                            ") catch unreachable,
    };
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-rand-machines ");
    try clap.usage(stream, &params);
    try stream.writeAll("\nRandomizes the moves of tms.\n" ++
        "\n" ++
        "Options:\n");
    try clap.help(stream, &params);
}

const Preference = enum {
    random,
    stab,
};

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime InStream: type,
    comptime OutStream: type,
    stdio: util.CustomStdIoStreams(InStream, OutStream),
    args: var,
) u8 {
    const hms = args.flag("--hms");
    const seed = if (args.option("--seed")) |seed|
        fmt.parseUnsigned(u64, seed, 10) catch |err| {
            stdio.err.print("'{}' could not be parsed as a number to --seed: {}\n", .{ seed, err }) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    else blk: {
        var buf: [8]u8 = undefined;
        os.getrandom(buf[0..]) catch break :blk @as(u64, 0);
        break :blk mem.readInt(u64, &buf, .Little);
    };

    var stdin = io.bufferedInStream(stdio.in);
    var line_buf = std.ArrayList(u8).init(allocator);
    var data = Data{
        .strings = std.StringHashMap(usize).init(allocator),
    };

    while (util.readLine(&stdin, &line_buf) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(allocator, &data, hms, str) catch |err| switch (err) {
            error.OutOfMemory => return exit.allocErr(stdio.err),
            error.InvalidUtf8,
            error.ParseError,
            => true,
        };
        if (print_line)
            stdio.out.print("{}\n", .{str}) catch |err| return exit.stdoutErr(stdio.err, err);

        line_buf.resize(0) catch unreachable;
    }

    randomize(&data, seed) catch return exit.allocErr(stdio.err);

    for (data.tms.values()) |tm, i| {
        stdio.out.print(".tms[{}]={}\n", .{
            data.tms.at(i).key,
            tm,
        }) catch |err| return exit.stdoutErr(stdio.err, err);
    }
    for (data.hms.values()) |hm, i| {
        stdio.out.print(".hms[{}]={}\n", .{
            data.hms.at(i).key,
            hm,
        }) catch |err| return exit.stdoutErr(stdio.err, err);
    }
    for (data.items.values()) |item, i| {
        stdio.out.print(".items[{}].description=", .{
            data.items.at(i).key,
        }) catch |err| return exit.stdoutErr(stdio.err, err);
        escape.writeEscaped(stdio.out, item.description.bytes, escape.zig_escapes) catch |err| return exit.stdoutErr(stdio.err, err);
        stdio.out.writeAll("\n") catch |err| return exit.stdoutErr(stdio.err, err);
    }

    return 0;
}

fn parseLine(allocator: *mem.Allocator, data: *Data, hms: bool, str: []const u8) !bool {
    const sw = util.parse.Swhash(16);
    const m = sw.match;
    const c = sw.case;

    var p = parse.MutParser{ .str = str };
    switch (m(try p.parse(parse.anyField))) {
        c("tms") => {
            _ = try data.tms.put(
                allocator,
                try p.parse(parse.index),
                try p.parse(parse.usizev),
            );
            return false;
        },
        c("hms") => if (hms) {
            _ = try data.hms.put(
                allocator,
                try p.parse(parse.index),
                try p.parse(parse.usizev),
            );
            return false;
        },
        c("moves") => {
            const index = try p.parse(parse.index);
            const move = try data.moves.getOrPutValue(allocator, index, Move{});

            switch (m(try p.parse(parse.anyField))) {
                c("description") => {
                    const desc = try escape.unEscape(
                        allocator,
                        try p.parse(parse.strv),
                        escape.zig_escapes,
                    );
                    move.description = try Utf8.init(desc);
                },

                else => {},
            }
            return true;
        },
        c("items") => {
            const index = try p.parse(parse.index);
            const item = try data.items.getOrPutValue(allocator, index, Item{});

            switch (m(try p.parse(parse.anyField))) {
                c("pocket") => item.pocket = try data.string(try p.parse(parse.strv)),
                c("name") => {
                    const name = try mem.dupe(allocator, u8, try p.parse(parse.strv));
                    item.name = try Utf8.init(name);
                },
                c("description") => {
                    const desc = try escape.unEscape(
                        allocator,
                        try p.parse(parse.strv),
                        escape.zig_escapes,
                    );
                    item.description = try Utf8.init(desc);
                },
                else => {},
            }
            return true;
        },
        else => return true,
    }
    return true;
}

fn randomize(data: *Data, seed: u64) !void {
    const allocator = data.strings.allocator;
    var random = &rand.DefaultPrng.init(seed).random;

    for (data.tms.values()) |*tm|
        tm.* = data.moves.at(random.intRangeLessThan(usize, 0, data.moves.count())).key;
    for (data.hms.values()) |*hm|
        hm.* = data.moves.at(random.intRangeLessThan(usize, 0, data.moves.count())).key;

    // Find the maximum length of a line. Used to split descriptions into lines.
    var max_line_len: usize = 0;
    for (data.items.values()) |item| {
        var description = item.description;
        while (mem.indexOf(u8, description.bytes, "\n")) |index| {
            const line = Utf8.init(description.bytes[0..index]) catch unreachable;
            max_line_len = math.max(line.len, max_line_len);
            description = Utf8.init(description.bytes[index + 1 ..]) catch unreachable;
        }
        max_line_len = math.max(description.len, max_line_len);
    }

    // HACK: The games does not used mono fonts, so actually, using the
    //       max_line_len to destribute newlines will not actually be totally
    //       correct. The best I can do here is to just reduce the max_line_len
    //       by some amount and hope it is enough for all strings.
    max_line_len = math.sub(usize, max_line_len, 5) catch max_line_len;

    const tms_hms_pocket = try data.string("tms_hms");
    for (data.items.values()) |*item, i| {
        const id = data.items.at(i).key;
        if (item.pocket != tms_hms_pocket)
            continue;

        const is_tm = mem.startsWith(u8, item.name.bytes, "TM");
        const is_hm = mem.startsWith(u8, item.name.bytes, "HM");
        if (is_tm or is_hm) {
            const number = fmt.parseUnsigned(usize, item.name.bytes[2..], 10) catch continue;
            const machines = if (is_tm) data.tms else data.hms;
            const move_id = machines.get(number - 1) orelse continue;
            const move = data.moves.get(move_id.*) orelse continue;
            const new_desc = try util.unicode.splitIntoLines(allocator, max_line_len, move.description);
            item.description = new_desc.slice(0, item.description.len);
        }
    }
}

fn utf8Len(str: Utf8) usize {
    var res: usize = 0;
    var it = str.iterator();
    while (it.nextCodepointSlice()) |_| : (res += 1) {}
    return res;
}

fn utf8Slice(str: Utf8, max_len: usize) Utf8 {
    var codepoints: usize = 0;
    var it = str.iterator();
    while (it.nextCodepointSlice()) |_| : (codepoints += 1) {
        if (codepoints == max_len)
            break;
    }

    return Utf8.initUnchecked(str.bytes[0..it.i]);
}

const Machines = util.container.IntMap.Unmanaged(usize, usize);
const Moves = util.container.IntMap.Unmanaged(usize, Move);
const Items = util.container.IntMap.Unmanaged(usize, Item);

const Data = struct {
    strings: std.StringHashMap(usize),
    items: Items = Items{},
    moves: Moves = Moves{},
    tms: Machines = Machines{},
    hms: Machines = Machines{},

    fn string(d: *Data, str: []const u8) !usize {
        const res = try d.strings.getOrPut(str);
        if (!res.found_existing) {
            res.kv.key = try mem.dupe(d.strings.allocator, u8, str);
            res.kv.value = d.strings.count() - 1;
        }
        return res.kv.value;
    }
};

const Item = struct {
    pocket: usize = math.maxInt(usize),
    name: Utf8 = Utf8.init("") catch unreachable,
    description: Utf8 = Utf8.init("") catch unreachable,
};

const Move = struct {
    description: Utf8 = Utf8.init("") catch unreachable,
};

test "tm35-rand-machines" {
    const result_prefix =
        \\.moves[0].power=10
        \\.moves[1].power=30
        \\.moves[2].power=30
        \\.moves[3].power=30
        \\.moves[4].power=50
        \\.moves[5].power=70
        \\
    ;
    const test_string = result_prefix ++
        \\.tms[0]=0
        \\.tms[1]=2
        \\.tms[2]=4
        \\.hms[0]=1
        \\.hms[1]=3
        \\.hms[2]=5
        \\
    ;
    util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.hms[0]=1
        \\.hms[1]=3
        \\.hms[2]=5
        \\.tms[0]=1
        \\.tms[1]=0
        \\.tms[2]=0
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--hms" }, test_string, result_prefix ++
        \\.tms[0]=1
        \\.tms[1]=0
        \\.tms[2]=0
        \\.hms[0]=1
        \\.hms[1]=2
        \\.hms[2]=5
        \\
    );
}
