pub const command = Command{
    .name = "randomize-wild-encounters",
    .description = "",
    .parameters = Command.Parameter.fromType(Options, .{
        .seed = .{},
        .pokemons = .{},
        .stats = .{},
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

    switch (options.pokemons) {
        .unchanged => return,
        .randomize => {},
    }

    var this = try init(arena, random.random(), options, game);

    const wild_areas = try game.wildAreas();
    var i: usize = 0;
    while (i < wild_areas.len()) : (i += 1) {
        const wild_pokemons = wild_areas.at(i) catch continue;

        var j: usize = 0;
        while (j < wild_pokemons.len()) : (j += 1) {
            const wild_pokemon = wild_pokemons.at(j) catch continue;
            try this.randomizeWildPokemon(game, wild_pokemon);
        }
    }
}

fn randomizeWildPokemon(this: *@This(), game: anytype, wild_pokemon: anytype) !void {
    const pokemons = try game.pokemons();
    wild_pokemon.setSpecies(switch (this.options.stats) {
        .random0, .random1 => this.base.randomItem(this.base.species.keys()).?.*,
        .similar => if (pokemons.at(wild_pokemon.species())) |pokemon|
            try this.base.randomSpeciesWithSimilarTotalStats(
                game,
                this.base.species,
                pokemon.stats.total(),
            )
        else |_|
            this.base.randomItem(this.base.species.keys()).?.*,
        .follow_level => try this.base.randomSpeciesWithStatsFollowingLevel(
            game,
            this.base.species,
            wild_pokemon.level(),
        ),
    });
}

base: common.Randomizer,
options: Options,

fn init(arena: std.mem.Allocator, random: std.Random, options: Options, game: anytype) !This {
    const base = try common.Randomizer.init(arena, random, game);

    return .{
        .base = base,
        .options = options,
    };
}

const Options = packed struct {
    seed: u64 = 0,
    pokemons: Pokemons = .unchanged,
    stats: Stats = .random0,

    // TODO: Avoid same

    const Pokemons = enum(u1) {
        unchanged,
        randomize,
    };

    const Stats = enum(u2) {
        random0,
        random1,
        similar,
        follow_level,
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
    try doTest(.{
        .pokemons = .randomize,
    }, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.wild_areas = &.{
            .init(&.{
                .init(50, 2, 5),
                .init(58, 2, 4),
            }),
            .init(&.{
                .init(55, 18, 22),
                .init(2, 23, 25),
                .init(75, 20, 22),
                .init(4, 24, 24),
                .init(130, 18, 22),
            }),
            .init(&.{
                .init(128, 5, 40),
                .init(45, 5, 5),
                .init(12, 10, 10),
                .init(48, 10, 10),
                .init(10, 20, 40),
                .init(16, 15, 15),
                .init(15, 15, 15),
                .init(10, 15, 15),
            }),
        };
        break :blk res;
    });
    try doTest(.{
        .pokemons = .randomize,
        .stats = .similar,
    }, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.wild_areas = &.{
            .init(&.{
                .init(16, 2, 5),
                .init(41, 2, 4),
            }),
            .init(&.{
                .init(19, 18, 22),
                .init(17, 23, 25),
                .init(19, 20, 22),
                .init(22, 24, 24),
                .init(90, 18, 22),
            }),
            .init(&.{
                .init(104, 5, 40),
                .init(13, 5, 5),
                .init(37, 10, 10),
                .init(104, 10, 10),
                .init(121, 20, 40),
                .init(48, 15, 15),
                .init(37, 15, 15),
                .init(109, 15, 15),
            }),
        };
        break :blk res;
    });
    try doTest(.{
        .pokemons = .randomize,
        .stats = .follow_level,
    }, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.wild_areas = &.{
            .init(&.{
                .init(16, 2, 5),
                .init(19, 2, 4),
            }),
            .init(&.{
                .init(33, 18, 22),
                .init(44, 23, 25),
                .init(95, 20, 22),
                .init(44, 24, 24),
                .init(95, 18, 22),
            }),
            .init(&.{
                .init(64, 5, 40),
                .init(21, 5, 5),
                .init(132, 10, 10),
                .init(32, 10, 10),
                .init(24, 20, 40),
                .init(98, 15, 15),
                .init(96, 15, 15),
                .init(88, 15, 15),
            }),
        };
        break :blk res;
    });
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
