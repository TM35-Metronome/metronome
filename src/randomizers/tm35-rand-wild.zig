const clap = @import("clap");
const format = @import("format");
const it = @import("ziter");
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
const meta = std.meta;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const Program = @This();

allocator: mem.Allocator,
options: struct {
    seed: u64,
    simular_total_stats: bool,
},
pokedex: Set = Set{},
pokemons: Pokemons = Pokemons{},
wild_pokemons: Zones = Zones{},

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Randomizes wild Pokémon encounters.
    \\
;

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam("-h, --help                 Display this help text and exit.                                                          ") catch unreachable,
    clap.parseParam("-s, --seed <INT>           The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
    clap.parseParam("-t, --simular-total-stats  Replaced wild Pokémons should have simular total stats.                                   ") catch unreachable,
    clap.parseParam("-v, --version              Output version information and exit.                                                      ") catch unreachable,
};

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    return Program{
        .allocator = allocator,
        .options = .{
            .seed = try util.getSeed(args),
            .simular_total_stats = args.flag("--simular-total-stats"),
        },
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) !void {
    try format.io(program.allocator, stdio.in, stdio.out, program, useGame);
    try program.randomize();
    try program.output(stdio.out);
}

fn output(program: *Program, writer: anytype) !void {
    for (program.wild_pokemons.values()) |zone, i| {
        const zone_id = program.wild_pokemons.keys()[i];
        for (zone.wild_areas) |area, j| {
            const aid = @intToEnum(meta.Tag(format.WildPokemons), @intCast(u5, j));
            try ston.serialize(writer, .{
                .wild_pokemons = ston.index(zone_id, ston.field(@tagName(aid), .{
                    .pokemons = area.pokemons,
                })),
            });
        }
    }
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try program.pokedex.put(allocator, pokedex.index, {});
            return error.DidNotConsumeData;
        },
        .pokemons => |pokemons| {
            const pokemon = (try program.pokemons.getOrPutValue(allocator, pokemons.index, .{}))
                .value_ptr;
            switch (pokemons.value) {
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .pokedex_entry => |pokedex_entry| pokemon.pokedex_entry = pokedex_entry,
                .stats => |stats| pokemon.stats[@enumToInt(stats)] = stats.value(),
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
                .evos,
                .moves,
                .tms,
                .hms,
                .name,
                => return error.DidNotConsumeData,
            }
            return error.DidNotConsumeData;
        },
        .wild_pokemons => |wild_areas| {
            const zone = (try program.wild_pokemons.getOrPutValue(
                allocator,
                wild_areas.index,
                .{},
            )).value_ptr;
            const area = &zone.wild_areas[@enumToInt(wild_areas.value)];
            const wild_area = wild_areas.value.value();

            switch (wild_area) {
                .pokemons => |pokemons| {
                    const pokemon = (try area.pokemons.getOrPutValue(
                        allocator,
                        pokemons.index,
                        .{},
                    )).value_ptr;

                    // TODO: We're not using min/max level for anything yet
                    switch (pokemons.value) {
                        .min_level => |min_level| pokemon.min_level = min_level,
                        .max_level => |max_level| pokemon.max_level = max_level,
                        .species => |species| pokemon.species = species,
                    }
                    return;
                },
                .encounter_rate => return error.DidNotConsumeData,
            }
        },
        .version,
        .game_title,
        .gamecode,
        .instant_text,
        .starters,
        .text_delays,
        .trainers,
        .moves,
        .abilities,
        .types,
        .tms,
        .hms,
        .items,
        .maps,
        .static_pokemons,
        .given_pokemons,
        .pokeball_items,
        .hidden_hollows,
        .text,
        => return error.DidNotConsumeData,
    }
    unreachable;
}

fn randomize(program: *Program) !void {
    const allocator = program.allocator;
    const random = rand.DefaultPrng.init(program.options.seed).random();
    var simular = std.ArrayList(u16).init(allocator);

    const species = try pokedexPokemons(allocator, program.pokemons, program.pokedex);
    for (program.wild_pokemons.values()) |zone| {
        for (zone.wild_areas) |area| {
            for (area.pokemons.values()) |*wild_pokemon| {
                const old_species = wild_pokemon.species orelse continue;

                if (program.options.simular_total_stats) blk: {
                    // If we don't know what the old Pokemon was, then we can't do simular_total_stats.
                    // We therefor just pick a random pokemon and continue.
                    const pokemon = program.pokemons.get(old_species) orelse {
                        wild_pokemon.species = util.random.item(random, species.keys()).?.*;
                        break :blk;
                    };

                    var min = @intCast(i64, it.fold(&pokemon.stats, @as(usize, 0), foldu8));
                    var max = min;

                    simular.shrinkRetainingCapacity(0);
                    while (simular.items.len < 5) {
                        min -= 5;
                        max += 5;

                        for (species.keys()) |s| {
                            const p = program.pokemons.get(s).?;
                            const total = @intCast(i64, it.fold(&p.stats, @as(usize, 0), foldu8));
                            if (min <= total and total <= max)
                                try simular.append(s);
                        }
                    }

                    wild_pokemon.species = util.random.item(random, simular.items).?.*;
                } else {
                    wild_pokemon.species = util.random.item(random, species.keys()).?.*;
                }
            }
        }
    }
}

