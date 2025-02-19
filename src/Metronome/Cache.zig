//! It is quite useful to structure the data in a pokemon game in certain ways, like getting a map
//! of type -> species and others. The `Cache` provides methods for getting the data of the game
//! structured in a certain way. This data is cached so it does not need to be recomputed every
//! time it is needed.
//!
//! It is the responsibility of the owner of the cache to invalidate entries when they modify the
//! game in a way that makes certain entries invalid. For example, if you change the types pokemon
//! have, then you should also set `cache.species_by_type_valid = false`.

game_ptr: ?*const anyopaque = null,

arena: std.mem.Allocator,

species_list: SpeciesList = .{},
species_set: SpeciesSet = .{},
species_valid: bool = false,

legendary_ratings: std.AutoArrayHashMapUnmanaged(u16, i16) = .{},
legendaries_set: SpeciesSet = .{},
legendaries_valid: bool = false,

evolutions_set: SpeciesSet = .{},
evolutions_valid: bool = false,

total_stats_min_max: MinMax(u16) = undefined,
total_stats_min_max_valid: bool = false,

species_by_type: SpeciesByType = .{},
species_by_type_valid: bool = false,

species_by_dual_type: SpeciesByDualType = .{},
species_by_dual_type_valid: bool = false,

species_by_ability: SpeciesByAbility = .{},
species_by_ability_valid: bool = false,

lowest_evolutions: LowestEvolutions = .{},
lowest_evolutions_valid: bool = false,

// Fields like `species_by_type` is a map of sets. When such entries needs to be recomputed, the
// old sets will be put into this list so they capacity can be reused.
species_set_freelist: std.ArrayListUnmanaged(SpeciesSet) = .{},

/// The cache is only valid for one specific game. This function asserts that the same game is
/// always passed to the cache.
fn assertCorrectGame(cache: *Cache, game: anytype) void {
    const ptr = cache.game_ptr orelse {
        cache.game_ptr = game;
        return;
    };

    const other_ptr: *const anyopaque = game;
    std.debug.assert(ptr == other_ptr);
}

/// Gets the set of all valid species in a pokemon game. This will exclude things like:
/// * species 0, which is always the "null" pokemon
/// * gen5 Pokéstar Studios pokemon
pub fn species(cache: *Cache, game: anytype) !*const SpeciesSet {
    cache.assertCorrectGame(game);
    if (cache.species_valid)
        return &cache.species_set;

    {
        cache.species_list.shrinkRetainingCapacity(0);
        var valid_species = cache.species_list.toManaged(cache.arena);
        try game.validSpecies(&valid_species);
        cache.species_list = valid_species.moveToUnmanaged();
    }

    const pokemons = try game.pokemons();
    try cache.species_set.ensureTotalCapacity(cache.arena, cache.species_list.items.len);
    cache.species_set.shrinkRetainingCapacity(0);

    for (cache.species_list.items) |s| {
        _ = pokemons.at(s) catch continue;
        cache.species_set.putAssumeCapacity(s, {});
    }

    cache.species_valid = true;
    return &cache.species_set;
}

/// Finds the minimum and maximum total stats species in the `species_set` has. In gen5, this is
/// 180 (Sunkern) and 720 (Arceus)
pub fn totalStatsMinMax(cache: *Cache, game: anytype) !*const MinMax(u16) {
    cache.assertCorrectGame(game);
    if (cache.total_stats_min_max_valid)
        return &cache.total_stats_min_max;

    const species_set = try cache.species(game);
    const pokemons = try game.pokemons();
    cache.total_stats_min_max = .{ .max = 0, .min = std.math.maxInt(u16) };

    for (species_set.keys()) |s| {
        const pokemon = pokemons.at(s) catch unreachable;
        const total_stats = pokemon.stats.total();
        cache.total_stats_min_max.min = @min(cache.total_stats_min_max.min, total_stats);
        cache.total_stats_min_max.max = @max(cache.total_stats_min_max.max, total_stats);
    }

    cache.total_stats_min_max_valid = true;
    return &cache.total_stats_min_max;
}

