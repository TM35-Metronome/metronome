const clap = @import("clap");
const format = @import("format");
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

const algo = util.algorithm;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help                 Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-s, --seed <INT>           The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-t, --simular-total-stats  Replaced wild Pokémons should have simular total stats.                                   ") catch unreachable,
        clap.parseParam("-v, --version              Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-rand-wild ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nRandomizes wild Pokémon encounters.\n" ++
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
    const simular_total_stats = args.flag("--simular-total-stats");

    const data = try handleInput(allocator, stdio.in, stdio.out);
    try randomize(data, allocator, seed, simular_total_stats);
    try outputData(stdio.out, data);
}

fn handleInput(allocator: *mem.Allocator, reader: anytype, writer: anytype) !Data {
    var fifo = util.io.Fifo(.Dynamic).init(allocator);
    var data = Data{};
    while (try util.io.readLine(reader, &fifo)) |line| {
        parseLine(&data, allocator, line) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParserFailed => try writer.print("{}\n", .{line}),
        };
    }
    return data;
}

fn outputData(writer: anytype, data: Data) !void {
    for (data.wild_pokemons.items()) |zone| {
        for (zone.value.wild_areas) |area, j| {
            const aid = @intToEnum(@TagType(format.WildPokemons), @intCast(u5, j));
            for (area.pokemons.items()) |pokemon| {
                if (pokemon.value.min_level) |l|
                    try format.write(writer, format.Game.wild_pokemon(zone.key, format.WildPokemons.init(aid, .{ .pokemons = .{ .index = pokemon.key, .value = .{ .min_level = l } } })));
                if (pokemon.value.max_level) |l|
                    try format.write(writer, format.Game.wild_pokemon(zone.key, format.WildPokemons.init(aid, .{ .pokemons = .{ .index = pokemon.key, .value = .{ .max_level = l } } })));
                if (pokemon.value.species) |s|
                    try format.write(writer, format.Game.wild_pokemon(zone.key, format.WildPokemons.init(aid, .{ .pokemons = .{ .index = pokemon.key, .value = .{ .species = s } } })));
            }
        }
    }
}

fn parseLine(data: *Data, allocator: *mem.Allocator, str: []const u8) !void {
    const parsed = try format.parseNoEscape(str);
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try data.pokedex.put(allocator, pokedex.index, {});
            return error.ParserFailed;
        },
        .pokemons => |pokemons| {
            const pokemon = &(try data.pokemons.getOrPutValue(allocator, pokemons.index, Pokemon{})).value;
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
                => return error.ParserFailed,
            }
            return error.ParserFailed;
        },
        .wild_pokemons => |wild_areas| {
            const zone = &(try data.wild_pokemons.getOrPutValue(allocator, wild_areas.index, Zone{})).value;
            const area = &zone.wild_areas[@enumToInt(wild_areas.value)];
            const wild_area = wild_areas.value.value();

            switch (wild_area) {
                .pokemons => |pokemons| {
                    const pokemon = &(try area.pokemons.getOrPutValue(allocator, pokemons.index, WildPokemon{})).value;

                    // TODO: We're not using min/max level for anything yet
                    switch (pokemons.value) {
                        .min_level => |min_level| pokemon.min_level = min_level,
                        .max_level => |max_level| pokemon.max_level = max_level,
                        .species => |species| pokemon.species = species,
                    }
                    return;
                },
                .encounter_rate => return error.ParserFailed,
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
        => return error.ParserFailed,
    }
    unreachable;
}

fn randomize(data: Data, allocator: *mem.Allocator, seed: u64, simular_total_stats: bool) !void {
    const random = &rand.DefaultPrng.init(seed).random;
    var simular = std.ArrayList(u16).init(allocator);

    const species = try data.pokedexPokemons(allocator);
    for (data.wild_pokemons.items()) |zone| {
        for (zone.value.wild_areas) |area| {
            for (area.pokemons.items()) |*wild_pokemon| {
                const old_species = wild_pokemon.value.species orelse continue;

                if (simular_total_stats) blk: {
                    // If we don't know what the old Pokemon was, then we can't do simular_total_stats.
                    // We therefor just pick a random pokemon and continue.
                    const pokemon = data.pokemons.get(old_species) orelse {
                        wild_pokemon.value.species = util.random.item(random, species.items()).?.key;
                        break :blk;
                    };

                    var min = @intCast(i64, algo.fold(&pokemon.stats, @as(usize, 0), algo.add));
                    var max = min;

                    simular.shrinkRetainingCapacity(0);
                    while (simular.items.len < 5) {
                        min -= 5;
                        max += 5;

                        for (species.items()) |s| {
                            const p = data.pokemons.get(s.key).?;
                            const total = @intCast(i64, algo.fold(&p.stats, @as(usize, 0), algo.add));
                            if (min <= total and total <= max)
                                try simular.append(s.key);
                        }
                    }

                    wild_pokemon.value.species = util.random.item(random, simular.items).?.*;
                } else {
                    wild_pokemon.value.species = util.random.item(random, species.items()).?.key;
                }
            }
        }
    }
}

