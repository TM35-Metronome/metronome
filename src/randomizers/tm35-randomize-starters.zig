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
const log = std.log;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const format = core.format;

const Program = @This();

allocator: mem.Allocator,
options: struct {
    seed: u64,
    evolutions: usize,
    pick_lowest: bool,
},
pokedex: Set = Set{},
starters: Starters = Starters{},
pokemons: Pokemons = Pokemons{},
evolves_from: Evolutions = Evolutions{},
evolves_to: Evolutions = Evolutions{},

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Randomizes starter Pokémons.
    \\
;

pub const parsers = .{
    .INT = clap.parsers.int(u64, 0),
};

pub const params = clap.parseParamsComptime(
    \\-e, --evolutions <INT>
    \\        Only pick starters with NUM or more evolutions. (default: 0)
    \\
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\-l, --pick-lowest-evolution
    \\        Always pick the lowest evolution of a starter.
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
        .options = .{
            .seed = args.args.seed orelse std.crypto.random.int(u64),
            .pick_lowest = args.args.@"pick-lowest-evolution" != 0,
            .evolutions = math.cast(usize, args.args.evolutions orelse 0) orelse return error.ArgumentToBig,
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
    try ston.serialize(writer, .{ .starters = program.starters });
}

fn randomize(program: *Program) !void {
    var default_random = rand.DefaultPrng.init(program.options.seed);
    const random = default_random.random();
    const pick_from = try program.getStartersToPickFrom();

    const starters = program.starters.values();
    for (starters, 0..) |*starter, i| while (true) {
        starter.* = util.random.item(random, pick_from.keys()).?.*;

        // Prevent duplicates if possible. We cannot prevent it if we have less pokemon to pick
        // from than there is starters
        if (pick_from.count() < starters.len)
            break;
        if (mem.indexOfScalar(u16, starters[0..i], starter.*) == null)
            break;
    };
}

fn getStartersToPickFrom(program: *Program) !Set {
    const allocator = program.allocator;
    const dex_mons = try pokedexPokemons(allocator, program.pokemons, program.pokedex);
    var res = Set{};
    for (dex_mons.keys()) |species| {
        // Only pick lowest evo species if pick_lowest is true
        if (program.options.pick_lowest and program.evolves_from.get(species) != null)
            continue;
        if (countEvos(program.evolves_to, species) < program.options.evolutions)
            continue;

        _ = try res.put(allocator, species, {});
    }
    if (res.count() == 0)
        _ = try res.put(allocator, 0, {});

    return res;
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try program.pokedex.put(allocator, pokedex.index, {});
            return error.DidNotConsumeData;
        },
        .starters => |starters| {
            _ = try program.starters.put(allocator, starters.index, starters.value);
            return;
        },
        .pokemons => |pokemons| {
            const evolves_from = pokemons.index;
            const pokemon = (try program.pokemons.getOrPutValue(allocator, evolves_from, .{}))
                .value_ptr;
            switch (pokemons.value) {
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .pokedex_entry => |pokedex_entry| pokemon.pokedex_entry = pokedex_entry,
                .evos => |evos| switch (evos.value) {
                    .target => |evolves_to| {
                        const from_set = (try program.evolves_from.getOrPutValue(
                            allocator,
                            evolves_to,
                            .{},
                        )).value_ptr;
                        const to_set = (try program.evolves_to.getOrPutValue(
                            allocator,
                            evolves_from,
                            .{},
                        )).value_ptr;
                        _ = try program.pokemons.getOrPutValue(allocator, evolves_to, .{});
                        _ = try from_set.put(allocator, evolves_from, {});
                        _ = try to_set.put(allocator, evolves_to, {});
                    },
                    .param,
                    .method,
                    => return error.DidNotConsumeData,
                },
                .stats,
                .types,
                .base_exp_yield,
                .items,
                .gender_ratio,
                .egg_cycles,
                .base_friendship,
                .growth_rate,
                .egg_groups,
                .abilities,
                .moves,
                .tms,
                .hms,
                .name,
                .ev_yield,
                => return error.DidNotConsumeData,
            }
            return error.DidNotConsumeData;
        },
        .version,
        .game_title,
        .gamecode,
        .instant_text,
        .text_delays,
        .trainers,
        .moves,
        .abilities,
        .types,
        .tms,
        .hms,
        .items,
        .maps,
        .wild_pokemons,
        .static_pokemons,
        .given_pokemons,
        .pokeball_items,
        .hidden_hollows,
        .text,
        => return error.DidNotConsumeData,
    }
    unreachable;
}

fn countEvos(evolves_to: Evolutions, pokemon: u16) usize {
    var res: usize = 0;
    const evolutions = evolves_to.get(pokemon) orelse return 0;

    // TODO: We don't handle cycles here.
    for (evolutions.keys()) |evo| {
        const evos = countEvos(evolves_to, evo) + 1;
        res = @max(res, evos);
    }

    return res;
}

const Evolutions = std.AutoArrayHashMapUnmanaged(u16, Set);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);
const Starters = std.AutoArrayHashMapUnmanaged(u16, u16);

fn pokedexPokemons(allocator: mem.Allocator, pokemons: Pokemons, pokedex: Set) !Set {
    var res = Set{};
    errdefer res.deinit(allocator);

    for (pokemons.keys(), pokemons.values()) |species, pokemon| {
        if (pokemon.catch_rate == 0)
            continue;
        if (pokedex.get(pokemon.pokedex_entry) == null)
            continue;

        _ = try res.put(allocator, species, {});
    }

    return res;
}

const Pokemon = struct {
    pokedex_entry: u16 = math.maxInt(u16),
    catch_rate: usize = 1,
};

test "tm35-rand-starters" {
    const result_prefix =
        \\.pokemons[0].pokedex_entry=0
        \\.pokemons[0].evos[0].target=1
        \\.pokemons[1].pokedex_entry=1
        \\.pokemons[1].evos[0].target=2
        \\.pokemons[2].pokedex_entry=2
        \\.pokemons[3].pokedex_entry=3
        \\.pokemons[3].evos[0].target=4
        \\.pokemons[4].pokedex_entry=4
        \\.pokemons[5].pokedex_entry=5
        \\.pokedex[0].height=0
        \\.pokedex[1].height=0
        \\.pokedex[2].height=0
        \\.pokedex[3].height=0
        \\.pokedex[4].height=0
        \\.pokedex[5].height=0
        \\
    ;
    const test_string = result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=0
        \\.starters[2]=0
        \\
    ;

    try util.testing.testProgram(Program, &[_][]const u8{"--seed=1"}, test_string, result_prefix ++
        \\.starters[0]=4
        \\.starters[1]=0
        \\.starters[2]=1
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{ "--seed=1", "--pick-lowest-evolution" }, test_string, result_prefix ++
        \\.starters[0]=5
        \\.starters[1]=0
        \\.starters[2]=3
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{ "--seed=1", "--evolutions=1" }, test_string, result_prefix ++
        \\.starters[0]=3
        \\.starters[1]=0
        \\.starters[2]=1
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{ "--seed=1", "--evolutions=2" }, test_string, result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=0
        \\.starters[2]=0
        \\
    );
}
