const std = @import("std");

const testing = std.testing;

pub fn all(comptime T: type, items: []const T, pred: fn (T) bool) bool {
    for (items) |item|
        if (!pred(item))
            return false;
    return true;
}

test "all" {
    testing.expect(all(u8, "abcd", std.ascii.isAlpha));
    testing.expect(!all(u8, "1a3b", std.ascii.isAlpha));
}
