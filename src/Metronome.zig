gpa: std.mem.Allocator,
arena: std.heap.ArenaAllocator,
random: std.Random,

species: SpeciesSet,
species_by: struct {
    ability: SpeciesByAbility,
    type: SpeciesByType,
    dual_type: SpeciesByDualType,
},
evolutions: Evolutions,

legendaries: SpeciesSet,
stats: MinMax(u16),

// `randomSpeciesWithSimilarTotalStats` uses metronome as a buffer that is reused between calls
similar: std.ArrayListUnmanaged(u16) = std.ArrayListUnmanaged(u16){},

// TODO: Document where used
intersection: Set = Set{},
pick_from_excluded: Set = Set{},

pub fn init(gpa: std.mem.Allocator, random: std.Random, game: anytype) !Metronome {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();

    const species_set = try validSpecies(arena.allocator(), game);
    var res: Metronome = .{
        .gpa = gpa,
        .arena = undefined,
        .random = random,

        .species = species_set,
        .species_by = .{
            .ability = try speciesByAbility(arena.allocator(), species_set, game),
            .type = try speciesByType(arena.allocator(), species_set, game),
            .dual_type = try speciesByDualType(arena.allocator(), species_set, game),
        },
        .evolutions = try findEvolutions(arena.allocator(), species_set, game),
        .legendaries = try findLegendaries(arena.allocator(), species_set, game),
        .stats = minMaxTotalStats(species_set, game),
    };
    res.arena = arena;
    return res;
}

pub fn deinit(metronome: *Metronome) void {
    metronome.arena.deinit();
}

/// Gets the set of all valid species in a pokemon game. This will exclude things like:
/// * species 0, which is always the "null" pokemon
/// * gen5 Pokéstar Studios pokemon
fn validSpecies(arena: std.mem.Allocator, game: anytype) !SpeciesSet {
    var valid_species = std.ArrayList(u16).init(arena);
    try game.validSpecies(&valid_species);

    var species_set = SpeciesSet{};
    try species_set.ensureTotalCapacity(arena, valid_species.items.len);
    for (valid_species.items) |species|
        species_set.putAssumeCapacity(species, {});

    return species_set;
}

/// Finds the minimum and maximum total stats species in the `species_set` has. In gen5, this is
/// 180 (Sunkern) and 720 (Arceus)
fn minMaxTotalStats(species_set: SpeciesSet, game: anytype) MinMax(u16) {
    const pokemons = try game.pokemons();
    var stats: MinMax(u16) = .{ .max = 0, .min = std.math.maxInt(u16) };

    for (species_set.keys()) |species| {
        const pokemon = pokemons.at(species) catch continue;
        const total_stats = pokemon.stats.total();
        stats.min = @min(stats.min, total_stats);
        stats.max = @max(stats.max, total_stats);
    }

    return stats;
}

test minMaxTotalStats {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);
    const species = try validSpecies(arena.allocator(), game);
    const minmax = minMaxTotalStats(species, game);
    try std.testing.expectEqual(@as(u16, 195), minmax.min);
    try std.testing.expectEqual(@as(u16, 680), minmax.max);
}

const Evolutions = struct {
    lowest_2_stage: SpeciesSet,
    lowest_3_stage: SpeciesSet,
    lowest: SpeciesSet,
};

fn findEvolutions(arena: std.mem.Allocator, species_set: SpeciesSet, game: anytype) !Evolutions {
    var res = Evolutions{
        .lowest_2_stage = .{},
        .lowest_3_stage = .{},
        .lowest = try species_set.clone(arena),
    };

    const pokemons_evolutions = try game.evolutions();
    for (species_set.keys()) |species| {
        const evolutions = pokemons_evolutions.at(species) catch continue;
        for (evolutions) |evolution| {
            if (evolution.method == .unused)
                continue;
            _ = res.lowest.swapRemove(evolution.target);
        }
    }

    for (res.lowest.keys()) |species| {
        switch (countEvolutions(species, species, game)) {
            1 => try res.lowest_2_stage.put(arena, species, {}),
            2 => try res.lowest_3_stage.put(arena, species, {}),
            else => {},
        }
    }

    return res;
}

test findEvolutions {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);
    const species = try validSpecies(arena.allocator(), game);
    const evolutions = try findEvolutions(arena.allocator(), species, game);

    try std.testing.expectEqualSlices(u16, &.{
        1,   151, 150, 4,   96,  81,  7,  147, 146, 10,  145, 144, 13,  143, 142, 16,  104, 140,
        19,  83,  21,  138, 23,  137, 25, 84,  27,  98,  29,  86,  133, 32,  132, 131, 35,  102,
        37,  129, 39,  128, 41,  127, 43, 126, 125, 46,  124, 48,  123, 50,  122, 52,  88,  54,
        120, 56,  95,  58,  118, 60,  90, 116, 63,  115, 114, 66,  113, 100, 69,  111, 92,  72,
        109, 74,  108, 107, 77,  106, 79,
    }, evolutions.lowest.keys());
    try std.testing.expectEqualSlices(u16, &.{
        96, 81, 104, 140, 19, 21, 138, 23, 25, 84,  27, 98,  86,  133, 35, 102, 37, 129, 39, 41,
        46, 48, 50,  52,  88, 54, 120, 56, 58, 118, 90, 116, 100, 111, 72, 109, 77, 79,
    }, evolutions.lowest_2_stage.keys());
    try std.testing.expectEqualSlices(u16, &.{
        1, 4, 7, 147, 10, 13, 16, 29, 32, 43, 60, 63, 66, 69, 92, 74,
    }, evolutions.lowest_3_stage.keys());
}

