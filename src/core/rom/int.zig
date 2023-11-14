const builtin = @import("builtin");
const std = @import("std");

const debug = std.debug;
const mem = std.mem;
const testing = std.testing;

const native_endian = builtin.target.cpu.arch.endian();

pub const li128 = Int(i128, .little);
pub const li16 = Int(i16, .little);
pub const li32 = Int(i32, .little);
pub const li64 = Int(i64, .little);
pub const lu128 = Int(u128, .little);
pub const lu16 = Int(u16, .little);
pub const lu32 = Int(u32, .little);
pub const lu64 = Int(u64, .little);

pub const bi128 = Int(i128, .big);
pub const bi16 = Int(i16, .big);
pub const bi32 = Int(i32, .big);
pub const bu128 = Int(u128, .big);
pub const bu16 = Int(u16, .big);
pub const bu32 = Int(u32, .big);
pub const bu64 = Int(u64, .big);

/// A data structure representing an integer of a specific endianness
pub fn Int(comptime _Inner: type, comptime _endian: std.builtin.Endian) type {
    return enum(_Inner) {
        _,

        pub const Inner = _Inner;
        pub const endian = _endian;

        pub fn init(v: Inner) @This() {
            @setEvalBranchQuota(100000000);
            return @enumFromInt(swap(v));
        }

        /// Converts the integer to native endianness and returns it.
        pub fn value(int: @This()) Inner {
            return swap(@intFromEnum(int));
        }

        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            return std.fmt.formatIntValue(self.value(), fmt, options, writer);
        }

        fn swap(v: Inner) Inner {
            return if (_endian != native_endian) @byteSwap(v) else v;
        }
    };
}

test "Int" {
    const value: u32 = 0x12345678;
    const numLittle = Int(u32, .Little).init(value);
    const numBig = Int(u32, .Big).init(value);
    try testing.expectEqual(value, numLittle.value());
    try testing.expectEqual(value, numBig.value());
    try testing.expectEqualSlices(u8, &[_]u8{ 0x78, 0x56, 0x34, 0x12 }, @ptrCast(&numLittle));
    try testing.expectEqualSlices(u8, &[_]u8{ 0x12, 0x34, 0x56, 0x78 }, @ptrCast(&numBig));
    switch (native_endian) {
        .Big => {
            try testing.expectEqual(@as(u32, 0x78563412), @intFromEnum(numLittle));
            try testing.expectEqual(value, @intFromEnum(numBig));
        },
        .Little => {
            try testing.expectEqual(@as(u32, 0x78563412), @intFromEnum(numBig));
            try testing.expectEqual(value, @intFromEnum(numLittle));
        },
    }
}
