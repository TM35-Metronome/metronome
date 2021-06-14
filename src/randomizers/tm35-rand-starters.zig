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
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-e, --evolutions <INT>       Only pick starters with NUM or more evolutions. (default: 0)                              ") catch unreachable,
        clap.parseParam("-h, --help                   Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-l, --pick-lowest-evolution  Always pick the lowest evolution of a starter.                                            ") catch unreachable,
        clap.parseParam("-s, --seed <INT>             The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-v, --version                Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-rand-starters ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nRandomizes starter Pokémons.\n" ++
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
    const evolutions = if (args.option("--evolutions")) |evos|
        fmt.parseUnsigned(usize, evos, 10) catch |err| {
            log.err("'{s}' could not be parsed as a number to --evolutions: {}\n", .{ evos, err });
            return error.InvalidArgument;
        }
    else
        0;

    const pick_lowest = args.flag("--pick-lowest-evolution");

    var data = Data{ .allocator = allocator };
    try format.io(allocator, stdio.in, stdio.out, &data, useGame);

    const random = &rand.DefaultPrng.init(seed).random;
    const pick_from = try getStartersToPickFrom(random, data, pick_lowest, evolutions);
    try outputData(stdio.out, random, data, pick_from);
}

fn outputData(writer: anytype, random: *rand.Random, data: Data, pick_from: Set) !void {
    for (data.starters.keys()) |starter| {
        const res = util.random.item(random, pick_from.keys()).?.*;
        try ston.serialize(writer, format.Game.starter(@intCast(u8, starter), res));
    }
}

fn getStartersToPickFrom(
    random: *rand.Random,
    data: Data,
    pick_lowest: bool,
    evolutions: usize,
) !Set {
    const dex_mons = try data.pokedexPokemons();
    var res = Set{};
    for (dex_mons.keys()) |species| {
        // Only pick lowest evo species if pick_lowest is true
        if (pick_lowest and data.evolves_from.get(species) != null)
            continue;
        if (countEvos(data, species) < evolutions)
            continue;

        _ = try res.put(data.allocator, species, {});
    }
    if (res.count() == 0)
        _ = try res.put(data.allocator, 0, {});

    return res;
}

fn useGame(data: *Data, parsed: format.Game) !void {
    const allocator = data.allocator;
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try data.pokedex.put(allocator, pokedex.index, {});
            return error.ParserFailed;
        },
        .starters => |starters| {
            _ = try data.starters.put(allocator, starters.index, {});
            return;
        },
        .pokemons => |pokemons| {
            const evolves_from = pokemons.index;
            const pokemon = (try data.pokemons.getOrPutValue(allocator, evolves_from, .{})).value_ptr;
            switch (pokemons.value) {
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .pokedex_entry => |pokedex_entry| pokemon.pokedex_entry = pokedex_entry,
                .evos => |evos| switch (evos.value) {
                    .target => |evolves_to| {
                        const from_set = (try data.evolves_from.getOrPutValue(allocator, evolves_to, .{})).value_ptr;
                        const to_set = (try data.evolves_to.getOrPutValue(allocator, evolves_from, .{})).value_ptr;
                        _ = try data.pokemons.getOrPutValue(allocator, evolves_to, .{});
                        _ = try from_set.put(allocator, evolves_from, {});
                        _ = try to_set.put(allocator, evolves_to, {});
                    },
                    .param,
                    .method,
                    => return error.ParserFailed,
                },
                .stats,
                .types,
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
                .moves,
                .tms,
                .hms,
                .name,
                => return error.ParserFailed,
            }
            return error.ParserFailed;
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
        => return error.ParserFailed,
    }
    unreachable;
}

fn countEvos(data: Data, pokemon: u16) usize {
    var res: usize = 0;
    const evolves_to = data.evolves_to.get(pokemon) orelse return 0;

    // TODO: We don't handle cycles here.
    for (evolves_to.keys()) |evo| {
        const evos = countEvos(data, evo) + 1;
        res = math.max(res, evos);
    }

    return res;
}

const Evolutions = std.AutoArrayHashMapUnmanaged(u16, Set);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);

const Data = struct {
    allocator: *mem.Allocator,
    pokedex: Set = Set{},
    starters: Set = Set{},
    pokemons: Pokemons = Pokemons{},
    evolves_from: Evolutions = Evolutions{},
    evolves_to: Evolutions = Evolutions{},

    fn pokedexPokemons(d: Data) !Set {
        var res = Set{};
        errdefer res.deinit(d.allocator);

        for (d.pokemons.values()) |pokemon, i| {
            const species = d.pokemons.keys()[i];
            if (pokemon.catch_rate == 0)
                continue;
            if (d.pokedex.get(pokemon.pokedex_entry) == null)
                continue;

            _ = try res.put(d.allocator, species, {});
        }

        return res;
    }
};

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

    try util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=1"}, test_string, result_prefix ++
        \\.starters[0]=1
        \\.starters[1]=5
        \\.starters[2]=0
        \\
    );
    try util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=1", "--pick-lowest-evolution" }, test_string, result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=5
        \\.starters[2]=0
        \\
    );
    try util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=1", "--evolutions=1" }, test_string, result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=3
        \\.starters[2]=0
        \\
    );
    try util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=1", "--evolutions=2" }, test_string, result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=0
        \\.starters[2]=0
        \\
    );
}