fn countEvolutions(species: u16, start_species: u16, game: anytype) usize {
    var res: usize = 0;

    const pokemons_evolutions = game.evolutions() catch return res;
    const evolutions = pokemons_evolutions.at(species) catch return res;
    for (evolutions) |evolution| {
        if (evolution.method == .unused)
            continue;
        if (start_species == evolution.target)
            continue;

        res = @max(res, 1 + countEvolutions(evolution.target, start_species, game));
    }

    return res;
}

test countEvolutions {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);
    try std.testing.expectEqual(@as(usize, 2), countEvolutions(1, 1, &game));
    try std.testing.expectEqual(@as(usize, 1), countEvolutions(2, 2, &game));
    try std.testing.expectEqual(@as(usize, 0), countEvolutions(3, 3, &game));
    try std.testing.expectEqual(@as(usize, 1), countEvolutions(21, 21, &game));
    try std.testing.expectEqual(@as(usize, 0), countEvolutions(22, 22, &game));
    try std.testing.expectEqual(@as(usize, 0), countEvolutions(150, 150, &game));
}

fn findLegendaries(arena: std.mem.Allocator, species_set: SpeciesSet, game: anytype) !SpeciesSet {
    // There is no way to specify in game that a Pokemon is a legendary. Instead we find
    // legendaries by looking at their stats, evolution line and other patterns common for
    // legendaries

    const pokemons = try game.pokemons();
    const pokemon_evolutions = try game.evolutions();

    var is_evolution = SpeciesSet{};
    for (species_set.keys()) |species| {
        const evolutions = pokemon_evolutions.at(species) catch continue;
        for (evolutions) |evo| {
            if (evo.method == .unused) continue;
            try is_evolution.put(arena, evo.target, {});
        }
    }

    // First, lets give each Pokemon a "legendary rating" which is a measure as to how many
    // "legendary" criteria this pokemon fits into. This rating can be negative.
    var ratings = std.AutoArrayHashMap(u16, isize).init(arena);
    try ratings.ensureTotalCapacity(species_set.count());

    for (species_set.keys()) |species| {
        const pokemon = pokemons.at(species) catch continue;
        const rating = (ratings.getOrPutAssumeCapacity(species)).value_ptr;
        rating.* = 0;

        // Legendaries are generally in the "slow" to "medium_slow" growth rating
        rating.* += @as(isize, @intFromBool(pokemon.growth_rate == .slow or
            pokemon.growth_rate == .medium_slow));

        // They generally have a catch rate of 45 or less
        rating.* += @as(isize, @intFromBool(pokemon.catch_rate <= 45));

        // They tend to not have a gender (255 in gender_ratio means genderless).
        rating.* += @as(isize, @intFromBool(pokemon.gender_ratio == 255));

        // Most are part of the "undiscovered" egg group
        for (pokemon.egg_groups) |egg_group|
            rating.* += @as(isize, @intFromBool(egg_group == .undiscovered));

        // They don't evolve from anything. Subtract score from metronome Pokemons evolutions.
        rating.* -= @as(isize, @intFromBool(is_evolution.get(species) != null)) * 10;
    }

    const rating_to_be_legendary = blk: {
        var res: isize = 0;
        for (ratings.values()) |rating|
            res = @max(res, rating);

        // Not all legendaries match all criteria. Let's allow for legendaries that miss on
        // criteria.
        break :blk res - 1;
    };

    var res = SpeciesSet{};
    for (ratings.keys(), ratings.values()) |species, rating| {
        if (rating < rating_to_be_legendary)
            continue;
        _ = try res.put(arena, species, {});
    }

    return res;
}

test findLegendaries {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);
    const species = try validSpecies(arena.allocator(), game);
    const legendaries = try findLegendaries(arena.allocator(), species, game);

    try std.testing.expectEqualSlices(u16, &.{
        144, 145, 146,
        150, 151,
    }, legendaries.keys());
}

fn speciesByType(arena: std.mem.Allocator, species_set: SpeciesSet, game: anytype) !SpeciesByType {
    const pokemons = try game.pokemons();
    var species_by_type = SpeciesByType{};
    for (species_set.keys()) |species| {
        const pokemon = try pokemons.at(species);

        for (pokemon.types) |t| {
            const entry = try species_by_type.getOrPutValue(arena, t, .{});
            try entry.value_ptr.put(arena, species, {});
        }
    }

    return species_by_type;
}

test speciesByType {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);
    const species = try validSpecies(arena.allocator(), game);
    const species_by_type = try speciesByType(arena.allocator(), species, game);

    try std.testing.expectEqual(@as(usize, 16), species_by_type.count());
    try std.testing.expectEqualSlices(u16, &.{ // Normal
        16,  17,  18,  19, 20, 21, 22, 35, 36, 39, 40, 52, 53, 83, 84, 85, 108, 113, 115, 128, 132,
        133, 137, 143,
    }, species_by_type.get(0).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Fighting
        56, 57, 62, 66, 67, 68, 106, 107,
    }, species_by_type.get(1).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Flying
        6, 12, 16, 17, 18, 21, 22, 41, 42, 83, 84, 85, 123, 130, 142, 144, 145, 146, 149,
    }, species_by_type.get(2).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Poison
        1,  2,  3,  13, 14, 15, 23, 24, 29, 30,  31,  32, 33, 34, 41, 42, 43, 44, 45, 48, 49, 69,
        70, 71, 72, 73, 88, 89, 92, 93, 94, 109, 110,
    }, species_by_type.get(3).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Ground
        27, 28, 31, 34, 50, 51, 74, 75, 76, 95, 104, 105, 111, 112,
    }, species_by_type.get(4).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Rock
        74, 75, 76, 95, 111, 112, 138, 139, 140, 141, 142,
    }, species_by_type.get(5).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Bug
        10, 11, 12, 13, 14, 15, 46, 47, 48, 49, 123, 127,
    }, species_by_type.get(6).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Ghost
        92, 93, 94,
    }, species_by_type.get(7).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Steel
        81, 82,
    }, species_by_type.get(8).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Fire
        4, 5, 6, 37, 38, 58, 59, 77, 78, 126, 136, 146,
    }, species_by_type.get(9).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Water
        7,   8,   9,   54,  55,  60,  61,  62,  72,  73,  79,  80,  86, 87, 90, 91, 98, 99, 116, 117,
        118, 119, 120, 121, 129, 130, 131, 134, 138, 139, 140, 141,
    }, species_by_type.get(10).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Grass
        1, 2, 3, 43, 44, 45, 46, 47, 69, 70, 71, 102, 103, 114,
    }, species_by_type.get(11).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Electric
        25, 26, 81, 82, 100, 101, 125, 135, 145,
    }, species_by_type.get(12).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Psychic
        63, 64, 65, 79, 80, 96, 97, 102, 103, 121, 122, 124, 150, 151,
    }, species_by_type.get(13).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Ice
        87, 91, 124, 131, 144,
    }, species_by_type.get(14).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Dragon
        147, 148, 149,
    }, species_by_type.get(15).?.keys());
}

