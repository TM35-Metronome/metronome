pub const command = Command{
    .name = "static-encounters",
    .description = "",
    .parameters = Command.Parameter.fromType(Options, .{
        .seed = .{},
        .static_pokemons = .{},
        .given_pokemons = .{},
        // .hidden_hollows = .{}, TODO
        .legendary_with_legendary = .{},
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

    const pick_from_legendaries = switch (options.legendary_with_legendary) {
        true => this.legendaries,
        false => this.base.species,
    };
    const pick_from_non_legendaries = switch (options.legendary_with_legendary) {
        true => this.non_legendaries,
        false => this.base.species,
    };

    inline for (.{
        .{ options.static_pokemons, game.staticPokemons() },
        .{ options.given_pokemons, game.givenPokemons() },
    }) |item| switch (item[0]) {
        .unchanged => {},
        .randomize => for (item[1]) |*static_pokemon| {
            const pick_from = switch (this.legendaries.get(static_pokemon.species()) != null) {
                true => pick_from_legendaries,
                false => pick_from_non_legendaries,
            };

            const new_species = this.base.randomItem(pick_from.keys()).?.*;
            static_pokemon.setSpecies(new_species);
        },
    };

    // switch (options.hidden_hollows) {
    //     .unchanged => {},
    //     .randomize => {},
    // }
}

base: common.Randomizer,
options: Options,

legendaries: common.SpeciesSet,
non_legendaries: common.SpeciesSet,

fn init(arena: std.mem.Allocator, random: std.Random, options: Options, game: anytype) !This {
    const base = try common.Randomizer.init(arena, random, game);

    const legendaries = try base.legendaries(game);
    return .{
        .base = base,
        .options = options,

        .legendaries = legendaries,
        .non_legendaries = blk: {
            var res = common.SpeciesSet{};
            for (base.species.keys()) |species| {
                if (legendaries.get(species)) |_| continue;
                _ = try res.put(base.arena, species, {});
            }

            break :blk res;
        },
    };
}

const Options = packed struct {
    seed: u64 = 0,
    static_pokemons: Pokemons = .unchanged,
    given_pokemons: Pokemons = .unchanged,
    // hidden_hollows: Pokemons = .unchanged, TODO
    legendary_with_legendary: bool = false,

    pub const Pokemons = enum(u1) {
        unchanged,
        randomize,
    };
};

test randomizeAny {
    try core.dummy.doTest(Options{}, randomizeAny, core.dummy.default, core.dummy.default);
    try core.dummy.doTest(Options{
        .static_pokemons = .randomize,
    }, randomizeAny, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.static_pokemons = &.{
            .init(50, 30),
            .init(58, 50),
            .init(55, 50),
            .init(2, 50),
            .init(75, 70),
        };
        break :blk res;
    });
    try core.dummy.doTest(Options{
        .static_pokemons = .randomize,
        .legendary_with_legendary = true,
    }, randomizeAny, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.static_pokemons = &.{
            .init(48, 30),
            .init(145, 50),
            .init(145, 50),
            .init(144, 50),
            .init(146, 70),
        };
        break :blk res;
    });
    try core.dummy.doTest(Options{
        .given_pokemons = .randomize,
    }, randomizeAny, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.given_pokemons = &.{
            .init(50, 30),
            .init(58, 30),
            .init(55, 5),
            .init(2, 15),
            .init(75, 25),
            .init(4, 30),
            .init(130, 30),
            .init(128, 30),
        };
        break :blk res;
    });
    try core.dummy.doTest(Options{
        .given_pokemons = .randomize,
        .legendary_with_legendary = true,
    }, randomizeAny, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.given_pokemons = &.{
            .init(48, 30),
            .init(56, 30),
            .init(53, 5),
            .init(2, 15),
            .init(73, 25),
            .init(4, 30),
            .init(126, 30),
            .init(124, 30),
        };
        break :blk res;
    });
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
