const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const common = @import("common.zig");
const gen3 = @import("gen3.zig");
const gen4 = @import("gen4.zig");
const gen5 = @import("gen5.zig");
const rom = @import("rom.zig");

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const unicode = std.unicode;

const gba = rom.gba;
const nds = rom.nds;

const lu16 = rom.int.lu16;

const bit = util.bit;
const escape = util.escape;
const exit = util.exit;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = [_]Param{
    clap.parseParam("-h, --help     Display this help text and exit.    ") catch unreachable,
    clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
    clap.parseParam("<ROM>          The rom to identify.                ") catch unreachable,
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-identify");
    try clap.usage(writer, &params);
    try writer.writeAll("\nIdentify which Pokémon game a file is.\n" ++
        "\n" ++
        "Options:\n");
    try clap.help(writer, &params);
}

pub fn main2(
    allocator: *mem.Allocator,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) u8 {
    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else {
        stdio.err.writeAll("No file provided\n") catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const file = fs.cwd().openFile(file_name, .{}) catch |err| return exit.openErr(stdio.err, file_name, err);
    const reader = file.reader();
    defer file.close();

    inline for ([_]type{
        gen3.Game,
        gen4.Game,
        gen5.Game,
    }) |Game| {
        file.seekTo(0) catch |err| return exit.readErr(stdio.err, file_name, err);
        if (Game.identify(reader)) |info| {
            stdio.out.print("Version: Pokémon {}\nGamecode: {}\n", .{
                info.version.humanString(),
                info.gamecode,
            }) catch |err| return exit.stdoutErr(stdio.err, err);
            return 0;
        } else |err| switch (err) {
            error.UnknownGame => {},
            else => return exit.readErr(stdio.err, file_name, err),
        }
    }

    return exit.err(stdio.err, "File is not a Pokémon rom.", .{});
}
