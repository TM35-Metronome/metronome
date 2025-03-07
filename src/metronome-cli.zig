pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const args_slice = try std.process.argsAlloc(arena);
    var args = util.ArgParser{ .args = args_slice[1..] };

    var seed: ?u64 = null;
    var input: ?[]const u8 = null;
    var output: ?[]const u8 = null;
    while (args.next()) {
        if (args.flag(&.{ "-h", "--help" }))
            return printHelp(std.io.getStdOut());
        if (args.option(&.{ "-i", "--input" })) |i|
            input = i;
        if (args.option(&.{ "-o", "--output" })) |o|
            output = o;
        if (args.option(&.{ "-s", "--seed" })) |s|
            seed = try parseString(u64, s);
        if (!args.consumed)
            break;
    }

    var commands = Metronome.Commands{};

    while (args.next()) {
        const command_name = args.positional().?;

        inline for (Metronome.Commands.descriptions) |command_description| loop_blk: {
            if (!std.mem.eql(u8, command_name, command_description.id))
                break :loop_blk; // TODO: We cannot use `continue` in `inline for`

            var command_outer = @unionInit(Metronome.Command, command_description.id, .{});
            const command = &@field(command_outer, command_description.id);

            while (args.next()) {
                if (args.flag(&.{ "-h", "--help" })) {
                    try printCommandHelp(std.io.getStdOut(), command_description);
                    return;
                }

                var buf: [128]u8 = undefined;
                inline for (command_description.options) |option_desciption| {
                    const cli_id = try std.fmt.bufPrint(&buf, "--{s}", .{option_desciption.id});
                    const OptionT = @TypeOf(@field(command, option_desciption.id));

                    if (OptionT == bool and args.flag(&.{cli_id}))
                        @field(command, option_desciption.id) = true;
                    if (args.option(&.{cli_id})) |value|
                        @field(command, option_desciption.id) = try parseString(OptionT, value);
                }

                if (!args.consumed)
                    break;
            }

            try commands.commands.append(arena, command_outer);
        }
    }

    var input_file = try std.fs.cwd().openFile(input orelse return error.NoInput, .{});
    defer input_file.close();
    var output_file = try std.fs.cwd().createFile(output orelse return error.NoOutput, .{});
    defer output_file.close();

    var game = try core.Game.fromFile(input_file, gpa);
    defer game.deinit();

    var random = std.Random.DefaultPrng.init(seed orelse std.crypto.random.int(u64));
    var metronome = try Metronome.init(gpa, arena, random.random());
    switch (game) {
        inline else => |*g| try metronome.runCommands(commands, g),
    }

    try game.apply();
    try game.write(output_file.writer());
}

fn printHelp(file: std.fs.File) !void {
    const writer = file.writer();

    try writer.writeAll(
        \\A tool for modifying and randomizing Pokémon game roms.
        \\
        \\Usage: metronome-cli [OPTIONS] [COMMAND]...
        \\
        \\Options:
        \\  -i, --input <path>
        \\  -o, --output <path>
        \\  -s, --seed <seed>
        \\
    );
}

fn printCommandHelp(file: std.fs.File, description: Metronome.Command.Description) !void {
    const writer = file.writer();

    try writer.writeAll(description.description);
    try writer.writeAll("\n\n");
    try writer.writeAll("Usage: metronome-cli ");
    try writer.writeAll(description.id);
    try writer.writeAll(" [OPTIONS] [COMMAND]...\n\nOptions:\n");

    // pub const Description = struct {
    //     id: []const u8,
    //     name: []const u8,
    //     description: []const u8,
    //     options: []const OptionDescription,
    // };

    // pub const OptionDescription = struct {
    //     id: []const u8,
    //     name: []const u8,
    //     description: []const u8,
    // };

}

fn parseString(comptime T: type, string: []const u8) !T {
    switch (@typeInfo(T)) {
        .int => return std.fmt.parseInt(T, string, 0),
        .@"enum" => return std.meta.stringToEnum(T, string) orelse return error.InvalidValue,
        .bool => return (std.meta.stringToEnum(enum { false, true }, string) orelse
            return error.InvalidValue) == .true,
        else => @compileError("Not implemented for " ++ @typeName(T)),
    }
}

test {
    _ = Metronome;

    _ = core;
    _ = util;
}

const Metronome = @import("Metronome.zig");

const core = @import("core.zig");
const util = @import("util.zig");

const std = @import("std");
