name: []const u8,
description: []const u8,
parameters: []const Parameter,
createOptions: Options.Create,
function: *const fn (std.mem.Allocator, Options, *core.Game) anyerror!void,

pub const all = [_]Command{
    @import("cmd/starters.zig").command,
    @import("cmd/static-encounters.zig").command,
    @import("cmd/trainers.zig").command,
    @import("cmd/wiki.zig").command,
    @import("cmd/wild-encounters.zig").command,
};

pub fn find(name: []const u8) ?*const Command {
    for (&all) |*command| {
        if (std.mem.eql(u8, name, command.name))
            return command;
    }

    return null;
}

pub const Parameter = struct {
    type: Type,
    name: []const u8,
    desc: []const u8,
    options: []const []const u8 = &.{},

    pub fn init(comptime T: type, name: []const u8, desc: []const u8) Parameter {
        return switch (@typeInfo(T)) {
            .bool => .{ .type = .bool, .name = name, .desc = desc },
            .int => |i| switch (i.signedness) {
                .unsigned => .{ .type = .unsigned_int, .name = name, .desc = desc },
                .signed => .{ .type = .signed_int, .name = name, .desc = desc },
            },
            .@"enum" => .{ .type = .enumeration, .name = name, .desc = desc, .options = std.meta.fieldNames(T) },
            else => comptime unreachable,
        };
    }

    pub fn fromType(comptime T: type, comptime desc: Desc(T)) []const Parameter {
        return comptime blk: {
            const fields = std.meta.fields(T);
            var params: [fields.len]Parameter = undefined;
            for (&params, fields) |*param, field| {
                param.* = .init(field.type, field.name, @field(desc, field.name).desc);
            }

            const res = params;
            break :blk &res;
        };
    }

    pub fn Desc(comptime T: type) type {
        const DescField = struct {
            desc: []const u8 = "",
        };

        const t_fields = std.meta.fields(T);
        var fields: [t_fields.len]std.builtin.Type.StructField = undefined;
        for (&fields, t_fields) |*res, field| {
            res.* = .{
                .name = field.name,
                .type = DescField,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(DescField),
            };
        }
        return @Type(.{ .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    }

    pub const Type = enum {
        bool,
        enumeration,
        signed_int,
        unsigned_int,
    };
};

pub const Options = struct {
    ptr: Ptr,
    set: Set,

    pub const Ptr = *opaque {};
    pub const Create = *const fn (std.mem.Allocator) anyerror!Options;
    pub const Set = *const fn (Options, std.mem.Allocator, []const u8, []const u8) anyerror!void;

    pub fn cast(options: Options, comptime T: type) *T {
        return @ptrCast(@alignCast(options.ptr));
    }

    pub fn createFromType(comptime T: type) Create {
        return struct {
            fn create(arena: std.mem.Allocator) anyerror!Options {
                const data = try arena.create(T);
                data.* = .{};

                return .{
                    .ptr = @ptrCast(data),
                    .set = setFromType(T),
                };
            }
        }.create;
    }

    pub fn setFromType(comptime T: type) Set {
        return struct {
            fn set(options: Options, _: std.mem.Allocator, name: []const u8, value: []const u8) anyerror!void {
                const data = options.cast(T);
                inline for (std.meta.fields(T)) |field| loop_block: {
                    if (!std.mem.eql(u8, field.name, name))
                        break :loop_block;

                    switch (@typeInfo(field.type)) {
                        .int => @field(data, field.name) = try std.fmt.parseInt(field.type, value, 0),
                        .@"enum" => @field(data, field.name) = std.meta.stringToEnum(field.type, value) orelse
                            return error.InvalidString,
                        .bool => {
                            const res = std.meta.stringToEnum(enum { false, true }, value) orelse
                                return error.InvalidString;
                            @field(data, field.name) = res == .true;
                        },
                        else => return error.UnsupportedType,
                    }
                    return;
                }

                return error.NoFieldWithName;
            }
        }.set;
    }
};

test {
    _ = all;
    _ = core;
}

const Command = @This();

const core = @import("core.zig");

const std = @import("std");
