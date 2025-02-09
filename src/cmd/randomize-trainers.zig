pub const command = Command{
    .name = "randomize-trainers",
    .description = "",
    .parameters = Command.Parameter.fromType(Options, .{
        .seed = .{},
        .party_size_max = .{},
        .party_size_min = .{},
        .moves = .{},
        .held_items = .{},
        .abilities = .{},
        .types = .{},
        .stats = .{},
        .party_size = .{},
        .party_pokemons = .{},
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

    var this = try init(arena, random.random(), options, game);
    if (this.species.count() == 0)
        return;

    const parties = try game.trainerParties();

    var i: usize = 0;
    while (i < parties.len()) : (i += 1) {
        const party = parties.at(i) catch continue;
        if (party.size == 0)
            continue;

        try this.randomizeParty(game, party);
    }
}

fn randomizeParty(this: *This, game: anytype, party: anytype) !void {
    const themes = Themes{
        .types = switch (this.options.types) {
            .themed => blk: {
                const types = this.species_by_type.keys();
                const t = types[this.random.uintAtMost(usize, types.len - 1)];
                break :blk [_]u8{ t, t };
            },
            .dual_themed => blk: {
                const types = this.species_by_dual_type.keys();
                break :blk types[this.random.uintAtMost(usize, types.len - 1)];
            },
            else => null,
        },
        .ability = switch (this.options.abilities) {
            .themed => blk: {
                const abilities = this.species_by_ability.keys();
                break :blk abilities[this.random.uintAtMost(usize, abilities.len - 1)];
            },
            else => null,
        },
    };

    const wants_moves = switch (this.options.moves) {
        .unchanged => party.type.haveMoves(),
        .none0, .none1, .none2 => false,
        .best,
        .best_for_level,
        .random_learnable,
        .random,
        => true,
    };
    const wants_items = switch (this.options.held_items) {
        .unchanged => party.type.haveItem(),
        .none0, .none1 => false,
        .random => true,
    };

    const average_level = common.averagePartyLevel(party);
    const old_party_size = party.size;
    party.size = switch (this.options.party_size) {
        .unchanged => std.math.clamp(
            party.size,
            this.options.party_size_min,
            this.options.party_size_max,
        ),
        .random => this.random.intRangeAtMost(
            u8,
            this.options.party_size_min,
            this.options.party_size_max,
        ),
        .follow_level => common.partySizeLevelScaling(
            this.options.party_size_min,
            this.options.party_size_max,
            average_level,
        ),
        .minimum => this.options.party_size_min,
    };
    party.type = switch (wants_moves) {
        true => switch (wants_items) {
            true => .both,
            false => .moves,
        },
        false => switch (wants_items) {
            true => .item,
            false => .none,
        },
    };

    // Fill trainer party with more Pokémons. The Pokémons we fill the party with are Pokémons that
    // are already in the party.
    if (old_party_size != 0) for (0..party.size) |to| {
        const from = to % old_party_size;
        party.members[to] = party.members[from];
    };
    @memset(party.members[party.size..], .{});

    const members = party.members[0..party.size];
    for (members, 0..) |*member, member_i| {
        switch (this.options.party_pokemons) {
            .randomize => try this.randomizePartyMember(
                themes,
                game,
                party.members[0..member_i],
                member,
            ),
            .unchanged => {},
        }
        // TODO:
        // switch (this.options.held_items) {
        //     .unchanged => {},
        //     .none0, .none1 => member.item = 0,
        //     .random => {}, // TODO
        // }
        // switch (this.options.moves) {
        //     .none0, .none1, .none2, .unchanged => {},
        //     .best, .best_for_level => {},
        //     .random_learnable => {},
        //     .random => {},
        // }
    }
}

fn randomizePartyMember(
    this: *@This(),
    themes: Themes,
    game: anytype,
    other_members: anytype,
    member: anytype,
) !void {
    const pokemons = try game.pokemons();
    const pick_from_type = switch (this.options.types) {
        .same => blk: {
            const pokemon = pokemons.at(member.base.species) catch break :blk this.species;
            break :blk this.species_by_type.get(pokemon.types[0]).?;
        },
        .themed => this.species_by_type.get(themes.types.?[0]).?,
        .dual_themed => this.species_by_dual_type.get(themes.types.?).?,
        .random => Set{},
    };

    var new_ability: ?u16 = null;
    const pick_from_ability = switch (this.options.abilities) {
        .same0, .same1 => blk: {
            const pokemon = pokemons.at(member.base.species) catch break :blk this.species;
            const ability = pokemon.abilities[member.ability()];
            if (ability == 0)
                break :blk this.species;

            new_ability = ability;
            break :blk this.species_by_ability.get(ability).?;
        },
        .themed => blk: {
            new_ability = themes.ability;
            break :blk this.species_by_ability.get(themes.ability.?).?;
        },
        .random => Set{},
    };

    if (this.options.abilities != .random and this.options.types != .random) {
        // The intersection between the type_set and ability_set will give
        // us all pokémons that have a certain type+ability pair. This is
        // the set we will pick from.
        var intersection = this.intersection.promote(this.arena);
        intersection.clearRetainingCapacity();
        try util.set.intersectInline(&intersection, pick_from_ability, pick_from_type);
        this.intersection = intersection.unmanaged;
    }

    // Pick the first set that has items in it.
    var pick_from = if (this.intersection.count() != 0)
        this.intersection
    else if (pick_from_ability.count() != 0)
        pick_from_ability
    else if (pick_from_type.count() != 0)
        pick_from_type
    else
        this.species;

    if (this.options.avoid_same) {
        // Now, we have to exclude party members already in the party. To do this we construct a
        // new set from `pick_from` with `other_party_members` excluded.
        this.pick_from_excluded.clearRetainingCapacity();
        try this.pick_from_excluded.ensureTotalCapacity(this.arena, pick_from.count());

        for (pick_from.keys()) |picked|
            this.pick_from_excluded.putAssumeCapacity(picked, {});
        for (other_members) |other_member|
            _ = this.pick_from_excluded.swapRemove(other_member.base.species);

        // If we end up with 0 things to pick from, then we cannot avoid same. So only use our
        // newly created set, if it actually has things to pick from.
        if (this.pick_from_excluded.count() != 0)
            pick_from = this.pick_from_excluded;
    }

    // When we have picked a new species for our Pokémon we also need
    // to fix the ability the Pokémon have, if we're picking Pokémons
    // based on ability.
    defer if (new_ability) |ability_to_find| {
        // A valid species should have been picked, so this should never fail
        const pokemon = pokemons.at(member.base.species) catch unreachable;

        // Find the index of the ability we want the party member to
        // have. If we don't find the ability. The best we can do is
        // just let the Pokémon keep the ability it already has.
        for (pokemon.abilities, 0..) |ability, ability_i| {
            if (ability == ability_to_find) {
                member.setAbility(@intCast(ability_i));
                break;
            }
        }
    };

    member.base.species = switch (this.options.stats) {
        .follow_level => try this.randomSpeciesWithSimilarTotalStats(
            game,
            pick_from,
            common.totalStatsLevelScaling(this.stats.min, this.stats.max, member.base.level),
        ),
        .similar => if (pokemons.at(member.base.species)) |pokemon|
            try this.randomSpeciesWithSimilarTotalStats(
                game,
                pick_from,
                pokemon.stats.total(),
            )
        else |_|
            pick_from.keys()[this.random.uintAtMost(usize, pick_from.count() - 1)],
        .random0, .random1 => pick_from.keys()[this.random.uintAtMost(usize, pick_from.count() - 1)],
    };
}

fn randomSpeciesWithSimilarTotalStats(this: *@This(), game: anytype, pick_from: Set, total_stats: u16) !u16 {
    const pokemons = try game.pokemons();
    const range = 5;
    var min = @as(isize, @intCast(total_stats)) - range;
    var max = min + range * 2;

    this.similar.shrinkRetainingCapacity(0);
    while (this.similar.items.len < 25) : ({
        min -= range;
        max += range;
    }) {
        try this.similar.ensureUnusedCapacity(this.arena, pick_from.count());
        for (pick_from.keys()) |s| {
            const p = pokemons.at(s) catch continue;
            const total: isize = @intCast(p.stats.total());
            if (min <= total and total <= max)
                this.similar.appendAssumeCapacity(s);
        }
    }

    return this.similar.items[this.random.uintAtMost(usize, this.similar.items.len - 1)];
}

arena: std.mem.Allocator,
random: std.Random,
options: Options,

stats: MinMax(u16),
species: Set,
species_by_ability: SpeciesByAbility,
species_by_type: SpeciesByType,
species_by_dual_type: SpeciesByDualType,

// Containers we reuse often enough that keeping them around with their preallocated capacity
// is worth the hassle.
similar: std.ArrayListUnmanaged(u16) = std.ArrayListUnmanaged(u16){},
intersection: Set = Set{},
pick_from_excluded: Set = Set{},

fn init(arena: std.mem.Allocator, random: std.Random, opt: Options, game: anytype) !This {
    var options = opt;
    options.party_size_min = @min(opt.party_size_min, opt.party_size_max);
    options.party_size_max = @max(opt.party_size_min, opt.party_size_max);
    options.party_size_min = std.math.clamp(options.party_size_min, 1, 6);
    options.party_size_max = std.math.clamp(options.party_size_max, 1, 6);

    var valid_species = std.ArrayList(u16).init(arena);
    try game.validSpecies(&valid_species);

    var species_set = Set{};
    try species_set.ensureTotalCapacity(arena, valid_species.items.len);
    for (valid_species.items) |species|
        species_set.putAssumeCapacity(species, {});

    var species_by_ability = SpeciesByAbility{};
    var species_by_type = SpeciesByType{};
    var species_by_dual_type = SpeciesByDualType{};
    var stats: MinMax(u16) = .{
        .min = std.math.maxInt(u16),
        .max = 0,
    };
    species_by_ability = species_by_ability;
    species_by_type = species_by_type;
    species_by_dual_type = species_by_dual_type;

    const pokemons = try game.pokemons();
    for (species_set.keys()) |species| {
        const pokemon = try pokemons.at(species);

        const total_stats = pokemon.stats.total();
        stats.min = @min(stats.min, total_stats);
        stats.max = @max(stats.max, total_stats);

        for (pokemon.abilities) |ability| {
            if (ability == 0)
                continue;
            const entry = try species_by_ability.getOrPutValue(arena, ability, .{});
            try entry.value_ptr.put(arena, species, {});
        }

        var types: [2]u8 = .{ 0, 0 };
        comptime std.debug.assert(pokemon.types.len <= types.len);

        for (pokemon.types, 0..) |t, i| {
            const entry = try species_by_type.getOrPutValue(arena, t, .{});
            try entry.value_ptr.put(arena, species, {});
            types[i] = t;
        }
        {
            const entry = try species_by_dual_type.getOrPutValue(arena, .{
                @min(types[0], types[1]),
                @max(types[0], types[1]),
            }, .{});
            try entry.value_ptr.put(arena, species, {});
        }
    }

    return .{
        .arena = arena,
        .random = random,
        .options = options,
        .stats = stats,
        .species = species_set,
        .species_by_ability = species_by_ability,
        .species_by_type = species_by_type,
        .species_by_dual_type = species_by_dual_type,
    };
}

const Set = std.AutoArrayHashMapUnmanaged(u16, void);
const SpeciesByAbility = std.AutoArrayHashMapUnmanaged(u16, Set);
const SpeciesByType = std.AutoArrayHashMapUnmanaged(u8, Set);
const SpeciesByDualType = std.AutoArrayHashMapUnmanaged([2]u8, Set);

fn MinMax(comptime T: type) type {
    return struct { min: T, max: T };
}

const Themes = struct {
    types: ?[2]u8,
    ability: ?u16,
};

const Options = packed struct {
    seed: u64 = 0,
    party_size_max: u3 = 6,
    party_size_min: u3 = 1,
    moves: Move = .unchanged,
    held_items: HeldItem = .unchanged,
    abilities: AbilityTheme = .random,
    types: TypeTheme = .random,
    stats: Stats = .random0,
    party_size: PartySize = .unchanged,
    party_pokemons: PartyPokemons = .unchanged,
    avoid_same: bool = false,

    const Move = enum(u3) {
        none0,
        none1,
        none2,
        unchanged,
        best,
        best_for_level,
        random_learnable,
        random,
    };

    const HeldItem = enum(u2) {
        none0,
        none1,
        unchanged,
        random,
    };

    const AbilityTheme = enum(u2) {
        same0,
        same1,
        random,
        themed,
    };

    const TypeTheme = enum(u2) {
        same,
        random,
        themed,
        dual_themed,
    };

    const Stats = enum(u2) {
        random0,
        random1,
        similar,
        follow_level,
    };

    const PartySize = enum(u2) {
        unchanged,
        minimum,
        follow_level,
        random,
    };

    const PartyPokemons = enum(u1) {
        unchanged,
        randomize,
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
        .party_pokemons = .randomize,
    }, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 50 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 58 } },
                .{ .base = .{ .level = 8, .species = 55 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 2 } },
                .{ .base = .{ .level = 15, .species = 75 } },
                .{ .base = .{ .level = 15, .species = 4 } },
                .{ .base = .{ .level = 17, .species = 130 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 128 } },
                .{ .base = .{ .level = 16, .species = 45 } },
                .{ .base = .{ .level = 18, .species = 12 } },
                .{ .base = .{ .level = 20, .species = 48 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 10 } },
                .{ .base = .{ .level = 23, .species = 16 } },
                .{ .base = .{ .level = 22, .species = 15 } },
                .{ .base = .{ .level = 20, .species = 10 } },
                .{ .base = .{ .level = 25, .species = 61 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 95 } },
                .{ .base = .{ .level = 38, .species = 18 } },
                .{ .base = .{ .level = 35, .species = 50 } },
                .{ .base = .{ .level = 35, .species = 61 } },
                .{ .base = .{ .level = 40, .species = 42 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 20 } },
                .{ .base = .{ .level = 45, .species = 7 } },
                .{ .base = .{ .level = 45, .species = 42 } },
                .{ .base = .{ .level = 47, .species = 66 } },
                .{ .base = .{ .level = 50, .species = 58 } },
                .{ .base = .{ .level = 53, .species = 21 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 98 } },
                .{ .base = .{ .level = 59, .species = 138 } },
                .{ .base = .{ .level = 61, .species = 7 } },
                .{ .base = .{ .level = 61, .species = 38 } },
                .{ .base = .{ .level = 63, .species = 59 } },
                .{ .base = .{ .level = 65, .species = 54 } },
            }),
        };
        break :blk res;
    });
    try doTest(.{
        .party_size_min = 1,
        .party_size_max = 1,
    }, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 16 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 18 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 18 } },
            }),
        };
        break :blk res;
    });
    try doTest(.{
        .party_size_min = 6,
        .party_size_max = 6,
    }, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 16 } },
                .{ .base = .{ .level = 8, .species = 1 } },
                .{ .base = .{ .level = 9, .species = 16 } },
                .{ .base = .{ .level = 8, .species = 1 } },
                .{ .base = .{ .level = 9, .species = 16 } },
                .{ .base = .{ .level = 8, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 63 } },
                .{ .base = .{ .level = 15, .species = 19 } },
                .{ .base = .{ .level = 17, .species = 1 } },
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 63 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 17 } },
                .{ .base = .{ .level = 16, .species = 20 } },
                .{ .base = .{ .level = 18, .species = 64 } },
                .{ .base = .{ .level = 20, .species = 2 } },
                .{ .base = .{ .level = 19, .species = 17 } },
                .{ .base = .{ .level = 16, .species = 20 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 17 } },
                .{ .base = .{ .level = 23, .species = 130 } },
                .{ .base = .{ .level = 22, .species = 58 } },
                .{ .base = .{ .level = 20, .species = 64 } },
                .{ .base = .{ .level = 25, .species = 2 } },
                .{ .base = .{ .level = 25, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 18 } },
                .{ .base = .{ .level = 38, .species = 130 } },
                .{ .base = .{ .level = 35, .species = 58 } },
                .{ .base = .{ .level = 35, .species = 65 } },
                .{ .base = .{ .level = 40, .species = 3 } },
                .{ .base = .{ .level = 37, .species = 18 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
                .{ .base = .{ .level = 45, .species = 111 } },
                .{ .base = .{ .level = 45, .species = 130 } },
                .{ .base = .{ .level = 47, .species = 58 } },
                .{ .base = .{ .level = 50, .species = 65 } },
                .{ .base = .{ .level = 53, .species = 3 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 18 } },
                .{ .base = .{ .level = 59, .species = 65 } },
                .{ .base = .{ .level = 61, .species = 112 } },
                .{ .base = .{ .level = 61, .species = 130 } },
                .{ .base = .{ .level = 63, .species = 59 } },
                .{ .base = .{ .level = 65, .species = 3 } },
            }),
        };
        break :blk res;
    });
    try doTest(.{
        .party_size_min = 1,
        .party_size_max = 6,
        .party_size = .random,
    }, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 16 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 63 } },
                .{ .base = .{ .level = 15, .species = 19 } },
                .{ .base = .{ .level = 17, .species = 1 } },
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 63 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 17 } },
                .{ .base = .{ .level = 23, .species = 130 } },
                .{ .base = .{ .level = 22, .species = 58 } },
                .{ .base = .{ .level = 20, .species = 64 } },
                .{ .base = .{ .level = 25, .species = 2 } },
                .{ .base = .{ .level = 25, .species = 17 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 18 } },
                .{ .base = .{ .level = 38, .species = 130 } },
                .{ .base = .{ .level = 35, .species = 58 } },
                .{ .base = .{ .level = 35, .species = 65 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
                .{ .base = .{ .level = 45, .species = 111 } },
                .{ .base = .{ .level = 45, .species = 130 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 18 } },
                .{ .base = .{ .level = 59, .species = 65 } },
                .{ .base = .{ .level = 61, .species = 112 } },
            }),
        };
        break :blk res;
    });
    try doTest(.{
        .party_size_min = 1,
        .party_size_max = 6,
        .party_size = .follow_level,
    }, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 16 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 63 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 17 } },
                .{ .base = .{ .level = 16, .species = 20 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 17 } },
                .{ .base = .{ .level = 23, .species = 130 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 18 } },
                .{ .base = .{ .level = 38, .species = 130 } },
                .{ .base = .{ .level = 35, .species = 58 } },
                .{ .base = .{ .level = 35, .species = 65 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
                .{ .base = .{ .level = 45, .species = 111 } },
                .{ .base = .{ .level = 45, .species = 130 } },
                .{ .base = .{ .level = 47, .species = 58 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 18 } },
                .{ .base = .{ .level = 59, .species = 65 } },
                .{ .base = .{ .level = 61, .species = 112 } },
                .{ .base = .{ .level = 61, .species = 130 } },
                .{ .base = .{ .level = 63, .species = 59 } },
                .{ .base = .{ .level = 65, .species = 3 } },
            }),
        };
        break :blk res;
    });
    try doTest(.{
        .party_pokemons = .randomize,
        .stats = .similar,
    }, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 21 } },
                .{ .base = .{ .level = 8, .species = 4 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 43 } },
                .{ .base = .{ .level = 15, .species = 16 } },
                .{ .base = .{ .level = 17, .species = 102 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 100 } },
                .{ .base = .{ .level = 16, .species = 51 } },
                .{ .base = .{ .level = 18, .species = 44 } },
                .{ .base = .{ .level = 20, .species = 8 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 83 } },
                .{ .base = .{ .level = 23, .species = 6 } },
                .{ .base = .{ .level = 22, .species = 83 } },
                .{ .base = .{ .level = 20, .species = 8 } },
                .{ .base = .{ .level = 25, .species = 47 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 71 } },
                .{ .base = .{ .level = 38, .species = 6 } },
                .{ .base = .{ .level = 35, .species = 83 } },
                .{ .base = .{ .level = 35, .species = 34 } },
                .{ .base = .{ .level = 40, .species = 6 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
                .{ .base = .{ .level = 45, .species = 58 } },
                .{ .base = .{ .level = 45, .species = 3 } },
                .{ .base = .{ .level = 47, .species = 111 } },
                .{ .base = .{ .level = 50, .species = 31 } },
                .{ .base = .{ .level = 53, .species = 121 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 82 } },
                .{ .base = .{ .level = 59, .species = 127 } },
                .{ .base = .{ .level = 61, .species = 65 } },
                .{ .base = .{ .level = 61, .species = 3 } },
                .{ .base = .{ .level = 63, .species = 130 } },
                .{ .base = .{ .level = 65, .species = 73 } },
            }),
        };
        break :blk res;
    });
    try doTest(.{
        .party_pokemons = .randomize,
        .stats = .similar,
        .avoid_same = true,
    }, core.dummy.default, blk: {
        var res = core.dummy.default;
        res.trainer_parties = &.{
            .init(.none, &.{
                .{ .base = .{ .level = 5, .species = 1 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 9, .species = 21 } },
                .{ .base = .{ .level = 8, .species = 4 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 18, .species = 17 } },
                .{ .base = .{ .level = 15, .species = 43 } },
                .{ .base = .{ .level = 15, .species = 16 } },
                .{ .base = .{ .level = 17, .species = 102 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 19, .species = 100 } },
                .{ .base = .{ .level = 16, .species = 51 } },
                .{ .base = .{ .level = 18, .species = 8 } },
                .{ .base = .{ .level = 20, .species = 20 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 25, .species = 83 } },
                .{ .base = .{ .level = 23, .species = 6 } },
                .{ .base = .{ .level = 22, .species = 138 } },
                .{ .base = .{ .level = 20, .species = 8 } },
                .{ .base = .{ .level = 25, .species = 51 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 37, .species = 71 } },
                .{ .base = .{ .level = 38, .species = 6 } },
                .{ .base = .{ .level = 35, .species = 83 } },
                .{ .base = .{ .level = 35, .species = 34 } },
                .{ .base = .{ .level = 40, .species = 3 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 47, .species = 18 } },
                .{ .base = .{ .level = 45, .species = 58 } },
                .{ .base = .{ .level = 45, .species = 3 } },
                .{ .base = .{ .level = 47, .species = 33 } },
                .{ .base = .{ .level = 50, .species = 31 } },
                .{ .base = .{ .level = 53, .species = 134 } },
            }),
            .init(.none, &.{
                .{ .base = .{ .level = 61, .species = 82 } },
                .{ .base = .{ .level = 59, .species = 127 } },
                .{ .base = .{ .level = 61, .species = 65 } },
                .{ .base = .{ .level = 61, .species = 3 } },
                .{ .base = .{ .level = 63, .species = 130 } },
                .{ .base = .{ .level = 65, .species = 91 } },
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
