const clap = @import("clap");
const format = @import("format");
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

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help        Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("    --hms         Also randomize hms (this may break your game).                                            ") catch unreachable,
        clap.parseParam("-s, --seed <INT>  The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-v, --version     Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-rand-machines ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nRandomizes the moves of tms.\n" ++
        "\n" ++
        "Options:\n");
    try clap.help(writer, &params);
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
    strings: *util.container.StringCache(.{}),
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) u8 {
    const seed = util.getSeed(stdio.err, usage, args) catch return 1;
    const hms = args.flag("--hms");

    var fifo = util.read.Fifo(.Dynamic).init(allocator);
    var data = Data{};
    while (util.read.line(stdio.in, &fifo) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        parseLine(allocator, strings, &data, hms, line) catch |err| switch (err) {
            error.OutOfMemory => return exit.allocErr(stdio.err),
            error.InvalidUtf8,
            error.ParserFailed,
            => stdio.out.print("{}\n", .{line}) catch |err2| {
                return exit.stdoutErr(stdio.err, err2);
            },
        };
    }

    randomize(allocator, strings, &data, seed) catch return exit.allocErr(stdio.err);

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
        const index = data.items.at(i).key;
        format.write(
            stdio.out,
            format.Game{ .items = .{ .index = index, .value = .{ .description = item.description.bytes } } },
        ) catch |err| return exit.stdoutErr(stdio.err, err);
    }

    return 0;
}

fn parseLine(
    allocator: *mem.Allocator,
    strings: *util.container.StringCache(.{}),
    data: *Data,
    hms: bool,
    str: []const u8,
) !void {
    switch (try format.parse(allocator, str)) {
        .tms => |tms| {
            _ = try data.tms.put(allocator, tms.index, tms.value);
            return;
        },
        .hms => |ms| if (hms) {
            _ = try data.hms.put(allocator, ms.index, ms.value);
            return;
        } else {
            return error.ParserFailed;
        },
        .moves => |moves| {
            const move = try data.moves.getOrPutValue(allocator, moves.index, Move{});
            switch (moves.value) {
                .description => |_desc| {
                    const desc = try mem.dupe(allocator, u8, _desc);
                    move.description = try Utf8.init(desc);
                },
                else => {},
            }
            return error.ParserFailed;
        },
        .items => |items| {
            const item = try data.items.getOrPutValue(allocator, items.index, Item{});
            switch (items.value) {
                .pocket => |pocket| item.pocket = pocket,
                .name => |_name| {
                    const name = try mem.dupe(allocator, u8, _name);
                    item.name = try Utf8.init(name);
                },
                .description => |_desc| {
                    const desc = try mem.dupe(allocator, u8, _desc);
                    item.description = try Utf8.init(desc);
                },
                else => {},
            }
            return error.ParserFailed;
        },
        else => return error.ParserFailed,
    }
    unreachable;
}

fn randomize(allocator: *mem.Allocator, strings: *util.container.StringCache(.{}), data: *Data, seed: u64) !void {
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

    for (data.items.values()) |*item, i| {
        const id = data.items.at(i).key;
        if (item.pocket != .tms_hms)
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

const Items = util.container.IntMap.Unmanaged(u16, Item);
const Machines = util.container.IntMap.Unmanaged(usize, usize);
const Moves = util.container.IntMap.Unmanaged(usize, Move);

const Data = struct {
    items: Items = Items{},
    moves: Moves = Moves{},
    tms: Machines = Machines{},
    hms: Machines = Machines{},
};

const Item = struct {
    pocket: format.Pocket = .none,
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
