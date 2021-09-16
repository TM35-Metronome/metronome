const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const gen3 = @import("gen3.zig");
const gen4 = @import("gen4.zig");
const gen5 = @import("gen5.zig");
const rom = @import("rom.zig");
const script = @import("script.zig");

const fs = std.fs;
const heap = std.heap;
const io = std.io;
const log = std.log;
const math = std.math;
const mem = std.mem;

const li16 = rom.int.li16;
const li32 = rom.int.li32;
const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;

const nds = rom.nds;

const Program = @This();

allocator: *mem.Allocator,
file: []const u8,

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Finds all scripts in a Pokemon game, disassembles them and writes them to stdout.
    \\
;

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam("-h, --help     Display this help text and exit.    ") catch unreachable,
    clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
    clap.parseParam("<ROM>") catch unreachable,
};

pub fn init(allocator: *mem.Allocator, args: anytype) !Program {
    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else return error.MissingFile;

    return Program{
        .allocator = allocator,
        .file = file_name,
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    const allocator = program.allocator;
    const file = try fs.cwd().openFile(program.file, .{});
    defer file.close();

    const gen3_error = if (gen3.Game.fromFile(file, allocator)) |*game| {
        defer game.deinit();
        try outputGen3GameScripts(game.*, stdio.out);
        return;
    } else |err| err;

    try file.seekTo(0);
    if (nds.Rom.fromFile(file, allocator)) |*nds_rom| {
        const gen4_error = if (gen4.Game.fromRom(allocator, nds_rom)) |*game| {
            defer game.deinit();
            try outputGen4GameScripts(game.*, allocator, stdio.out);
            return;
        } else |err| err;

        const gen5_error = if (gen5.Game.fromRom(allocator, nds_rom)) |*game| {
            defer game.deinit();
            try outputGen5GameScripts(game.*, allocator, stdio.out);
            return;
        } else |err| err;

        log.info("Successfully loaded '{s}' as a nds rom.", .{program.file});
        log.err("Failed to load '{s}' as a gen4 game: {}", .{ program.file, gen4_error });
        log.err("Failed to load '{s}' as a gen5 game: {}", .{ program.file, gen5_error });
        return gen5_error;
    } else |nds_error| {
        log.err("Failed to load '{s}' as a gen3 game: {}", .{ program.file, gen3_error });
        log.err("Failed to load '{s}' as a gen4/gen5 game: {}", .{ program.file, nds_error });
        return nds_error;
    }
}

pub fn deinit(program: Program) void {}

fn outputGen3GameScripts(game: gen3.Game, writer: anytype) !void {
    @setEvalBranchQuota(100000);
    for (game.map_headers) |map_header, map_id| {
        const scripts = try map_header.map_scripts.toSliceEnd(game.data);

        for (scripts) |s, script_id| {
            if (s.@"type" == 0)
                break;
            if (s.@"type" == 2 or s.@"type" == 4)
                continue;

            const script_data = try s.addr.other.toSliceEnd(game.data);
            var decoder = gen3.script.CommandDecoder{ .bytes = script_data };
            try writer.print("map_header[{}].map_script[{}]:\n", .{ map_id, script_id });
            while (try decoder.next()) |command|
                try printCommand(writer, command.*, decoder);

            try writer.writeAll("\n");
        }

        const events = try map_header.map_events.toPtr(game.data);
        for (try events.obj_events.toSlice(game.data, events.obj_events_len)) |obj_event, script_id| {
            const script_data = obj_event.script.toSliceEnd(game.data) catch continue;
            var decoder = gen3.script.CommandDecoder{ .bytes = script_data };
            try writer.print("map_header[{}].obj_events[{}]:\n", .{ map_id, script_id });
            while (try decoder.next()) |command|
                try printCommand(writer, command.*, decoder);

            try writer.writeAll("\n");
        }

        for (try events.coord_events.toSlice(game.data, events.coord_events_len)) |coord_event, script_id| {
            const script_data = coord_event.scripts.toSliceEnd(game.data) catch continue;
            var decoder = gen3.script.CommandDecoder{ .bytes = script_data };
            try writer.print("map_header[{}].coord_event[{}]:\n", .{ map_id, script_id });
            while (try decoder.next()) |command|
                try printCommand(writer, command.*, decoder);

            try writer.writeAll("\n");
        }
    }
}

fn outputGen4GameScripts(game: gen4.Game, allocator: *mem.Allocator, writer: anytype) anyerror!void {
    @setEvalBranchQuota(100000);
    for (game.ptrs.scripts.fat) |_, script_i| {
        const script_data = game.ptrs.scripts.fileData(.{ .i = @intCast(u32, script_i) });
        var offsets = std.ArrayList(isize).init(allocator);
        defer offsets.deinit();

        for (gen4.script.getScriptOffsets(script_data)) |relative_offset, i| {
            const offset = relative_offset.value() + @intCast(isize, i + 1) * @sizeOf(lu32);
            if (@intCast(isize, script_data.len) < offset)
                continue;
            if (offset < 0)
                continue;
            try offsets.append(offset);
        }

        var offset_i: usize = 0;
        while (offset_i < offsets.items.len) : (offset_i += 1) {
            const offset = offsets.items[offset_i];
            try writer.print("script[{}]@0x{x}:\n", .{ script_i, offset });
            if (@intCast(isize, script_data.len) < offset)
                continue;
            if (offset < 0)
                continue;

            var decoder = gen4.script.CommandDecoder{
                .bytes = script_data,
                .i = @intCast(usize, offset),
            };
            while (decoder.next() catch {
                const rest = decoder.bytes[decoder.i..];
                try writer.print("\tUnknown(0x{x})\t@0x{x}\n", .{
                    std.fmt.fmtSliceHexLower(rest[0..math.min(rest.len, 2)]),
                    decoder.i,
                });
                continue;
            }) |command| {
                try printCommand(writer, command.*, decoder);

                switch (command.tag) {
                    .jump, .compare_last_result_jump, .call, .compare_last_result_call => {
                        const off = switch (command.tag) {
                            .compare_last_result_call => command.data().compare_last_result_call.adr.value(),
                            .call => command.data().call.adr.value(),
                            .jump => command.data().jump.adr.value(),
                            .compare_last_result_jump => command.data().compare_last_result_jump.adr.value(),
                            else => unreachable,
                        };
                        const location = off + @intCast(isize, decoder.i);
                        if (mem.indexOfScalar(isize, offsets.items, location) == null)
                            try offsets.append(location);
                    },
                    else => {},
                }
            }
        }
    }
}

fn outputGen5GameScripts(game: gen5.Game, allocator: *mem.Allocator, writer: anytype) anyerror!void {
    @setEvalBranchQuota(100000);
    for (game.ptrs.scripts.fat) |_, script_i| {
        const script_data = game.ptrs.scripts.fileData(.{ .i = @intCast(u32, script_i) });

        var offsets = std.ArrayList(isize).init(allocator);
        defer offsets.deinit();

        for (gen5.script.getScriptOffsets(script_data)) |relative_offset, i| {
            const offset = relative_offset.value() + @intCast(isize, i + 1) * @sizeOf(lu32);
            if (@intCast(isize, script_data.len) < offset)
                continue;
            if (offset < 0)
                continue;
            try offsets.append(offset);
        }

        var offset_i: usize = 0;
        while (offset_i < offsets.items.len) : (offset_i += 1) {
            const offset = offsets.items[offset_i];
            try writer.print("script[{}]@0x{x}:\n", .{ script_i, offset });
            if (@intCast(isize, script_data.len) < offset)
                return error.Error;
            if (offset < 0)
                return error.Error;

            var decoder = gen5.script.CommandDecoder{
                .bytes = script_data,
                .i = @intCast(usize, offset),
            };
            while (decoder.next() catch {
                const rest = decoder.bytes[decoder.i..];
                try writer.print("\tUnknown(0x{x})\t@0x{x}\n", .{
                    std.fmt.fmtSliceHexLower(rest[0..math.min(rest.len, 2)]),
                    decoder.i,
                });
                continue;
            }) |command| {
                try printCommand(writer, command.*, decoder);

                switch (command.tag) {
                    .jump, .@"if" => {
                        const off = switch (command.tag) {
                            .jump => command.data().jump.offset.value(),
                            .@"if" => command.data().@"if".offset.value(),
                            else => unreachable,
                        };
                        const location = off + @intCast(isize, decoder.i);
                        if (mem.indexOfScalar(isize, offsets.items, location) == null)
                            try offsets.append(location);
                    },
                    else => {},
                }
            }
        }
    }
}

fn printCommand(writer: anytype, command: anytype, decoder: anytype) !void {
    try writer.writeAll("\t");
    try printCommandHelper(writer, command);
    try writer.print("\t@0x{x}\n", .{decoder.i - try script.packedLength(command)});
}

fn printCommandHelper(writer: anytype, value: anytype) !void {
    const T = @TypeOf(value);

    // Infered error sets enforce us to have to return an error somewhere. This
    // messes up with the below comptime branch selection, where some branches
    // does not return any errors.
    try writer.writeAll("");
    switch (@typeInfo(T)) {
        .Void => {},
        .Int => |i| try writer.print("{}", .{value}),
        .Enum => |e| try writer.print("{s}", .{@tagName(value)}),
        .Array => for (value) |v| {
            try printCommandHelper(writer, v);
        },
        .Struct => |s| {
            // lu16 and lu16 are seen as structs, but really they should be treated
            // the same as int values.
            if (T == lu16)
                return printCommandHelper(writer, value.value());
            if (T == lu32)
                return printCommandHelper(writer, value.value());
            if (T == li16)
                return printCommandHelper(writer, value.value());
            if (T == li32)
                return printCommandHelper(writer, value.value());

            inline for (s.fields) |struct_field, i| {
                switch (@typeInfo(struct_field.field_type)) {
                    .Union => |u| {
                        if (u.tag_type != null)
                            @compileError(@typeName(struct_field.field_type) ++ " cannot have a tag.");

                        // Find the field most likly to be this unions tag.
                        const tag_field = (comptime script.findTagFieldName(T, struct_field.name)) orelse
                            @compileError("Could not find a tag for " ++ struct_field.name);
                        const tag = @field(value, tag_field);
                        const union_value = @field(value, struct_field.name);
                        const TagEnum = @TypeOf(tag);

                        var found: bool = true;
                        inline for (@typeInfo(TagEnum).Enum.fields) |enum_field| {
                            if (@field(TagEnum, enum_field.name) == tag) {
                                try printCommandHelper(writer, @field(union_value, enum_field.name));
                                found = true;
                            }
                        }

                        // @"if" no member of 'TagEnum' match, then 'tag' must be a value
                        // it is not suppose to be.
                        if (!found)
                            return error.InvalidTag;
                    },
                    else => try printCommandHelper(writer, @field(value, struct_field.name)),
                }
                if (i + 1 != s.fields.len)
                    try writer.writeAll(" ");
            }
        },
        else => @compileError(@typeName(T) ++ " not supported"),
    }
}
