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

const Program = @This();

allocator: mem.Allocator,
seed: u64,
preference: Preference,
pokemons: Pokemons = Pokemons{},
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
    \\Randomizes the moves Pokémons can learn.
    \\
;

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam("-h, --help                      Display this help text and exit.                                                                ") catch unreachable,
    clap.parseParam("-p, --preference <random|stab>  Which moves the randomizer should prefer picking (90% preference, 10% random). (default: random)") catch unreachable,
    clap.parseParam("-s, --seed <INT>                The seed to use for random numbers. A random seed will be picked if this is not specified.      ") catch unreachable,
    clap.parseParam("-v, --version                   Output version information and exit.                                                            ") catch unreachable,
};

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const seed = try util.getSeed(args);
    const pref = if (args.option("--preference")) |pref|
        if (mem.eql(u8, pref, "random"))
            Preference.random
        else if (mem.eql(u8, pref, "stab"))
            Preference.stab
        else {
            log.err("--preference does not support '{s}'", .{pref});
            return error.InvalidArgument;
        }
    else
        Preference.random;

    return Program{
        .allocator = allocator,
        .seed = seed,
        .preference = pref,
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
    for (program.pokemons.values()) |pokemon, i| {
        const species = program.pokemons.keys()[i];
        try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
            .tms = pokemon.tms,
            .hms = pokemon.hms,
        }) });
    }
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .pokemons => |pokemons| {
            const pokemon = (try program.pokemons.getOrPutValue(allocator, pokemons.index, .{}))
                .value_ptr;
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
            const move = (try program.moves.getOrPutValue(allocator, moves.index, .{})).value_ptr;
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
            _ = try program.tms.put(allocator, tms.index, tms.value);
            return error.ParserFailed;
        },
        .hms => |hms| {
            _ = try program.hms.put(allocator, hms.index, hms.value);
            return error.ParserFailed;
        },
        else => return error.ParserFailed,
    }
    unreachable;
}

fn randomize(program: *Program) !void {
    const random = rand.DefaultPrng.init(program.seed).random();

    for (program.pokemons.values()) |pokemon| {
        try randomizeMachinesLearned(program, pokemon, random, program.tms, pokemon.tms);
        try randomizeMachinesLearned(program, pokemon, random, program.hms, pokemon.hms);
    }
}

fn randomizeMachinesLearned(
    program: *Program,
    pokemon: Pokemon,
    random: rand.Random,
    machines: Machines,
    learned: MachinesLearned,
) !void {
    for (learned.values()) |*is_learned, i| {
        switch (program.preference) {
            .random => is_learned.* = random.boolean(),
            .stab => {
                const low_chance = 0.1;
                const chance: f64 = blk: {
                    const tm_index = learned.keys()[i];
                    const index = machines.get(tm_index) orelse break :blk low_chance;
                    const move = program.moves.get(index) orelse break :blk low_chance;
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

const MachinesLearned = std.AutoArrayHashMapUnmanaged(u8, bool);
const Machines = std.AutoArrayHashMapUnmanaged(u16, u16);
const Moves = std.AutoArrayHashMapUnmanaged(u16, Move);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);

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
    try util.testing.testProgram(Program, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.pokemons[0].tms[0]=true
        \\.pokemons[0].tms[1]=true
        \\.pokemons[0].tms[2]=false
        \\.pokemons[0].hms[0]=false
        \\.pokemons[0].hms[1]=false
        \\.pokemons[0].hms[2]=false
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{ "--seed=0", "--preference=stab" }, test_string, result_prefix ++
        \\.pokemons[0].tms[0]=true
        \\.pokemons[0].tms[1]=false
        \\.pokemons[0].tms[2]=true
        \\.pokemons[0].hms[0]=true
        \\.pokemons[0].hms[1]=false
        \\.pokemons[0].hms[2]=true
        \\
    );
}
