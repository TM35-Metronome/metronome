const std = @import("std");

const mem = std.mem;
const testing = std.testing;

pub fn all(items: anytype, pred: anytype) bool {
    for (items) |item|
        if (!pred(item))
            return false;
    return true;
}

test "all" {
    testing.expect(all("abcd", std.ascii.isAlpha));
    testing.expect(!all("1a3b", std.ascii.isAlpha));
}

pub fn fold(items: anytype, init: anytype, func: anytype) @TypeOf(init) {
    var res = init;
    for (items) |item|
        res = func(res, item);
    return res;
}

test "fold" {
    testing.expectEqual(@as(usize, 12), fold(&[_]u8{ 1, 2, 3, 3, 2, 1 }, @as(usize, 0), add));
    testing.expectEqual(@as(usize, 15), fold(&[_]u8{ 5, 5, 5 }, @as(usize, 0), add));
}

pub fn reduce(items: anytype, func: anytype) ?@typeInfo(mem.Span(@TypeOf(items))).Pointer.child {
    if (items.len == 0)
        return null;

    return fold(items[1..], items[0], func);
}

test "reduce" {
    testing.expectEqual(@as(?u8, 12), reduce(&[_]u8{ 1, 2, 3, 3, 2, 1 }, add));
    testing.expectEqual(@as(?u8, 15), reduce(&[_]u8{ 5, 5, 5 }, add));
    testing.expectEqual(@as(?u8, null), reduce(&[_]u8{}, add));
}

pub fn add(a: anytype, b: anytype) @TypeOf(a + b) {
    return a + b;
}
