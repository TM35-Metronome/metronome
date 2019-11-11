const builtin = @import("builtin");
const std = @import("std");

const debug = std.debug;
const mem = std.mem;

pub const lu16 = Int(u16, builtin.Endian.Little);
pub const lu32 = Int(u32, builtin.Endian.Little);
pub const lu64 = Int(u64, builtin.Endian.Little);
pub const lu128 = Int(u128, builtin.Endian.Little);
pub const li16 = Int(i16, builtin.Endian.Little);
pub const li32 = Int(i32, builtin.Endian.Little);
pub const li64 = Int(i64, builtin.Endian.Little);
pub const li128 = Int(i128, builtin.Endian.Little);

pub const bu16 = Int(u16, builtin.Endian.Big);
pub const bu32 = Int(u32, builtin.Endian.Big);
pub const bu64 = Int(u64, builtin.Endian.Big);
pub const bu128 = Int(u128, builtin.Endian.Big);
pub const bi16 = Int(i16, builtin.Endian.Big);
pub const bi32 = Int(i32, builtin.Endian.Big);
pub const bi128 = Int(i128, builtin.Endian.Big);

/// A data structure representing an integer of a specific endianess
pub fn Int(comptime Inner: type, comptime endian: builtin.Endian) type {
    comptime debug.assert(@typeId(Inner) == .Int);

    return packed struct {
        const Self = @This();

        bytes: [@sizeOf(Inner)]u8,

        pub fn init(v: Inner) Self {
            var res: Self = undefined;
            mem.writeInt(Inner, &res.bytes, v, endian);

            return res;
        }

        pub fn value(int: Self) Inner {
            return mem.readInt(Inner, &int.bytes, endian);
        }
    };
}

test "Int" {
    const value: u32 = 0x12345678;
    const numLittle = Int(u32, builtin.Endian.Little).init(value);
    const numBig = Int(u32, builtin.Endian.Big).init(value);
    testing.expectEqual(value, numLittle.value());
    testing.expectEqual(value, numBig.value());
    testing.expectEqualSlices(u8, [_]u8{ 0x78, 0x56, 0x34, 0x12 }, numLittle.bytes);
    testing.expectEqualSlices(u8, [_]u8{ 0x12, 0x34, 0x56, 0x78 }, numBig.bytes);
}
