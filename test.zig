const builtin = @import("builtin");
const std = @import("std");

const meta = std.meta;
const trait = meta.trait;
const mem = std.mem;
const debug = std.debug;

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
        found: for (meta.fields(Union)) |u_field| {
            for (meta.fields(Enum)) |e_field| {
                if (mem.eql(u8, u_field.name, e_field.name))
                    continue :found;
            }

            continue :outer;
        }

        return field.name;
    }

    return null;
}

fn testFindTagFieldName(comptime Container: type, comptime union_field: []const u8, expect: ?[]const u8) void {
    if (comptime findTagFieldName(Container, union_field)) |actual| {
        debug.assertOrPanic(expect != null);
        debug.assertOrPanic(mem.eql(u8, expect.?, actual));
    } else {
        debug.assertOrPanic(expect == null);
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
        builtin.TypeId.Struct => |s| {
            if (s.layout != builtin.TypeInfo.ContainerLayout.Packed)
                @compileError(@typeName(T) ++ " is not packed");

            var res: usize = 0;
            inline for (s.fields) |struct_field|
                switch (@typeInfo(struct_field.field_type)) {
                builtin.TypeId.Union => |u| next: {
                    if (u.layout != builtin.TypeInfo.ContainerLayout.Packed)
                        @compileError(@typeName(struct_field.field_type) ++ " is not packed");
                    if (u.tag_type != null)
                        @compileError(@typeName(struct_field.field_type) ++ " cannot have a tag.");

                    // Find the field most likly to be this unions tag.
                    const tag_field = (comptime findTagFieldName(T, struct_field.name)) orelse @compileError("Could not find a tag for " ++ struct_field.name);
                    const tag = @field(value, tag_field);
                    const union_value = @field(value, struct_field.name);
                    const TagEnum = @typeOf(tag);

                    // Switch over all tags. 'TagEnum' have the same field names as
                    // 'union' so if one member of 'TagEnum' matches 'tag', then
                    // we can add the size of ''@field(union, tag_name)' to res and
                    // break out.
                    inline for (@typeInfo(TagEnum).Enum.fields) |enum_field| {
                        if (@field(TagEnum, enum_field.name) == tag) {
                            const union_field = @field(union_value, enum_field.name);
                            res += try packedLength(union_field);
                            break :next;
                        }
                    }

                    // If no member of 'TagEnum' match, then 'tag' must be a value
                    // it is not suppose to be.
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
        debug.assertOrPanic(size == expected_size);
    } else |err| {
        const expected_err = if (expect) |_| unreachable else |e| e;
        debug.assertOrPanic(expected_err == err);
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
