const clap = @import("clap");
const std = @import("std");

const gen3 = @import("gen3-types.zig");
const common = @import("common.zig");
const rom = @import("rom.zig");

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;

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
    const stdout_file = io.getStdOut() catch |err| return errPrint("Could not aquire stdout: {}\n", err);
    const stderr_file = io.getStdErr() catch |err| return errPrint("Could not aquire stderr: {}\n", err);

    const stdout = &BufOutStream.init(&stdout_file.outStream().stream);
    const stderr = &stderr_file.outStream().stream;

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        debug.warn("{}\n", err);
        usage(stderr) catch |err2| return failedWriteError("<stderr>", err2);
        return 1;
    };

    if (args.flag("--help")) {
        usage(&stdout.stream) catch |err| return failedWriteError("<stdout>", err);
        stdout.flush() catch |err| return failedWriteError("<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdout.stream.print("{}\n", program_version) catch |err| return failedWriteError("<stdout>", err);
        stdout.flush() catch |err| return failedWriteError("<stdout>", err);
        return 0;
    }

    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else {
        debug.warn("No file provided\n");
        usage(stderr) catch |err| return failedWriteError("<stderr>", err);
        return 1;
    };

    var file = fs.File.openRead(file_name) catch |err| return errPrint("Unable to open '{}': {}\n", file_name, err);
    defer file.close();

    const game = gen3.Game.fromFile(file, allocator) catch |err| return errPrint("Error while loading gen3 game: {}\n", err);

    outputGameScripts(game, &stdout.stream) catch |err| return failedWriteError("<stdout>", err);
    stdout.flush() catch |err| return failedWriteError("<stdout>", err);
    return 0;
}

fn failedWriteError(file: []const u8, err: anyerror) u8 {
    debug.warn("Failed to write data to '{}': {}\n", file, err);
    return 1;
}

fn errPrint(comptime format_str: []const u8, args: ...) u8 {
    debug.warn(format_str, args);
    return 1;
}

fn outputGameScripts(game: gen3.Game, stream: var) !void {
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
                try printCommand(stream, command.*);

            try stream.write("\n");
        }

        const events = try map_header.map_events.toSingle(game.data);
        for (try events.obj_events.toSlice(game.data, events.obj_events_len)) |obj_event, script_id| {
            const script_data = obj_event.script.toSliceEnd(game.data) catch continue;
            var decoder = gen3.script.CommandDecoder{ .bytes = script_data };
            try stream.print("map_header[{}].obj_events[{}]:\n", map_id, script_id);
            while (try decoder.next()) |command|
                try printCommand(stream, command.*);

            try stream.write("\n");
        }

        for (try events.coord_events.toSlice(game.data, events.coord_events_len)) |coord_event, script_id| {
            const script_data = coord_event.scripts.toSliceEnd(game.data) catch continue;
            var decoder = gen3.script.CommandDecoder{ .bytes = script_data };
            try stream.print("map_header[{}].coord_event[{}]:\n", map_id, script_id);
            while (try decoder.next()) |command|
                try printCommand(stream, command.*);

            try stream.write("\n");
        }
    }
}

pub fn printCommand(stream: var, command: gen3.script.Command) !void {
    try stream.write("\t");
    try printCommandHelper(stream, command);
    try stream.write("\n");
}

pub fn printCommandHelper(stream: var, value: var) !void {
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

            inline for (s.fields) |struct_field, i| {
                switch (@typeInfo(struct_field.field_type)) {
                    .Union => |u| {
                        if (u.tag_type != null)
                            @compileError(@typeName(struct_field.field_type) ++ " cannot have a tag.");

                        // Find the field most likly to be this unions tag.
                        const tag_field = (comptime gen3.script.findTagFieldName(T, struct_field.name)) orelse @compileError("Could not find a tag for " ++ struct_field.name);
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
