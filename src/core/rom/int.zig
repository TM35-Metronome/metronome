const builtin = @import("builtin");
const std = @import("std");

const debug = std.debug;
const mem = std.mem;
const testing = std.testing;

pub const li128 = Int(i128, .Little);
pub const li16 = Int(i16, .Little);
pub const li32 = Int(i32, .Little);
pub const li64 = Int(i64, .Little);
pub const lu128 = Int(u128, .Little);
pub const lu16 = Int(u16, .Little);
pub const lu32 = Int(u32, .Little);
pub const lu64 = Int(u64, .Little);

pub const bi128 = Int(i128, .Big);
pub const bi16 = Int(i16, .Big);
pub const bi32 = Int(i32, .Big);
pub const bu128 = Int(u128, .Big);
pub const bu16 = Int(u16, .Big);
pub const bu32 = Int(u32, .Big);
pub const bu64 = Int(u64, .Big);

/// A data structure representing an integer of a specific endianess
pub fn Int(comptime _Inner: type, comptime _endian: std.builtin.Endian) type {
    comptime debug.assert(@typeInfo(_Inner) == .Int);

    return packed struct {
        __inner: Inner,

        pub const Inner = _Inner;
        pub const endian = _endian;

        pub fn init(v: Inner) @This() {
            return .{ .__inner = swap(v) };
        }

        /// Converts the integer to native endianess and returns it.
        pub fn value(int: @This()) Inner {
            return swap(int.__inner);
        }

        /// Ignore the integers endianess and read it as if it was a native integer.
        /// You probably shouldn't call this function as it is most likely not what you want.
        /// The few cases this is useful is for things like defining an endian aware enum:
        /// pub const E = enum(u16) {
        ///     A = lu16.init(1).valueNative(),
        ///     B = lu16.init(2).valueNative(),
        ///     C = lu16.init(3).valueNative(),
        /// }
        ///
        /// Here, we cannot define the tag as a `lu16´, so instead we use `valueNative`.
        /// The values of A,B,C will differ on platforms of different endianess, but
        /// the bit layout of A,B,C will always be the same no matter the endianess.
        pub fn valueNative(int: @This()) Inner {
            return int.__inner;
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
            return if (_endian != builtin.target.cpu.arch.endian()) @byteSwap(Inner, v) else v;
        }
    };
}

test "Int" {
    const value: u32 = 0x12345678;
    const numLittle = Int(u32, .Little).init(value);
    const numBig = Int(u32, .Big).init(value);
    testing.expectEqual(value, numLittle.value());
    testing.expectEqual(value, numBig.value());
    testing.expectEqualSlices(u8, &[_]u8{ 0x78, 0x56, 0x34, 0x12 }, &@bitCast([4]u8, numLittle));
    testing.expectEqualSlices(u8, &[_]u8{ 0x12, 0x34, 0x56, 0x78 }, &@bitCast([4]u8, numBig));
    switch (builtin.endian) {
        .Big => {
            testing.expectEqual(@as(u32, 0x78563412), numLittle.valueNative());
            testing.expectEqual(value, numBig.valueNative());
        },
        .Little => {
            testing.expectEqual(@as(u32, 0x78563412), numBig.valueNative());
            testing.expectEqual(value, numLittle.valueNative());
        },
    }
}
