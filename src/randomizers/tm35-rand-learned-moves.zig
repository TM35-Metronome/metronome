const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const exit = util.exit;
const parse = util.parse;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help                      Display this help text and exit.                                                                ") catch unreachable,
        clap.parseParam("-p, --preference <random|stab>  Which moves the randomizer should prefer picking (90% preference, 10% random). (default: random)") catch unreachable,
        clap.parseParam("-s, --seed <INT>                The seed to use for random numbers. A random seed will be picked if this is not specified.      ") catch unreachable,
        clap.parseParam("-v, --version                   Output version information and exit.                                                            ") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-rand-learned-moves ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nRandomizes the moves Pokémons can learn.\n" ++
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
) u8 {
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

    const pref = if (args.option("--preference")) |pref|
        if (mem.eql(u8, pref, "random"))
            Preference.random
        else if (mem.eql(u8, pref, "stab"))
            Preference.stab
        else {
            stdio.err.print("--preference does not support '{}'\n", .{pref}) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    else
        Preference.random;

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

    randomize(allocator, data, seed, pref) catch return exit.allocErr(stdio.err);

    for (data.pokemons.values()) |*pokemon, i| {
        const pokemon_index = data.pokemons.at(i).key;
        for (pokemon.tms.span()) |range| {
            var tm = range.start;
            while (tm <= range.end) : (tm += 1) {
                stdio.out.print(".pokemons[{}].tms[{}]={}\n", .{
                    pokemon_index,
                    tm,
                    pokemon.tms_learned.exists(tm),
                }) catch |err| return exit.stdoutErr(stdio.err, err);
            }
        }
        for (pokemon.hms.span()) |range| {
            var hm = range.start;
            while (hm <= range.end) : (hm += 1) {
                stdio.out.print(".pokemons[{}].hms[{}]={}\n", .{
                    pokemon_index,
                    hm,
                    pokemon.hms_learned.exists(hm),
                }) catch |err| return exit.stdoutErr(stdio.err, err);
            }
        }
    }

    return 0;
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !void {
    const sw = util.parse.Swhash(8);
    const m = sw.match;
    const c = sw.case;

    var p = parse.MutParser{ .str = str };
    switch (m(try p.parse(parse.anyField))) {
        c("pokemons") => {
            const pokemon_index = try p.parse(parse.index);
            const pokemon = try data.pokemons.getOrPutValue(allocator, pokemon_index, Pokemon{});

            const field = try p.parse(parse.anyField);
            const index = try p.parse(parse.index);
            switch (m(field)) {
                c("tms") => {
                    _ = try pokemon.tms.put(allocator, index);
                    if (try p.parse(parse.boolv))
                        _ = try pokemon.tms_learned.put(allocator, index);
                    return;
                },
                c("hms") => {
                    _ = try pokemon.hms.put(allocator, index);
                    if (try p.parse(parse.boolv))
                        _ = try pokemon.hms_learned.put(allocator, index);
                    return;
                },
                c("types") => {
                    _ = try pokemon.types.put(allocator, try p.parse(parse.usizev));
                    return error.ParseError;
                },
                else => return error.ParseError,
            }
        },
        c("moves") => {
            const index = try p.parse(parse.index);
            const move = try data.moves.getOrPutValue(allocator, index, Move{});

            switch (m(try p.parse(parse.anyField))) {
                c("power") => move.power = try p.parse(parse.usizev),
                c("type") => move.type = try p.parse(parse.usizev),
                else => {},
            }
            return error.ParseError;
        },
        c("tms") => {
            _ = try data.tms.put(
                allocator,
                try p.parse(parse.index),
                try p.parse(parse.usizev),
            );
            return error.ParseError;
        },
        c("hms") => {
            _ = try data.hms.put(
                allocator,
                try p.parse(parse.index),
                try p.parse(parse.usizev),
            );
            return error.ParseError;
        },
        else => return error.ParseError,
    }
}

fn randomize(allocator: *mem.Allocator, data: Data, seed: u64, pref: Preference) !void {
    var random = &rand.DefaultPrng.init(seed).random;

    for (data.pokemons.values()) |*pokemon, i| {
        const pokemon_index = data.pokemons.at(i).key;
        try randomizeMachinesLearned(allocator, data, pokemon.*, random, pref, data.tms, pokemon.tms, &pokemon.tms_learned);
        try randomizeMachinesLearned(allocator, data, pokemon.*, random, pref, data.hms, pokemon.hms, &pokemon.hms_learned);
    }
}

fn randomizeMachinesLearned(
    allocator: *mem.Allocator,
    data: Data,
    pokemon: Pokemon,
    random: *rand.Random,
    pref: Preference,
    machines: Machines,
    have: Set,
    learned: *Set,
) !void {
    for (have.span()) |range| {
        var machine = range.start;
        while (machine <= range.end) : (machine += 1) switch (pref) {
            .random => if (random.boolean()) {
                _ = try learned.put(allocator, machine);
            } else {
                _ = try learned.remove(allocator, machine);
            },
            .stab => {
                const low_chance = 0.1;
                const chance: f64 = blk: {
                    const index = machines.get(machine) orelse break :blk low_chance;
                    const move = data.moves.get(index.*) orelse break :blk low_chance;
                    const move_type = move.type orelse break :blk low_chance;
                    if (!pokemon.types.exists(move_type))
                        break :blk low_chance;

                    // Yay the move is stab. Give it a higher chance.
                    break :blk @as(f64, 1.0 - low_chance);
                };

                if (random.float(f64) < chance)
                    _ = try learned.put(allocator, machine)
                else
                    _ = try learned.remove(allocator, machine);
            },
        };
    }
}

const Set = util.container.IntSet.Unmanaged(usize);
const Pokemons = util.container.IntMap.Unmanaged(usize, Pokemon);
const Machines = util.container.IntMap.Unmanaged(usize, usize);
//const LvlUpMoves = std.AutoHashMap(usize, LvlUpMove);
const Moves = util.container.IntMap.Unmanaged(usize, Move);

const Data = struct {
    pokemons: Pokemons = Pokemons{},
    moves: Moves = Moves{},
    tms: Machines = Machines{},
    hms: Machines = Machines{},
};

const Pokemon = struct {
    types: Set = Set{},
    tms_learned: Set = Set{},
    tms: Set = Set{},
    hms_learned: Set = Set{},
    hms: Set = Set{},
    //lvl_up_moves: LvlUpMoves
};

const LvlUpMove = struct {
    level: ?u16 = null,
    id: ?usize = null,
};

const Move = struct {
    power: ?usize = null,
    type: ?usize = null,
};

test "tm35-rand-learned-moves" {
    const result_prefix =
        \\.moves[0].power=10
        \\.moves[0].type=0
        \\.moves[1].power=30
        \\.moves[1].type=12
        \\.moves[2].power=30
        \\.moves[2].type=16
        \\.moves[3].power=30
        \\.moves[3].type=10
        \\.moves[4].power=50
        \\.moves[4].type=0
        \\.moves[5].power=70
        \\.moves[5].type=0
        \\.tms[0]=0
        \\.tms[1]=2
        \\.tms[2]=4
        \\.hms[0]=1
        \\.hms[1]=3
        \\.hms[2]=5
        \\.pokemons[0].types[0]=0
        \\
    ;
    const test_string = result_prefix ++
        \\.pokemons[0].tms[0]=false
        \\.pokemons[0].tms[1]=false
        \\.pokemons[0].tms[2]=false
        \\.pokemons[0].hms[0]=false
        \\.pokemons[0].hms[1]=false
        \\.pokemons[0].hms[2]=false
        \\
    ;
    util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.pokemons[0].tms[0]=true
        \\.pokemons[0].tms[1]=false
        \\.pokemons[0].tms[2]=true
        \\.pokemons[0].hms[0]=false
        \\.pokemons[0].hms[1]=true
        \\.pokemons[0].hms[2]=false
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--preference=stab" }, test_string, result_prefix ++
        \\.pokemons[0].tms[0]=true
        \\.pokemons[0].tms[1]=true
        \\.pokemons[0].tms[2]=true
        \\.pokemons[0].hms[0]=false
        \\.pokemons[0].hms[1]=false
        \\.pokemons[0].hms[2]=true
        \\
    );
}
