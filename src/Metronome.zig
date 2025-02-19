gpa: std.mem.Allocator,
arena: std.mem.Allocator,
random: std.Random,
cache: Cache,

// `randomSpeciesWithSimilarTotalStats` uses metronome as a buffer that is reused between calls
similar: Cache.SpeciesList = .{},

// TODO: Document where used
intersection: Cache.SpeciesSet = .{},
pick_from_excluded: Cache.SpeciesSet = .{},

pub fn init(gpa: std.mem.Allocator, arena: std.mem.Allocator, random: std.Random) !Metronome {
    return .{
        .gpa = gpa,
        .arena = arena,
        .random = random,
        .cache = .{ .arena = arena },
    };
}

pub const RandomizeTrainerOptions = struct {
    seed: u64 = 0,
    party_size_max: u3 = 6,
    party_size_min: u3 = 1,
    // moves: Move = .unchanged, TODO
    // held_items: HeldItem = .unchanged, TODO
    abilities: AbilityTheme = .random,
    types: TypeTheme = .random,
    stats: Stats = .random,
    party_size: PartySize = .unchanged,
    party_pokemons: PartyPokemons = .unchanged,
    avoid_same: bool = false,

    const Move = enum {
        none,
        unchanged,
        best,
        best_for_level,
        random_learnable,
        random,
    };

    const HeldItem = enum {
        none,
        unchanged,
        random,
    };

    const AbilityTheme = enum {
        same,
        random,
        themed,
    };

    const TypeTheme = enum {
        same,
        random,
        themed,
        dual_themed,
    };

    const Stats = enum {
        random,
        similar,
        follow_level,
    };

    const PartySize = enum {
        unchanged,
        minimum,
        follow_level,
        random,
    };

    const PartyPokemons = enum {
        unchanged,
        randomize,
    };
};

pub fn randomizeTrainers(
    metronome: *Metronome,
    options: RandomizeTrainerOptions,
    game: anytype,
) !void {
    const species = try metronome.cache.species(game);
    if (species.count() == 0)
        return;

    const parties = try game.trainerParties();

    var i: usize = 0;
    while (i < parties.len()) : (i += 1) {
        const party = parties.at(i) catch continue;
        if (party.size == 0)
            continue;

        try metronome.randomizeParty(options, game, party);
    }
}