fn foldu8(a: usize, b: u8) usize {
    return a + b;
}

const number_of_areas = @typeInfo(format.WildPokemons).Union.fields.len;

const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);
const WildAreas = [number_of_areas]WildArea;
const WildPokemons = std.AutoArrayHashMapUnmanaged(u8, WildPokemon);
const Zones = std.AutoArrayHashMapUnmanaged(u16, Zone);

fn pokedexPokemons(allocator: mem.Allocator, pokemons: Pokemons, pokedex: Set) !Set {
    var res = Set{};
    errdefer res.deinit(allocator);

    for (pokemons.values()) |pokemon, i| {
        if (pokemon.catch_rate == 0)
            continue;
        if (pokedex.get(pokemon.pokedex_entry) == null)
            continue;

        _ = try res.put(allocator, pokemons.keys()[i], {});
    }

    return res;
}

const Zone = struct {
    wild_areas: WildAreas = [_]WildArea{WildArea{}} ** number_of_areas,
};

const WildArea = struct {
    pokemons: WildPokemons = WildPokemons{},
};

const WildPokemon = struct {
    min_level: ?u8 = null,
    max_level: ?u8 = null,
    species: ?u16 = null,
};

const Pokemon = struct {
    stats: [6]u8 = [_]u8{0} ** 6,
    catch_rate: usize = 1,
    pokedex_entry: u16 = math.maxInt(u16),
};

