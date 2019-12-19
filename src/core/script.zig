const builtin = @import("builtin");
const std = @import("std");

const meta = std.meta;
const trait = meta.trait;
const mem = std.mem;
const math = std.math;
const testing = std.testing;

/// Find the field name which is most likly to be the tag of 'union_field'.
/// This function looks at all fields declared before 'union_field'. If one
/// of these field is an enum which has the same fields as the 'union_field's
/// type, then that is assume to be the tag of 'union_field'.
pub fn findTagFieldName(comptime Container: type, comptime union_field: []const u8) ?[]const u8 {
    if (!trait.is(builtin.TypeId.Struct)(Container))
        @compileError(@typeName(Container) ++ " is not a struct.");

    const container_fields = meta.fields(Container);
    const u_index = for (container_fields) |f, i| {
        if (mem.eql(u8, f.name, union_field))
            break i;
    } else {
        @compileError("No field called " ++ union_field ++ " in " ++ @typeName(Container));
    };

    const Union = container_fields[u_index].field_type;
    if (!trait.is(builtin.TypeId.Union)(Union))
        @compileError(union_field ++ " is not a union.");

    // Check all fields before 'union_field'.
    outer: for (container_fields[0..u_index]) |field| {
        const Enum = field.field_type;
        if (!trait.is(builtin.TypeId.Enum)(Enum))
            continue;

        // Check if 'Enum' and 'Union' have the same names
        // of their fields.
        const u_fields = meta.fields(Union);
        const e_fields = meta.fields(Enum);
        if (u_fields.len != e_fields.len)
            continue;

        // The 'Enum' and 'Union' have to have the same fields
        // in the same order. It's too slow otherwise (an it keeps
        // this impl simple)
        for (u_fields) |u_field, i| {
            const e_field = e_fields[i];
            if (!mem.eql(u8, u_field.name, e_field.name))
                continue :outer;
        }

        return field.name;
    }

    return null;
}

fn testFindTagFieldName(comptime Container: type, comptime union_field: []const u8, expect: ?[]const u8) void {
    if (comptime findTagFieldName(Container, union_field)) |actual| {
        testing.expectEqualSlices(u8, expect.?, actual);
    } else {
        testing.expectEqual(expect, null);
    }
}

test "findTagFieldName" {
    const Union = union {
        A: void,
        B: u8,
        C: u16,
    };

    const Tag = enum {
        A,
        B,
        C,
    };
    testFindTagFieldName(struct {
        tag: Tag,
        un: Union,
    }, "un", "tag");
    testFindTagFieldName(struct {
        tag: Tag,
        not_tag: u8,
        un: Union,
        not_tag2: struct {},
        not_tag3: enum {
            A,
            B,
            Q,
        },
    }, "un", "tag");
    testFindTagFieldName(struct {
        not_tag: u8,
        un: Union,
        not_tag2: struct {},
        not_tag3: enum {
            A,
            B,
            Q,
        },
    }, "un", null);
}

/// Calculates the packed size of 'value'. The packed size is the size 'value'
/// would have if unions did not have to have the size of their biggest field.
pub fn packedLength(value: var) error{InvalidTag}!usize {
    @setEvalBranchQuota(10000000);
    const T = @typeOf(value);
    switch (@typeInfo(T)) {
        builtin.TypeId.Void => return 0,
        builtin.TypeId.Int => |i| {
            if (i.bits % 8 != 0)
                @compileError("Does not support none power of two intergers");
            return usize(i.bits / 8);
        },
        builtin.TypeId.Enum => |e| {
            if (e.layout != builtin.TypeInfo.ContainerLayout.Packed)
                @compileError(@typeName(T) ++ " is not packed");

            return packedLength(@enumToInt(value)) catch unreachable;
        },
        builtin.TypeId.Array => |a| {
            var res: usize = 0;
            for (value) |item|
                res += try packedLength(item);

            return res;
        },
        builtin.TypeId.Struct => |s| {
            if (s.layout != builtin.TypeInfo.ContainerLayout.Packed)
                @compileError(@typeName(T) ++ " is not packed");

            var res: usize = 0;
            inline for (s.fields) |struct_field|
                switch (@typeInfo(struct_field.field_type)) {
                    builtin.TypeId.Union => |u| {
                        if (u.layout != .Packed and u.layout != .Extern)
                            @compileError(@typeName(struct_field.field_type) ++ " is not packed or extern");
                        if (u.tag_type != null)
                            @compileError(@typeName(struct_field.field_type) ++ " cannot have a tag.");

                        // Find the field most likly to be this unions tag.
                        const tag_field = (comptime findTagFieldName(T, struct_field.name)) orelse
                            @compileError("Could not find a tag for " ++ struct_field.name);
                        const tag = @field(value, tag_field);
                        const union_value = @field(value, struct_field.name);
                        const TagEnum = @typeOf(tag);

                        // Switch over all tags. 'TagEnum' have the same field names as
                        // 'union' so if one member of 'TagEnum' matches 'tag', then
                        // we can add the size of ''@field(union, tag_name)' to res and
                        // break out.
                        var found: bool = false;
                        inline for (@typeInfo(TagEnum).Enum.fields) |enum_field| {
                            if (@field(TagEnum, enum_field.name) == tag) {
                                const union_field = @field(union_value, enum_field.name);
                                res += try packedLength(union_field);
                                found = true;
                            }
                        }

                        // If no member of 'TagEnum' match, then 'tag' must be a value
                        // it is not suppose to be.
                        if (!found)
                            return error.InvalidTag;
                    },
                    else => res += try packedLength(@field(value, struct_field.name)),
                };
            return res;
        },
        else => @compileError(@typeName(T) ++ " not supported"),
    }
}

fn testPackedLength(value: var, expect: error{InvalidTag}!usize) void {
    if (packedLength(value)) |size| {
        const expected_size = expect catch unreachable;
        testing.expectEqual(expected_size, size);
    } else |err| {
        const expected_err = if (expect) |_| unreachable else |e| e;
        testing.expectEqual(expected_err, err);
    }
}

test "packedLength" {
    const E = packed enum(u8) {
        A,
        B,
        C,
    };

    const U = packed union {
        A: void,
        B: u8,
        C: u16,
    };

    const S = packed struct {
        tag: E,
        pad: u8,
        data: U,
    };

    testPackedLength(S{ .tag = E.A, .pad = 0, .data = U{ .A = {} } }, 2);
    testPackedLength(S{ .tag = E.B, .pad = 0, .data = U{ .B = 0 } }, 3);
    testPackedLength(S{ .tag = E.C, .pad = 0, .data = U{ .C = 0 } }, 4);
}

pub fn CommandDecoder(comptime Command: type, comptime isEnd: fn (Command) bool) type {
    return struct {
        bytes: []u8,
        i: usize = 0,

        pub fn next(decoder: *@This()) !?*Command {
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

            const command = @bytesToSlice(Command, buf[0..])[0];
            const command_len = try packedLength(command);
            if (decoder.bytes.len < command_len)
                return error.InvalidCommand;

            decoder.i += command_len;
            if (isEnd(command))
                decoder.bytes = decoder.bytes[0..decoder.i];

            return @ptrCast(*Command, bytes.ptr);
        }
    };
}