fn speciesByDualType(arena: std.mem.Allocator, species_set: SpeciesSet, game: anytype) !SpeciesByDualType {
    const pokemons = try game.pokemons();
    var species_by_dual_type = SpeciesByDualType{};
    for (species_set.keys()) |species| {
        const pokemon = try pokemons.at(species);
        const entry = try species_by_dual_type.getOrPutValue(arena, .{
            @min(pokemon.types[0], pokemon.types[1]),
            @max(pokemon.types[0], pokemon.types[1]),
        }, .{});
        try entry.value_ptr.put(arena, species, {});
    }

    return species_by_dual_type;
}

test speciesByDualType {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);
    const species = try validSpecies(arena.allocator(), game);
    const species_by_dual_type = try speciesByDualType(arena.allocator(), species, game);

    try std.testing.expectEqual(@as(usize, 34), species_by_dual_type.count());
    try std.testing.expectEqualSlices(u16, &.{ // Normal, Normal
        19, 20, 35, 36, 39, 40, 52, 53, 108, 113, 115, 128, 132, 133, 137, 143,
    }, species_by_dual_type.get(.{ 0, 0 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Normal, Flying
        16, 17, 18, 21, 22, 83, 84, 85,
    }, species_by_dual_type.get(.{ 0, 2 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Fighting, Fighting
        56, 57, 66, 67, 68, 106, 107,
    }, species_by_dual_type.get(.{ 1, 1 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Fighting, Water
        62,
    }, species_by_dual_type.get(.{ 1, 10 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Flying, Poison
        41, 42,
    }, species_by_dual_type.get(.{ 2, 3 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Flying, Rock
        142,
    }, species_by_dual_type.get(.{ 2, 5 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Flying, Bug
        12, 123,
    }, species_by_dual_type.get(.{ 2, 6 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Flying, Fire
        6, 146,
    }, species_by_dual_type.get(.{ 2, 9 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Flying, Water
        130,
    }, species_by_dual_type.get(.{ 2, 10 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Flying, Electric
        145,
    }, species_by_dual_type.get(.{ 2, 12 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Flying, Ice
        144,
    }, species_by_dual_type.get(.{ 2, 14 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Flying, Dragon
        149,
    }, species_by_dual_type.get(.{ 2, 15 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Poison, Poison
        23, 24, 29, 30, 32, 33, 88, 89, 109, 110,
    }, species_by_dual_type.get(.{ 3, 3 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Poison, Ground
        31, 34,
    }, species_by_dual_type.get(.{ 3, 4 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Poison, Bug
        13, 14, 15, 48, 49,
    }, species_by_dual_type.get(.{ 3, 6 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Poison, Ghost
        92, 93, 94,
    }, species_by_dual_type.get(.{ 3, 7 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Poison, Water
        72, 73,
    }, species_by_dual_type.get(.{ 3, 10 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Poison, Grass
        1, 2, 3, 43, 44, 45, 69, 70, 71,
    }, species_by_dual_type.get(.{ 3, 11 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Ground, Ground
        27, 28, 50, 51, 104, 105,
    }, species_by_dual_type.get(.{ 4, 4 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Ground, Rock
        74, 75, 76, 95, 111, 112,
    }, species_by_dual_type.get(.{ 4, 5 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Rock, Water
        138, 139, 140, 141,
    }, species_by_dual_type.get(.{ 5, 10 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Bug, Bug
        10, 11, 127,
    }, species_by_dual_type.get(.{ 6, 6 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Bug, Grass
        46, 47,
    }, species_by_dual_type.get(.{ 6, 11 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Steel, Eletric
        81, 82,
    }, species_by_dual_type.get(.{ 8, 12 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Fire, Fire
        4, 5, 37, 38, 58, 59, 77, 78, 126, 136,
    }, species_by_dual_type.get(.{ 9, 9 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Water, Water
        7, 8, 9, 54, 55, 60, 61, 86, 90, 98, 99, 116, 117, 118, 119, 120, 129, 134,
    }, species_by_dual_type.get(.{ 10, 10 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Water, Psychic
        79, 80, 121,
    }, species_by_dual_type.get(.{ 10, 13 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Water, Ice
        87, 91, 131,
    }, species_by_dual_type.get(.{ 10, 14 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Grass, Grass
        114,
    }, species_by_dual_type.get(.{ 11, 11 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Grass, Psychic
        102, 103,
    }, species_by_dual_type.get(.{ 11, 13 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Electric, Electric
        25, 26, 100, 101, 125, 135,
    }, species_by_dual_type.get(.{ 12, 12 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Psychic, Psychic
        63, 64, 65, 96, 97, 122, 150, 151,
    }, species_by_dual_type.get(.{ 13, 13 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Psychic, Ice
        124,
    }, species_by_dual_type.get(.{ 13, 14 }).?.keys());
    try std.testing.expectEqualSlices(u16, &.{ // Dragon, Dragon
        147, 148,
    }, species_by_dual_type.get(.{ 15, 15 }).?.keys());
}

fn speciesByAbility(arena: std.mem.Allocator, species_set: SpeciesSet, game: anytype) !SpeciesByAbility {
    const pokemons = try game.pokemons();
    var species_by_ability = SpeciesByAbility{};
    for (species_set.keys()) |species| {
        const pokemon = try pokemons.at(species);

        for (pokemon.abilities) |t| {
            const entry = try species_by_ability.getOrPutValue(arena, t, .{});
            try entry.value_ptr.put(arena, species, {});
        }
    }

    return species_by_ability;
}

test speciesByAbility {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);
    const species = try validSpecies(arena.allocator(), game);
    const species_by_ability = try speciesByAbility(arena.allocator(), species, game);
    _ = species_by_ability; // TODO

    // try std.testing.expectEqualSlices(u16, &.{
    //     144, 145, 146,
    //     150, 151,
    // }, legendaries.keys());
}

pub const RandomizeTrainerOptions = packed struct {
    seed: u64 = 0,
    party_size_max: u3 = 6,
    party_size_min: u3 = 1,
    // moves: Move = .unchanged, TODO
    // held_items: HeldItem = .unchanged, TODO
    abilities: AbilityTheme = .random,
    types: TypeTheme = .random,
    stats: Stats = .random,
    party_size: PartySize = .unchanged,
    party_pokemons: PartyPokemons = .unchanged,
    avoid_same: bool = false,

    const Move = enum(u3) {
        none,
        unchanged,
        best,
        best_for_level,
        random_learnable,
        random,
    };

    const HeldItem = enum(u2) {
        none,
        unchanged,
        random,
    };

    const AbilityTheme = enum(u2) {
        same,
        random,
        themed,
    };

    const TypeTheme = enum(u2) {
        same,
        random,
        themed,
        dual_themed,
    };

    const Stats = enum(u2) {
        random,
        similar,
        follow_level,
    };

    const PartySize = enum(u2) {
        unchanged,
        minimum,
        follow_level,
        random,
    };

    const PartyPokemons = enum(u1) {
        unchanged,
        randomize,
    };
};

pub fn randomizeTrainers(metronome: *Metronome, options: RandomizeTrainerOptions, game: anytype) !void {
    if (metronome.species.count() == 0)
        return;

    const parties = try game.trainerParties();

    var i: usize = 0;
    while (i < parties.len()) : (i += 1) {
        const party = parties.at(i) catch continue;
        if (party.size == 0)
            continue;

        try metronome.randomizeParty(options, game, party);
    }
}

test randomizeTrainers {
    try testCommand(0, RandomizeTrainerOptions{}, randomizeTrainers, core.dummy.default, core.dummy.default);
    try testCommand(0, RandomizeTrainerOptions{
        .party_pokemons = .randomize,
    }, randomizeTrainers, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 50 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 58 } },
                .{ .base = .{ .level = 8, .species = 55 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 2 } },
                .{ .base = .{ .level = 15, .species = 75 } },
                .{ .base = .{ .level = 15, .species = 4 } },
                .{ .base = .{ .level = 17, .species = 130 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 128 } },
                .{ .base = .{ .level = 16, .species = 45 } },
                .{ .base = .{ .level = 18, .species = 12 } },
                .{ .base = .{ .level = 20, .species = 48 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 10 } },
                .{ .base = .{ .level = 23, .species = 16 } },
                .{ .base = .{ .level = 22, .species = 15 } },
                .{ .base = .{ .level = 20, .species = 10 } },
                .{ .base = .{ .level = 25, .species = 61 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 95 } },
                .{ .base = .{ .level = 38, .species = 18 } },
                .{ .base = .{ .level = 35, .species = 50 } },
                .{ .base = .{ .level = 35, .species = 61 } },
                .{ .base = .{ .level = 40, .species = 42 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 20 } },
                .{ .base = .{ .level = 45, .species = 7 } },
                .{ .base = .{ .level = 45, .species = 42 } },
                .{ .base = .{ .level = 47, .species = 66 } },
                .{ .base = .{ .level = 50, .species = 58 } },
                .{ .base = .{ .level = 53, .species = 21 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 98 } },
                .{ .base = .{ .level = 59, .species = 138 } },
                .{ .base = .{ .level = 61, .species = 7 } },
                .{ .base = .{ .level = 61, .species = 38 } },
                .{ .base = .{ .level = 63, .species = 59 } },
                .{ .base = .{ .level = 65, .species = 54 } },
            }),
        };
        break :blk res;
    });
    try testCommand(0, RandomizeTrainerOptions{
        .party_size_min = 1,
        .party_size_max = 1,
    }, randomizeTrainers, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 16 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 18 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 18 } },
            }),
        };
        break :blk res;
    });
    try testCommand(0, RandomizeTrainerOptions{
        .party_size_min = 6,
        .party_size_max = 6,
    }, randomizeTrainers, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 16 } },
                .{ .base = .{ .level = 8, .species = 1 } },
                .{ .base = .{ .level = 9, .species = 16 } },
                .{ .base = .{ .level = 8, .species = 1 } },
                .{ .base = .{ .level = 9, .species = 16 } },
                .{ .base = .{ .level = 8, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 63 } },
                .{ .base = .{ .level = 15, .species = 19 } },
                .{ .base = .{ .level = 17, .species = 1 } },
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 63 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 17 } },
                .{ .base = .{ .level = 16, .species = 20 } },
                .{ .base = .{ .level = 18, .species = 64 } },
                .{ .base = .{ .level = 20, .species = 2 } },
                .{ .base = .{ .level = 19, .species = 17 } },
                .{ .base = .{ .level = 16, .species = 20 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 17 } },
                .{ .base = .{ .level = 23, .species = 130 } },
                .{ .base = .{ .level = 22, .species = 58 } },
                .{ .base = .{ .level = 20, .species = 64 } },
                .{ .base = .{ .level = 25, .species = 2 } },
                .{ .base = .{ .level = 25, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 18 } },
                .{ .base = .{ .level = 38, .species = 130 } },
                .{ .base = .{ .level = 35, .species = 58 } },
                .{ .base = .{ .level = 35, .species = 65 } },
                .{ .base = .{ .level = 40, .species = 3 } },
                .{ .base = .{ .level = 37, .species = 18 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
                .{ .base = .{ .level = 45, .species = 111 } },
                .{ .base = .{ .level = 45, .species = 130 } },
                .{ .base = .{ .level = 47, .species = 58 } },
                .{ .base = .{ .level = 50, .species = 65 } },
                .{ .base = .{ .level = 53, .species = 3 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 18 } },
                .{ .base = .{ .level = 59, .species = 65 } },
                .{ .base = .{ .level = 61, .species = 112 } },
                .{ .base = .{ .level = 61, .species = 130 } },
                .{ .base = .{ .level = 63, .species = 59 } },
                .{ .base = .{ .level = 65, .species = 3 } },
            }),
        };
        break :blk res;
    });
    try testCommand(0, RandomizeTrainerOptions{
        .party_size_min = 1,
        .party_size_max = 6,
        .party_size = .random,
    }, randomizeTrainers, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 16 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 63 } },
                .{ .base = .{ .level = 15, .species = 19 } },
                .{ .base = .{ .level = 17, .species = 1 } },
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 63 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 17 } },
                .{ .base = .{ .level = 23, .species = 130 } },
                .{ .base = .{ .level = 22, .species = 58 } },
                .{ .base = .{ .level = 20, .species = 64 } },
                .{ .base = .{ .level = 25, .species = 2 } },
                .{ .base = .{ .level = 25, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 18 } },
                .{ .base = .{ .level = 38, .species = 130 } },
                .{ .base = .{ .level = 35, .species = 58 } },
                .{ .base = .{ .level = 35, .species = 65 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
                .{ .base = .{ .level = 45, .species = 111 } },
                .{ .base = .{ .level = 45, .species = 130 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 18 } },
                .{ .base = .{ .level = 59, .species = 65 } },
                .{ .base = .{ .level = 61, .species = 112 } },
            }),
        };
        break :blk res;
    });
    try testCommand(0, RandomizeTrainerOptions{
        .party_size_min = 1,
        .party_size_max = 6,
        .party_size = .follow_level,
    }, randomizeTrainers, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 16 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 63 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 17 } },
                .{ .base = .{ .level = 16, .species = 20 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 17 } },
                .{ .base = .{ .level = 23, .species = 130 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 18 } },
                .{ .base = .{ .level = 38, .species = 130 } },
                .{ .base = .{ .level = 35, .species = 58 } },
                .{ .base = .{ .level = 35, .species = 65 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
                .{ .base = .{ .level = 45, .species = 111 } },
                .{ .base = .{ .level = 45, .species = 130 } },
                .{ .base = .{ .level = 47, .species = 58 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 18 } },
                .{ .base = .{ .level = 59, .species = 65 } },
                .{ .base = .{ .level = 61, .species = 112 } },
                .{ .base = .{ .level = 61, .species = 130 } },
                .{ .base = .{ .level = 63, .species = 59 } },
                .{ .base = .{ .level = 65, .species = 3 } },
            }),
        };
        break :blk res;
    });
    try testCommand(0, RandomizeTrainerOptions{
        .party_pokemons = .randomize,
        .stats = .similar,
    }, randomizeTrainers, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 21 } },
                .{ .base = .{ .level = 8, .species = 4 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 43 } },
                .{ .base = .{ .level = 15, .species = 16 } },
                .{ .base = .{ .level = 17, .species = 102 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 100 } },
                .{ .base = .{ .level = 16, .species = 51 } },
                .{ .base = .{ .level = 18, .species = 44 } },
                .{ .base = .{ .level = 20, .species = 8 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 83 } },
                .{ .base = .{ .level = 23, .species = 6 } },
                .{ .base = .{ .level = 22, .species = 83 } },
                .{ .base = .{ .level = 20, .species = 8 } },
                .{ .base = .{ .level = 25, .species = 47 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 71 } },
                .{ .base = .{ .level = 38, .species = 6 } },
                .{ .base = .{ .level = 35, .species = 83 } },
                .{ .base = .{ .level = 35, .species = 34 } },
                .{ .base = .{ .level = 40, .species = 6 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
                .{ .base = .{ .level = 45, .species = 58 } },
                .{ .base = .{ .level = 45, .species = 3 } },
                .{ .base = .{ .level = 47, .species = 111 } },
                .{ .base = .{ .level = 50, .species = 31 } },
                .{ .base = .{ .level = 53, .species = 121 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 82 } },
                .{ .base = .{ .level = 59, .species = 127 } },
                .{ .base = .{ .level = 61, .species = 65 } },
                .{ .base = .{ .level = 61, .species = 3 } },
                .{ .base = .{ .level = 63, .species = 130 } },
                .{ .base = .{ .level = 65, .species = 73 } },
            }),
        };
        break :blk res;
    });
    try testCommand(0, RandomizeTrainerOptions{
        .party_pokemons = .randomize,
        .stats = .similar,
        .avoid_same = true,
    }, randomizeTrainers, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 21 } },
                .{ .base = .{ .level = 8, .species = 4 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 43 } },
                .{ .base = .{ .level = 15, .species = 16 } },
                .{ .base = .{ .level = 17, .species = 102 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 100 } },
                .{ .base = .{ .level = 16, .species = 51 } },
                .{ .base = .{ .level = 18, .species = 8 } },
                .{ .base = .{ .level = 20, .species = 20 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 83 } },
                .{ .base = .{ .level = 23, .species = 6 } },
                .{ .base = .{ .level = 22, .species = 138 } },
                .{ .base = .{ .level = 20, .species = 8 } },
                .{ .base = .{ .level = 25, .species = 51 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 71 } },
                .{ .base = .{ .level = 38, .species = 6 } },
                .{ .base = .{ .level = 35, .species = 83 } },
                .{ .base = .{ .level = 35, .species = 34 } },
                .{ .base = .{ .level = 40, .species = 3 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
                .{ .base = .{ .level = 45, .species = 58 } },
                .{ .base = .{ .level = 45, .species = 3 } },
                .{ .base = .{ .level = 47, .species = 33 } },
                .{ .base = .{ .level = 50, .species = 31 } },
                .{ .base = .{ .level = 53, .species = 134 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 82 } },
                .{ .base = .{ .level = 59, .species = 127 } },
                .{ .base = .{ .level = 61, .species = 65 } },
                .{ .base = .{ .level = 61, .species = 3 } },
                .{ .base = .{ .level = 63, .species = 130 } },
                .{ .base = .{ .level = 65, .species = 91 } },
            }),
        };
        break :blk res;
    });
}

