const std = @import("std");

const math = std.math;
const testing = std.testing;

pub fn setTo(comptime Int: type, num: Int, bit: math.Log2Int(Int), value: bool) Int {
    return switch (value) {
        true => set(Int, num, bit),
        false => clear(Int, num, bit),
    };
}

test "setTo" {
    const v = @as(u8, 0b10);
    testing.expectEqual(@as(u8, 0b11), setTo(u8, v, 0, true));
    testing.expectEqual(@as(u8, 0b00), setTo(u8, v, 1, false));
}

pub fn set(comptime Int: type, num: Int, bit: math.Log2Int(Int)) Int {
    return num | (@as(Int, 1) << bit);
}

test "set" {
    const v = @as(u8, 0b10);
    testing.expectEqual(@as(u8, 0b11), set(u8, v, 0));
    testing.expectEqual(@as(u8, 0b10), set(u8, v, 1));
}

pub fn clear(comptime Int: type, num: Int, bit: math.Log2Int(Int)) Int {
    return num & ~(@as(Int, 1) << bit);
}

test "clear" {
    const v = @as(u8, 0b10);
    testing.expectEqual(@as(u8, 0b10), clear(u8, v, 0));
    testing.expectEqual(@as(u8, 0b00), clear(u8, v, 1));
}

pub fn isSet(comptime Int: type, num: Int, bit: math.Log2Int(Int)) bool {
    return ((num >> bit) & 1) != 0;
}

test "isSet" {
    const v = @as(u8, 0b10);
    testing.expect(!isSet(u8, v, 0));
    testing.expect(isSet(u8, v, 1));
}

pub fn toggle(comptime Int: type, num: Int, bit: math.Log2Int(Int)) Int {
    return num ^ (@as(Int, 1) << bit);
}

test "toggle" {
    const v = @as(u8, 0b10);
    testing.expectEqual(@as(u8, 0b11), toggle(u8, v, 0));
    testing.expectEqual(@as(u8, 0b00), toggle(u8, v, 1));
}

pub fn count(comptime Int: type, num: Int) usize {
    var tmp = num;
    var res: usize = 0;
    while (tmp != 0) : (res += 1)
        tmp &= tmp - 1;

    return res;
}

test "count" {
    testing.expectEqual(@as(usize, 0), count(u8, 0b0));
    testing.expectEqual(@as(usize, 1), count(u8, 0b1));
    testing.expectEqual(@as(usize, 2), count(u8, 0b101));
    testing.expectEqual(@as(usize, 4), count(u8, 0b11011));
}
