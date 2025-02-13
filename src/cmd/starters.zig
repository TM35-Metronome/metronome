pub const command = Command{
    .name = "starters",
    .description = "",
    .parameters = Command.Parameter.fromType(Options, .{
        .seed = .{},
        .starters = .{},
        .avoid_same = .{},
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
    const pick_from_base = switch (options.starters) {
        .random => this.base.species,
        .random_lowest_2_stage_evolution => this.lowest_2_stage_evolutions,
        .random_lowest_3_stage_evolution => this.lowest_3_stage_evolutions,
        .random_lowest_evolution => this.lowest_evolutions,
        .unchanged => return,
    };
    if (pick_from_base.count() == 0)
        return error.NoStarterToPick;

    var pick_from = try pick_from_base.clone(arena);
    for (game.starters()) |*starter| {
        var pick_from_non_empty = pick_from;
        if (pick_from_non_empty.count() == 0)
            pick_from_non_empty = pick_from_base;

        starter.* = this.base.randomItem(pick_from_non_empty.keys()).?.*;
        if (options.avoid_same)
            _ = pick_from.swapRemove(starter.*);
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
    avoid_same: bool = false,

    const Starters = enum(u3) {
        unchanged,
        random,
        random_lowest_2_stage_evolution,
        random_lowest_3_stage_evolution,
        random_lowest_evolution,
    };
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