fn randomizeParty(metronome: *Metronome, options: RandomizeTrainerOptions, game: anytype, party: anytype) !void {
    const themes = TrainerTheme{
        .types = switch (options.types) {
            .themed => blk: {
                const types = metronome.species_by.type.keys();
                const t = metronome.randomItem(types).?.*;
                break :blk [_]u8{ t, t };
            },
            .dual_themed => blk: {
                const types = metronome.species_by.dual_type.keys();
                break :blk metronome.randomItem(types).?.*;
            },
            else => null,
        },
        .ability = switch (options.abilities) {
            .themed => blk: {
                const abilities = metronome.species_by.ability.keys();
                break :blk metronome.randomItem(abilities).?.*;
            },
            else => null,
        },
    };

    // const wants_moves = switch (options.moves) { TODO
    //     .unchanged => party.type.haveMoves(),
    //     .none => false,
    //     .best,
    //     .best_for_level,
    //     .random_learnable,
    //     .random,
    //     => true,
    // };
    // const wants_items = switch (options.held_items) { TODO
    //     .unchanged => party.type.haveItem(),
    //     .random => true,
    //     .none => false,
    // };

    const average_level = averagePartyLevel(party);
    const old_party_size = party.size;
    party.size = switch (options.party_size) {
        .unchanged => std.math.clamp(
            party.size,
            options.party_size_min,
            options.party_size_max,
        ),
        .random => metronome.random.intRangeAtMost(
            u8,
            options.party_size_min,
            options.party_size_max,
        ),
        .follow_level => partySizeLevelScaling(
            options.party_size_min,
            options.party_size_max,
            average_level,
        ),
        .minimum => options.party_size_min,
    };
    // party.type = switch (wants_moves) { TODO
    //     true => switch (wants_items) {
    //         true => .both,
    //         false => .moves,
    //     },
    //     false => switch (wants_items) {
    //         true => .item,
    //         false => .none,
    //     },
    // };

    // Fill trainer party with more Pokémons. The Pokémons we fill the party with are Pokémons that
    // are already in the party.
    if (old_party_size != 0) for (0..party.size) |to| {
        const from = to % old_party_size;
        party.members[to] = party.members[from];
    };
    @memset(party.members[party.size..], .{});

    const members = party.members[0..party.size];
    for (members, 0..) |*member, member_i| {
        switch (options.party_pokemons) {
            .randomize => try metronome.randomizePartyMember(
                options,
                themes,
                game,
                party.members[0..member_i],
                member,
            ),
            .unchanged => {},
        }
        // TODO:
        // switch (options.held_items) {
        //     .unchanged => {},
        //     .none0, .none1 => member.item = 0,
        //     .random => {}, // TODO
        // }
        // switch (options.moves) {
        //     .none0, .none1, .none2, .unchanged => {},
        //     .best, .best_for_level => {},
        //     .random_learnable => {},
        //     .random => {},
        // }
    }
}

