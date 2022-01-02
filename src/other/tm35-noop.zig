const clap = @import("clap");
const format = @import("format");
const std = @import("std");
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

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam("-h, --help     Display this help text and exit.") catch unreachable,
    clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
};

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    _ = args;
    return Program{ .allocator = allocator };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) !void {
    try format.io(program.allocator, stdio.in, stdio.out, .{}, useGame);
}

fn useGame(ctx: anytype, game: format.Game) !void {
    _ = ctx;
    _ = game;
    return error.ParserFailed;
}