test totalStatsMinMax {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cache = Cache{ .arena = arena.allocator() };
    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);

    for ([_][2]bool{
        .{ false, false },
        .{ true, true },
        .{ true, false },
    }) |cache_validation| {
        try std.testing.expectEqual(cache_validation[0], cache.total_stats_min_max_valid);
        cache.total_stats_min_max_valid = cache_validation[1];

        const minmax = try cache.totalStatsMinMax(&game);
        try std.testing.expectEqual(@as(u16, 195), minmax.min);
        try std.testing.expectEqual(@as(u16, 680), minmax.max);
    }
}

/// Finds all species that are evolutions of other species
pub fn evolutions(cache: *Cache, game: anytype) !*const SpeciesSet {
    cache.assertCorrectGame(game);
    if (cache.evolutions_valid)
        return &cache.evolutions_set;

    const species_set = try cache.species(game);
    const pokemon_evolutions = try game.evolutions();
    cache.evolutions_set.shrinkRetainingCapacity(0);

    for (species_set.keys()) |s| {
        const evos = pokemon_evolutions.at(s) catch continue;
        for (evos) |evo| {
            if (evo.method == .unused) continue;
            try cache.evolutions_set.put(cache.arena, evo.target, {});
        }
    }

    cache.evolutions_valid = true;
    return &cache.evolutions_set;
}

test evolutions {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cache = Cache{ .arena = arena.allocator() };
    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);

    for ([_][2]bool{
        .{ false, false },
        .{ true, true },
        .{ true, false },
    }) |cache_validation| {
        try std.testing.expectEqual(cache_validation[0], cache.evolutions_valid);
        cache.evolutions_valid = cache_validation[1];

        const res = try cache.evolutions(&game);
        try std.testing.expectEqualSlices(u16, &.{
            2,  3,  5,   6,   8,   9,   11,  12,  14,  15,  17,  18,  20,  22,  24,  26,  28,  30,
            31, 33, 34,  36,  38,  40,  42,  44,  45,  47,  49,  51,  53,  55,  57,  59,  61,  62,
            64, 65, 67,  68,  70,  71,  73,  75,  76,  78,  80,  82,  85,  87,  89,  91,  93,  94,
            97, 99, 101, 103, 105, 110, 112, 117, 119, 121, 130, 134, 135, 136, 139, 141, 148, 149,
        }, res.keys());
    }
}

/// Finds all legendary species
pub fn legendaries(cache: *Cache, game: anytype) !*const SpeciesSet {
    cache.assertCorrectGame(game);
    if (cache.legendaries_valid)
        return &cache.legendaries_set;

    // There is no way to specify in game that a Pokemon is a legendary. Instead we find
    // legendaries by looking at their stats, evolution line and other patterns common for
    // legendaries

    const species_set = try cache.species(game);
    const is_evolution = try cache.evolutions(game);
    const pokemons = try game.pokemons();

    // First, lets give each Pokemon a "legendary rating" which is a measure as to how many
    // "legendary" criteria this pokemon fits into. This rating can be negative.

    try cache.legendary_ratings.ensureTotalCapacity(cache.arena, species_set.count());
    cache.legendary_ratings.shrinkRetainingCapacity(0);

    for (species_set.keys()) |s| {
        const pokemon = pokemons.at(s) catch undefined;
        const rating = (cache.legendary_ratings.getOrPutAssumeCapacity(s)).value_ptr;
        rating.* = 0;

        // Legendaries are generally in the "slow" to "medium_slow" growth rating
        rating.* += @as(i16, @intFromBool(pokemon.growth_rate == .slow or
            pokemon.growth_rate == .medium_slow));

        // They generally have a catch rate of 45 or less
        rating.* += @as(i16, @intFromBool(pokemon.catch_rate <= 45));

        // They tend to not have a gender (255 in gender_ratio means genderless).
        rating.* += @as(i16, @intFromBool(pokemon.gender_ratio == 255));

        // Most are part of the "undiscovered" egg group
        for (pokemon.egg_groups) |egg_group|
            rating.* += @as(i16, @intFromBool(egg_group == .undiscovered));

        // They don't evolve from anything. Subtract score from metronome Pokemons evolutions.
        rating.* -= @as(i16, @intFromBool(is_evolution.get(s) != null)) * 10;
    }

    const rating_to_be_legendary = blk: {
        var res: isize = 0;
        for (cache.legendary_ratings.values()) |rating|
            res = @max(res, rating);

        // Not all legendaries match all criteria. Let's allow for legendaries that miss on
        // criteria.
        break :blk res - 1;
    };

    cache.legendaries_set.shrinkRetainingCapacity(0);
    for (cache.legendary_ratings.keys(), cache.legendary_ratings.values()) |s, rating| {
        if (rating < rating_to_be_legendary)
            continue;
        _ = try cache.legendaries_set.put(cache.arena, s, {});
    }

    cache.legendaries_valid = true;
    return &cache.legendaries_set;
}