const TrainerTheme = struct {
    types: ?[2]u8,
    ability: ?u16,
};

fn randomizePartyMember(
    metronome: *Metronome,
    options: RandomizeTrainerOptions,
    themes: TrainerTheme,
    game: anytype,
    other_members: anytype,
    member: anytype,
) !void {
    const pokemons = try game.pokemons();
    const pick_from_type = switch (options.types) {
        .same => blk: {
            const pokemon = pokemons.at(member.base.species) catch break :blk metronome.species;
            break :blk metronome.species_by.type.get(pokemon.types[0]).?;
        },
        .themed => metronome.species_by.type.get(themes.types.?[0]).?,
        .dual_themed => metronome.species_by.dual_type.get(themes.types.?).?,
        .random => Set{},
    };

    var new_ability: ?u16 = null;
    const pick_from_ability = switch (options.abilities) {
        .same => blk: {
            const pokemon = pokemons.at(member.base.species) catch break :blk metronome.species;
            const ability = pokemon.abilities[member.ability()];
            if (ability == 0)
                break :blk metronome.species;

            new_ability = ability;
            break :blk metronome.species_by.ability.get(ability).?;
        },
        .themed => blk: {
            new_ability = themes.ability;
            break :blk metronome.species_by.ability.get(themes.ability.?).?;
        },
        .random => Set{},
    };

    if (options.abilities != .random and options.types != .random) {
        // The intersection between the type_set and ability_set will give
        // us all pokémons that have a certain type+ability pair. This is
        // the set we will pick from.
        var intersection = metronome.intersection.promote(metronome.arena.allocator());
        intersection.clearRetainingCapacity();

        try util.set.intersectInline(&intersection, pick_from_ability, pick_from_type);
        metronome.intersection = intersection.unmanaged;
    }

    // Pick the first set that has items in it.
    var pick_from = if (metronome.intersection.count() != 0)
        metronome.intersection
    else if (pick_from_ability.count() != 0)
        pick_from_ability
    else if (pick_from_type.count() != 0)
        pick_from_type
    else
        metronome.species;

    if (options.avoid_same) {
        // Now, we have to exclude party members already in the party. To do this we construct a
        // new set from `pick_from` with `other_party_members` excluded.
        metronome.pick_from_excluded.clearRetainingCapacity();
        try metronome.pick_from_excluded.ensureTotalCapacity(metronome.arena.allocator(), pick_from.count());

        for (pick_from.keys()) |picked|
            metronome.pick_from_excluded.putAssumeCapacity(picked, {});
        for (other_members) |other_member|
            _ = metronome.pick_from_excluded.swapRemove(other_member.base.species);

        // If we end up with 0 things to pick from, then we cannot avoid same. So only use our
        // newly created set, if it actually has things to pick from.
        if (metronome.pick_from_excluded.count() != 0)
            pick_from = metronome.pick_from_excluded;
    }

    // When we have picked a new species for our Pokémon we also need
    // to fix the ability the Pokémon have, if we're picking Pokémons
    // based on ability.
    defer if (new_ability) |ability_to_find| {
        // A valid species should have been picked, so this should never fail
        const pokemon = pokemons.at(member.base.species) catch unreachable;

        // Find the index of the ability we want the party member to
        // have. If we don't find the ability. The best we can do is
        // just let the Pokémon keep the ability it already has.
        for (pokemon.abilities, 0..) |ability, ability_i| {
            if (ability == ability_to_find) {
                member.setAbility(@intCast(ability_i));
                break;
            }
        }
    };

    member.base.species = switch (options.stats) {
        .follow_level => try metronome.randomSpeciesWithStatsFollowingLevel(
            game,
            pick_from,
            member.base.level,
        ),
        .similar => if (pokemons.at(member.base.species)) |pokemon|
            try metronome.randomSpeciesWithSimilarTotalStats(
                game,
                pick_from,
                pokemon.stats.total(),
            )
        else |_|
            metronome.randomItem(pick_from.keys()).?.*,
        .random => metronome.randomItem(pick_from.keys()).?.*,
    };
}

