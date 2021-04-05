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

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help                 Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-s, --seed <INT>           The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-v, --version              Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-random-names ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nRandomizes the names of things." ++
        "\n" ++
        "Options:\n");
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
    const seed = try util.getSeed(args);

    const data = try handleInput(allocator, stdio.in, stdio.out);
    try randomize(allocator, data, seed);
    try outputData(stdio.out, data);
}

fn handleInput(allocator: *mem.Allocator, reader: anytype, writer: anytype) !Data {
    var fifo = util.io.Fifo(.Dynamic).init(allocator);
    var data = Data{};
    while (try util.io.readLine(reader, &fifo)) |line| {
        parseLine(allocator, &data, line) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParserFailed => try writer.print("{}\n", .{line}),
        };
    }
    return data;
}

fn outputData(writer: anytype, data: Data) !void {
    for (data.pokemons.items()) |name|
        try format.write(writer, format.Game.pokemon(name.key, .{ .name = name.value }));
    for (data.trainers.items()) |name|
        try format.write(writer, format.Game.trainer(name.key, .{ .name = name.value }));
    for (data.moves.items()) |name|
        try format.write(writer, format.Game.move(name.key, .{ .name = name.value }));
    for (data.abilities.items()) |name|
        try format.write(writer, format.Game.ability(name.key, .{ .name = name.value }));
    for (data.item_names.items()) |name|
        try format.write(writer, format.Game.item(name.key, .{ .name = name.value }));
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !void {
    const parsed = try format.parseEscape(allocator, str);
    switch (parsed) {
        .pokemons => |pokemons| switch (pokemons.value) {
            .name => |name| {
                _ = try data.pokemons.put(allocator, pokemons.index, try mem.dupe(allocator, u8, name));
                return;
            },
            .stats,
            .types,
            .catch_rate,
            .base_exp_yield,
            .ev_yield,
            .items,
            .gender_ratio,
            .egg_cycles,
            .base_friendship,
            .growth_rate,
            .egg_groups,
            .abilities,
            .color,
            .evos,
            .moves,
            .tms,
            .hms,
            .pokedex_entry,
            => return error.ParserFailed,
        },
        .trainers => |trainers| switch (trainers.value) {
            .name => |name| {
                _ = try data.trainers.put(allocator, trainers.index, try mem.dupe(allocator, u8, name));
                return;
            },
            .class,
            .encounter_music,
            .trainer_picture,
            .items,
            .party_type,
            .party_size,
            .party,
            => return error.ParserFailed,
        },
        .moves => |moves| switch (moves.value) {
            .name => |name| {
                _ = try data.moves.put(allocator, moves.index, try mem.dupe(allocator, u8, name));
                return;
            },
            .description,
            .effect,
            .power,
            .type,
            .accuracy,
            .pp,
            .target,
            .priority,
            .category,
            => return error.ParserFailed,
        },
        .abilities => |abilities| switch (abilities.value) {
            .name => |name| {
                _ = try data.abilities.put(allocator, abilities.index, try mem.dupe(allocator, u8, name));
                return;
            },
        },
        .items => |items| switch (items.value) {
            .name => |name| {
                _ = try data.item_names.put(allocator, items.index, try mem.dupe(allocator, u8, name));
                return;
            },
            .battle_effect,
            .description,
            .price,
            .pocket,
            => return error.ParserFailed,
        },
        .version,
        .game_title,
        .gamecode,
        .instant_text,
        .starters,
        .text_delays,
        .types,
        .tms,
        .hms,
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

fn randomize(allocator: *mem.Allocator, data: Data, seed: usize) !void {
    const random = &rand.DefaultPrng.init(seed).random;

    for ([_]NameSet{
        data.pokemons,
        data.trainers,
        data.moves,
        data.abilities,
        data.item_names,
    }) |set| {
        var max: usize = 0;
        var pairs = CodepointPairs{};

        // Build our codepoint pair map. This map contains a mapping from C1 -> []C2+N,
        // where CX is a codepoint and N is the number of times C2 was seen after C1.
        // This map will be used to generate names later.
        for (set.items()) |item| {
            const view = unicode.Utf8View.init(item.value) catch continue;

            var node = &(try pairs.getOrPutValue(allocator, start_of_string, Occurences{})).value;
            var it = view.iterator();
            while (it.nextCodepointSlice()) |code| {
                const occurance = try node.codepoints.getOrPutValue(allocator, code, 0);
                occurance.value += 1;
                node.total += 1;
                node = &(try pairs.getOrPutValue(allocator, code, Occurences{})).value;
            }

            const occurance = try node.codepoints.getOrPutValue(allocator, end_of_string, 0);
            occurance.value += 1;
            node.total += 1;
            max = math.max(max, item.value.len);
        }

        // Generate our random names from our pair map. This is done by picking a C2
        // based on our current C1. C2 is chosen by using the occurnaces of C2 as weights
        // and picking at random from here.
        for (set.items()) |*name| {
            var new_name = std.ArrayList(u8).init(allocator);
            var node = pairs.get(start_of_string).?;

            while (new_name.items.len < max) {
                var i = random.intRangeLessThan(usize, 0, node.total);
                const pick = for (node.codepoints.items()) |item| {
                    if (i < item.value)
                        break item.key;
                    i -= item.value;
                } else unreachable;

                if (mem.eql(u8, pick, end_of_string))
                    break;
                if (new_name.items.len + pick.len > max)
                    break;

                try new_name.appendSlice(pick);
                node = pairs.get(pick).?;
            }

            name.value = new_name.toOwnedSlice();
        }
    }
}

const end_of_string = "\x00";
const start_of_string = "\x01";

const CodepointPairs = std.StringArrayHashMapUnmanaged(Occurences);
const NameSet = std.AutoArrayHashMapUnmanaged(u16, []const u8);

const Data = struct {
    pokemons: NameSet = NameSet{},
    trainers: NameSet = NameSet{},
    moves: NameSet = NameSet{},
    abilities: NameSet = NameSet{},
    item_names: NameSet = NameSet{},
};

const Occurences = struct {
    total: usize = 0,
    codepoints: std.StringArrayHashMapUnmanaged(usize) = std.StringArrayHashMapUnmanaged(usize){},
};

test "tm35-random-names" {
    // TODO: Tests
}
