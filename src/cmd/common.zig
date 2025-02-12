pub fn averagePartyLevel(party: anytype) u8 {
    if (party.size == 0)
        return 2;

    var sum: u16 = 0;
    for (party.members[0..party.size]) |member|
        sum += member.base.level;
    return @intCast(sum / party.size);
}

pub fn totalStatsLevelScaling(min: u16, max: u16, level: u16) u16 {
    const fmin: f64 = @floatFromInt(min);
    const fmax: f64 = @floatFromInt(max);
    const diff = fmax - fmin;
    const x: f64 = @floatFromInt(level);

    // Function adapted from -0.0001 * x^2 + 0.02 * x
    // This functions grows fast at the start, getting 75%
    // to max stats at level 50.
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

pub fn partySizeLevelScaling(min: u8, max: u8, level: u16) u8 {
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

pub const Randomizer = struct {
    arena: std.mem.Allocator,
    random: std.Random,

    species: SpeciesSet,
    stats: MinMax(u16),

    // `randomSpeciesWithSimilarTotalStats` uses this as a buffer that is reused between calls
    similar: std.ArrayListUnmanaged(u16) = std.ArrayListUnmanaged(u16){},

    pub fn init(arena: std.mem.Allocator, random: std.Random, game: anytype) !Randomizer {
        var valid_species = std.ArrayList(u16).init(arena);
        try game.validSpecies(&valid_species);

        var species_set = SpeciesSet{};
        try species_set.ensureTotalCapacity(arena, valid_species.items.len);
        for (valid_species.items) |species|
            species_set.putAssumeCapacity(species, {});

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

        return .{
            .arena = arena,
            .random = random,
            .species = species_set,
            .stats = stats,
        };
    }

    pub fn randomItem(this: Randomizer, items: anytype) ?@TypeOf(&items[0]) {
        if (items.len == 0)
            return null;
        return &items[this.random.uintAtMost(usize, items.len - 1)];
    }

    pub fn randomSpeciesWithSimilarTotalStats(this: *Randomizer, game: anytype, pick_from: SpeciesSet, total_stats: u16) !u16 {
        const pokemons = try game.pokemons();
        const range = 5;
        var min = @as(isize, @intCast(total_stats)) - range;
        var max = min + range * 2;

        this.similar.shrinkRetainingCapacity(0);
        while (this.similar.items.len < 25) : ({
            min -= range;
            max += range;
        }) {
            try this.similar.ensureUnusedCapacity(this.arena, pick_from.count());
            for (pick_from.keys()) |s| {
                const p = pokemons.at(s) catch continue;
                const total: isize = @intCast(p.stats.total());
                if (min <= total and total <= max)
                    this.similar.appendAssumeCapacity(s);
            }
        }

        return this.randomItem(this.similar.items).?.*;
    }

    pub fn randomSpeciesWithStatsFollowingLevel(this: *Randomizer, game: anytype, pick_from: SpeciesSet, level: u16) !u16 {
        return this.randomSpeciesWithSimilarTotalStats(
            game,
            pick_from,
            totalStatsLevelScaling(this.stats.min, this.stats.max, level),
        );
    }
};

pub fn MinMax(comptime T: type) type {
    return struct { min: T, max: T };
}

pub const SpeciesSet = std.AutoArrayHashMapUnmanaged(u16, void);
pub const SpeciesToSpeciesMap = std.AutoArrayHashMapUnmanaged(u16, void);

const std = @import("std");