pub const RandomizeStartersOptions = packed struct {
    seed: u64 = 0,
    starters: Starters = .unchanged,
    avoid_same: bool = false,

    const Starters = enum(u3) {
        unchanged,
        random,
        random_lowest_2_stage_evolution,
        random_lowest_3_stage_evolution,
        random_lowest_evolution,
    };
};

fn randomizeStarters(metronome: *Metronome, options: RandomizeStartersOptions, game: anytype) !void {
    const pick_from_base = switch (options.starters) {
        .random => metronome.species,
        .random_lowest_2_stage_evolution => metronome.evolutions.lowest_2_stage,
        .random_lowest_3_stage_evolution => metronome.evolutions.lowest_3_stage,
        .random_lowest_evolution => metronome.evolutions.lowest,
        .unchanged => return,
    };
    if (pick_from_base.count() == 0)
        return error.NoStarterToPick;

    var pick_from = try pick_from_base.clone(metronome.gpa);
    defer pick_from.deinit(metronome.gpa);

    for (game.starters()) |*starter| {
        var pick_from_non_empty = pick_from;
        if (pick_from_non_empty.count() == 0)
            pick_from_non_empty = pick_from_base;

        starter.* = metronome.randomItem(pick_from_non_empty.keys()).?.*;
        if (options.avoid_same)
            _ = pick_from.swapRemove(starter.*);
    }
}