test legendaries {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cache = Cache{ .arena = arena.allocator() };
    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);

    for ([_][2]bool{
        .{ false, false },
        .{ true, true },
        .{ true, false },
    }) |cache_validation| {
        try std.testing.expectEqual(cache_validation[0], cache.legendaries_valid);
        cache.legendaries_valid = cache_validation[1];

        const res = try cache.legendaries(&game);
        try std.testing.expectEqualSlices(u16, &.{
            144, 145, 146,
            150, 151,
        }, res.keys());
    }
}

/// Construct a map from pokemon type to all species having that type
pub fn speciesByType(cache: *Cache, game: anytype) !*const SpeciesByType {
    cache.assertCorrectGame(game);
    if (cache.species_by_type_valid)
        return &cache.species_by_type;

    const species_set = try cache.species(game);
    const pokemons = try game.pokemons();

    try cache.species_set_freelist.ensureUnusedCapacity(cache.arena, cache.species_by_type.count());
    for (cache.species_by_type.values()) |*set| {
        set.shrinkRetainingCapacity(0);
        cache.species_set_freelist.appendAssumeCapacity(set.*);
    }
    cache.species_by_type.shrinkRetainingCapacity(0);

    for (species_set.keys()) |s| {
        const pokemon = pokemons.at(s) catch unreachable;

        for (pokemon.types) |t| {
            const entry = try cache.species_by_type.getOrPut(cache.arena, t);
            if (!entry.found_existing)
                entry.value_ptr.* = cache.species_set_freelist.pop() orelse .{};
            try entry.value_ptr.put(cache.arena, s, {});
        }
    }

    cache.species_by_type_valid = true;
    return &cache.species_by_type;
}

