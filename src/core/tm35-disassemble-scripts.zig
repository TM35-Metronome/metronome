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
const mem = std.mem;

const errors = util.errors;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const li16 = rom.int.li16;
const li32 = rom.int.li32;

const nds = rom.nds;

const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);

const Clap = clap.ComptimeClap(clap.Help, params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

const params = [_]Param{
    clap.parseParam("-h, --help     Display this help text and exit.    ") catch unreachable,
    clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
    Param{ .takes_value = true },
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-gen3-disassemble-scripts [-hv] <FILE>
        \\Finds all scripts in a generation 3 Pokemon game, disassembles them
        \\and writes them to stdout.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    var stdio_unbuf = util.getStdIo() catch |err| return 1;
    var stdio = stdio_unbuf.getBuffered();
    defer stdio.err.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(&arena.allocator) catch
        return errors.allocErr(&stdio.err.stream);
    const res = main2(
        &arena.allocator,
        fs.File.ReadError,
        fs.File.WriteError,
        stdio.getStreams(),
        clap.args.OsIterator,
        &arg_iter,
    );

    stdio.out.flush() catch |err| return errors.writeErr(&stdio.err.stream, "<stdout>", err);
    return res;
}

pub fn main2(
    allocator: *mem.Allocator,
    comptime ReadError: type,
    comptime WriteError: type,
    stdio: util.CustomStdIoStreams(ReadError, WriteError),
    comptime ArgIterator: type,
    arg_iter: *ArgIterator,
) u8 {
    var args = Clap.parse(allocator, ArgIterator, arg_iter) catch |err| {
        stdio.err.print("{}\n", err) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    if (args.flag("--help")) {
        usage(stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.print("{}\n", program_version) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else {
        stdio.err.write("No file provided\n") catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const file = fs.File.openRead(file_name) catch |err| return errors.openErr(stdio.err, file_name, err);
    defer file.close();

    const gen3_error = if (gen3.Game.fromFile(file, allocator)) |*game| {
        defer game.deinit();
        outputGen3GameScripts(game.*, stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    } else |err| err;

    file.seekTo(0) catch |err| return errors.readErr(stdio.err, file_name, err);
    if (nds.Rom.fromFile(file, allocator)) |nds_rom| {
        const gen4_error = if (gen4.Game.fromRom(allocator, nds_rom)) |*game| {
            defer game.deinit();
            outputGen4GameScripts(game.*, allocator, stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            return 0;
        } else |err| err;

        const gen5_error = if (gen5.Game.fromRom(allocator, nds_rom)) |*game| {
            defer game.deinit();
            outputGen5GameScripts(game.*, allocator, stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            return 0;
        } else |err| err;

        stdio.err.print("Successfully loaded '{}' as a nds rom.\n", file_name) catch {};
        stdio.err.print("Failed to load '{}' as a gen4 game: {}\n", file_name, gen4_error) catch {};
        stdio.err.print("Failed to load '{}' as a gen5 game: {}\n", file_name, gen5_error) catch {};
        return 1;
    } else |nds_error| {
        stdio.err.print("Failed to load '{}' as a gen3 game: {}\n", file_name, gen3_error) catch {};
        stdio.err.print("Failed to load '{}' as a gen4/gen5 game: {}\n", file_name, nds_error) catch {};
        return 1;
    }
}

fn outputGen3GameScripts(game: gen3.Game, stream: var) !void {
    @setEvalBranchQuota(100000);
    for (game.map_headers) |map_header, map_id| {
        const scripts = try map_header.map_scripts.toSliceTerminated(game.data, struct {
            fn isTerm(ms: gen3.MapScript) bool {
                return ms.@"type" == 0;
            }
        }.isTerm);

        for (scripts) |s, script_id| {
            if (s.@"type" == 2 or s.@"type" == 4)
                continue;

            const script_data = try s.addr.Other.toSliceEnd(game.data);
            var decoder = gen3.script.CommandDecoder{ .bytes = script_data };
            try stream.print("map_header[{}].map_script[{}]:\n", map_id, script_id);
            while (try decoder.next()) |command|
                try printCommand(stream, command.*, decoder);

            try stream.write("\n");
        }

        const events = try map_header.map_events.toSingle(game.data);
        for (try events.obj_events.toSlice(game.data, events.obj_events_len)) |obj_event, script_id| {
            const script_data = obj_event.script.toSliceEnd(game.data) catch continue;
            var decoder = gen3.script.CommandDecoder{ .bytes = script_data };
            try stream.print("map_header[{}].obj_events[{}]:\n", map_id, script_id);
            while (try decoder.next()) |command|
                try printCommand(stream, command.*, decoder);

            try stream.write("\n");
        }

        for (try events.coord_events.toSlice(game.data, events.coord_events_len)) |coord_event, script_id| {
            const script_data = coord_event.scripts.toSliceEnd(game.data) catch continue;
            var decoder = gen3.script.CommandDecoder{ .bytes = script_data };
            try stream.print("map_header[{}].coord_event[{}]:\n", map_id, script_id);
            while (try decoder.next()) |command|
                try printCommand(stream, command.*, decoder);

            try stream.write("\n");
        }
    }
}

fn outputGen4GameScripts(game: gen4.Game, allocator: *mem.Allocator, stream: var) anyerror!void {
    for (game.scripts.nodes.toSlice()) |node, script_i| {
        const script_file = node.asFile() catch continue;
        const script_data = script_file.data;

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
        while (offset_i < offsets.count()) : (offset_i += 1) {
            const offset = offsets.at(offset_i);
            try stream.print("script[{}]@0x{x}:\n", script_i, offset);
            if (@intCast(isize, script_data.len) < offset)
                return error.Error;
            if (offset < 0)
                return error.Error;

            var decoder = gen4.script.CommandDecoder{
                .bytes = script_data,
                .i = @intCast(usize, offset),
            };
            while (decoder.next() catch {
                try stream.print("\tUnknown(0x{x})\t@0x{x}\n", decoder.bytes[decoder.i], decoder.i);
                continue;
            }) |command| {
                try printCommand(stream, command.*, decoder);

                switch (command.tag) {
                    .Jump => {
                        const off = command.data.Jump.adr.value();
                        if (off >= 0)
                            try offsets.append(off + @intCast(isize, decoder.i));
                    },
                    .CompareLastResultJump => {
                        const off = command.data.CompareLastResultJump.adr.value();
                        if (off >= 0)
                            try offsets.append(off + @intCast(isize, decoder.i));
                    },
                    .Call => {
                        const off = command.data.Call.adr.value();
                        if (off >= 0)
                            try offsets.append(off + @intCast(isize, decoder.i));
                    },
                    .CompareLastResultCall => {
                        const off = command.data.CompareLastResultCall.adr.value();
                        if (off >= 0)
                            try offsets.append(off + @intCast(isize, decoder.i));
                    },
                    else => {},
                }
            }
        }
    }
}

fn outputGen5GameScripts(game: gen5.Game, allocator: *mem.Allocator, stream: var) anyerror!void {
    for (game.scripts.nodes.toSlice()) |node, script_i| {
        const script_file = node.asFile() catch continue;
        const script_data = script_file.data;

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
        while (offset_i < offsets.count()) : (offset_i += 1) {
            const offset = offsets.at(offset_i);
            try stream.print("script[{}]@0x{x}:\n", script_i, offset);
            if (@intCast(isize, script_data.len) < offset)
                return error.Error;
            if (offset < 0)
                return error.Error;

            var decoder = gen5.script.CommandDecoder{
                .bytes = script_data,
                .i = @intCast(usize, offset),
            };
            while (decoder.next() catch {
                try stream.print("\tUnknown(0x{x})\t@0x{x}\n", decoder.bytes[decoder.i], decoder.i);
                continue;
            }) |command| {
                try printCommand(stream, command.*, decoder);

                switch (command.tag) {
                    .Jump => {
                        const off = command.data.Jump.offset.value();
                        if (off >= 0)
                            try offsets.append(off + @intCast(isize, decoder.i));
                    },
                    .If => {
                        const off = command.data.If.offset.value();
                        if (off >= 0)
                            try offsets.append(off + @intCast(isize, decoder.i));
                    },
                    else => {},
                }
            }
        }
    }
}

fn printCommand(stream: var, command: var, decoder: var) !void {
    try stream.write("\t");
    try printCommandHelper(stream, command);
    try stream.print("\t@0x{x}\n", decoder.i - try script.packedLength(command));
}

fn printCommandHelper(stream: var, value: var) !void {
    const T = @typeOf(value);

    // Infered error sets enforce us to have to return an error somewhere. This
    // messes up with the below comptime branch selection, where some branches
    // does not return any errors.
    try stream.write("");
    switch (@typeInfo(T)) {
        .Void => {},
        .Int => |i| try stream.print("{}", value),
        .Enum => |e| try stream.print("{}", @tagName(value)),
        .Struct => |s| {
            // lu16 and lu16 are seen as structs, but really they should be treated
            // the same as int values.
            if (T == lu16)
                return printCommandHelper(stream, value.value());
            if (T == lu32)
                return printCommandHelper(stream, value.value());
            if (T == li16)
                return printCommandHelper(stream, value.value());
            if (T == li32)
                return printCommandHelper(stream, value.value());

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
                        const TagEnum = @typeOf(tag);

                        var found: bool = true;
                        inline for (@typeInfo(TagEnum).Enum.fields) |enum_field| {
                            if (@field(TagEnum, enum_field.name) == tag) {
                                try printCommandHelper(stream, @field(union_value, enum_field.name));
                                found = true;
                            }
                        }

                        // If no member of 'TagEnum' match, then 'tag' must be a value
                        // it is not suppose to be.
                        if (!found)
                            return error.InvalidTag;
                    },
                    else => try printCommandHelper(stream, @field(value, struct_field.name)),
                }
                if (i + 1 != s.fields.len)
                    try stream.write(" ");
            }
        },
        else => @compileError(@typeName(T) ++ " not supported"),
    }
}