test randomizeStarters {
    try testCommand(0, RandomizeStartersOptions{}, randomizeStarters, core.dummy.default, core.dummy.default);
    try testCommand(0, RandomizeStartersOptions{
        .starters = .random,
    }, randomizeStarters, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.starters = &.{ 50, 58, 55 };
        break :blk res;
    });
    try testCommand(0, RandomizeStartersOptions{
        .starters = .random_lowest_2_stage_evolution,
    }, randomizeStarters, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.starters = &.{ 86, 35, 133 };
        break :blk res;
    });
    try testCommand(0, RandomizeStartersOptions{
        .starters = .random_lowest_3_stage_evolution,
    }, randomizeStarters, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.starters = &.{ 13, 16, 13 };
        break :blk res;
    });
    try testCommand(0, RandomizeStartersOptions{
        .starters = .random_lowest_3_stage_evolution,
        .avoid_same = true,
    }, randomizeStarters, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.starters = &.{ 13, 74, 92 };
        break :blk res;
    });
    try testCommand(0, RandomizeStartersOptions{
        .starters = .random_lowest_evolution,
    }, randomizeStarters, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.starters = &.{ 84, 133, 29 };
        break :blk res;
    });
}

fn randomItem(metronome: Metronome, items: anytype) ?@TypeOf(&items[0]) {
    if (items.len == 0)
        return null;
    return &items[metronome.random.uintAtMost(usize, items.len - 1)];
}

fn randomSpeciesWithSimilarTotalStats(metronome: *Metronome, game: anytype, pick_from: SpeciesSet, total_stats: u16) !u16 {
    const pokemons = try game.pokemons();
    const range = 5;
    var min = @as(isize, @intCast(total_stats)) - range;
    var max = min + range * 2;

    metronome.similar.shrinkRetainingCapacity(0);
    while (metronome.similar.items.len < 25) : ({
        min -= range;
        max += range;
    }) {
        try metronome.similar.ensureUnusedCapacity(metronome.arena.allocator(), pick_from.count());
        for (pick_from.keys()) |s| {
            const p = pokemons.at(s) catch continue;
            const total: isize = @intCast(p.stats.total());
            if (min <= total and total <= max)
                metronome.similar.appendAssumeCapacity(s);
        }
    }

    return metronome.randomItem(metronome.similar.items).?.*;
}

