const clap = @import("clap");
const core = @import("core");
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

const format = core.format;

const escape = util.escape.default;
const Utf8 = util.unicode.Utf8View;

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

pub const parsers = .{
    .INT = clap.parsers.int(u64, 0),
};

pub const params = clap.parseParamsComptime(
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\-s, --seed <INT>
    \\        The seed to use for random numbers. A random seed will be picked if this is not
    \\        specified.
    \\
    \\-v, --version
    \\        Output version information and exit.
    \\
);

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    return Program{
        .allocator = allocator,
        .seed = args.args.seed orelse std.crypto.random.int(u64),
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
                _ = try program.pokemons.put(allocator, pokemons.index, .{ .name = .{
                    .value = try escape.unescapeAlloc(allocator, str),
                } });
                return;
            },
            else => return error.DidNotConsumeData,
        },
        .trainers => |trainers| switch (trainers.value) {
            .name => |str| {
                _ = try program.trainers.put(allocator, trainers.index, .{ .name = .{
                    .value = try escape.unescapeAlloc(allocator, str),
                } });
                return;
            },
            else => return error.DidNotConsumeData,
        },
        .moves => |moves| switch (moves.value) {
            .name => |str| {
                _ = try program.moves.put(allocator, moves.index, .{ .name = .{
                    .value = try escape.unescapeAlloc(allocator, str),
                } });
                return;
            },
            else => return error.DidNotConsumeData,
        },
        .abilities => |abilities| switch (abilities.value) {
            .name => |str| {
                _ = try program.abilities.put(allocator, abilities.index, .{ .name = .{
                    .value = try escape.unescapeAlloc(allocator, str),
                } });
                return;
            },
        },
        .items => |items| switch (items.value) {
            .name => |str| {
                _ = try program.items.put(allocator, items.index, .{ .name = .{
                    .value = try escape.unescapeAlloc(allocator, str),
                } });
                return;
            },
            else => return error.DidNotConsumeData,
        },
        else => return error.DidNotConsumeData,
    }
    unreachable;
}

fn randomize(program: *Program) !void {
    const allocator = program.allocator;
    var default_random = rand.DefaultPrng.init(program.seed);
    const random = default_random.random();

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
                const occurrence = (try node.codepoints.getOrPutValue(allocator, code, 0))
                    .value_ptr;
                occurrence.* += 1;
                node.total += 1;
                node = (try pairs.getOrPutValue(allocator, code, .{})).value_ptr;
            }

            const occurrence = (try node.codepoints.getOrPutValue(allocator, end_of_string, 0))
                .value_ptr;
            occurrence.* += 1;
            node.total += 1;
            max = @max(max, item.name.value.len);
        }

        // Generate our random names from our pair map. This is done by picking a C2
        // based on our current C1. C2 is chosen by using the occurnaces of C2 as weights
        // and picking at random from here.
        for (set.values()) |*str| {
            var new_name = std.ArrayList(u8).init(allocator);
            var node = pairs.get(start_of_string).?;

            while (new_name.items.len < max) {
                var i = random.intRangeLessThan(usize, 0, node.total);
                const pick = for (node.codepoints.keys(), node.codepoints.values()) |key, item| {
                    if (i < item)
                        break key;
                    i -= item;
                } else unreachable;

                if (mem.eql(u8, pick, end_of_string))
                    break;
                if (new_name.items.len + pick.len > max)
                    break;

                try new_name.appendSlice(pick);
                node = pairs.get(pick).?;
            }

            str.name.value = try new_name.toOwnedSlice();
        }
    }
}

const end_of_string = "\x00";
const start_of_string = "\x01";

const CodepointPairs = std.StringArrayHashMapUnmanaged(Occurrences);
const NameSet = std.AutoArrayHashMapUnmanaged(u16, Name);

const Name = struct {
    name: ston.String([]const u8),
};

const Occurrences = struct {
    total: usize = 0,
    codepoints: std.StringArrayHashMapUnmanaged(usize) = std.StringArrayHashMapUnmanaged(usize){},
};

test "tm35-random-names" {
    // TODO: Tests
}
