const clap = @import("clap");
const format = @import("format");
const std = @import("std");
const ston = @import("ston");
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
const parse = util.parse;

const Program = @This();

allocator: mem.Allocator,
options: struct {
    seed: u64,
    hms: bool,
},
items: Items = Items{},
moves: Moves = Moves{},
tms: Machines = Machines{},
hms: Machines = Machines{},

const Preference = enum {
    random,
    stab,
};

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Randomizes the moves of tms.
    \\
;

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam("-h, --help        Display this help text and exit.                                                          ") catch unreachable,
    clap.parseParam("    --hms         Also randomize hms (this may break your game).                                            ") catch unreachable,
    clap.parseParam("-s, --seed <INT>  The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
    clap.parseParam("-v, --version     Output version information and exit.                                                      ") catch unreachable,
};

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const seed = try util.getSeed(args);
    const hms = args.flag("--hms");

    return Program{
        .allocator = allocator,
        .options = .{
            .seed = seed,
            .hms = hms,
        },
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    try format.io(program.allocator, stdio.in, stdio.out, program, useGame);
    try program.randomize();
    try program.output(stdio.out);
}

fn output(program: *Program, writer: anytype) !void {
    try ston.serialize(writer, .{
        .tms = program.tms,
        .hms = program.hms,
    });
    for (program.items.values()) |item, i| {
        try ston.serialize(writer, .{ .items = ston.index(program.items.keys()[i], .{
            .description = ston.string(escape.default.escapeFmt(item.description)),
        }) });
    }
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .tms => |tms| {
            _ = try program.tms.put(allocator, tms.index, tms.value);
            return;
        },
        .hms => |ms| if (program.options.hms) {
            _ = try program.hms.put(allocator, ms.index, ms.value);
            return;
        } else {
            return error.ParserFailed;
        },
        .moves => |moves| {
            const move = (try program.moves.getOrPutValue(allocator, moves.index, .{})).value_ptr;
            switch (moves.value) {
                .description => |_desc| {
                    const desc = try escape.default.unescapeAlloc(allocator, _desc);
                    move.description = try Utf8.init(desc);
                },
                else => {},
            }
            return error.ParserFailed;
        },
        .items => |items| {
            const item = (try program.items.getOrPutValue(allocator, items.index, .{})).value_ptr;
            switch (items.value) {
                .pocket => |pocket| item.pocket = pocket,
                .name => |_name| {
                    const unescaped_name = try escape.default.unescapeAlloc(allocator, _name);
                    item.name = try Utf8.init(unescaped_name);
                },
                .description => |_desc| {
                    const desc = try escape.default.unescapeAlloc(allocator, _desc);
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

fn randomize(program: *Program) !void {
    const allocator = program.allocator;
    const random = rand.DefaultPrng.init(program.options.seed).random();

    for (program.tms.values()) |*tm|
        tm.* = util.random.item(random, program.moves.keys()).?.*;
    for (program.hms.values()) |*hm|
        hm.* = util.random.item(random, program.moves.keys()).?.*;

    // Find the maximum length of a line. Used to split descriptions into lines.
    var max_line_len: usize = 0;
    for (program.items.values()) |item| {
        var desc = item.description;
        while (mem.indexOf(u8, desc.bytes, "\n")) |index| {
            const line = Utf8.init(desc.bytes[0..index]) catch unreachable;
            max_line_len = math.max(line.len, max_line_len);
            desc = Utf8.init(desc.bytes[index + 1 ..]) catch unreachable;
        }
        max_line_len = math.max(description.len, max_line_len);
    }

    // HACK: The games does not used mono fonts, so actually, using the
    //       max_line_len to destribute newlines will not actually be totally
    //       correct. The best I can do here is to just reduce the max_line_len
    //       by some amount and hope it is enough for all strings.
    max_line_len = math.sub(usize, max_line_len, 5) catch 0;

    for (program.items.values()) |*item| {
        if (item.pocket != .tms_hms)
            continue;

        const is_tm = mem.startsWith(u8, item.name.bytes, "TM");
        const is_hm = mem.startsWith(u8, item.name.bytes, "HM");
        if (is_tm or is_hm) {
            const number = fmt.parseUnsigned(u8, item.name.bytes[2..], 10) catch continue;
            const machines = if (is_tm) program.tms else program.hms;
            const move_id = machines.get(number - 1) orelse continue;
            const move = program.moves.get(move_id) orelse continue;
            const new_desc = try util.unicode.splitIntoLines(
                allocator,
                max_line_len,
                move.description,
            );
            item.description = new_desc.slice(0, item.description.len);
        }
    }
}

const Items = std.AutoArrayHashMapUnmanaged(u16, Item);
const Machines = std.AutoArrayHashMapUnmanaged(u8, u16);
const Moves = std.AutoArrayHashMapUnmanaged(u16, Move);

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
    try util.testing.testProgram(Program, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.hms[0]=1
        \\.hms[1]=3
        \\.hms[2]=5
        \\.tms[0]=1
        \\.tms[1]=2
        \\.tms[2]=2
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{ "--seed=0", "--hms" }, test_string, result_prefix ++
        \\.tms[0]=1
        \\.tms[1]=2
        \\.tms[2]=2
        \\.hms[0]=0
        \\.hms[1]=2
        \\.hms[2]=0
        \\
    );
}