fn randomSpeciesWithStatsFollowingLevel(metronome: *Metronome, game: anytype, pick_from: SpeciesSet, level: u16) !u16 {
    return metronome.randomSpeciesWithSimilarTotalStats(
        game,
        pick_from,
        totalStatsLevelScaling(metronome.stats.min, metronome.stats.max, level),
    );
}

fn averagePartyLevel(party: anytype) u8 {
    if (party.size == 0)
        return 2;

    var sum: u16 = 0;
    for (party.members[0..party.size]) |member|
        sum += member.base.level;
    return @intCast(sum / party.size);
}

fn totalStatsLevelScaling(min: u16, max: u16, level: u16) u16 {
    const fmin: f64 = @floatFromInt(min);
    const fmax: f64 = @floatFromInt(max);
    const diff = fmax - fmin;
    const x: f64 = @floatFromInt(level);

    // Function adapted from -0.0001 * x^2 + 0.02 * x
    // This functions grows fast at the start, getting 75% to max stats at level 50.
    const a = -0.0001 * diff;
    const b = 0.02 * diff;
    const xp2 = std.math.pow(f64, x, 2);
    const res = a * xp2 + b * x + fmin;
    return @intFromFloat(res);
}

test totalStatsLevelScaling {
    try std.testing.expectEqual(@as(u16, 180), totalStatsLevelScaling(180, 720, 0));
    try std.testing.expectEqual(@as(u16, 282), totalStatsLevelScaling(180, 720, 10));
    try std.testing.expectEqual(@as(u16, 374), totalStatsLevelScaling(180, 720, 20));
    try std.testing.expectEqual(@as(u16, 455), totalStatsLevelScaling(180, 720, 30));
    try std.testing.expectEqual(@as(u16, 525), totalStatsLevelScaling(180, 720, 40));
    try std.testing.expectEqual(@as(u16, 585), totalStatsLevelScaling(180, 720, 50));
    try std.testing.expectEqual(@as(u16, 633), totalStatsLevelScaling(180, 720, 60));
    try std.testing.expectEqual(@as(u16, 671), totalStatsLevelScaling(180, 720, 70));
    try std.testing.expectEqual(@as(u16, 698), totalStatsLevelScaling(180, 720, 80));
    try std.testing.expectEqual(@as(u16, 714), totalStatsLevelScaling(180, 720, 90));
    try std.testing.expectEqual(@as(u16, 720), totalStatsLevelScaling(180, 720, 100));
}

fn partySizeLevelScaling(min: u8, max: u8, level: u16) u8 {
    std.debug.assert(min <= max);
    std.debug.assert(1 <= min and min <= 6);
    std.debug.assert(1 <= max and max <= 6);

    const max_party_size_level = 60;
    const steps = max - min;
    if (steps == 0)
        return max;

    const level_steps = max_party_size_level / steps;
    const res = level / level_steps;
    return @intCast(std.math.clamp(min + res, min, max));
}

test partySizeLevelScaling {
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 6, 0));
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 6, 5));
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 6, 10));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 6, 15));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 6, 20));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 6, 25));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 6, 30));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 6, 35));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 6, 40));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 6, 45));
    try std.testing.expectEqual(@as(u16, 5), partySizeLevelScaling(1, 6, 50));
    try std.testing.expectEqual(@as(u16, 5), partySizeLevelScaling(1, 6, 55));
    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(1, 6, 60));
    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(1, 6, 70));
    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(1, 6, 80));
    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(1, 6, 90));
    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(1, 6, 100));

    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 4, 0));
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 4, 5));
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 4, 10));
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 4, 15));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 4, 20));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 4, 25));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 4, 30));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 4, 35));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 4, 40));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 4, 45));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 4, 50));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 4, 55));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 4, 60));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 4, 70));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 4, 80));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 4, 90));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 4, 100));

    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(6, 6, 100));
}

fn testCommand(seed: u64, options: anytype, function: anytype, from: core.dummy.Game.Init, to: core.dummy.Game.Init) !void {
    var random = std.Random.DefaultPrng.init(seed);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const from_game = try core.dummy.Game.init(arena, from);
    const to_game = try core.dummy.Game.init(arena, to);

    var metronome = try init(std.testing.allocator, random.random(), from_game);
    defer metronome.deinit();

    try function(&metronome, options, from_game);

    // Avoid large error trace by not using `catch` or `try` here
    const is_err = if (std.testing.expectEqualDeep(to_game.m, from_game.m)) false else |_| true;
    if (is_err) {
        const from_str = try std.fmt.allocPrint(arena, "{}", .{from_game});
        const to_str = try std.fmt.allocPrint(arena, "{}", .{to_game});
        try std.fs.cwd().writeFile(.{ .sub_path = ".zig-cache/from.json", .data = from_str });
        try std.fs.cwd().writeFile(.{ .sub_path = ".zig-cache/to.json", .data = to_str });
        std.testing.expectEqualStrings(to_str, from_str) catch {};
        return error.TestExpectedEqual;
    }
}

fn MinMax(comptime T: type) type {
    return struct { min: T, max: T };
}

const Set = std.AutoArrayHashMapUnmanaged(u16, void);
const SpeciesByAbility = std.AutoArrayHashMapUnmanaged(u16, Set);
const SpeciesByDualType = std.AutoArrayHashMapUnmanaged([2]u8, Set);
const SpeciesByType = std.AutoArrayHashMapUnmanaged(u8, Set);
const SpeciesSet = std.AutoArrayHashMapUnmanaged(u16, void);
const SpeciesToSpeciesMap = std.AutoArrayHashMapUnmanaged(u16, void);

const Metronome = @This();

test {
    _ = core;
    _ = util;
}

const core = @import("core.zig");
const util = @import("util.zig");

const std = @import("std");
