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

const escape = util.escape;
const exit = util.exit;
const parse = util.parse;

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
) u8 {
    const seed = util.getSeed(stdio.err, usage, args) catch return 1;
    var fifo = util.read.Fifo(.Dynamic).init(allocator);
    var data = Data{};
    while (util.read.line(stdio.in, &fifo) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        parseLine(allocator, &data, line) catch |err| switch (err) {
            error.OutOfMemory => return exit.allocErr(stdio.err),
            error.ParseError => stdio.out.print("{}\n", .{line}) catch |err2| {
                return exit.stdoutErr(stdio.err, err2);
            },
        };
    }

    randomize(allocator, &data, seed) catch return exit.allocErr(stdio.err);

    for (data.pokemons.values()) |name, i| {
        const id = data.pokemons.at(i).key;
        stdio.out.print(".pokemons[{}].name={}\n", .{ id, name }) catch |err| return exit.stdoutErr(stdio.err, err);
    }
    for (data.trainers.values()) |name, i| {
        const id = data.trainers.at(i).key;
        stdio.out.print(".trainers[{}].name={}\n", .{ id, name }) catch |err| return exit.stdoutErr(stdio.err, err);
    }
    for (data.moves.values()) |name, i| {
        const id = data.moves.at(i).key;
        stdio.out.print(".moves[{}].name={}\n", .{ id, name }) catch |err| return exit.stdoutErr(stdio.err, err);
    }
    for (data.abilities.values()) |name, i| {
        const id = data.abilities.at(i).key;
        stdio.out.print(".abilities[{}].name={}\n", .{ id, name }) catch |err| return exit.stdoutErr(stdio.err, err);
    }
    for (data.item_names.values()) |name, i| {
        const id = data.item_names.at(i).key;
        stdio.out.print(".items[{}].name={}\n", .{ id, name }) catch |err| return exit.stdoutErr(stdio.err, err);
    }
    return 0;
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !void {
    const sw = parse.Swhash(16);
    const m = sw.match;
    const c = sw.case;

    var p = parse.MutParser{ .str = str };
    switch (m(try p.parse(parse.anyField))) {
        c("pokemons") => {
            const index = try p.parse(parse.index);
            try p.parse(comptime parse.field("name"));
            const name = try p.parse(parse.strv);
            _ = try data.pokemons.put(allocator, index, try mem.dupe(allocator, u8, name));
            return;
        },
        c("trainers") => {
            const index = try p.parse(parse.index);
            try p.parse(comptime parse.field("name"));
            const name = try p.parse(parse.strv);
            _ = try data.trainers.put(allocator, index, try mem.dupe(allocator, u8, name));
            return;
        },
        c("moves") => {
            const index = try p.parse(parse.index);
            try p.parse(comptime parse.field("name"));
            const name = try p.parse(parse.strv);
            _ = try data.moves.put(allocator, index, try mem.dupe(allocator, u8, name));
            return;
        },
        c("abilities") => {
            const index = try p.parse(parse.index);
            try p.parse(comptime parse.field("name"));
            const name = try p.parse(parse.strv);
            _ = try data.abilities.put(allocator, index, try mem.dupe(allocator, u8, name));
            return;
        },
        c("items") => {
            const index = try p.parse(parse.index);
            try p.parse(comptime parse.field("name"));
            const name = try mem.dupe(allocator, u8, try p.parse(parse.strv));
            _ = try data.item_names.put(allocator, index, try mem.dupe(allocator, u8, name));
            return;
        },
        else => return error.ParseError,
    }
    unreachable;
}

fn randomize(allocator: *mem.Allocator, data: *Data, seed: usize) !void {
    const random = &rand.DefaultPrng.init(seed).random;

    for ([_]*NameSet{
        &data.pokemons,
        &data.trainers,
        &data.moves,
        &data.abilities,
        &data.item_names,
    }) |set| {
        var max: usize = 0;
        var pairs = CodepointPairs{};

        // Build our codepoint pair map. This map contains a mapping from C1 -> []C2+N,
        // where CX is a codepoint and N is the number of times C2 was seen after C1.
        // This map will be used to generate names later.
        for (set.values()) |item| {
            const view = unicode.Utf8View.init(item) catch continue;

            var node = &(try pairs.getOrPutValue(allocator, start_of_string, Occurences{})).value;
            var len: usize = 0;
            var it = view.iterator();
            while (it.nextCodepointSlice()) |code| : (len += 1) {
                const occurance = try node.codepoints.getOrPutValue(allocator, code, 0);
                occurance.value += 1;
                node.total += 1;
                node = &(try pairs.getOrPutValue(allocator, code, Occurences{})).value;
            }

            const occurance = try node.codepoints.getOrPutValue(allocator, end_of_string, 0);
            occurance.value += 1;
            node.total += 1;
            max = math.max(max, len);
        }

        // Generate our random names from our pair map. This is done by picking a C2
        // based on our current C1. C2 is chosen by using the occurnaces of C2 as weights
        // and picking at random from here.
        for (set.values()) |*name| {
            var new_name = std.ArrayList(u8).init(allocator);
            var node = pairs.get(start_of_string).?;

            var len: usize = 0;
            while (len < max) : (len += 1) {
                var i = random.intRangeLessThan(usize, 0, node.total);
                const pick = for (node.codepoints.items()) |item| {
                    if (i < item.value)
                        break item.key;
                    i -= item.value;
                } else unreachable;

                if (mem.eql(u8, pick, end_of_string))
                    break;

                try new_name.appendSlice(pick);
                node = pairs.get(pick).?;
            }

            name.* = new_name.toOwnedSlice();
        }
    }
}

const end_of_string = "\x00";
const start_of_string = "\x01";

const CodepointPairs = std.StringArrayHashMapUnmanaged(Occurences);
const NameSet = util.container.IntMap.Unmanaged(usize, []const u8);

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
