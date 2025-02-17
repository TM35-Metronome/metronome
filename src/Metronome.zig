gpa: std.mem.Allocator,
arena: std.heap.ArenaAllocator,
random: std.Random,

species: SpeciesSet,
species_by_ability: SpeciesByAbility,
species_by_type: SpeciesByType,
species_by_dual_type: SpeciesByDualType,

legendaries: SpeciesSet,
stats: MinMax(u16),

// `randomSpeciesWithSimilarTotalStats` uses metronome as a buffer that is reused between calls
similar: std.ArrayListUnmanaged(u16) = std.ArrayListUnmanaged(u16){},

// TODO: Document where used
intersection: Set = Set{},
pick_from_excluded: Set = Set{},

pub fn init(gpa: std.mem.Allocator, random: std.Random, game: anytype) !Metronome {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    var species_set = blk: {
        var valid_species = std.ArrayList(u16).init(arena);
        try game.validSpecies(&valid_species);

        var species_set = SpeciesSet{};
        try species_set.ensureTotalCapacity(arena, valid_species.items.len);
        for (valid_species.items) |species|
            species_set.putAssumeCapacity(species, {});

        break :blk species_set;
    };

    const legendaries = try findLegendaries(arena, species_set, game);
    return .{
        .gpa = gpa,
        .arena = arena_state,
        .random = random,

        .species = species_set,

        .legendaries = legendaries,
        .stats = blk: {
            var stats: MinMax(u16) = .{
                .min = std.math.maxInt(u16),
                .max = 0,
            };

            const pokemons = try game.pokemons();
            for (species_set.keys()) |species| {
                const pokemon = try pokemons.at(species);

                const total_stats = pokemon.stats.total();
                stats.min = @min(stats.min, total_stats);
                stats.max = @max(stats.max, total_stats);
            }

            break :blk stats;
        },
    };
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
    const metronome = try Metronome.init(arena.allocator(), undefined, game);
    const legendaries = try metronome.findLegendaries(game);

    try std.testing.expectEqualSlices(u16, &.{
        144, 145, 146,
        150, 151,
    }, legendaries.keys());
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
        try metronome.similar.ensureUnusedCapacity(metronome.arena, pick_from.count());
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
}

const core = @import("../core.zig");

const std = @import("std");
