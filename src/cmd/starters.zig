pub const command = Command{
    .name = "starters",
    .description = "",
    .parameters = Command.Parameter.fromType(Options, .{
        .seed = .{},
        .starters = .{},
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

    switch (options.starters) {
        .unchanged => return,
        .random0,
        .random1,
        .random2,
        .random3,
        .random_lowest_2_stage_evolution,
        .random_lowest_3_stage_evolution,
        .random_lowest_evolution,
        => {},
    }
}

base: common.Randomizer,
options: Options,

lowest_2_stage_evolutions: common.SpeciesSet,
lowest_3_stage_evolutions: common.SpeciesSet,
lowest_evolutions: common.SpeciesSet,

fn init(arena: std.mem.Allocator, random: std.Random, options: Options, game: anytype) !This {
    const base = try common.Randomizer.init(arena, random, game);

    var lowest_2_stage_evolutions = common.SpeciesSet{};
    var lowest_3_stage_evolutions = common.SpeciesSet{};
    var lowest_evolutions = try base.species.clone(arena);

    const pokemons_evolutions = try game.evolutions();
    for (base.species.keys()) |species| {
        const evolutions = pokemons_evolutions.at(species) catch continue;
        for (evolutions) |evolution| {
            if (evolution.method == .unused)
                continue;
            _ = lowest_evolutions.swapRemove(evolution.target);
        }
    }

    for (lowest_evolutions.keys()) |species| {
        switch (countEvolutions(species, species, game)) {
            1 => try lowest_2_stage_evolutions.put(arena, species, {}),
            2 => try lowest_3_stage_evolutions.put(arena, species, {}),
            else => {},
        }
    }

    return .{
        .base = base,
        .options = options,

        .lowest_2_stage_evolutions = lowest_2_stage_evolutions,
        .lowest_3_stage_evolutions = lowest_3_stage_evolutions,
        .lowest_evolutions = lowest_evolutions,
    };
}

fn countEvolutions(species: u16, start_species: u16, game: anytype) usize {
    var res: usize = 0;

    const pokemons_evolutions = game.evolutions() catch return res;
    const evolutions = pokemons_evolutions.at(species) catch return res;
    for (evolutions) |evolution| {
        if (evolution.method == .unused)
            continue;
        if (start_species == evolution.target)
            continue;

        res = @max(res, 1 + countEvolutions(evolution.target, start_species, game));
    }

    return res;
}

const Options = packed struct {
    seed: u64 = 0,
    starters: Starters = .unchanged,

    const Starters = enum(u3) {
        unchanged,
        random0,
        random1,
        random2,
        random3,
        random_lowest_2_stage_evolution,
        random_lowest_3_stage_evolution,
        random_lowest_evolution,
    };
};

fn doTest(options: Options, from: core.dummy.Game.Init, to: core.dummy.Game.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const from_game = try core.dummy.Game.init(arena, from);
    const to_game = try core.dummy.Game.init(arena, to);
    try randomizeAny(std.testing.allocator, options, from_game);

    // Avoid large error trace by not using `catch` or `try` here
    const is_err = if (std.testing.expectEqualDeep(to_game.m, from_game.m)) false else |_| true;
    if (is_err) {
        const from_str = try std.fmt.allocPrint(arena, "{}", .{from_game});
        const to_str = try std.fmt.allocPrint(arena, "{}", .{to_game});
        try std.fs.cwd().writeFile(.{ .sub_path = ".zig-cache/from.json", .data = from_str });
        try std.fs.cwd().writeFile(.{ .sub_path = ".zig-cache/to.json", .data = to_str });
        std.testing.expectEqualStrings(to_str, from_str) catch {};
        return error.TestExpectedEqual;
    }
}

test randomizeAny {
    try doTest(.{}, core.dummy.default, core.dummy.default);
}

fn fuzzOne(input: []const u8) !void {
    var options: Options = .{};
    const options_bytes = std.mem.asBytes(&options);
    const len = @min(options_bytes.len, input.len);
    @memcpy(options_bytes[0..len], input[0..len]);

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const first = try core.dummy.Game.init(arena, core.dummy.default);
    const second = try core.dummy.Game.init(arena, core.dummy.default);
    try randomizeAny(std.testing.allocator, options, first);
    try randomizeAny(std.testing.allocator, options, second);
    try std.testing.expectEqualDeep(first.m, second.m);
}

test "fuzz" {
    try std.testing.fuzz(fuzzOne, .{});
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
