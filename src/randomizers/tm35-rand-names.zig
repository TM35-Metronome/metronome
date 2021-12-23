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

const Program = @This();

allocator: mem.Allocator,
seed: u64,
pokemons: NameSet = NameSet{},
trainers: NameSet = NameSet{},
moves: NameSet = NameSet{},
abilities: NameSet = NameSet{},
items: NameSet = NameSet{},

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Randomizes the names of things.
    \\
;

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam("-h, --help                 Display this help text and exit.                                                          ") catch unreachable,
    clap.parseParam("-s, --seed <INT>           The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
    clap.parseParam("-v, --version              Output version information and exit.                                                      ") catch unreachable,
};

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const seed = try util.getSeed(args);
    return Program{
        .allocator = allocator,
        .seed = seed,
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
        .pokemons = program.pokemons,
        .trainers = program.trainers,
        .moves = program.moves,
        .abilities = program.abilities,
        .items = program.items,
    });
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .pokemons => |pokemons| switch (pokemons.value) {
            .name => |str| {
                _ = try program.pokemons.put(allocator, pokemons.index, .{
                    .name = .{ .value = try escape.default.unescapeAlloc(allocator, str) },
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
            .name => |str| {
                _ = try program.trainers.put(allocator, trainers.index, .{
                    .name = .{ .value = try escape.default.unescapeAlloc(allocator, str) },
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
            .name => |str| {
                _ = try program.moves.put(allocator, moves.index, .{
                    .name = .{ .value = try escape.default.unescapeAlloc(allocator, str) },
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
            .name => |str| {
                _ = try program.abilities.put(allocator, abilities.index, .{
                    .name = .{ .value = try escape.default.unescapeAlloc(allocator, str) },
                });
                return;
            },
        },
        .items => |items| switch (items.value) {
            .name => |str| {
                _ = try program.items.put(allocator, items.index, .{
                    .name = .{ .value = try escape.default.unescapeAlloc(allocator, str) },
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

fn randomize(program: *Program) !void {
    const allocator = program.allocator;
    const random = rand.DefaultPrng.init(program.seed).random();

    for ([_]NameSet{
        program.pokemons,
        program.trainers,
        program.moves,
        program.abilities,
        program.items,
    }) |set| {
        var max: usize = 0;
        var pairs = CodepointPairs{};

        // Build our codepoint pair map. This map contains a mapping from C1 -> []C2+N,
        // where CX is a codepoint and N is the number of times C2 was seen after C1.
        // This map will be used to generate names later.
        for (set.values()) |item| {
            const view = unicode.Utf8View.init(item.name.value) catch continue;

            var node = (try pairs.getOrPutValue(allocator, start_of_string, .{})).value_ptr;
            var it = view.iterator();
            while (it.nextCodepointSlice()) |code| {
                const occurance = (try node.codepoints.getOrPutValue(allocator, code, 0))
                    .value_ptr;
                occurance.* += 1;
                node.total += 1;
                node = (try pairs.getOrPutValue(allocator, code, .{})).value_ptr;
            }

            const occurance = (try node.codepoints.getOrPutValue(allocator, end_of_string, 0))
                .value_ptr;
            occurance.* += 1;
            node.total += 1;
            max = math.max(max, item.name.value.len);
        }

        // Generate our random names from our pair map. This is done by picking a C2
        // based on our current C1. C2 is chosen by using the occurnaces of C2 as weights
        // and picking at random from here.
        for (set.values()) |*str| {
            var new_name = std.ArrayList(u8).init(allocator);
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

            str.name.value = new_name.toOwnedSlice();
        }
    }
}

const end_of_string = "\x00";
const start_of_string = "\x01";

const CodepointPairs = std.StringArrayHashMapUnmanaged(Occurences);
const NameSet = std.AutoArrayHashMapUnmanaged(u16, Name);

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