test speciesByType {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cache = Cache{ .arena = arena.allocator() };
    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);

    for ([_][2]bool{
        .{ false, false },
        .{ true, true },
        .{ true, false },
    }) |cache_validation| {
        try std.testing.expectEqual(cache_validation[0], cache.species_by_type_valid);
        cache.species_by_type_valid = cache_validation[1];

        const species_by_type = try cache.speciesByType(&game);

        try std.testing.expectEqual(@as(usize, 16), species_by_type.count());
        try std.testing.expectEqualSlices(u16, &.{ // Normal
            16,  17,  18,  19,  20, 21, 22, 35, 36, 39, 40, 52, 53, 83, 84, 85, 108, 113, 115, 128,
            132, 133, 137, 143,
        }, species_by_type.get(0).?.keys());
        try std.testing.expectEqualSlices(u16, &.{ // Fighting
            56, 57, 62, 66, 67, 68, 106, 107,
        }, species_by_type.get(1).?.keys());
        try std.testing.expectEqualSlices(u16, &.{ // Flying
            6, 12, 16, 17, 18, 21, 22, 41, 42, 83, 84, 85, 123, 130, 142, 144, 145, 146, 149,
        }, species_by_type.get(2).?.keys());
        try std.testing.expectEqualSlices(u16, &.{ // Poison
            1,  2,  3,  13, 14, 15, 23, 24, 29, 30, 31,  32,  33, 34, 41, 42, 43, 44, 45, 48, 49,
            69, 70, 71, 72, 73, 88, 89, 92, 93, 94, 109, 110,
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
            7,   8,   9,   54,  55,  60,  61,  62,  72,  73,  79,  80,  86,  87,  90, 91, 98, 99,
            116, 117, 118, 119, 120, 121, 129, 130, 131, 134, 138, 139, 140, 141,
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
}

/// Construct a map from pokemon dual typing to all species having that dual typing
pub fn speciesByDualType(
    cache: *Cache,
    game: anytype,
) !*const SpeciesByDualType {
    cache.assertCorrectGame(game);
    if (cache.species_by_dual_type_valid)
        return &cache.species_by_dual_type;

    const species_set = try cache.species(game);
    const pokemons = try game.pokemons();

    try cache.species_set_freelist.ensureUnusedCapacity(
        cache.arena,
        cache.species_by_dual_type.count(),
    );
    for (cache.species_by_dual_type.values()) |*set| {
        set.shrinkRetainingCapacity(0);
        cache.species_set_freelist.appendAssumeCapacity(set.*);
    }
    cache.species_by_dual_type.shrinkRetainingCapacity(0);

    for (species_set.keys()) |s| {
        const pokemon = pokemons.at(s) catch unreachable;

        const entry = try cache.species_by_dual_type.getOrPut(cache.arena, .{
            @min(pokemon.types[0], pokemon.types[1]),
            @max(pokemon.types[0], pokemon.types[1]),
        });
        if (!entry.found_existing)
            entry.value_ptr.* = cache.species_set_freelist.pop() orelse .{};
        try entry.value_ptr.put(cache.arena, s, {});
    }

    cache.species_by_dual_type_valid = true;
    return &cache.species_by_dual_type;
}

test speciesByDualType {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cache = Cache{ .arena = arena.allocator() };
    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);

    for ([_][2]bool{
        .{ false, false },
        .{ true, true },
        .{ true, false },
    }) |cache_validation| {
        try std.testing.expectEqual(cache_validation[0], cache.species_by_dual_type_valid);
        cache.species_by_dual_type_valid = cache_validation[1];

        const species_by_dual_type = try cache.speciesByDualType(&game);

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
}

pub fn speciesByAbility(cache: *Cache, game: anytype) !*const SpeciesByAbility {
    cache.assertCorrectGame(game);
    if (cache.species_by_ability_valid)
        return &cache.species_by_ability;

    const species_set = try cache.species(game);
    const pokemons = try game.pokemons();

    try cache.species_set_freelist.ensureUnusedCapacity(cache.arena, cache.species_by_ability.count());
    for (cache.species_by_ability.values()) |*set| {
        set.shrinkRetainingCapacity(0);
        cache.species_set_freelist.appendAssumeCapacity(set.*);
    }
    cache.species_by_ability.shrinkRetainingCapacity(0);

    for (species_set.keys()) |s| {
        const pokemon = pokemons.at(s) catch unreachable;

        for (pokemon.abilities) |t| {
            const entry = try cache.species_by_ability.getOrPut(cache.arena, t);
            if (!entry.found_existing)
                entry.value_ptr.* = cache.species_set_freelist.pop() orelse .{};
            try entry.value_ptr.put(cache.arena, s, {});
        }
    }

    cache.species_by_ability_valid = true;
    return &cache.species_by_ability;
}

test speciesByAbility {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cache = Cache{ .arena = arena.allocator() };
    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);

    for ([_][2]bool{
        .{ false, false },
        .{ true, true },
        .{ true, false },
    }) |cache_validation| {
        try std.testing.expectEqual(cache_validation[0], cache.species_by_ability_valid);
        cache.species_by_ability_valid = cache_validation[1];

        const species_by_ability = try cache.speciesByAbility(&game);
        try std.testing.expectEqual(@as(usize, 112), species_by_ability.count());
        // TODO: Check all results
    }
}

pub const LowestEvolutions = struct {
    stage_2: SpeciesSet = .{},
    stage_3: SpeciesSet = .{},
    all: SpeciesSet = .{},
};

pub fn lowestEvolutions(cache: *Cache, game: anytype) !*const LowestEvolutions {
    if (cache.lowest_evolutions_valid)
        return &cache.lowest_evolutions;

    cache.lowest_evolutions.stage_2.shrinkRetainingCapacity(0);
    cache.lowest_evolutions.stage_3.shrinkRetainingCapacity(0);
    cache.lowest_evolutions.all.shrinkRetainingCapacity(0);

    const species_set = try cache.species(game);
    const evos = try cache.evolutions(game);

    try cache.lowest_evolutions.all.ensureTotalCapacity(cache.arena, species_set.count());
    for (species_set.keys()) |s| {
        if (evos.get(s)) |_|
            continue;
        cache.lowest_evolutions.all.putAssumeCapacity(s, {});
    }

    for (cache.lowest_evolutions.all.keys()) |s| {
        switch (countEvolutions(s, s, game)) {
            1 => try cache.lowest_evolutions.stage_2.put(cache.arena, s, {}),
            2 => try cache.lowest_evolutions.stage_3.put(cache.arena, s, {}),
            else => {},
        }
    }

    cache.lowest_evolutions_valid = true;
    return &cache.lowest_evolutions;
}

test lowestEvolutions {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cache = Cache{ .arena = arena.allocator() };
    const game = try core.dummy.Game.init(arena.allocator(), core.dummy.default);

    for ([_][2]bool{
        .{ false, false },
        .{ true, true },
        .{ true, false },
    }) |cache_validation| {
        try std.testing.expectEqual(cache_validation[0], cache.lowest_evolutions_valid);
        cache.lowest_evolutions_valid = cache_validation[1];

        const lowest_evolutions = try cache.lowestEvolutions(&game);
        try std.testing.expectEqualSlices(u16, &.{
            1,   4,   7,   10,  13,  16,  19,  21,  23,  25,  27,  29,  32,  35,  37,  39,  41,
            43,  46,  48,  50,  52,  54,  56,  58,  60,  63,  66,  69,  72,  74,  77,  79,  81,
            83,  84,  86,  88,  90,  92,  95,  96,  98,  100, 102, 104, 106, 107, 108, 109, 111,
            113, 114, 115, 116, 118, 120, 122, 123, 124, 125, 126, 127, 128, 129, 131, 132, 133,
            137, 138, 140, 142, 143, 144, 145, 146, 147, 150, 151,
        }, lowest_evolutions.all.keys());
        try std.testing.expectEqualSlices(u16, &.{
            19, 21, 23, 25, 27, 35, 37, 39,  41,  46,  48,  50,  52,  54,  56,  58,  72,  77,  79,
            81, 84, 86, 88, 90, 96, 98, 100, 102, 104, 109, 111, 116, 118, 120, 129, 133, 138, 140,
        }, lowest_evolutions.stage_2.keys());
        try std.testing.expectEqualSlices(u16, &.{
            1, 4, 7, 10, 13, 16, 29, 32, 43, 60, 63, 66, 69, 74, 92, 147,
        }, lowest_evolutions.stage_3.keys());
    }
}

fn countEvolutions(s: u16, start_species: u16, game: anytype) usize {
    var res: usize = 0;

    const pokemons_evolutions = game.evolutions() catch return res;
    const evos = pokemons_evolutions.at(s) catch return res;
    for (evos) |evolution| {
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

pub fn MinMax(comptime T: type) type {
    return struct { min: T, max: T };
}

pub const SpeciesByAbility = std.AutoArrayHashMapUnmanaged(u16, SpeciesSet);
pub const SpeciesByDualType = std.AutoArrayHashMapUnmanaged([2]u8, SpeciesSet);
pub const SpeciesByType = std.AutoArrayHashMapUnmanaged(u8, SpeciesSet);
pub const SpeciesList = std.ArrayListUnmanaged(u16);
pub const SpeciesSet = std.AutoArrayHashMapUnmanaged(u16, void);

const Cache = @This();

test {
    _ = Metronome;

    _ = core;
}

const Metronome = @import("../Metronome.zig");

const core = @import("../core.zig");

const std = @import("std");
