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
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) anyerror!void {
    const seed = try util.getSeed(args);
    const hms = args.flag("--hms");

    var data = Data{ .allocator = allocator };
    try format.io(
        allocator,
        stdio.in,
        stdio.out,
        true,
        .{ .hms = hms, .data = &data },
        useGame,
    );
    try randomize(data, seed);
    try outputData(stdio.out, data);
}

fn outputData(writer: anytype, data: Data) !void {
    for (data.tms.values()) |tm, i|
        try format.write(writer, format.Game.tm(data.tms.keys()[i], tm));
    for (data.hms.values()) |hm, i|
        try format.write(writer, format.Game.hm(data.hms.keys()[i], hm));
    for (data.items.values()) |item, i| {
        try format.write(writer, format.Game.item(data.items.keys()[i], .{
            .description = item.description.bytes,
        }));
    }
}

fn useGame(ctx: anytype, parsed: format.Game) !void {
    const hms = ctx.hms;
    const data = ctx.data;
    const allocator = data.allocator;
    switch (parsed) {
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
            const move = (try data.moves.getOrPutValue(allocator, moves.index, .{})).value_ptr;
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
            const item = (try data.items.getOrPutValue(allocator, items.index, .{})).value_ptr;
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
        .version,
        .game_title,
        .gamecode,
        .instant_text,
        .starters,
        .text_delays,
        .trainers,
        .pokemons,
        .abilities,
        .types,
        .pokedex,
        .maps,
        .wild_pokemons,
        .static_pokemons,
        .given_pokemons,
        .pokeball_items,
        .hidden_hollows,
        .text,
        => return error.ParserFailed,
    }
    unreachable;
}

fn randomize(data: Data, seed: u64) !void {
    var random = &rand.DefaultPrng.init(seed).random;

    for (data.tms.values()) |*tm|
        tm.* = util.random.item(random, data.moves.keys()).?.*;
    for (data.hms.values()) |*hm|
        hm.* = util.random.item(random, data.moves.keys()).?.*;

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

    for (data.items.values()) |*item| {
        if (item.pocket != .tms_hms)
            continue;

        const is_tm = mem.startsWith(u8, item.name.bytes, "TM");
        const is_hm = mem.startsWith(u8, item.name.bytes, "HM");
        if (is_tm or is_hm) {
            const number = fmt.parseUnsigned(u8, item.name.bytes[2..], 10) catch continue;
            const machines = if (is_tm) data.tms else data.hms;
            const move_id = machines.get(number - 1) orelse continue;
            const move = data.moves.get(move_id) orelse continue;
            const new_desc = try util.unicode.splitIntoLines(data.allocator, max_line_len, move.description);
            item.description = new_desc.slice(0, item.description.len);
        }
    }
}

const Items = std.AutoArrayHashMapUnmanaged(u16, Item);
const Machines = std.AutoArrayHashMapUnmanaged(u8, u16);
const Moves = std.AutoArrayHashMapUnmanaged(u16, Move);

const Data = struct {
    allocator: *mem.Allocator,
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
    try util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.hms[0]=1
        \\.hms[1]=3
        \\.hms[2]=5
        \\.tms[0]=1
        \\.tms[1]=0
        \\.tms[2]=0
        \\
    );
    try util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--hms" }, test_string, result_prefix ++
        \\.tms[0]=1
        \\.tms[1]=0
        \\.tms[2]=0
        \\.hms[0]=1
        \\.hms[1]=2
        \\.hms[2]=5
        \\
    );
}
