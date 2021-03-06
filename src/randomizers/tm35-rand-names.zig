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
    try writer.writeAll(
        \\
        \\Randomizes the names of things.
        \\
        \\Options:
        \\
    );
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

    var data = Data{ .allocator = allocator };
    try format.io(allocator, stdio.in, stdio.out, &data, useGame);

    try randomize(data, seed);
    try outputData(stdio.out, data);
}

fn outputData(writer: anytype, data: Data) !void {
    try ston.serialize(writer, .{
        .pokemons = data.pokemons,
        .trainers = data.trainers,
        .moves = data.moves,
        .abilities = data.abilities,
        .items = data.items,
    });
}

fn useGame(data: *Data, parsed: format.Game) !void {
    const allocator = data.allocator;
    switch (parsed) {
        .pokemons => |pokemons| switch (pokemons.value) {
            .name => |name| {
                _ = try data.pokemons.put(allocator, pokemons.index, .{
                    .name = .{ .value = try escape.default.unescapeAlloc(allocator, name) },
                });
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
                _ = try data.trainers.put(allocator, trainers.index, .{
                    .name = .{ .value = try escape.default.unescapeAlloc(allocator, name) },
                });
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
                _ = try data.moves.put(allocator, moves.index, .{
                    .name = .{ .value = try escape.default.unescapeAlloc(allocator, name) },
                });
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
                _ = try data.abilities.put(allocator, abilities.index, .{
                    .name = .{ .value = try escape.default.unescapeAlloc(allocator, name) },
                });
                return;
            },
        },
        .items => |items| switch (items.value) {
            .name => |name| {
                _ = try data.items.put(allocator, items.index, .{
                    .name = .{ .value = try escape.default.unescapeAlloc(allocator, name) },
                });
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

fn randomize(data: Data, seed: usize) !void {
    const random = &rand.DefaultPrng.init(seed).random;

    for ([_]NameSet{
        data.pokemons,
        data.trainers,
        data.moves,
        data.abilities,
        data.items,
    }) |set| {
        var max: usize = 0;
        var pairs = CodepointPairs{};

        // Build our codepoint pair map. This map contains a mapping from C1 -> []C2+N,
        // where CX is a codepoint and N is the number of times C2 was seen after C1.
        // This map will be used to generate names later.
        for (set.values()) |item| {
            const view = unicode.Utf8View.init(item.name.value) catch continue;

            var node = (try pairs.getOrPutValue(data.allocator, start_of_string, .{})).value_ptr;
            var it = view.iterator();
            while (it.nextCodepointSlice()) |code| {
                const occurance = (try node.codepoints.getOrPutValue(data.allocator, code, 0)).value_ptr;
                occurance.* += 1;
                node.total += 1;
                node = (try pairs.getOrPutValue(data.allocator, code, .{})).value_ptr;
            }

            const occurance = (try node.codepoints.getOrPutValue(data.allocator, end_of_string, 0)).value_ptr;
            occurance.* += 1;
            node.total += 1;
            max = math.max(max, item.name.value.len);
        }

        // Generate our random names from our pair map. This is done by picking a C2
        // based on our current C1. C2 is chosen by using the occurnaces of C2 as weights
        // and picking at random from here.
        for (set.values()) |*name| {
            var new_name = std.ArrayList(u8).init(data.allocator);
            var node = pairs.get(start_of_string).?;

            while (new_name.items.len < max) {
                var i = random.intRangeLessThan(usize, 0, node.total);
                const pick = for (node.codepoints.values()) |item, j| {
                    if (i < item)
                        break node.codepoints.keys()[j];
                    i -= item;
                } else unreachable;

                if (mem.eql(u8, pick, end_of_string))
                    break;
                if (new_name.items.len + pick.len > max)
                    break;

                try new_name.appendSlice(pick);
                node = pairs.get(pick).?;
            }

            name.name.value = new_name.toOwnedSlice();
        }
    }
}

const end_of_string = "\x00";
const start_of_string = "\x01";

const CodepointPairs = std.StringArrayHashMapUnmanaged(Occurences);
const NameSet = std.AutoArrayHashMapUnmanaged(u16, Name);

const Data = struct {
    allocator: *mem.Allocator,
    pokemons: NameSet = NameSet{},
    trainers: NameSet = NameSet{},
    moves: NameSet = NameSet{},
    abilities: NameSet = NameSet{},
    items: NameSet = NameSet{},
};

const Name = struct {
    name: ston.String([]const u8),
};

const Occurences = struct {
    total: usize = 0,
    codepoints: std.StringArrayHashMapUnmanaged(usize) = std.StringArrayHashMapUnmanaged(usize){},
};

test "tm35-random-names" {
    // TODO: Tests
}
