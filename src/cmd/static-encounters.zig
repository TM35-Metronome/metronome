pub const command = Command{
    .name = "static-encounters",
    .description = "",
    .parameters = Command.Parameter.fromType(Options, .{
        .seed = .{},
    }),
    .createOptions = Command.Options.createFromType(Options),
    .function = randomize,
};

fn randomize(gpa: std.mem.Allocator, options: Command.Options, game: *core.Game) anyerror!void {
    switch (game.*) {
        inline else => |*g| return randomizeAny(gpa, options.cast(Options).*, g),
    }
}

fn randomizeAny(gpa: std.mem.Allocator, options: Options, game: anytype) !void {
    var random = std.Random.DefaultPrng.init(options.seed);
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const this = try init(arena, random.random(), options, game);
    _ = this; // autofix
}

base: common.Randomizer,
options: Options,

legendaries: common.SpeciesSet,

fn init(arena: std.mem.Allocator, random: std.Random, options: Options, game: anytype) !This {
    const base = try common.Randomizer.init(arena, random, game);

    return .{
        .base = base,
        .options = options,

        .legendaries = try base.legendaries(game),
    };
}

const Options = packed struct {
    seed: u64 = 0,
};

test randomizeAny {
    try core.dummy.doTest(Options{}, randomizeAny, core.dummy.default, core.dummy.default);
}

test "fuzz" {
    try core.dummy.doFuzz(Options, randomizeAny);
}

test {
    _ = Command;
    _ = common;
    _ = core;
    _ = util;
}

const This = @This();

const Command = @import("../Command.zig");
const common = @import("common.zig");
const core = @import("../core.zig");
const util = @import("../util.zig");

const std = @import("std");