const number_of_areas = @typeInfo(format.WildPokemons).Union.fields.len;

const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);
const WildAreas = [number_of_areas]WildArea;
const WildPokemons = std.AutoArrayHashMapUnmanaged(u8, WildPokemon);
const Zones = std.AutoArrayHashMapUnmanaged(u16, Zone);

const Data = struct {
    pokedex: Set = Set{},
    pokemons: Pokemons = Pokemons{},
    wild_pokemons: Zones = Zones{},

    fn pokedexPokemons(d: Data, allocator: *mem.Allocator) !Set {
        var res = Set{};
        errdefer res.deinit(allocator);

        for (d.pokemons.items()) |pokemon| {
            if (pokemon.value.catch_rate == 0)
                continue;
            if (d.pokedex.get(pokemon.value.pokedex_entry) == null)
                continue;

            _ = try res.put(allocator, pokemon.key, {});
        }

        return res;
    }
};

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
        \\.wild_pokemons[0].grass.pokemons[0].species=0
        \\.wild_pokemons[0].grass.pokemons[1].species=0
        \\.wild_pokemons[0].grass.pokemons[2].species=0
        \\.wild_pokemons[0].grass.pokemons[3].species=0
        \\.wild_pokemons[1].grass.pokemons[0].species=0
        \\.wild_pokemons[1].grass.pokemons[1].species=0
        \\.wild_pokemons[1].grass.pokemons[2].species=0
        \\.wild_pokemons[1].grass.pokemons[3].species=0
        \\.wild_pokemons[2].grass.pokemons[0].species=0
        \\.wild_pokemons[2].grass.pokemons[1].species=0
        \\.wild_pokemons[2].grass.pokemons[2].species=0
        \\.wild_pokemons[2].grass.pokemons[3].species=0
        \\.wild_pokemons[3].grass.pokemons[0].species=0
        \\.wild_pokemons[3].grass.pokemons[1].species=0
        \\.wild_pokemons[3].grass.pokemons[2].species=0
        \\.wild_pokemons[3].grass.pokemons[3].species=0
        \\
    ;
    util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.wild_pokemons[0].grass.pokemons[0].species=2
        \\.wild_pokemons[0].grass.pokemons[1].species=0
        \\.wild_pokemons[0].grass.pokemons[2].species=0
        \\.wild_pokemons[0].grass.pokemons[3].species=2
        \\.wild_pokemons[1].grass.pokemons[0].species=3
        \\.wild_pokemons[1].grass.pokemons[1].species=7
        \\.wild_pokemons[1].grass.pokemons[2].species=1
        \\.wild_pokemons[1].grass.pokemons[3].species=6
        \\.wild_pokemons[2].grass.pokemons[0].species=6
        \\.wild_pokemons[2].grass.pokemons[1].species=6
        \\.wild_pokemons[2].grass.pokemons[2].species=8
        \\.wild_pokemons[2].grass.pokemons[3].species=8
        \\.wild_pokemons[3].grass.pokemons[0].species=0
        \\.wild_pokemons[3].grass.pokemons[1].species=0
        \\.wild_pokemons[3].grass.pokemons[2].species=4
        \\.wild_pokemons[3].grass.pokemons[3].species=7
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--simular-total-stats" }, test_string, result_prefix ++
        \\.wild_pokemons[0].grass.pokemons[0].species=0
        \\.wild_pokemons[0].grass.pokemons[1].species=0
        \\.wild_pokemons[0].grass.pokemons[2].species=0
        \\.wild_pokemons[0].grass.pokemons[3].species=0
        \\.wild_pokemons[1].grass.pokemons[0].species=0
        \\.wild_pokemons[1].grass.pokemons[1].species=1
        \\.wild_pokemons[1].grass.pokemons[2].species=0
        \\.wild_pokemons[1].grass.pokemons[3].species=0
        \\.wild_pokemons[2].grass.pokemons[0].species=0
        \\.wild_pokemons[2].grass.pokemons[1].species=0
        \\.wild_pokemons[2].grass.pokemons[2].species=1
        \\.wild_pokemons[2].grass.pokemons[3].species=1
        \\.wild_pokemons[3].grass.pokemons[0].species=0
        \\.wild_pokemons[3].grass.pokemons[1].species=0
        \\.wild_pokemons[3].grass.pokemons[2].species=0
        \\.wild_pokemons[3].grass.pokemons[3].species=1
        \\
    );
}
