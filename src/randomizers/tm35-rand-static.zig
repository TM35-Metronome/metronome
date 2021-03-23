const clap = @import("clap");
const format = @import("format");
const std = @import("std");
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
        clap.parseParam("-h, --help                                                               Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-s, --seed <INT>                                                         The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-m, --method <random|same-stats|simular-stats|legendary-with-legendary>  The method used to pick the new static Pokémon. (default: random)                         ") catch unreachable,
        clap.parseParam("-t, --types <random|same>                                                Which type each static pokemon should be. (default: random)                               ") catch unreachable,
        clap.parseParam("-v, --version                                                            Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-rand-starters ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nRandomizes static, given and hollow Pokémons. Doesn't work for " ++
        "hg and ss yet.\n" ++
        "\n" ++
        "Options:\n");
    try clap.help(writer, &params);
}

const Method = enum {
    random,
    @"same-stats",
    @"simular-stats",
    @"legendary-with-legendary",
};

const Type = enum {
    random,
    same,
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
    const type_arg = args.option("--types") orelse "random";
    const types = std.meta.stringToEnum(Type, type_arg) orelse {
        log.err("--types does not support '{}'\n", .{type_arg});
        return error.InvalidArgument;
    };

    const method_arg = args.option("--method") orelse "random";
    const method = std.meta.stringToEnum(Method, method_arg) orelse {
        log.err("--method does not support '{}'\n", .{method_arg});
        return error.InvalidArgument;
    };

    var fifo = util.io.Fifo(.Dynamic).init(allocator);
    var data = Data{};
    while (try util.io.readLine(stdio.in, &fifo)) |line| {
        parseLine(allocator, &data, line) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParserFailed => try stdio.out.print("{}\n", .{line}),
        };
    }

    try randomize(
        allocator,
        data,
        seed,
        method,
        types,
    );

    for (data.static_mons.values()) |static, i| {
        const static_i = data.static_mons.at(i).key;
        try stdio.out.print(".static_pokemons[{}].species={}\n", .{ static_i, static });
    }
    for (data.hidden_hollows.values()) |hollow, i| {
        const hi = data.hidden_hollows.at(i).key;
        for (hollow.values()) |version, j| {
            const vi = version.at(j).key;
            for (version.values()) |group, k| {
                const gi = version.at(k).key;
                for (group.values()) |pokemon, g| {
                    const pi = version.at(g).key;
                    if (pokemon.species_index) |si| {
                        try stdio.out.print(
                            ".hidden_hollows[{}].versions[{}].groups[{}].pokemons[{}].species={}\n",
                            .{ hi, vi, gi, pi, data.hollow_mons.get(si).?.* },
                        );
                    }
                }
            }
        }
    }
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !void {
    const parsed = try format.parseNoEscape(str);
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try data.pokedex.put(allocator, pokedex.index);
            return error.ParserFailed;
        },
        .pokemons => |pokemons| {
            const pokemon = try data.pokemons.getOrPutValue(allocator, pokemons.index, Pokemon{});
            switch (pokemons.value) {
                .stats => |stats| switch (stats) {
                    .hp => |hp| pokemon.stats[0] = hp,
                    .attack => |attack| pokemon.stats[1] = attack,
                    .defense => |defense| pokemon.stats[2] = defense,
                    .speed => |speed| pokemon.stats[3] = speed,
                    .sp_attack => |sp_attack| pokemon.stats[4] = sp_attack,
                    .sp_defense => |sp_defense| pokemon.stats[5] = sp_defense,
                },
                .types => |types| _ = try pokemon.types.put(allocator, types.value),
                .growth_rate => |growth_rate| pokemon.growth_rate = growth_rate,
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .gender_ratio => |gender_ratio| pokemon.gender_ratio = gender_ratio,
                .pokedex_entry => |pokedex_entry| pokemon.pokedex_entry = pokedex_entry,
                .egg_groups => |groups| {
                    // TODO: Should we save both egg groups?
                    if (groups.index == 0)
                        pokemon.egg_group = groups.value;
                },
                .evos => |evos| switch (evos.value) {
                    .target => |target| _ = try pokemon.evos.put(allocator, target),
                    .method,
                    .param,
                    => return error.ParserFailed,
                },
                .base_exp_yield,
                .ev_yield,
                .items,
                .egg_cycles,
                .base_friendship,
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
        .static_pokemons => |pokemons| switch (pokemons.value) {
            .species => |species| {
                _ = try data.static_mons.put(allocator, pokemons.index, species);
                return;
            },
            .level => return error.ParserFailed,
        },
        .given_pokemons => |pokemons| switch (pokemons.value) {
            .species => |species| {
                _ = try data.given_mons.put(allocator, pokemons.index, species);
                return;
            },
            .level => return error.ParserFailed,
        },
        .hidden_hollows => |hollows| {
            const versions = try data.hidden_hollows.getOrPutValue(allocator, hollows.index, HollowVersions{});

            switch (hollows.value) {
                .versions => |version| {
                    const groups = try versions.getOrPutValue(allocator, version.index, HollowGroups{});

                    switch (version.value) {
                        .groups => |group| {
                            const pokemons = try groups.getOrPutValue(allocator, group.index, HollowPokemons{});

                            switch (group.value) {
                                .pokemons => |mon| {
                                    const pokemon = try pokemons.getOrPutValue(allocator, mon.index, HollowMon{});

                                    switch (mon.value) {
                                        .species => |species| {
                                            const index = data.hollow_mons.count();
                                            _ = try data.hollow_mons.put(allocator, index, species);
                                            pokemon.species_index = index;
                                        },
                                    }
                                    return;
                                },
                            }
                        },
                    }
                },
                .items => return error.ParserFailed,
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
        .wild_pokemons,
        .pokeball_items,
        .text,
        => return error.ParserFailed,
    }
    unreachable;
}

fn randomize(
    allocator: *mem.Allocator,
    data: Data,
    seed: u64,
    method: Method,
    _type: Type,
) !void {
    var random_adapt = rand.DefaultPrng.init(seed);
    const random = &random_adapt.random;

    const species = try data.getPokedexPokemons(allocator);

    for ([_]StaticMons{
        data.static_mons,
        data.given_mons,
        data.hollow_mons,
    }) |static_mons| {
        switch (method) {
            .random => switch (_type) {
                .random => {
                    const max = species.count();
                    if (max == 0)
                        return;

                    for (static_mons.values()) |*static|
                        static.* = species.at(random.intRangeLessThan(usize, 0, max));
                },
                .same => {
                    const by_type = try data.getSpeciesByType(allocator, &species);
                    for (static_mons.values()) |*static| {
                        const pokemon = data.pokemons.get(static.*).?;
                        const type_max = pokemon.types.count();
                        if (type_max == 0)
                            continue;

                        const t = pokemon.types.at(random.intRangeLessThan(usize, 0, type_max));
                        const pokemons = by_type.get(t).?;
                        const max = pokemons.count();
                        static.* = pokemons.at(random.intRangeLessThan(usize, 0, max));
                    }
                },
            },
            .@"same-stats", .@"simular-stats" => {
                const by_type = switch (_type) {
                    // When we do random, we should never actually touch the 'by_type'
                    // table, so let's just avoid doing the work of constructing it :)
                    .random => undefined,
                    .same => try data.getSpeciesByType(allocator, &species),
                };

                var simular = std.ArrayList(usize).init(allocator);
                for (static_mons.values()) |*static| {
                    defer simular.resize(0) catch unreachable;

                    // If the static Pokémon does not exist in the data
                    // we received, then there is no way for us to compare
                    // its stats with other Pokémons. The only thing we can
                    // assume is that the Pokémon it currently is
                    // is simular/same as itself.
                    const prev_pokemon = data.pokemons.get(static.*) orelse continue;

                    var min = @intCast(i64, sum(u8, &prev_pokemon.stats));
                    var max = min;

                    // For same-stats, we can just make this loop run once, which will
                    // make the simular list only contain pokemons with the same stats.
                    const condition = if (method == .@"simular-stats") @as(usize, 25) else @as(usize, 1);
                    while (simular.items.len < condition) : ({
                        min -= 5;
                        max += 5;
                    }) {
                        switch (_type) {
                            .random => for (species.span()) |range| {
                                var s = range.start;
                                while (s <= range.end) : (s += 1) {
                                    const pokemon = data.pokemons.get(s).?;

                                    const total = @intCast(i64, sum(u8, &pokemon.stats));
                                    if (min <= total and total <= max)
                                        try simular.append(s);
                                }
                            },
                            .same => {
                                // If this Pokémon has no type (for some reason), then we
                                // cannot pick a pokemon of the same type. The only thing
                                // we can assume is that the Pokémon is the same type
                                // as it self, and therefor just use that as the simular
                                // Pokémon.
                                const type_max = prev_pokemon.types.count();
                                if (type_max == 0) {
                                    try simular.append(static.*);
                                    break;
                                }
                                for (prev_pokemon.types.span()) |range| {
                                    var t = range.start;
                                    while (t <= range.end) : (t += 1) {
                                        const pokemons_of_type = by_type.get(t).?;
                                        for (pokemons_of_type.span()) |range2| {
                                            var s = range2.start;
                                            while (s <= range2.end) : (s += 1) {
                                                const pokemon = data.pokemons.get(s).?;

                                                const total = @intCast(i64, sum(u8, &pokemon.stats));
                                                if (min <= total and total <= max)
                                                    try simular.append(s);
                                            }
                                        }
                                    }
                                }
                            },
                        }
                    }

                    const pick_from = simular.items;
                    static.* = pick_from[random.intRangeLessThan(usize, 0, pick_from.len)];
                }
            },
            .@"legendary-with-legendary" => {
                // There is no way to specify in game that a Pokemon is a legendary.
                // There are therefor two methods we can use to pick legendaries
                // 1. Have a table of Pokemons which are legendaries.
                //    - This does not work with roms that have been hacked
                //      in a way that changes which Pokemons should be considered
                //      legendary
                // 2. Find legendaries by looking at their stats, evolution line
                //    and other patterns common for legendaries
                //
                // I have chosen the latter method.

                // First, lets give each Pokemon a "legendary rating" which
                // is a measure as to how many "legendary" criteria this
                // Pokemon fits into. This rating can be negative.
                var ratings = util.container.IntMap.Unmanaged(usize, isize){};
                for (species.span()) |range| {
                    var _species = range.start;
                    while (_species <= range.end) : (_species += 1) {
                        const pokemon = data.pokemons.get(_species).?;
                        const rating = try ratings.getOrPutValue(allocator, _species, 0);

                        // Legendaries are generally in the "slow" to "medium_slow"
                        // growth rating
                        rating.* += @as(isize, @boolToInt(pokemon.growth_rate == .slow or
                            pokemon.growth_rate == .medium_slow));

                        // They generally have a catch rate of 45 or less
                        rating.* += @as(isize, @boolToInt(pokemon.catch_rate <= 45));

                        // They tend to not have a gender (255 in gender_ratio means
                        // genderless).
                        rating.* += @as(isize, @boolToInt(pokemon.gender_ratio == 255));

                        // Most are part of the "undiscovered" egg group
                        rating.* += @as(isize, @boolToInt(pokemon.egg_group == .undiscovered));

                        // And they don't evolve from anything. Subtract
                        // score from this Pokemons evolutions.
                        for (pokemon.evos.span()) |range2| {
                            var evo = range2.start;
                            while (evo <= range2.end) : (evo += 1) {
                                const evo_rating = try ratings.getOrPutValue(allocator, evo, 0);
                                evo_rating.* -= 10;
                                rating.* -= 10;
                            }
                        }
                    }
                }

                const rating_to_be_legendary = blk: {
                    var res: isize = 0;
                    for (ratings.values()) |rating|
                        res = math.max(res, rating);

                    // Not all legendaries match all criteria.
                    break :blk res - 1;
                };

                var legendaries = Set{};
                var rest = Set{};
                for (ratings.values()) |rating, i| {
                    const s = ratings.at(i).key;
                    if (rating >= rating_to_be_legendary) {
                        _ = try legendaries.put(allocator, s);
                    } else {
                        _ = try rest.put(allocator, s);
                    }
                }

                const legendaries_by_type = switch (_type) {
                    .random => undefined,
                    .same => try data.getSpeciesByType(allocator, &legendaries),
                };
                const rest_by_type = switch (_type) {
                    .random => undefined,
                    .same => try data.getSpeciesByType(allocator, &rest),
                };

                for (static_mons.values()) |*static| {
                    const pokemon = data.pokemons.get(static.*) orelse continue;
                    const rating = (ratings.get(static.*) orelse continue).*;
                    const pick_from = switch (_type) {
                        .random => if (rating >= rating_to_be_legendary) legendaries else rest,
                        .same => blk: {
                            const type_max = pokemon.types.count();
                            if (type_max == 0)
                                continue;

                            const types = pokemon.types;
                            const picked_type = types.at(random.intRangeLessThan(usize, 0, type_max));
                            const pick_from_by_type = if (rating >= rating_to_be_legendary) legendaries_by_type else rest_by_type;
                            break :blk (pick_from_by_type.get(picked_type) orelse continue).*;
                        },
                    };

                    const max = pick_from.count();
                    if (max == 0)
                        continue;
                    static.* = pick_from.at(random.intRangeLessThan(usize, 0, max));
                }
            },
        }
    }
}

fn SumReturn(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Int => u64,
        .Float => f64,
        else => unreachable,
    };
}

fn sum(comptime T: type, buf: []const T) SumReturn(T) {
    var res: SumReturn(T) = 0;
    for (buf) |item|
        res += item;

    return res;
}

const Pokemons = util.container.IntMap.Unmanaged(usize, Pokemon);
const Set = util.container.IntSet.Unmanaged(usize);
const SpeciesByType = util.container.IntMap.Unmanaged(usize, Set);
const StaticMons = util.container.IntMap.Unmanaged(usize, usize);

const HiddenHollows = util.container.IntMap.Unmanaged(usize, HollowVersions);
const HollowGroups = util.container.IntMap.Unmanaged(usize, HollowPokemons);
const HollowPokemons = util.container.IntMap.Unmanaged(usize, HollowMon);
const HollowVersions = util.container.IntMap.Unmanaged(usize, HollowGroups);

const Data = struct {
    pokedex: Set = Set{},
    pokemons: Pokemons = Pokemons{},
    static_mons: StaticMons = StaticMons{},
    given_mons: StaticMons = StaticMons{},
    hollow_mons: StaticMons = StaticMons{},
    hidden_hollows: HiddenHollows = HiddenHollows{},

    fn getPokedexPokemons(d: Data, allocator: *mem.Allocator) !Set {
        var res = Set{};
        errdefer res.deinit(allocator);

        for (d.pokemons.values()) |pokemon, i| {
            const s = d.pokemons.at(i).key;
            if (pokemon.catch_rate == 0 or !d.pokedex.exists(pokemon.pokedex_entry))
                continue;

            _ = try res.put(allocator, s);
        }

        return res;
    }

    fn getSpeciesByType(d: Data, allocator: *mem.Allocator, _species: *const Set) !SpeciesByType {
        var res = SpeciesByType{};
        errdefer {
            for (res.values()) |v|
                v.deinit(allocator);
            res.deinit(allocator);
        }

        for (_species.span()) |range| {
            var s = range.start;
            while (s <= range.end) : (s += 1) {
                const pokemon = d.pokemons.get(s) orelse continue;
                for (pokemon.types.span()) |range2| {
                    var t = range2.start;
                    while (t <= range2.end) : (t += 1) {
                        const set = try res.getOrPutValue(allocator, t, Set{});
                        _ = try set.put(allocator, s);
                    }
                }
            }
        }

        return res;
    }
};

const HollowMon = struct {
    species_index: ?usize = null,
};

const Pokemon = struct {
    stats: [6]u8 = [_]u8{0} ** 6,
    pokedex_entry: usize = math.maxInt(usize),
    catch_rate: usize = 1,
    growth_rate: format.GrowthRate = .fast,
    gender_ratio: usize = math.maxInt(usize),
    egg_group: format.EggGroup = .invalid,
    types: Set = Set{},
    evos: Set = Set{},
};

test "tm35-rand-static" {
    const H = struct {
        fn pokemon(
            comptime id: []const u8,
            comptime stat: []const u8,
            comptime t1: []const u8,
            comptime t2: []const u8,
            comptime growth_rate: []const u8,
            comptime catch_rate: []const u8,
            comptime gender_ratio: []const u8,
            comptime egg_groups: []const u8,
            comptime evo: ?[]const u8,
        ) []const u8 {
            return ".pokedex[" ++ id ++ "].height=0\n" ++
                ".pokemons[" ++ id ++ "].pokedex_entry=" ++ id ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.hp=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.attack=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.defense=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.speed=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.sp_attack=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.sp_defense=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].types[0]=" ++ t1 ++ "\n" ++
                ".pokemons[" ++ id ++ "].types[1]=" ++ t2 ++ "\n" ++
                ".pokemons[" ++ id ++ "].growth_rate=" ++ growth_rate ++ "\n" ++
                ".pokemons[" ++ id ++ "].catch_rate=" ++ catch_rate ++ "\n" ++
                ".pokemons[" ++ id ++ "].gender_ratio=" ++ gender_ratio ++ "\n" ++
                ".pokemons[" ++ id ++ "].egg_groups[0]=" ++ egg_groups ++ "\n" ++
                if (evo) |e| ".pokemons[" ++ id ++ "].evos[0].target=" ++ e ++ "\n" else "";
        }
        fn static(
            comptime id: []const u8,
            comptime species: []const u8,
        ) []const u8 {
            return ".static_pokemons[" ++ id ++ "].species=" ++ species ++ "\n";
        }
    };

    const legendaries = comptime H.pokemon("0", "10", "15", "2", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("1", "10", "13", "2", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("2", "10", "10", "2", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("3", "10", "13", "13", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("4", "11", "11", "11", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("5", "11", "5", "5", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("6", "11", "15", "15", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("7", "12", "16", "14", "slow", "3", "254", "undiscovered", null) ++
        H.pokemon("8", "12", "16", "14", "slow", "3", "0", "undiscovered", null) ++
        H.pokemon("9", "12", "11", "11", "slow", "3", "255", "water1", null);

    const pseudo_legendaries = comptime H.pokemon("10", "10", "16", "16", "slow", "45", "127", "water1", "11") ++
        H.pokemon("11", "10", "16", "2", "slow", "45", "127", "water1", null) ++
        H.pokemon("12", "10", "5", "4", "slow", "45", "127", "monster", "13") ++
        H.pokemon("13", "10", "5", "17", "slow", "45", "127", "monster", null) ++
        H.pokemon("14", "11", "16", "16", "slow", "45", "127", "dragon", "15") ++
        H.pokemon("15", "11", "16", "2", "slow", "45", "127", "dragon", null) ++
        H.pokemon("16", "11", "8", "14", "slow", "3", "255", "mineral", "17") ++
        H.pokemon("17", "11", "8", "14", "slow", "3", "255", "mineral", null) ++
        H.pokemon("18", "12", "16", "4", "slow", "45", "127", "monster", "19") ++
        H.pokemon("19", "12", "16", "4", "slow", "45", "127", "monster", null) ++
        H.pokemon("20", "12", "17", "16", "slow", "45", "127", "dragon", "21") ++
        H.pokemon("21", "12", "17", "16", "slow", "45", "127", "dragon", null);

    const pokemons_to_not_pick_ever = comptime H.pokemon("22", "12", "11", "11", "slow", "0", "255", "water1", null) ++
        H.pokemon("23", "12", "17", "16", "slow", "0", "127", "dragon", null);

    const result_prefix = legendaries ++ pseudo_legendaries ++ pokemons_to_not_pick_ever;
    const test_string = comptime result_prefix ++
        H.static("0", "0") ++
        H.static("1", "1") ++
        H.static("2", "2") ++
        H.static("3", "3") ++
        H.static("4", "4") ++
        H.static("5", "21");

    util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.static_pokemons[0].species=6
        \\.static_pokemons[1].species=0
        \\.static_pokemons[2].species=1
        \\.static_pokemons[3].species=5
        \\.static_pokemons[4].species=8
        \\.static_pokemons[5].species=18
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--types=same" }, test_string, result_prefix ++
        \\.static_pokemons[0].species=0
        \\.static_pokemons[1].species=1
        \\.static_pokemons[2].species=15
        \\.static_pokemons[3].species=3
        \\.static_pokemons[4].species=9
        \\.static_pokemons[5].species=21
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=1", "--method=same-stats" }, test_string, result_prefix ++
        \\.static_pokemons[0].species=2
        \\.static_pokemons[1].species=13
        \\.static_pokemons[2].species=0
        \\.static_pokemons[3].species=3
        \\.static_pokemons[4].species=4
        \\.static_pokemons[5].species=9
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=1", "--method=same-stats", "--types=same" }, test_string, result_prefix ++
        \\.static_pokemons[0].species=1
        \\.static_pokemons[1].species=3
        \\.static_pokemons[2].species=0
        \\.static_pokemons[3].species=1
        \\.static_pokemons[4].species=4
        \\.static_pokemons[5].species=18
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=2", "--method=simular-stats" }, test_string, result_prefix ++
        \\.static_pokemons[0].species=2
        \\.static_pokemons[1].species=11
        \\.static_pokemons[2].species=6
        \\.static_pokemons[3].species=13
        \\.static_pokemons[4].species=4
        \\.static_pokemons[5].species=18
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=2", "--method=simular-stats", "--types=same" }, test_string, result_prefix ++
        \\.static_pokemons[0].species=0
        \\.static_pokemons[1].species=1
        \\.static_pokemons[2].species=11
        \\.static_pokemons[3].species=3
        \\.static_pokemons[4].species=9
        \\.static_pokemons[5].species=18
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=3", "--method=legendary-with-legendary" }, test_string, result_prefix ++
        \\.static_pokemons[0].species=8
        \\.static_pokemons[1].species=0
        \\.static_pokemons[2].species=8
        \\.static_pokemons[3].species=3
        \\.static_pokemons[4].species=7
        \\.static_pokemons[5].species=15
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=4", "--method=legendary-with-legendary", "--types=same" }, test_string, result_prefix ++
        \\.static_pokemons[0].species=2
        \\.static_pokemons[1].species=2
        \\.static_pokemons[2].species=2
        \\.static_pokemons[3].species=3
        \\.static_pokemons[4].species=4
        \\.static_pokemons[5].species=15
        \\
    );
}
