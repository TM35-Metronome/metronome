const std = @import("std");

const mem = std.mem;
const rand = std.rand;

/// Uses the random number generator `random` to pick a random item `span` to
/// return. If `span` has a length of `0`, `null` is returned instead.
pub fn item(random: rand.Random, span: anytype) ?@TypeOf(&span[0]) {
    if (span.len == 0)
        return null;
    return &span[random.intRangeLessThan(usize, 0, span.len)];
}

pub fn items(random: rand.Random, to_randomize: anytype, pick_from: anytype) void {
    for (to_randomize) |*v|
        v.* = item(random, pick_from).?.*;
}
