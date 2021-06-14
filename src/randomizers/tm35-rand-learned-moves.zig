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
const log = std.log;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

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
    try writer.writeAll(
        \\
        \\Randomizes the moves Pokémons can learn.
        \\
        \\Options:
        \\
    );
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
    const pref = if (args.option("--preference")) |pref|
        if (mem.eql(u8, pref, "random"))
            Preference.random
        else if (mem.eql(u8, pref, "stab"))
            Preference.stab
        else {
            log.err("--preference does not support '{s}'\n", .{pref});
            return error.InvalidArgument;
        }
    else
        Preference.random;

    var data = Data{ .allocator = allocator };
    try format.io(allocator, stdio.in, stdio.out, &data, useGame);

    try randomize(data, seed, pref);
    try outputData(stdio.out, data);
}

fn outputData(writer: anytype, data: Data) !void {
    for (data.pokemons.values()) |pokemon, i| {
        const species = data.pokemons.keys()[i];
        for (pokemon.tms.values()) |tm, j| {
            const tm_index = pokemon.tms.keys()[j];
            try ston.serialize(writer, format.Game.pokemon(species, .{
                .tms = .{ .index = tm_index, .value = tm },
            }));
        }
        for (pokemon.hms.values()) |hm, j| {
            const hm_index = pokemon.hms.keys()[j];
            try ston.serialize(writer, format.Game.pokemon(species, .{
                .hms = .{ .index = hm_index, .value = hm },
            }));
        }
    }
}

fn useGame(data: *Data, parsed: format.Game) !void {
    const allocator = data.allocator;
    switch (parsed) {
        .pokemons => |pokemons| {
            const pokemon = (try data.pokemons.getOrPutValue(allocator, pokemons.index, .{})).value_ptr;
            switch (pokemons.value) {
                .tms => |tms| _ = try pokemon.tms.put(allocator, tms.index, tms.value),
                .hms => |hms| _ = try pokemon.hms.put(allocator, hms.index, hms.value),
                .types => |types| {
                    _ = try pokemon.types.put(allocator, types.value, {});
                    return error.ParserFailed;
                },
                .stats,
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
                .name,
                .pokedex_entry,
                => return error.ParserFailed,
            }
            return;
        },
        .moves => |moves| {
            const move = (try data.moves.getOrPutValue(allocator, moves.index, .{})).value_ptr;
            switch (moves.value) {
                .power => |power| move.power = power,
                .type => |_type| move.type = _type,
                .name,
                .description,
                .effect,
                .accuracy,
                .pp,
                .target,
                .priority,
                .category,
                => {},
            }
            return error.ParserFailed;
        },
        .tms => |tms| {
            _ = try data.tms.put(allocator, tms.index, tms.value);
            return error.ParserFailed;
        },
        .hms => |hms| {
            _ = try data.hms.put(allocator, hms.index, hms.value);
            return error.ParserFailed;
        },
        else => return error.ParserFailed,
    }
    unreachable;
}

fn randomize(data: Data, seed: u64, pref: Preference) !void {
    var random = &rand.DefaultPrng.init(seed).random;

    for (data.pokemons.values()) |pokemon| {
        try randomizeMachinesLearned(data, pokemon, random, pref, data.tms, pokemon.tms);
        try randomizeMachinesLearned(data, pokemon, random, pref, data.hms, pokemon.hms);
    }
}

fn randomizeMachinesLearned(
    data: Data,
    pokemon: Pokemon,
    random: *rand.Random,
    pref: Preference,
    machines: Machines,
    learned: MachinesLearned,
) !void {
    for (learned.values()) |*is_learned, i| {
        switch (pref) {
            .random => is_learned.* = random.boolean(),
            .stab => {
                const low_chance = 0.1;
                const chance: f64 = blk: {
                    const tm_index = learned.keys()[i];
                    const index = machines.get(tm_index) orelse break :blk low_chance;
                    const move = data.moves.get(index) orelse break :blk low_chance;
                    const move_type = move.type orelse break :blk low_chance;
                    if (pokemon.types.get(move_type) == null)
                        break :blk low_chance;

                    // Yay the move is stab. Give it a higher chance.
                    break :blk @as(f64, 1.0 - low_chance);
                };

                is_learned.* = random.float(f64) < chance;
            },
        }
    }
}

const Machines = std.AutoArrayHashMapUnmanaged(u16, u16);
const MachinesLearned = std.AutoArrayHashMapUnmanaged(u8, bool);
const Moves = std.AutoArrayHashMapUnmanaged(u16, Move);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);

const Data = struct {
    allocator: *mem.Allocator,
    pokemons: Pokemons = Pokemons{},
    moves: Moves = Moves{},
    tms: Machines = Machines{},
    hms: Machines = Machines{},
};

const Pokemon = struct {
    types: Set = Set{},
    tms: MachinesLearned = MachinesLearned{},
    hms: MachinesLearned = MachinesLearned{},
};

const LvlUpMove = struct {
    level: ?u16 = null,
    id: ?usize = null,
};

const Move = struct {
    power: ?u8 = null,
    type: ?u16 = null,
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
    try util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.pokemons[0].tms[0]=true
        \\.pokemons[0].tms[1]=false
        \\.pokemons[0].tms[2]=true
        \\.pokemons[0].hms[0]=false
        \\.pokemons[0].hms[1]=true
        \\.pokemons[0].hms[2]=false
        \\
    );
    try util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--preference=stab" }, test_string, result_prefix ++
        \\.pokemons[0].tms[0]=true
        \\.pokemons[0].tms[1]=true
        \\.pokemons[0].tms[2]=true
        \\.pokemons[0].hms[0]=false
        \\.pokemons[0].hms[1]=false
        \\.pokemons[0].hms[2]=true
        \\
    );
}
