const builtin = @import("builtin");
const clap = @import("zig-clap");
const common = @import("tm35-common");
const fun = @import("fun-with-zig");
const gba = @import("gba.zig");
const gen3 = @import("gen3-types.zig");
const offsets = @import("gen3-offsets.zig");
const std = @import("std");
const script = @import("gen3-script.zig");

const bits = fun.bits;
const debug = std.debug;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;

const BufOutStream = io.BufferedOutStream(os.File.OutStream.Error);
const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = []Param{
    Param.flag(
        "display this help text and exit",
        Names.both("help"),
    ),
    Param.positional(""),
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-gen3-disassemble-scripts [OPTION]... FILE
        \\Finds all scripts in a generation 3 Pokemon game, disassembles them
        \\and writes them to stdout.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() !void {
    const unbuf_stdout = &(try io.getStdOut()).outStream().stream;
    var buf_stdout = BufOutStream.init(unbuf_stdout);
    defer buf_stdout.flush() catch {};

    const stderr = &(try io.getStdErr()).outStream().stream;
    const stdout = &buf_stdout.stream;

    var direct_allocator = heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    var arena = heap.ArenaAllocator.init(&direct_allocator.allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const file_name = blk: {
        const poss = args.positionals();
        if (poss.len == 0) {
            usage(stderr) catch {};
            return error.NoFileProvided;
        }

        break :blk poss[0];
    };

    var game = blk: {
        var file = os.File.openRead(file_name) catch |err| {
            debug.warn("Couldn't open {}.\n", file_name);
            return err;
        };
        defer file.close();

        break :blk try gen3.Game.fromFile(file, allocator);
    };

    try outputGameScripts(game, stdout);
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

            try stream.print("map_header[{}].map_script[{}]:\n", map_id, script_id);
            var script_data = try s.addr.Other.toSliceEnd(game.data);
            var decoder = script.CommandDecoder.init(script_data);
            while (try decoder.next()) |command|
                try printCommand(stream, command.*);

            try stream.write("\n");
        }
    }
}

pub fn printCommand(stream: var, command: script.Command) !void {
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
        builtin.TypeId.Void => {},
        builtin.TypeId.Int => |i| try stream.print("{}", value),
        builtin.TypeId.Enum => |e| try stream.print("{}", @tagName(value)),
        builtin.TypeId.Struct => |s| {
            // lu16 and lu16 are seen as structs, but really they should be treated
            // the same as int values.
            if (T == lu16)
                return printCommandHelper(stream, value.value());
            if (T == lu32)
                return printCommandHelper(stream, value.value());

            inline for (s.fields) |struct_field, i| {
                switch (@typeInfo(struct_field.field_type)) {
                    builtin.TypeId.Union => |u| next: {
                        if (u.tag_type != null)
                            @compileError(@typeName(struct_field.field_type) ++ " cannot have a tag.");

                        // Find the field most likly to be this unions tag.
                        const tag_field = (comptime script.findTagFieldName(T, struct_field.name)) orelse @compileError("Could not find a tag for " ++ struct_field.name);
                        const tag = @field(value, tag_field);
                        const union_value = @field(value, struct_field.name);
                        const TagEnum = @typeOf(tag);

                        // Switch over all tags. 'TagEnum' have the same field names as
                        // 'union' so if one member of 'TagEnum' matches 'tag', then
                        // we can add the size of ''@field(union, tag_name)' to res and
                        // break out.
                        inline for (@typeInfo(TagEnum).Enum.fields) |enum_field| {
                            if (@field(TagEnum, enum_field.name) == tag) {
                                try printCommandHelper(stream, @field(union_value, enum_field.name));
                                break :next;
                            }
                        }

                        // If no member of 'TagEnum' match, then 'tag' must be a value
                        // it is not suppose to be.
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
