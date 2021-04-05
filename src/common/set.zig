const std = @import("std");

const debug = std.debug;
const mem = std.mem;
const testing = std.testing;

/// Returns a set of type `Out` which contains the intersection of `a` and `b`.
pub fn intersect(comptime Out: type, allocator: *mem.Allocator, a: anytype, b: anytype) !Out {
    var res = Out.init(allocator);
    try intersectInline(&res, a, b);
    return res;
}

/// Stores the intersection of `a` and `b` in `out`.
pub fn intersectInline(out: anytype, a: anytype, b: anytype) !void {
    if (a.count() < b.count())
        return intersectImpl(out, b, a);
    return intersectImpl(out, a, b);
}

fn intersectImpl(out: anytype, biggest: anytype, smallest: anytype) !void {
    debug.assert(biggest.count() >= smallest.count());
    var it = biggest.iterator();
    while (it.next()) |entry| {
        if (smallest.get(entry.key) != null)
            _ = try out.put(entry.key, {});
    }
}

test "intersect" {
    const Set = std.AutoHashMap(u8, void);

    for ([_][3][]const u8{
        .{ "abc", "abc", "abc" },
        .{ "abc", "bcd", "bc" },
        .{ "abc", "def", "" },
    }) |test_case| {
        var a = try initWithMembers(Set, testing.allocator, test_case[0]);
        defer a.deinit();
        var b = try initWithMembers(Set, testing.allocator, test_case[1]);
        defer b.deinit();
        var expect = try initWithMembers(Set, testing.allocator, test_case[2]);
        defer expect.deinit();

        var res_a = try intersect(Set, testing.allocator, a, b);
        defer res_a.deinit();
        var res_b = try intersect(Set, testing.allocator, b, a);
        defer res_b.deinit();
        expectEqual(expect, res_a);
        expectEqual(expect, res_b);
    }
}

/// Puts all items of a slice/array into `set`.
pub fn putMany(set: anytype, members: anytype) !void {
    for (members) |member|
        _ = try set.put(member, {});
}

/// Initializes a set of type `Set` with the members contained in the array/slice
/// `members`.
pub fn initWithMembers(comptime Set: type, allocator: *mem.Allocator, members: anytype) !Set {
    var set = Set.init(allocator);
    errdefer set.deinit();
    try putMany(&set, members);
    return set;
}

/// Checks that the two sets `a` and `b` contains the exact same members.
pub fn eql(a: anytype, b: anytype) bool {
    if (a.count() != b.count())
        return false;

    var it = a.iterator();
    while (it.next()) |entry| {
        if (b.get(entry.key) == null)
            return false;
    }

    return true;
}

/// Tests that the set `actual` is equal to the set `expect`.
pub fn expectEqual(expect: anytype, actual: anytype) void {
    testing.expect(eql(expect, actual));
}
