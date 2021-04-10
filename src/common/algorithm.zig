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

pub fn find(items: anytype, ctx: anytype, pred: anytype) ?FindResult(@TypeOf(items)) {
    for (items) |*item| {
        if (pred(ctx, item.*))
            return item;
    }
    return null;
}

pub fn FindResult(comptime Span: type) type {
    var info = @typeInfo(mem.Span(Span));
    info.Pointer.size = .One;
    return @Type(info);
}

test "find" {
    const s = &[_]u8{ 1, 2, 3, 3, 2, 1 };
    testing.expectEqual(@as(?*const u8, &s[0]), find(s, {}, eqlPred(1)));
    testing.expectEqual(@as(?*const u8, &s[1]), find(s, {}, eqlPred(2)));
    testing.expectEqual(@as(?*const u8, &s[2]), find(s, {}, eqlPred(3)));
}

pub fn findLast(items: anytype, ctx: anytype, pred: anytype) ?FindResult(@TypeOf(items)) {
    for (items) |_, i_forward| {
        const i = items.len - (i_forward + 1);
        if (pred(ctx, items[i]))
            return &items[i];
    }
    return null;
}

test "findLast" {
    const s = &[_]u8{ 1, 2, 3, 3, 2, 1 };
    testing.expectEqual(@as(?*const u8, &s[5]), findLast(s, {}, eqlPred(1)));
    testing.expectEqual(@as(?*const u8, &s[4]), findLast(s, {}, eqlPred(2)));
    testing.expectEqual(@as(?*const u8, &s[3]), findLast(s, {}, eqlPred(3)));
}

fn dummy(ctx: anytype, item: anytype) bool {}

pub fn eqlPred(comptime value: anytype) @TypeOf(dummy) {
    return struct {
        fn pred(_: anytype, item: anytype) bool {
            return item == value;
        }
    }.pred;
}

pub fn groupBy(output_map: anytype, items: anytype, ctx: anytype, get_value: anytype, get_key: anytype) !void {
    for (items) |item| {
        const key = get_key(ctx, item);
        output_map.getOrPutValue();
    }
}
