const clap = @import("clap");
const format = @import("format");
const std = @import("std");
const ston = @import("ston");
const util = @import("util");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const log = std.log;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const Program = @This();

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Doesn't do anything (used for debugging)
    \\
;

allocator: mem.Allocator,
serialize: bool,

pub const parsers = .{};

pub const params = clap.parseParamsComptime(
    \\-s, --serialize
    \\        Instead of not consuming the data, the tm35-noop will instead serialize the data
    \\        itself.
    \\
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\-v, --version
    \\        Output version information and exit.
    \\
);

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    return Program{
        .allocator = allocator,
        .serialize = args.args.serialize,
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) !void {
    try format.io(
        program.allocator,
        stdio.in,
        stdio.out,
        .{ .out = stdio.out, .program = program },
        useGame,
    );
}

fn useGame(ctx: anytype, game: format.Game) !void {
    const out = ctx.out;
    const program = ctx.program;
    if (program.serialize) {
        try ston.serialize(out, game);
        try out.context.flush();
    } else {
        return error.DidNotConsumeData;
    }
}

test {
    const test_string =
        \\.wild_pokemons[1].surf_0.pokemons[4].species=118
        \\.wild_pokemons[1].fishing_0.encounter_rate=30
        \\
    ;
    try util.testing.testProgram(Program, &[_][]const u8{"--serialize"}, test_string, test_string);
}
