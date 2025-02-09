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
}

const std = @import("std");
