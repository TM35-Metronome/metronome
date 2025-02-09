pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const args_slice = try std.process.argsAlloc(arena);
    var args = ArgParser{ .args = args_slice[1..] };

    var input: ?[]const u8 = null;
    var output: ?[]const u8 = null;
    while (args.next()) {
        if (args.option(&.{ "-i", "--input" })) |i|
            input = i;
        if (args.option(&.{ "-o", "--output" })) |o|
            output = o;
        if (!args.consumed)
            break;
    }

    var input_file = try std.fs.cwd().openFile(input orelse return error.NoInput, .{});
    defer input_file.close();
    var output_file = try std.fs.cwd().createFile(output orelse return error.NoOutput, .{});
    defer output_file.close();

    var game = try core.Game.fromFile(input_file, arena);
    while (args.next()) {
        const command_name = args.positional().?;
        const command = Command.find(command_name) orelse return error.UnknownCommand;
        const options = try command.createOptions(arena);

        while (args.next()) {
            for (command.parameters) |parameter| {
                var buf: [128]u8 = undefined;
                const cli_param = try std.fmt.bufPrint(&buf, "--{s}", .{parameter.name});
                if (args.option(&.{cli_param})) |value|
                    try options.set(options, arena, parameter.name, value);
            }
            if (!args.consumed)
                break;
        }

        try command.function(arena, options, &game);
    }

    try game.apply();
    try game.write(output_file.writer());
}

test {
    _ = ArgParser;
    _ = Command;

    _ = core;
}

const ArgParser = @import("util/ArgParser.zig");
const Command = @import("Command.zig");

const core = @import("core.zig");
const std = @import("std");
