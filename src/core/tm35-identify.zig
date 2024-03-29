const clap = @import("clap");
const core = @import("core");
const std = @import("std");
const util = @import("util");

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const unicode = std.unicode;

const common = core.common;
const gen3 = core.gen3;
const gen4 = core.gen4;
const gen5 = core.gen5;
const rom = core.rom;

const gba = rom.gba;
const nds = rom.nds;

const Program = @This();

allocator: mem.Allocator,
file: []const u8,

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Identify which Pokémon game a file is.
    \\
;

pub const parsers = .{
    .ROM = clap.parsers.string,
};

pub const params = clap.parseParamsComptime(
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\-v, --version
    \\        Output version information and exit.
    \\
    \\<ROM>
    \\        The rom to identify.
    \\
);

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const pos = args.positionals;
    const file_name = if (pos.len > 0) pos[0] else return error.MissingFile;
    return Program{ .allocator = allocator, .file = file_name };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    const file = try fs.cwd().openFile(program.file, .{});
    const reader = file.reader();
    defer file.close();

    inline for ([_]type{
        gen3.Game,
        gen4.Game,
        gen5.Game,
    }) |Game| {
        try file.seekTo(0);
        if (Game.identify(reader)) |info| {
            try stdio.out.print("Version: Pokémon {s}\nGamecode: {s}\n", .{
                info.version.humanString(),
                info.gamecode,
            });
            return;
        } else |err| switch (err) {
            error.UnknownGame => {},
            else => return err,
        }
    }

    return error.InvalidRom;
}
