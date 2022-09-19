const builtin = @import("builtin");
const std = @import("std");

const math = std.math;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const trait = meta.trait;

/// Calculates the packed size of 'value'. The packed size is the size 'value'
/// would have if unions did not have to have the size of their biggest field.
pub fn packedLength(value: anytype) error{InvalidTag}!usize {
    @setEvalBranchQuota(10000000);
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Void => return 0,
        .Int => |i| {
            if (i.bits % 8 != 0)
                @compileError("Does not support none power of two intergers");
            return @as(usize, i.bits / 8);
        },
        .Enum => return packedLength(@enumToInt(value)) catch unreachable,
        .Array => {
            var res: usize = 0;
            for (value) |item|
                res += try packedLength(item);

            return res;
        },
        .Struct => |s| {
            var res: usize = 0;
            inline for (s.fields) |struct_field|
                res += try packedLength(@field(value, struct_field.name));
            return res;
        },
        .Union => |u| {
            if (u.layout != .Packed and u.layout != .Extern)
                @compileError(@typeName(T) ++ " is not packed or extern");
            if (u.tag_type != null)
                @compileError(@typeName(T) ++ " cannot have a tag.");

            // Find the field most likly to be this unions tag.
            const tag_field = u.fields[0];
            const tag = @field(value, tag_field.name);
            const TagEnum = @TypeOf(tag);
            if (@typeInfo(TagEnum) != .Enum)
                @compileError(@typeName(T) ++ " tag is not enum: " ++ @typeName(TagEnum));

            // Switch over all tags. 'TagEnum' have the same field names as
            // 'union' so if one member of 'TagEnum' matches 'tag', then
            // we can add the size of ''@field(union, tag_name)' to res and
            // break out.
            var res: ?usize = null;
            inline for (@typeInfo(TagEnum).Enum.fields) |enum_field| {
                if (@field(TagEnum, enum_field.name) == tag) {
                    const union_field = @field(value, enum_field.name);
                    res = try packedLength(union_field);
                }
            }

            // If no member of 'TagEnum' match, then 'tag' must be a value
            // it is not suppose to be.
            return res orelse return error.InvalidTag;
        },
        else => @compileError(@typeName(T) ++ " not supported"),
    }
}

fn testPackedLength(value: anytype, expect: error{InvalidTag}!usize) !void {
    if (packedLength(value)) |size| {
        const expected_size = expect catch unreachable;
        try testing.expectEqual(expected_size, size);
    } else |err| {
        const expected_err = if (expect) |_| unreachable else |e| e;
        try testing.expectEqual(expected_err, err);
    }
}

test "packedLength" {
    const E = enum(u8) {
        a,
        b,
        c,
    };

    const U = packed union {
        tag: E,
        a: packed struct {
            tag: E,
        },
        b: packed struct {
            tag: E,
            a: u8,
        },
        c: packed struct {
            tag: E,
            a: u16,
        },
    };

    try testPackedLength(U{ .a = .{ .tag = E.a } }, 1);
    try testPackedLength(U{ .b = .{ .tag = E.b, .a = 0 } }, 2);
    try testPackedLength(U{ .c = .{ .tag = E.c, .a = 0 } }, 3);
}

pub fn CommandDecoder(comptime Command: type, comptime isEnd: fn (Command) bool) type {
    return struct {
        bytes: []u8,
        i: usize = 0,

        pub fn next(decoder: *@This()) !?*align(1) Command {
            const bytes = decoder.bytes[decoder.i..];
            if (bytes.len == 0)
                return null;

            var buf = [_]u8{0} ** @sizeOf(Command);
            const len = math.min(bytes.len, buf.len);

            // Copy the bytes to a buffer of size @sizeOf(Command).
            // The reason this is done is that s.len might be smaller
            // than @sizeOf(Command) but still contain a command because
            // encoded commands can be smaller that @sizeOf(Command).
            // If the command we are trying to decode is invalid this
            // will be caught by the calculation of the commands length.
            mem.copy(u8, &buf, bytes[0..len]);

            const command = mem.bytesAsSlice(Command, buf[0..])[0];
            const command_len = try packedLength(command);
            if (decoder.bytes.len - decoder.i < command_len)
                return error.InvalidCommand;

            decoder.i += command_len;
            if (isEnd(command))
                decoder.bytes = decoder.bytes[0..decoder.i];

            return @ptrCast(*align(1) Command, bytes.ptr);
        }
    };
}