test randomizeTrainers {
    try testCommand(0, RandomizeTrainerOptions{}, randomizeTrainers, core.dummy.default);
    try testCommand(0, RandomizeTrainerOptions{
        .party_pokemons = .randomize,
    }, randomizeTrainers, blk: {
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
    try testCommand(0, RandomizeTrainerOptions{
        .party_size_min = 1,
        .party_size_max = 1,
    }, randomizeTrainers, blk: {
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
    try testCommand(0, RandomizeTrainerOptions{
        .party_size_min = 6,
        .party_size_max = 6,
    }, randomizeTrainers, blk: {
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
    try testCommand(0, RandomizeTrainerOptions{
        .party_size_min = 1,
        .party_size_max = 6,
        .party_size = .random,
    }, randomizeTrainers, blk: {
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
    try testCommand(0, RandomizeTrainerOptions{
        .party_size_min = 1,
        .party_size_max = 6,
        .party_size = .follow_level,
    }, randomizeTrainers, blk: {
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
    try testCommand(0, RandomizeTrainerOptions{
        .party_pokemons = .randomize,
        .stats = .similar,
    }, randomizeTrainers, blk: {
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
    try testCommand(0, RandomizeTrainerOptions{
        .party_pokemons = .randomize,
        .stats = .similar,
        .avoid_same = true,
    }, randomizeTrainers, blk: {
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

fn randomizeParty(
    metronome: *Metronome,
    options: RandomizeTrainerOptions,
    game: anytype,
    party: anytype,
) !void {
    const themes = TrainerTheme{
        .types = switch (options.types) {
            .themed => blk: {
                const species_by = try metronome.cache.speciesByType(game);
                const t = metronome.randomItem(species_by.keys()).?.*;
                break :blk [_]u8{ t, t };
            },
            .dual_themed => blk: {
                const species_by = try metronome.cache.speciesByDualType(game);
                break :blk metronome.randomItem(species_by.keys()).?.*;
            },
            else => null,
        },
        .ability = switch (options.abilities) {
            .themed => blk: {
                const species_by = try metronome.cache.speciesByAbility(game);
                break :blk metronome.randomItem(species_by.keys()).?.*;
            },
            else => null,
        },
    };

    // const wants_moves = switch (options.moves) { TODO
    //     .unchanged => party.type.haveMoves(),
    //     .none => false,
    //     .best,
    //     .best_for_level,
    //     .random_learnable,
    //     .random,
    //     => true,
    // };
    // const wants_items = switch (options.held_items) { TODO
    //     .unchanged => party.type.haveItem(),
    //     .random => true,
    //     .none => false,
    // };

    const average_level = averagePartyLevel(party);
    const old_party_size = party.size;
    party.size = switch (options.party_size) {
        .unchanged => std.math.clamp(
            party.size,
            options.party_size_min,
            options.party_size_max,
        ),
        .random => metronome.random.intRangeAtMost(
            u8,
            options.party_size_min,
            options.party_size_max,
        ),
        .follow_level => partySizeLevelScaling(
            options.party_size_min,
            options.party_size_max,
            average_level,
        ),
        .minimum => options.party_size_min,
    };
    // party.type = switch (wants_moves) { TODO
    //     true => switch (wants_items) {
    //         true => .both,
    //         false => .moves,
    //     },
    //     false => switch (wants_items) {
    //         true => .item,
    //         false => .none,
    //     },
    // };

    // Fill trainer party with more Pokémons. The Pokémons we fill the party with are Pokémons that
    // are already in the party.
    if (old_party_size != 0) for (0..party.size) |to| {
        const from = to % old_party_size;
        party.members[to] = party.members[from];
    };
    @memset(party.members[party.size..], .{});

    const members = party.members[0..party.size];
    for (members, 0..) |*member, member_i| {
        switch (options.party_pokemons) {
            .randomize => try metronome.randomizePartyMember(
                options,
                themes,
                game,
                party.members[0..member_i],
                member,
            ),
            .unchanged => {},
        }
        // TODO:
        // switch (options.held_items) {
        //     .unchanged => {},
        //     .none0, .none1 => member.item = 0,
        //     .random => {}, // TODO
        // }
        // switch (options.moves) {
        //     .none0, .none1, .none2, .unchanged => {},
        //     .best, .best_for_level => {},
        //     .random_learnable => {},
        //     .random => {},
        // }
    }
}

const TrainerTheme = struct {
    types: ?[2]u8,
    ability: ?u16,
};

fn randomizePartyMember(
    metronome: *Metronome,
    options: RandomizeTrainerOptions,
    themes: TrainerTheme,
    game: anytype,
    other_members: anytype,
    member: anytype,
) !void {
    const pokemons = try game.pokemons();
    const pick_from_type = switch (options.types) {
        .same => blk: {
            const species_by = try metronome.cache.speciesByType(game);
            const pokemon = pokemons.at(member.base.species) catch break :blk metronome.species;
            break :blk species_by.get(pokemon.types[0]).?;
        },
        .themed => blk: {
            const species_by = try metronome.cache.speciesByType(game);
            break :blk species_by.get(themes.types.?[0]).?;
        },
        .dual_themed => blk: {
            const species_by = try metronome.cache.speciesByDualType(game);
            break :blk species_by.get(themes.types.?).?;
        },
        .random => Cache.SpeciesSet{},
    };

    var new_ability: ?u16 = null;
    const pick_from_ability = switch (options.abilities) {
        .same => blk: {
            const species = try metronome.cache.species(game);
            const pokemon = pokemons.at(member.base.species) catch break :blk metronome.species;
            const ability = pokemon.abilities[member.ability()];
            if (ability == 0)
                break :blk species.*;

            const species_by = try metronome.cache.speciesByAbility(game);
            new_ability = ability;
            break :blk species_by.get(ability).?;
        },
        .themed => blk: {
            const species_by = try metronome.cache.speciesByAbility(game);
            new_ability = themes.ability;
            break :blk species_by.get(themes.ability.?).?;
        },
        .random => Cache.SpeciesSet{},
    };

    if (options.abilities != .random and options.types != .random) {
        // The intersection between the type_set and ability_set will give
        // us all pokémons that have a certain type+ability pair. This is
        // the set we will pick from.
        var intersection = metronome.intersection.promote(metronome.arena);
        intersection.clearRetainingCapacity();

        try util.set.intersectInline(&intersection, pick_from_ability, pick_from_type);
        metronome.intersection = intersection.unmanaged;
    }

    // Pick the first set that has items in it.
    var pick_from = if (metronome.intersection.count() != 0)
        &metronome.intersection
    else if (pick_from_ability.count() != 0)
        &pick_from_ability
    else if (pick_from_type.count() != 0)
        &pick_from_type
    else
        (try metronome.cache.species(game));

    if (options.avoid_same) {
        // Now, we have to exclude party members already in the party. To do this we construct a
        // new set from `pick_from` with `other_party_members` excluded.
        metronome.pick_from_excluded.clearRetainingCapacity();
        try metronome.pick_from_excluded.ensureTotalCapacity(metronome.arena, pick_from.count());

        for (pick_from.keys()) |picked|
            metronome.pick_from_excluded.putAssumeCapacity(picked, {});
        for (other_members) |other_member|
            _ = metronome.pick_from_excluded.swapRemove(other_member.base.species);

        // If we end up with 0 things to pick from, then we cannot avoid same. So only use our
        // newly created set, if it actually has things to pick from.
        if (metronome.pick_from_excluded.count() != 0)
            pick_from = &metronome.pick_from_excluded;
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

    member.base.species = switch (options.stats) {
        .follow_level => try metronome.randomSpeciesWithStatsFollowingLevel(
            game,
            pick_from,
            member.base.level,
        ),
        .similar => if (pokemons.at(member.base.species)) |pokemon|
            try metronome.randomSpeciesWithSimilarTotalStats(
                game,
                pick_from,
                pokemon.stats.total(),
            )
        else |_|
            metronome.randomItem(pick_from.keys()).?.*,
        .random => metronome.randomItem(pick_from.keys()).?.*,
    };
}

pub const RandomizeStartersOptions = struct {
    seed: u64 = 0,
    starters: Starters = .unchanged,
    avoid_same: bool = false,

    const Starters = enum {
        unchanged,
        random,
        random_lowest_2_stage_evolution,
        random_lowest_3_stage_evolution,
        random_lowest_evolution,
    };
};

fn randomizeStarters(
    metronome: *Metronome,
    options: RandomizeStartersOptions,
    game: anytype,
) !void {
    const pick_from_base = switch (options.starters) {
        .random => try metronome.cache.species(game),
        .random_lowest_2_stage_evolution => &(try metronome.cache.lowestEvolutions(game)).stage_2,
        .random_lowest_3_stage_evolution => &(try metronome.cache.lowestEvolutions(game)).stage_3,
        .random_lowest_evolution => &(try metronome.cache.lowestEvolutions(game)).all,
        .unchanged => return,
    };
    if (pick_from_base.count() == 0)
        return error.NoStarterToPick;

    var pick_from = try pick_from_base.clone(metronome.gpa);
    defer pick_from.deinit(metronome.gpa);

    for (game.starters()) |*starter| {
        var pick_from_non_empty: *const Cache.SpeciesSet = &pick_from;
        if (pick_from_non_empty.count() == 0)
            pick_from_non_empty = pick_from_base;

        starter.* = metronome.randomItem(pick_from_non_empty.keys()).?.*;
        if (options.avoid_same)
            _ = pick_from.swapRemove(starter.*);
    }
}

test randomizeStarters {
    try testCommand(0, RandomizeStartersOptions{}, randomizeStarters, core.dummy.default);
    try testCommand(0, RandomizeStartersOptions{
        .starters = .random,
    }, randomizeStarters, blk: {
        var res = core.dummy.default;
        res.starters = &.{ 50, 58, 55 };
        break :blk res;
    });
    try testCommand(0, RandomizeStartersOptions{
        .starters = .random_lowest_2_stage_evolution,
    }, randomizeStarters, blk: {
        var res = core.dummy.default;
        res.starters = &.{ 52, 56, 54 };
        break :blk res;
    });
    try testCommand(0, RandomizeStartersOptions{
        .starters = .random_lowest_3_stage_evolution,
    }, randomizeStarters, blk: {
        var res = core.dummy.default;
        res.starters = &.{ 16, 29, 16 };
        break :blk res;
    });
    try testCommand(0, RandomizeStartersOptions{
        .starters = .random_lowest_3_stage_evolution,
        .avoid_same = true,
    }, randomizeStarters, blk: {
        var res = core.dummy.default;
        res.starters = &.{ 16, 147, 92 };
        break :blk res;
    });
    try testCommand(0, RandomizeStartersOptions{
        .starters = .random_lowest_evolution,
    }, randomizeStarters, blk: {
        var res = core.dummy.default;
        res.starters = &.{ 60, 74, 69 };
        break :blk res;
    });
}

const RandomizeWildEncountersOptions = struct {
    seed: u64 = 0,
    stats: Stats = .random,

    // TODO: Avoid same

    const Stats = enum {
        random,
        similar,
        follow_level,
    };
};

pub fn randomizeWildEncounters(
    metronome: *Metronome,
    options: RandomizeWildEncountersOptions,
    game: anytype,
) !void {
    const wild_areas = try game.wildAreas();
    var i: usize = 0;
    while (i < wild_areas.len()) : (i += 1) {
        const wild_pokemons = try wild_areas.at(i);

        var j: usize = 0;
        while (j < wild_pokemons.len()) : (j += 1) {
            const wild_pokemon = try wild_pokemons.at(j);
            try metronome.randomizeWildPokemon(options, game, wild_pokemon);
        }
    }
}

test randomizeWildEncounters {
    try testCommand(0, RandomizeWildEncountersOptions{}, randomizeWildEncounters, blk: {
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
    try testCommand(0, RandomizeWildEncountersOptions{
        .stats = .similar,
    }, randomizeWildEncounters, blk: {
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
    try testCommand(0, RandomizeWildEncountersOptions{
        .stats = .follow_level,
    }, randomizeWildEncounters, blk: {
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

fn randomizeWildPokemon(
    metronome: *Metronome,
    options: RandomizeWildEncountersOptions,
    game: anytype,
    wild_pokemon: anytype,
) !void {
    const pokemons = try game.pokemons();
    const species = try metronome.cache.species(game);
    wild_pokemon.setSpecies(switch (options.stats) {
        .similar => if (pokemons.at(wild_pokemon.species())) |pokemon|
            try metronome.randomSpeciesWithSimilarTotalStats(
                game,
                species,
                pokemon.stats.total(),
            )
        else |_|
            metronome.randomItem(species.keys()).?.*,
        .follow_level => try metronome.randomSpeciesWithStatsFollowingLevel(
            game,
            species,
            wild_pokemon.level(),
        ),
        .random => metronome.randomItem(species.keys()).?.*,
    });
}

const RandomizeStaticEncountersOptions = packed struct {
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

pub fn randomizeStaticEncouncters(
    metronome: *Metronome,
    options: RandomizeStaticEncountersOptions,
    game: anytype,
) !void {
    const legendaries = try metronome.cache.legendaries(game);
    const pick_from_legendaries = switch (options.legendary_with_legendary) {
        true => legendaries,
        false => try metronome.cache.species(game),
    };
    const pick_from_non_legendaries = switch (options.legendary_with_legendary) {
        true => try metronome.cache.noneLegendaries(game),
        false => try metronome.cache.species(game),
    };

    inline for (.{
        .{ options.static_pokemons, game.staticPokemons() },
        .{ options.given_pokemons, game.givenPokemons() },
    }) |item| switch (item[0]) {
        .unchanged => {},
        .randomize => for (item[1]) |*static_pokemon| {
            const pick_from = switch (legendaries.get(static_pokemon.species()) != null) {
                true => pick_from_legendaries,
                false => pick_from_non_legendaries,
            };

            const new_species = metronome.randomItem(pick_from.keys()).?.*;
            static_pokemon.setSpecies(new_species);
        },
    };
}

test randomizeStaticEncouncters {
    try testCommand(0, RandomizeStaticEncountersOptions{}, randomizeStaticEncouncters, core.dummy.default);
    try testCommand(0, RandomizeStaticEncountersOptions{
        .static_pokemons = .randomize,
    }, randomizeStaticEncouncters, blk: {
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
    try testCommand(0, RandomizeStaticEncountersOptions{
        .static_pokemons = .randomize,
        .legendary_with_legendary = true,
    }, randomizeStaticEncouncters, blk: {
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
    try testCommand(0, RandomizeStaticEncountersOptions{
        .given_pokemons = .randomize,
    }, randomizeStaticEncouncters, blk: {
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
    try testCommand(0, RandomizeStaticEncountersOptions{
        .given_pokemons = .randomize,
        .legendary_with_legendary = true,
    }, randomizeStaticEncouncters, blk: {
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

pub fn generateWiki(metronome: *Metronome, game: anytype) !void {
    var arena_state = std.heap.ArenaAllocator.init(metronome.gpa);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const header =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\<style>
        \\
        \\* {font-family: Arial, Helvetica, sans-serif;}
        \\.type {border-style: solid; border-width: 1px; border-color: black; color: white;}
        \\.type_Bug {background-color: #88960e;}
        \\.type_Dark {background-color: #3c2d23;}
        \\.type_Dragon {background-color: #4e3ba4;}
        \\.type_Electric {background-color: #e79302;}
        \\.type_Fairy {background-color: #e08ee0;}
        \\.type_Fighting {background-color: #5f2311;}
        \\.type_Fight {background-color: #5f2311;}
        \\.type_Fire {background-color: #c72100;}
        \\.type_Flying {background-color: #5d73d4;}
        \\.type_Ghost {background-color: #454593;}
        \\.type_Grass {background-color: #389a02;}
        \\.type_Ground {background-color: #ad8c33;}
        \\.type_Ice {background-color: #6dd3f5;}
        \\.type_Normal {background-color: #ada594;}
        \\.type_Poison {background-color: #6b246e;}
        \\.type_Psychic {background-color: #dc3165;}
        \\.type_Psychc {background-color: #dc3165;}
        \\.type_Rock {background-color: #9e863d;}
        \\.type_Steel {background-color: #8e8e9f;}
        \\.type_Water {background-color: #0c67c2;}
        \\
        \\.pokemon_stat {width:80%; border-style: solid; border-width: 1px; border-color: black;}
        \\.pokemon_stat_hp {background-color: #6ab04c;}
        \\.pokemon_stat_attack {background-color: #eb4d4b;}
        \\.pokemon_stat_defense {background-color: #f0932b;}
        \\.pokemon_stat_sp_attack {background-color:#be2edd;}
        \\.pokemon_stat_sp_defense {background-color: #686de0;}
        \\.pokemon_stat_speed {background-color: #f9ca24;}
        \\.pokemon_stat_total {background-color: #95afc0;}
        \\.pokemon_stat_p0 {width: 0%}
        \\.pokemon_stat_p1 {width: 1%}
        \\.pokemon_stat_p2 {width: 2%}
        \\.pokemon_stat_p3 {width: 3%}
        \\.pokemon_stat_p4 {width: 4%}
        \\.pokemon_stat_p5 {width: 5%}
        \\.pokemon_stat_p6 {width: 6%}
        \\.pokemon_stat_p7 {width: 7%}
        \\.pokemon_stat_p8 {width: 8%}
        \\.pokemon_stat_p9 {width: 9%}
        \\.pokemon_stat_p10 {width: 10%}
        \\.pokemon_stat_p11 {width: 11%}
        \\.pokemon_stat_p12 {width: 12%}
        \\.pokemon_stat_p13 {width: 13%}
        \\.pokemon_stat_p14 {width: 14%}
        \\.pokemon_stat_p15 {width: 15%}
        \\.pokemon_stat_p16 {width: 16%}
        \\.pokemon_stat_p17 {width: 17%}
        \\.pokemon_stat_p18 {width: 18%}
        \\.pokemon_stat_p19 {width: 19%}
        \\.pokemon_stat_p20 {width: 20%}
        \\.pokemon_stat_p21 {width: 21%}
        \\.pokemon_stat_p22 {width: 22%}
        \\.pokemon_stat_p23 {width: 23%}
        \\.pokemon_stat_p24 {width: 24%}
        \\.pokemon_stat_p25 {width: 25%}
        \\.pokemon_stat_p26 {width: 26%}
        \\.pokemon_stat_p27 {width: 27%}
        \\.pokemon_stat_p28 {width: 28%}
        \\.pokemon_stat_p29 {width: 29%}
        \\.pokemon_stat_p30 {width: 30%}
        \\.pokemon_stat_p31 {width: 31%}
        \\.pokemon_stat_p32 {width: 32%}
        \\.pokemon_stat_p33 {width: 33%}
        \\.pokemon_stat_p34 {width: 34%}
        \\.pokemon_stat_p35 {width: 35%}
        \\.pokemon_stat_p36 {width: 36%}
        \\.pokemon_stat_p37 {width: 37%}
        \\.pokemon_stat_p38 {width: 38%}
        \\.pokemon_stat_p39 {width: 39%}
        \\.pokemon_stat_p40 {width: 40%}
        \\.pokemon_stat_p41 {width: 41%}
        \\.pokemon_stat_p42 {width: 42%}
        \\.pokemon_stat_p43 {width: 43%}
        \\.pokemon_stat_p44 {width: 44%}
        \\.pokemon_stat_p45 {width: 45%}
        \\.pokemon_stat_p46 {width: 46%}
        \\.pokemon_stat_p47 {width: 47%}
        \\.pokemon_stat_p48 {width: 48%}
        \\.pokemon_stat_p49 {width: 49%}
        \\.pokemon_stat_p50 {width: 50%}
        \\.pokemon_stat_p51 {width: 51%}
        \\.pokemon_stat_p52 {width: 52%}
        \\.pokemon_stat_p53 {width: 53%}
        \\.pokemon_stat_p54 {width: 54%}
        \\.pokemon_stat_p55 {width: 55%}
        \\.pokemon_stat_p56 {width: 56%}
        \\.pokemon_stat_p57 {width: 57%}
        \\.pokemon_stat_p58 {width: 58%}
        \\.pokemon_stat_p59 {width: 59%}
        \\.pokemon_stat_p60 {width: 60%}
        \\.pokemon_stat_p61 {width: 61%}
        \\.pokemon_stat_p62 {width: 62%}
        \\.pokemon_stat_p63 {width: 63%}
        \\.pokemon_stat_p64 {width: 64%}
        \\.pokemon_stat_p65 {width: 65%}
        \\.pokemon_stat_p66 {width: 66%}
        \\.pokemon_stat_p67 {width: 67%}
        \\.pokemon_stat_p68 {width: 68%}
        \\.pokemon_stat_p69 {width: 69%}
        \\.pokemon_stat_p70 {width: 70%}
        \\.pokemon_stat_p71 {width: 71%}
        \\.pokemon_stat_p72 {width: 72%}
        \\.pokemon_stat_p73 {width: 73%}
        \\.pokemon_stat_p74 {width: 74%}
        \\.pokemon_stat_p75 {width: 75%}
        \\.pokemon_stat_p76 {width: 76%}
        \\.pokemon_stat_p77 {width: 77%}
        \\.pokemon_stat_p78 {width: 78%}
        \\.pokemon_stat_p79 {width: 79%}
        \\.pokemon_stat_p80 {width: 80%}
        \\.pokemon_stat_p81 {width: 81%}
        \\.pokemon_stat_p82 {width: 82%}
        \\.pokemon_stat_p83 {width: 83%}
        \\.pokemon_stat_p84 {width: 84%}
        \\.pokemon_stat_p85 {width: 85%}
        \\.pokemon_stat_p86 {width: 86%}
        \\.pokemon_stat_p87 {width: 87%}
        \\.pokemon_stat_p88 {width: 88%}
        \\.pokemon_stat_p89 {width: 89%}
        \\.pokemon_stat_p90 {width: 90%}
        \\.pokemon_stat_p91 {width: 91%}
        \\.pokemon_stat_p92 {width: 92%}
        \\.pokemon_stat_p93 {width: 93%}
        \\.pokemon_stat_p94 {width: 94%}
        \\.pokemon_stat_p95 {width: 95%}
        \\.pokemon_stat_p96 {width: 96%}
        \\.pokemon_stat_p97 {width: 97%}
        \\.pokemon_stat_p98 {width: 98%}
        \\.pokemon_stat_p99 {width: 99%}
        \\.pokemon_stat_p100 {width: 100%}
        \\
        \\</style>
        \\</head>
        \\<body>
        \\<main>
        \\
    ;

    const footer =
        \\</main>
        \\</body>
        \\</html>
        \\
    ;

    var content_root = std.ArrayList(u8).init(arena);
    var content_file = std.ArrayList(u8).init(arena);
    const content_root_writer = content_root.writer();
    const content_file_writer = content_file.writer();

    const cwd = std.fs.cwd();
    try cwd.deleteTree("wiki");

    var root_dir = try cwd.makeOpenPath("wiki", .{});
    defer root_dir.close();

    try root_dir.makeDir("pokemons");
    try root_dir.makeDir("trainers");

    try root_dir.writeFile(.{
        .sub_path = "index.html",
        .data = header ++
            \\<a href="./pokemons/index.html">Pokemons</a><br/>
            \\<a href="./trainers/index.html">Trainers</a><br/>
            \\
        ++ footer,
    });

    {
        content_root.shrinkRetainingCapacity(0);
        try content_root_writer.writeAll(header);

        const pokemons = try game.pokemons();
        var species: usize = 0;
        while (species < pokemons.len()) : (species += 1) {
            try content_root_writer.print("<a href=\"{:0>3}.html\">#{:0>3}</a><br/>\n", .{ species, species });

            content_file.shrinkRetainingCapacity(0);
            try content_file_writer.writeAll(header);

            if (pokemons.at(species)) |pokemon| {
                try content_file_writer.writeAll(
                    \\<table>
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Type:</td><td>
                );
                for (pokemon.types, 0..) |t, i| {
                    if (i != 0) try content_file_writer.writeAll(" ");
                    try content_file_writer.print("{}", .{t});
                }
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Abilities:</td><td>
                );
                for (pokemon.abilities, 0..) |a, i| {
                    if (i != 0) try content_file_writer.writeAll(" ");
                    try content_file_writer.print("{}", .{a});
                }
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Items:</td><td>
                );
                for (pokemon.items, 0..) |a, i| {
                    if (i != 0) try content_file_writer.writeAll(" ");
                    try content_file_writer.print("{}", .{a});
                }
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Egg Groups:</td><td>
                );
                for (pokemon.egg_groups, 0..) |e, i| {
                    switch (e) {
                        .invalid,
                        .monster,
                        .water1,
                        .bug,
                        .flying,
                        .field,
                        .fairy,
                        .grass,
                        .human_like,
                        .water3,
                        .mineral,
                        .amorphous,
                        .water2,
                        .ditto,
                        .dragon,
                        .undiscovered,
                        => {},
                        _ => continue,
                    }

                    if (i != 0) try content_file_writer.writeAll(" ");
                    try content_file_writer.print("{s}", .{@tagName(e)});
                }
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Gender ratio:</td><td>
                );
                try content_file_writer.print("{}", .{pokemon.gender_ratio});
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Catch rate:</td><td>
                );
                try content_file_writer.print("{}", .{pokemon.catch_rate});
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Growth Rate:</td><td>
                );
                try content_file_writer.print("{s}", .{@tagName(pokemon.growth_rate)});
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                const stat_names = [_][2][]const u8{
                    .{ "hp", "Hp" },
                    .{ "attack", "Attack" },
                    .{ "defense", "Defense" },
                    .{ "sp_attack", "Sp. Atk" },
                    .{ "sp_defense", "Sp. Def" },
                    .{ "speed", "Speed" },
                };

                var total_stats: usize = 0;
                inline for (stat_names) |stat| {
                    const value = @field(pokemon.stats, stat[0]);
                    const percent: u8 = @intFromFloat((@as(f64, @floatFromInt(value)) / 255) * 100);
                    try content_file_writer.print("<tr><td>{s}:</td><td class=\"pokemon_stat\"><div class=\"pokemon_stat_p{} pokemon_stat_{s}\">{}</div></td></tr>\n", .{ stat[1], percent, stat[0], value });
                    total_stats += value;
                }

                const percent: u8 = @intFromFloat((@as(f64, @floatFromInt(total_stats)) / 1000) * 100);
                try content_file_writer.print("<tr><td>Total:</td><td class=\"pokemon_stat\"><div class=\"pokemon_stat_p{} pokemon_stat_total\">{}</div></td></tr>\n", .{ percent, total_stats });

                try content_file_writer.writeAll(
                    \\</table>
                    \\
                );
            } else |_| {}

            try content_file_writer.writeAll(footer);

            var buf: [128]u8 = undefined;
            try root_dir.writeFile(.{
                .sub_path = try std.fmt.bufPrint(&buf, "pokemons/{:0>3}.html", .{species}),
                .data = content_file.items,
            });
        }

        try content_root_writer.writeAll(footer);

        try root_dir.writeFile(.{
            .sub_path = "pokemons/index.html",
            .data = content_root.items,
        });
    }

    {
        content_root.shrinkRetainingCapacity(0);
        try content_root_writer.writeAll(header);

        const trainers = try game.trainers();
        const trainer_parties = try game.trainerParties();

        var trainer_id: usize = 0;
        while (trainer_id < trainers.len()) : (trainer_id += 1) {
            try content_root_writer.print("<a href=\"{:0>3}.html\">#{:0>3}</a><br/>\n", .{ trainer_id, trainer_id });

            content_file.shrinkRetainingCapacity(0);
            try content_file_writer.writeAll(header);

            done: {
                const trainer = trainers.at(trainer_id) catch break :done;
                _ = trainer; // autofix
                const party = trainer_parties.at(trainer_id) catch break :done;

                try content_file_writer.writeAll(
                    \\<table>
                );

                for (party.members[0..party.size], 0..) |member, i| {
                    try content_file_writer.print(
                        \\<tr><td>Party Member {}:</td><td>lvl {} <a href="../pokemons/{:0>3}.html">{:0>3}</a></td></tr>
                        \\
                    , .{ i, member.base.level, member.base.species, member.base.species });
                }

                try content_file_writer.writeAll(
                    \\</table>
                    \\
                );
            }

            try content_file_writer.writeAll(footer);

            var buf: [128]u8 = undefined;
            try root_dir.writeFile(.{
                .sub_path = try std.fmt.bufPrint(&buf, "trainers/{:0>3}.html", .{trainer_id}),
                .data = content_file.items,
            });
        }

        try content_root_writer.writeAll(footer);

        try root_dir.writeFile(.{
            .sub_path = "trainers/index.html",
            .data = content_root.items,
        });
    }
}

test generateWiki {
    _ = generateWiki; // TODO
}

fn randomItem(metronome: Metronome, items: anytype) ?@TypeOf(&items[0]) {
    if (items.len == 0)
        return null;
    return &items[metronome.random.uintAtMost(usize, items.len - 1)];
}

fn randomSpeciesWithSimilarTotalStats(
    metronome: *Metronome,
    game: anytype,
    pick_from: *const Cache.SpeciesSet,
    total_stats: u16,
) !u16 {
    const pokemons = try game.pokemons();
    const range = 5;
    var min = @as(isize, @intCast(total_stats)) - range;
    var max = min + range * 2;

    metronome.similar.shrinkRetainingCapacity(0);
    while (metronome.similar.items.len < 25) : ({
        min -= range;
        max += range;
    }) {
        try metronome.similar.ensureUnusedCapacity(metronome.arena, pick_from.count());
        for (pick_from.keys()) |s| {
            const p = pokemons.at(s) catch continue;
            const total: isize = @intCast(p.stats.total());
            if (min <= total and total <= max)
                metronome.similar.appendAssumeCapacity(s);
        }
    }

    return metronome.randomItem(metronome.similar.items).?.*;
}

fn randomSpeciesWithStatsFollowingLevel(
    metronome: *Metronome,
    game: anytype,
    pick_from: *const Cache.SpeciesSet,
    level: u16,
) !u16 {
    const stats = try metronome.cache.totalStatsMinMax(game);
    return metronome.randomSpeciesWithSimilarTotalStats(
        game,
        pick_from,
        totalStatsLevelScaling(stats.min, stats.max, level),
    );
}

fn averagePartyLevel(party: anytype) u8 {
    if (party.size == 0)
        return 2;

    var sum: u16 = 0;
    for (party.members[0..party.size]) |member|
        sum += member.base.level;
    return @intCast(sum / party.size);
}

fn totalStatsLevelScaling(min: u16, max: u16, level: u16) u16 {
    const fmin: f64 = @floatFromInt(min);
    const fmax: f64 = @floatFromInt(max);
    const diff = fmax - fmin;
    const x: f64 = @floatFromInt(level);

    // Function adapted from -0.0001 * x^2 + 0.02 * x
    // This functions grows fast at the start, getting 75% to max stats at level 50.
    const a = -0.0001 * diff;
    const b = 0.02 * diff;
    const xp2 = std.math.pow(f64, x, 2);
    const res = a * xp2 + b * x + fmin;
    return @intFromFloat(res);
}

test totalStatsLevelScaling {
    try std.testing.expectEqual(@as(u16, 180), totalStatsLevelScaling(180, 720, 0));
    try std.testing.expectEqual(@as(u16, 282), totalStatsLevelScaling(180, 720, 10));
    try std.testing.expectEqual(@as(u16, 374), totalStatsLevelScaling(180, 720, 20));
    try std.testing.expectEqual(@as(u16, 455), totalStatsLevelScaling(180, 720, 30));
    try std.testing.expectEqual(@as(u16, 525), totalStatsLevelScaling(180, 720, 40));
    try std.testing.expectEqual(@as(u16, 585), totalStatsLevelScaling(180, 720, 50));
    try std.testing.expectEqual(@as(u16, 633), totalStatsLevelScaling(180, 720, 60));
    try std.testing.expectEqual(@as(u16, 671), totalStatsLevelScaling(180, 720, 70));
    try std.testing.expectEqual(@as(u16, 698), totalStatsLevelScaling(180, 720, 80));
    try std.testing.expectEqual(@as(u16, 714), totalStatsLevelScaling(180, 720, 90));
    try std.testing.expectEqual(@as(u16, 720), totalStatsLevelScaling(180, 720, 100));
}

fn partySizeLevelScaling(min: u8, max: u8, level: u16) u8 {
    std.debug.assert(min <= max);
    std.debug.assert(1 <= min and min <= 6);
    std.debug.assert(1 <= max and max <= 6);

    const max_party_size_level = 60;
    const steps = max - min;
    if (steps == 0)
        return max;

    const level_steps = max_party_size_level / steps;
    const res = level / level_steps;
    return @intCast(std.math.clamp(min + res, min, max));
}

test partySizeLevelScaling {
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 6, 0));
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 6, 5));
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 6, 10));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 6, 15));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 6, 20));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 6, 25));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 6, 30));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 6, 35));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 6, 40));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 6, 45));
    try std.testing.expectEqual(@as(u16, 5), partySizeLevelScaling(1, 6, 50));
    try std.testing.expectEqual(@as(u16, 5), partySizeLevelScaling(1, 6, 55));
    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(1, 6, 60));
    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(1, 6, 70));
    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(1, 6, 80));
    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(1, 6, 90));
    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(1, 6, 100));

    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 4, 0));
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 4, 5));
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 4, 10));
    try std.testing.expectEqual(@as(u16, 1), partySizeLevelScaling(1, 4, 15));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 4, 20));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 4, 25));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 4, 30));
    try std.testing.expectEqual(@as(u16, 2), partySizeLevelScaling(1, 4, 35));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 4, 40));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 4, 45));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 4, 50));
    try std.testing.expectEqual(@as(u16, 3), partySizeLevelScaling(1, 4, 55));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 4, 60));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 4, 70));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 4, 80));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 4, 90));
    try std.testing.expectEqual(@as(u16, 4), partySizeLevelScaling(1, 4, 100));

    try std.testing.expectEqual(@as(u16, 6), partySizeLevelScaling(6, 6, 100));
}

fn testCommand(
    seed: u64,
    options: anytype,
    function: anytype,
    expected: core.dummy.Game.Init,
) !void {
    var random = std.Random.DefaultPrng.init(seed);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const actual_game = try core.dummy.Game.init(arena, core.dummy.default);
    const expected_game = try core.dummy.Game.init(arena, expected);

    var metronome = try init(std.testing.allocator, arena, random.random());
    try function(&metronome, options, &actual_game);

    // Avoid large error trace by not using `catch` or `try` here
    const is_err = if (std.testing.expectEqualDeep(expected_game.m, actual_game.m)) false else |_| true;
    if (is_err) {
        const from_str = try std.fmt.allocPrint(arena, "{}", .{actual_game});
        const to_str = try std.fmt.allocPrint(arena, "{}", .{expected_game});
        try std.fs.cwd().writeFile(.{ .sub_path = ".zig-cache/from.json", .data = from_str });
        try std.fs.cwd().writeFile(.{ .sub_path = ".zig-cache/to.json", .data = to_str });
        return std.testing.expectEqualStrings(to_str, from_str);
    }
}

pub const Commands = struct {
    commands: std.ArrayListUnmanaged(Command),

    pub const Command = union(enum) {
        generate_wiki: void,
        randomize_starters: RandomizeStartersOptions,
        randomize_static_encounters: RandomizeStaticEncountersOptions,
        randomize_trainers: RandomizeTrainerOptions,
        randomize_wild_encounters: RandomizeWildEncountersOptions,
    };
};

pub fn runCommands(metronome: *Metronome, commands: Commands, game: anytype) !void {
    for (commands.commands.items) |command| switch (command) {
        .generate_wiki => try metronome.generateWiki(game),
        .randomize_starters => |options| try metronome.randomizeStarters(options, game),
        .randomize_static_encounters => |options| try metronome.randomizeStaticEncouncters(options, game),
        .randomize_trainers => |options| try metronome.randomizeTrainers(options, game),
        .randomize_wild_encounters => |options| try metronome.randomizeWildEncounters(options, game),
    };
}

test runCommands {
    // Just tests that the function compiles
    var random = std.Random.DefaultPrng.init(0);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const game = try core.dummy.Game.init(arena, core.dummy.default);

    var metronome = try init(std.testing.allocator, arena, random.random());
    try metronome.runCommands(.{ .commands = .{} }, &game);
}

const Metronome = @This();

test {
    _ = Cache;

    _ = core;
    _ = util;
}

const Cache = @import("Metronome/Cache.zig");

const core = @import("core.zig");
const util = @import("util.zig");

const std = @import("std");
