const std = @import("std");

const mem = std.mem;
const rand = std.rand;

/// Uses the random number generator `random` to pick a random item `span` to
/// return. If `span` has a lenght of `0`, `null` is returned instead.
pub fn item(random: *rand.Random, span: anytype) ?ItemResult(@TypeOf(span)) {
    if (span.len == 0)
        return null;
    return &span[random.intRangeLessThan(usize, 0, span.len)];
}

pub fn ItemResult(comptime Span: type) type {
    var info = @typeInfo(mem.Span(Span));
    info.Pointer.size = .One;
    return @Type(info);
}
