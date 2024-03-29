const clap = @import("clap");
const core = @import("core");
const std = @import("std");
const util = @import("util");

const fs = std.fs;
const heap = std.heap;
const io = std.io;
const log = std.log;
const math = std.math;
const mem = std.mem;

const gen3 = core.gen3;
const gen4 = core.gen4;
const gen5 = core.gen5;
const rom = core.rom;
const script = core.script;

const li16 = rom.int.li16;
const li32 = rom.int.li32;
const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;

const nds = rom.nds;

const Program = @This();

allocator: mem.Allocator,
file: []const u8,

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Finds all scripts in a Pokemon game, disassembles them and writes them to stdout.
    \\
;

pub const parsers = .{
    .ROM = clap.parsers.string,
};

pub const params = clap.parseParamsComptime(
    \\-h, --help
    \\        Display this help text and exit.
    \\-v, --version
    \\        Output version information and exit.
    \\
    \\<ROM>
    \\
);

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const pos = args.positionals;
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
    var m_nds_rom = nds.Rom.fromFile(file, allocator);
    if (m_nds_rom) |*nds_rom| {
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

fn outputGen3GameScripts(game: gen3.Game, writer: anytype) !void {
    @setEvalBranchQuota(100000);
    for (game.map_headers, 0..) |map_header, map_id| {
        const scripts = try map_header.map_scripts.toSliceEnd(game.data);

        for (scripts, 0..) |*s, script_id| {
            if (s.type == 0)
                break;
            if (s.type == 2 or s.type == 4)
                continue;

            const script_data = try s.addr.other.toSliceEnd(game.data);
            var decoder = gen3.script.CommandDecoder{ .bytes = script_data };
            try writer.print("map_header[{}].map_script[{}]:\n", .{ map_id, script_id });
            while (try decoder.next()) |command|
                try printCommand(writer, command.*, decoder);

            try writer.writeAll("\n");
        }

        const events = try map_header.map_events.toPtr(game.data);
        for (try events.obj_events.toSlice(game.data, events.obj_events_len), 0..) |obj_event, script_id| {
            const script_data = obj_event.script.toSliceEnd(game.data) catch continue;
            var decoder = gen3.script.CommandDecoder{ .bytes = script_data };
            try writer.print("map_header[{}].obj_events[{}]:\n", .{ map_id, script_id });
            while (try decoder.next()) |command|
                try printCommand(writer, command.*, decoder);

            try writer.writeAll("\n");
        }

        for (try events.coord_events.toSlice(game.data, events.coord_events_len), 0..) |coord_event, script_id| {
            const script_data = coord_event.scripts.toSliceEnd(game.data) catch continue;
            var decoder = gen3.script.CommandDecoder{ .bytes = script_data };
            try writer.print("map_header[{}].coord_event[{}]:\n", .{ map_id, script_id });
            while (try decoder.next()) |command|
                try printCommand(writer, command.*, decoder);

            try writer.writeAll("\n");
        }
    }
}

fn outputGen4GameScripts(game: gen4.Game, allocator: mem.Allocator, writer: anytype) anyerror!void {
    @setEvalBranchQuota(100000);
    for (game.ptrs.scripts.fat, 0..) |_, script_i| {
        const script_data = game.ptrs.scripts.fileData(.{ .i = @intCast(script_i) });
        var offsets = std.ArrayList(isize).init(allocator);
        defer offsets.deinit();

        for (gen4.script.getScriptOffsets(script_data), 0..) |relative_offset, i| {
            const offset = relative_offset.value() + @as(isize, @intCast(i + 1)) * @sizeOf(lu32);
            if (@as(isize, @intCast(script_data.len)) < offset)
                continue;
            if (offset < 0)
                continue;
            try offsets.append(offset);
        }

        var offset_i: usize = 0;
        while (offset_i < offsets.items.len) : (offset_i += 1) {
            const offset = offsets.items[offset_i];
            try writer.print("script[{}]@0x{x}:\n", .{ script_i, offset });
            if (@as(isize, @intCast(script_data.len)) < offset)
                continue;
            if (offset < 0)
                continue;

            var decoder = gen4.script.CommandDecoder{
                .bytes = script_data,
                .i = @intCast(offset),
            };
            while (decoder.next() catch {
                const rest = decoder.bytes[decoder.i..];
                switch (rest.len) {
                    0 => try writer.print("\tEnd\t@0x{x}\n", .{decoder.i}),
                    1 => try writer.print("\tUnknown(0x{x:0>2})\t@0x{x}\n", .{
                        rest[0],
                        decoder.i,
                    }),
                    else => try writer.print("\tUnknown(0x{x:0>4})\t@0x{x}\n", .{
                        @as(lu16, @enumFromInt(@as(u16, @bitCast(rest[0..2].*)))).value(),
                        decoder.i,
                    }),
                }
                continue;
            }) |command| {
                try printCommand(writer, command.*, decoder);

                switch (command.kind) {
                    .jump, .compare_last_result_jump, .call, .compare_last_result_call => {
                        const off = switch (command.kind) {
                            .compare_last_result_call => command.compare_last_result_call.adr.value(),
                            .call => command.call.adr.value(),
                            .jump => command.jump.adr.value(),
                            .compare_last_result_jump => command.compare_last_result_jump.adr.value(),
                            else => unreachable,
                        };
                        const location = off + @as(isize, @intCast(decoder.i));
                        if (mem.indexOfScalar(isize, offsets.items, location) == null)
                            try offsets.append(location);
                    },
                    else => {},
                }
            }
        }
    }
}

fn outputGen5GameScripts(game: gen5.Game, allocator: mem.Allocator, writer: anytype) anyerror!void {
    @setEvalBranchQuota(100000);
    for (game.ptrs.scripts.fat, 0..) |_, script_i| {
        const script_data = game.ptrs.scripts.fileData(.{ .i = @intCast(script_i) });

        var offsets = std.ArrayList(usize).init(allocator);
        defer offsets.deinit();

        for (gen5.script.getScriptOffsets(script_data), 0..) |relative, i| {
            const position = @as(isize, @intCast(i + 1)) * @sizeOf(lu32);
            const offset = math.cast(usize, relative.value() + position) orelse continue;
            if (script_data.len < offset)
                continue;
            try offsets.append(offset);
        }

        var offset_i: usize = 0;
        while (offset_i < offsets.items.len) : (offset_i += 1) {
            const offset = offsets.items[offset_i];
            try writer.print("script[{}]@0x{x}:\n", .{ script_i, offset });

            var decoder = gen5.script.CommandDecoder{
                .bytes = script_data,
                .i = offset,
            };
            while (decoder.next() catch {
                const rest = decoder.bytes[decoder.i..];
                switch (rest.len) {
                    0 => try writer.print("\tEnd\t@0x{x}\n", .{decoder.i}),
                    1 => try writer.print("\tUnknown(0x{x:0>2})\t@0x{x}\n", .{
                        rest[0],
                        decoder.i,
                    }),
                    else => try writer.print("\tUnknown(0x{x:0>4})\t@0x{x}\n", .{
                        @as(lu16, @enumFromInt(@as(u16, @bitCast(rest[0..2].*)))).value(),
                        decoder.i,
                    }),
                }
                continue;
            }) |command| {
                try printCommand(writer, command.*, decoder);

                switch (command.kind) {
                    .jump, .@"if", .call_routine => {
                        const off = switch (command.kind) {
                            .jump => command.jump.offset.value(),
                            .@"if" => command.@"if".offset.value(),
                            .call_routine => command.call_routine.offset.value(),
                            else => unreachable,
                        };
                        if (math.cast(usize, off + @as(isize, @intCast(decoder.i)))) |loc| {
                            if (loc < script_data.len and
                                mem.indexOfScalar(usize, offsets.items, loc) == null)
                                try offsets.append(loc);
                        }
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

    // lu16 and lu16 are seen as enums, but really they should be treated
    // the same as int values.
    if (T == lu16)
        return printCommandHelper(writer, value.value());
    if (T == lu32)
        return printCommandHelper(writer, value.value());
    if (T == li16)
        return printCommandHelper(writer, value.value());
    if (T == li32)
        return printCommandHelper(writer, value.value());

    // Inferred error sets enforce us to have to return an error somewhere. This
    // messes up with the below comptime branch selection, where some branches
    // does not return any errors.
    try writer.writeAll("");
    switch (@typeInfo(T)) {
        .Void => {},
        .Int => try writer.print("{}", .{value}),
        .Enum => try writer.print("{s}", .{@tagName(value)}),
        .Array => for (value) |v| {
            try printCommandHelper(writer, v);
        },
        .Struct => |s| {
            inline for (s.fields, 0..) |struct_field, i| {
                try printCommandHelper(writer, @field(value, struct_field.name));
                if (i + 1 != s.fields.len)
                    try writer.writeAll(" ");
            }
        },
        .Union => |u| {
            if (u.layout != .Packed and u.layout != .Extern)
                @compileError(@typeName(T) ++ " is not packed or extern");
            if (u.tag_type != null)
                @compileError(@typeName(T) ++ " cannot have a tag.");

            const tag_field = u.fields[0];
            const tag = @field(value, tag_field.name);
            const TagEnum = @TypeOf(tag);

            inline for (@typeInfo(TagEnum).Enum.fields) |enum_field| {
                if (@field(TagEnum, enum_field.name) == tag) {
                    const union_field = @field(value, enum_field.name);
                    return printCommandHelper(writer, union_field);
                }
            }

            return error.InvalidTag;
        },
        else => @compileError(@typeName(T) ++ " not supported"),
    }
}
