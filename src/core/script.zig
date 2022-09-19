const builtin = @import("builtin");
const std = @import("std");

const math = std.math;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const trait = meta.trait;

/// Find the field name which is most likly to be the tag of 'union_field'.
/// This function looks at all fields declared before 'union_field'. If one
/// of these field is an enum which has the same fields as the 'union_field's
/// type, then that is assume to be the tag of 'union_field'.
pub fn findTagFieldName(comptime Container: type, comptime union_field: []const u8) ?[]const u8 {
    const info = @typeInfo(Container);
    if (info != .Struct)
        @compileError(@typeName(Container) ++ " is not a struct.");

    const container_fields = info.Struct.fields;
    const u_index = for (container_fields) |f, i| {
        if (mem.eql(u8, f.name, union_field))
            break i;
    } else {
        @compileError("No field called " ++ union_field ++ " in " ++ @typeName(Container));
    };

    const union_info = @typeInfo(container_fields[u_index].field_type);
    if (union_info != .Union)
        @compileError(union_field ++ " is not a union.");

    // Check all fields before 'union_field'.
    outer: for (container_fields) |field, i| {
        if (u_index <= i)
            break;
        const Enum = field.field_type;
        const enum_info = @typeInfo(Enum);
        if (enum_info != .Enum)
            continue;

        // Check if 'Enum' and 'Union' have the same names
        // of their fields.
        const u_fields = union_info.Union.fields;
        const e_fields = enum_info.Enum.fields;
        if (u_fields.len != e_fields.len)
            continue;

        // The 'Enum' and 'Union' have to have the same fields
        for (u_fields) |u_field| {
            if (!@hasField(Enum, u_field.name))
                continue :outer;
        }

        return field.name;
    }

    return null;
}

fn testFindTagFieldName(comptime Container: type, comptime union_field: []const u8, expect: ?[]const u8) !void {
    if (comptime findTagFieldName(Container, union_field)) |actual| {
        try testing.expectEqualStrings(expect.?, actual);
    } else {
        try testing.expectEqual(expect, null);
    }
}

test "findTagFieldName" {
    const Union = union {
        a: void,
        b: u8,
        c: u16,
    };

    const Tag = enum {
        a,
        b,
        c,
    };
    try testFindTagFieldName(struct {
        tag: Tag,
        un: Union,
    }, "un", "tag");
    try testFindTagFieldName(struct {
        tag: Tag,
        not_tag: u8,
        un: Union,
        not_tag2: struct {},
        not_tag3: enum {
            a,
            b,
            q,
        },
    }, "un", "tag");
    try testFindTagFieldName(struct {
        not_tag: u8,
        un: Union,
        not_tag2: struct {},
        not_tag3: enum {
            a,
            b,
            q,
        },
    }, "un", null);
}

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
        a: void,
        b: u8,
        c: u16,
    };

    const S = packed struct {
        tag: E,
        pad: u8,
        data: U,
    };

    try testPackedLength(S{ .tag = E.a, .pad = 0, .data = U{ .a = {} } }, 2);
    try testPackedLength(S{ .tag = E.b, .pad = 0, .data = U{ .b = 0 } }, 3);
    try testPackedLength(S{ .tag = E.c, .pad = 0, .data = U{ .c = 0 } }, 4);
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