test "tm35-rand-wild" {
    const result_prefix =
        \\.pokemons[0].pokedex_entry=0
        \\.pokemons[0].stats.hp=10
        \\.pokemons[0].stats.attack=10
        \\.pokemons[0].stats.defense=10
        \\.pokemons[0].stats.speed=10
        \\.pokemons[0].stats.sp_attack=10
        \\.pokemons[0].stats.sp_defense=10
        \\.pokemons[0].catch_rate=10
        \\.pokemons[1].pokedex_entry=1
        \\.pokemons[1].stats.hp=12
        \\.pokemons[1].stats.attack=12
        \\.pokemons[1].stats.defense=12
        \\.pokemons[1].stats.speed=12
        \\.pokemons[1].stats.sp_attack=12
        \\.pokemons[1].stats.sp_defense=12
        \\.pokemons[1].catch_rate=10
        \\.pokemons[2].pokedex_entry=2
        \\.pokemons[2].stats.hp=14
        \\.pokemons[2].stats.attack=14
        \\.pokemons[2].stats.defense=14
        \\.pokemons[2].stats.speed=14
        \\.pokemons[2].stats.sp_attack=14
        \\.pokemons[2].stats.sp_defense=14
        \\.pokemons[2].catch_rate=10
        \\.pokemons[3].pokedex_entry=3
        \\.pokemons[3].stats.hp=16
        \\.pokemons[3].stats.attack=16
        \\.pokemons[3].stats.defense=16
        \\.pokemons[3].stats.speed=16
        \\.pokemons[3].stats.sp_attack=16
        \\.pokemons[3].stats.sp_defense=16
        \\.pokemons[3].catch_rate=10
        \\.pokemons[4].pokedex_entry=4
        \\.pokemons[4].stats.hp=18
        \\.pokemons[4].stats.attack=18
        \\.pokemons[4].stats.defense=18
        \\.pokemons[4].stats.speed=18
        \\.pokemons[4].stats.sp_attack=18
        \\.pokemons[4].stats.sp_defense=18
        \\.pokemons[4].catch_rate=10
        \\.pokemons[5].pokedex_entry=5
        \\.pokemons[5].stats.hp=20
        \\.pokemons[5].stats.attack=20
        \\.pokemons[5].stats.defense=20
        \\.pokemons[5].stats.speed=20
        \\.pokemons[5].stats.sp_attack=20
        \\.pokemons[5].stats.sp_defense=20
        \\.pokemons[5].catch_rate=10
        \\.pokemons[6].pokedex_entry=6
        \\.pokemons[6].stats.hp=22
        \\.pokemons[6].stats.attack=22
        \\.pokemons[6].stats.defense=22
        \\.pokemons[6].stats.speed=22
        \\.pokemons[6].stats.sp_attack=22
        \\.pokemons[6].stats.sp_defense=22
        \\.pokemons[6].catch_rate=10
        \\.pokemons[7].pokedex_entry=7
        \\.pokemons[7].stats.hp=24
        \\.pokemons[7].stats.attack=24
        \\.pokemons[7].stats.defense=24
        \\.pokemons[7].stats.speed=24
        \\.pokemons[7].stats.sp_attack=24
        \\.pokemons[7].stats.sp_defense=24
        \\.pokemons[7].catch_rate=10
        \\.pokemons[8].pokedex_entry=8
        \\.pokemons[8].stats.hp=28
        \\.pokemons[8].stats.attack=28
        \\.pokemons[8].stats.defense=28
        \\.pokemons[8].stats.speed=28
        \\.pokemons[8].stats.sp_attack=28
        \\.pokemons[8].stats.sp_defense=28
        \\.pokemons[8].catch_rate=10
        \\.pokemons[9].pokedex_entry=9
        \\.pokemons[9].stats.hp=28
        \\.pokemons[9].stats.attack=28
        \\.pokemons[9].stats.defense=28
        \\.pokemons[9].stats.speed=28
        \\.pokemons[9].stats.sp_attack=28
        \\.pokemons[9].stats.sp_defense=28
        \\.pokemons[9].catch_rate=0
        \\.pokedex[0].height=0
        \\.pokedex[1].height=0
        \\.pokedex[2].height=0
        \\.pokedex[3].height=0
        \\.pokedex[4].height=0
        \\.pokedex[5].height=0
        \\.pokedex[6].height=0
        \\.pokedex[7].height=0
        \\.pokedex[8].height=0
        \\.pokedex[9].height=0
        \\
    ;

    const test_string = result_prefix ++
        \\.wild_pokemons[0].grass_0.pokemons[0].species=0
        \\.wild_pokemons[0].grass_0.pokemons[1].species=0
        \\.wild_pokemons[0].grass_0.pokemons[2].species=0
        \\.wild_pokemons[0].grass_0.pokemons[3].species=0
        \\.wild_pokemons[1].grass_0.pokemons[0].species=0
        \\.wild_pokemons[1].grass_0.pokemons[1].species=0
        \\.wild_pokemons[1].grass_0.pokemons[2].species=0
        \\.wild_pokemons[1].grass_0.pokemons[3].species=0
        \\.wild_pokemons[2].grass_0.pokemons[0].species=0
        \\.wild_pokemons[2].grass_0.pokemons[1].species=0
        \\.wild_pokemons[2].grass_0.pokemons[2].species=0
        \\.wild_pokemons[2].grass_0.pokemons[3].species=0
        \\.wild_pokemons[3].grass_0.pokemons[0].species=0
        \\.wild_pokemons[3].grass_0.pokemons[1].species=0
        \\.wild_pokemons[3].grass_0.pokemons[2].species=0
        \\.wild_pokemons[3].grass_0.pokemons[3].species=0
        \\
    ;
    try util.testing.testProgram(Program, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.wild_pokemons[0].grass_0.pokemons[0].species=2
        \\.wild_pokemons[0].grass_0.pokemons[1].species=3
        \\.wild_pokemons[0].grass_0.pokemons[2].species=3
        \\.wild_pokemons[0].grass_0.pokemons[3].species=0
        \\.wild_pokemons[1].grass_0.pokemons[0].species=4
        \\.wild_pokemons[1].grass_0.pokemons[1].species=0
        \\.wild_pokemons[1].grass_0.pokemons[2].species=7
        \\.wild_pokemons[1].grass_0.pokemons[3].species=7
        \\.wild_pokemons[2].grass_0.pokemons[0].species=2
        \\.wild_pokemons[2].grass_0.pokemons[1].species=0
        \\.wild_pokemons[2].grass_0.pokemons[2].species=2
        \\.wild_pokemons[2].grass_0.pokemons[3].species=0
        \\.wild_pokemons[3].grass_0.pokemons[0].species=0
        \\.wild_pokemons[3].grass_0.pokemons[1].species=0
        \\.wild_pokemons[3].grass_0.pokemons[2].species=0
        \\.wild_pokemons[3].grass_0.pokemons[3].species=3
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{ "--seed=0", "--simular-total-stats" }, test_string, result_prefix ++
        \\.wild_pokemons[0].grass_0.pokemons[0].species=0
        \\.wild_pokemons[0].grass_0.pokemons[1].species=0
        \\.wild_pokemons[0].grass_0.pokemons[2].species=0
        \\.wild_pokemons[0].grass_0.pokemons[3].species=0
        \\.wild_pokemons[1].grass_0.pokemons[0].species=0
        \\.wild_pokemons[1].grass_0.pokemons[1].species=0
        \\.wild_pokemons[1].grass_0.pokemons[2].species=1
        \\.wild_pokemons[1].grass_0.pokemons[3].species=1
        \\.wild_pokemons[2].grass_0.pokemons[0].species=0
        \\.wild_pokemons[2].grass_0.pokemons[1].species=0
        \\.wild_pokemons[2].grass_0.pokemons[2].species=0
        \\.wild_pokemons[2].grass_0.pokemons[3].species=0
        \\.wild_pokemons[3].grass_0.pokemons[0].species=0
        \\.wild_pokemons[3].grass_0.pokemons[1].species=0
        \\.wild_pokemons[3].grass_0.pokemons[2].species=0
        \\.wild_pokemons[3].grass_0.pokemons[3].species=0
        \\
    );
}
