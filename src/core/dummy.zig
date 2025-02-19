pub const Game = struct {
    arena: std.heap.ArenaAllocator,
    m: struct {
        starters: []u16,
        static_pokemons: []StaticPokemon,
        given_pokemons: []StaticPokemon,
        pokemons: []Pokemon,
        trainers: []Trainer,
        trainer_parties: []Party,
        wild_areas: []WildArea,
    },

    pub fn init(gpa: std.mem.Allocator, values: Init) !Game {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        const arena = arena_state.allocator();
        errdefer arena_state.deinit();

        var res = Game{
            .arena = undefined,
            .m = .{
                .starters = try arena.dupe(u16, values.starters),
                .static_pokemons = try arena.dupe(StaticPokemon, values.static_pokemons),
                .given_pokemons = try arena.dupe(StaticPokemon, values.given_pokemons),
                .pokemons = try arena.dupe(Pokemon, values.pokemons),
                .trainers = try arena.dupe(Trainer, values.trainers),
                .trainer_parties = try arena.dupe(Party, values.trainer_parties),
                .wild_areas = try arena.dupe(WildArea, values.wild_areas),
            },
        };
        res.arena = arena_state;
        return res;
    }

    pub fn deinit(game: Game) void {
        game.arena.deinit();
    }

    pub fn starters(game: Game) []u16 {
        return game.m.starters;
    }

    pub fn staticPokemons(game: Game) []StaticPokemon {
        return game.m.static_pokemons;
    }

    pub fn givenPokemons(game: Game) []StaticPokemon {
        return game.m.given_pokemons;
    }

    pub fn pokemons(game: Game) !Pokemons {
        return .{ .slice = game.m.pokemons };
    }

    pub fn evolutions(game: Game) !Evolutions {
        return .{ .pokemons = game.m.pokemons };
    }

    pub fn trainers(game: Game) !Trainers {
        return .{ .slice = game.m.trainers };
    }

    pub fn trainerParties(game: Game) !Parties {
        return .{ .slice = game.m.trainer_parties };
    }

    pub fn wildAreas(game: Game) !WildAreas {
        return .{ .slice = game.m.wild_areas };
    }

    pub fn validSpecies(game: Game, out: *std.ArrayList(u16)) !void {
        try out.ensureUnusedCapacity(game.m.pokemons.len);
        for (1..game.m.pokemons.len) |species|
            out.appendAssumeCapacity(@intCast(species));
    }

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        _ = fmt;
        _ = options;
        return std.json.stringify(self.m, .{
            .whitespace = .indent_2,
            .emit_strings_as_arrays = true,
        }, writer);
    }

    pub const Init = struct {
        starters: []const u16,
        static_pokemons: []const StaticPokemon,
        given_pokemons: []const StaticPokemon,
        pokemons: []const Pokemon,
        trainers: []const Trainer,
        trainer_parties: []const Party,
        wild_areas: []const WildArea,
    };
};

pub const Pokemon = struct {
    stats: common.Stats,
    types: [2]u8,
    abilities: [3]u8,
    items: [3]u16,
    gender_ratio: u8,
    catch_rate: u8,
    growth_rate: common.GrowthRate,
    egg_groups: [2]common.EggGroup,
    evolutions: [3]Evolution,

    pub fn init(values: struct {
        stats: common.Stats,
        types: [2]u8,
        abilities: [3]u8,
        gender_ratio: u8,
        catch_rate: u8,
        growth_rate: common.GrowthRate,
        egg_groups: [2]common.EggGroup,
        evolutions: []const Evolution,
    }) Pokemon {
        var res = Pokemon{
            .stats = values.stats,
            .types = values.types,
            .abilities = values.abilities,
            .items = .{ 0, 0, 0 },
            .gender_ratio = values.gender_ratio,
            .catch_rate = values.catch_rate,
            .growth_rate = values.growth_rate,
            .egg_groups = values.egg_groups,
            .evolutions = @splat(.{}),
        };
        @memcpy(res.evolutions[0..values.evolutions.len], values.evolutions);
        return res;
    }
};

pub const Evolution = struct {
    method: common.EvoMethod = .unused,
    target: u16 = 0,
};

pub const Trainer = struct {};

pub const Party = struct {
    size: u8,
    type: common.PartyType,
    members: [6]gen5.PartyMemberBoth,

    pub fn init(t: common.PartyType, members: []const gen5.PartyMemberBoth) Party {
        var res = Party{
            .size = @intCast(members.len),
            .type = t,
            .members = @splat(.{}),
        };
        @memcpy(res.members[0..members.len], members);
        return res;
    }
};

pub const WildReplacement = struct {
    species: u16,
};

pub const WildPokemon = struct {
    m: struct {
        min_level: u8,
        max_level: u8,
        species: u16,
    },

    pub fn init(s: u16, min: u8, max: u8) WildPokemon {
        return .{ .m = .{
            .species = s,
            .min_level = min,
            .max_level = max,
        } };
    }

    pub fn species(pokemon: WildPokemon) u16 {
        return pokemon.m.species;
    }

    pub fn setSpecies(pokemon: *WildPokemon, s: u16) void {
        pokemon.m.species = s;
    }

    pub fn level(pokemon: WildPokemon) u8 {
        return (pokemon.m.min_level + pokemon.m.max_level) / 2;
    }

    pub fn setLevel(pokemon: *WildPokemon, l: u8) void {
        pokemon.m.min_level = l;
        pokemon.m.max_level = l;
    }
};

pub const WildArea = struct {
    size: u8,
    mons: [8]WildPokemon,

    pub fn init(mons: []const WildPokemon) WildArea {
        var res = WildArea{
            .size = @intCast(mons.len),
            .mons = @splat(.init(0, 0, 0)),
        };
        @memcpy(res.mons[0..mons.len], mons);
        return res;
    }

    pub fn at(area: *WildArea, i: usize) !*WildPokemon {
        std.debug.assert(i < area.size);
        return &area.mons[i];
    }

    pub fn len(area: WildArea) usize {
        return area.size;
    }
};

pub const Evolutions = struct {
    pokemons: []Pokemon,

    pub fn at(evos: @This(), i: usize) ![]Evolution {
        return &evos.pokemons[i].evolutions;
    }

    pub fn len(evos: @This()) usize {
        return evos.pokemons.len;
    }
};

const StaticPokemon = struct {
    m: struct {
        species: u16,
        level: u8,
    },

    pub fn init(s: u16, l: u8) StaticPokemon {
        return .{ .m = .{ .species = s, .level = l } };
    }

    pub fn species(pokemon: StaticPokemon) u16 {
        return pokemon.m.species;
    }

    pub fn setSpecies(pokemon: *StaticPokemon, s: u16) void {
        pokemon.m.species = s;
    }

    pub fn level(pokemon: StaticPokemon) u8 {
        return pokemon.m.level;
    }

    pub fn setLevel(pokemon: *StaticPokemon, l: u8) void {
        pokemon.m.level = l;
    }
};

pub const Pokemons = common.IndexableSlice(Pokemon);
pub const Trainers = common.IndexableSlice(Trainer);
pub const Parties = common.IndexableSlice(Party);
pub const WildAreas = common.IndexableSlice(WildArea);

pub fn doTest(options: anytype, function: anytype, from: Game.Init, to: Game.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const from_game = try Game.init(arena, from);
    const to_game = try Game.init(arena, to);
    try function(std.testing.allocator, options, from_game);

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

pub fn doFuzz(comptime Options: type, comptime function: anytype) !void {
    return std.testing.fuzz({}, struct {
        fn fuzzOne(_: void, input: []const u8) !void {
            var options: Options = .{};
            const options_bytes = std.mem.asBytes(&options);
            const len = @min(options_bytes.len, input.len);
            @memcpy(options_bytes[0..len], input[0..len]);

            // We might get enums that do not exhaust all its bits. Handle this by finding each
            // enum field, take the integer value and converting it to a valid tag for that enum
            inline for (std.meta.fields(Options)) |field| {
                const field_info = @typeInfo(field.type);
                if (field_info != .@"enum")
                    continue;

                const tags = std.meta.tags(field.type);
                const field_value = @intFromEnum(@field(options, field.name));
                @field(options, field.name) = tags[field_value % tags.len];
            }

            var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
            const arena = arena_state.allocator();
            defer arena_state.deinit();

            const first = try Game.init(arena, default);
            const second = try Game.init(arena, default);
            try function(std.testing.allocator, options, first);
            try function(std.testing.allocator, options, second);
            try std.testing.expectEqualDeep(first.m, second.m);
        }
    }.fuzzOne, .{});
}

pub const default = Game.Init{
    .starters = &.{ 1, 4, 7 },
    .static_pokemons = &.{
        .init(143, 30),
        .init(144, 50),
        .init(145, 50),
        .init(146, 50),
        .init(150, 70),
    },
    .given_pokemons = &.{
        .init(106, 30),
        .init(107, 30),
        .init(129, 5),
        .init(131, 15),
        .init(133, 25),
        .init(138, 30),
        .init(140, 30),
        .init(142, 30),
    },
    .pokemons = &.{
        .init(.{
            .stats = .{
                .hp = 0,
                .attack = 0,
                .defense = 0,
                .sp_attack = 0,
                .sp_defense = 0,
                .speed = 0,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 0, 0, 0 },
            .gender_ratio = 255,
            .catch_rate = 0,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .invalid, .invalid },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 45,
                .attack = 49,
                .defense = 49,
                .sp_attack = 65,
                .sp_defense = 65,
                .speed = 45,
            },
            .types = .{ 11, 3 },
            .abilities = .{ 65, 0, 34 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .grass },
            .evolutions = &.{
                .{ .method = .level_up, .target = 2 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 62,
                .defense = 63,
                .sp_attack = 80,
                .sp_defense = 80,
                .speed = 60,
            },
            .types = .{ 11, 3 },
            .abilities = .{ 65, 0, 34 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .grass },
            .evolutions = &.{
                .{ .method = .level_up, .target = 3 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 80,
                .attack = 82,
                .defense = 83,
                .sp_attack = 100,
                .sp_defense = 100,
                .speed = 80,
            },
            .types = .{ 11, 3 },
            .abilities = .{ 65, 0, 34 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .grass },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 39,
                .attack = 52,
                .defense = 43,
                .sp_attack = 60,
                .sp_defense = 50,
                .speed = 65,
            },
            .types = .{ 9, 9 },
            .abilities = .{ 66, 0, 94 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .dragon },
            .evolutions = &.{
                .{ .method = .level_up, .target = 5 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 58,
                .attack = 64,
                .defense = 58,
                .sp_attack = 80,
                .sp_defense = 65,
                .speed = 80,
            },
            .types = .{ 9, 9 },
            .abilities = .{ 66, 0, 94 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .dragon },
            .evolutions = &.{
                .{ .method = .level_up, .target = 6 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 78,
                .attack = 84,
                .defense = 78,
                .sp_attack = 109,
                .sp_defense = 85,
                .speed = 100,
            },
            .types = .{ 9, 2 },
            .abilities = .{ 66, 0, 94 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .dragon },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 44,
                .attack = 48,
                .defense = 65,
                .sp_attack = 50,
                .sp_defense = 64,
                .speed = 43,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 67, 0, 44 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .water1 },
            .evolutions = &.{
                .{ .method = .level_up, .target = 8 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 59,
                .attack = 63,
                .defense = 80,
                .sp_attack = 65,
                .sp_defense = 80,
                .speed = 58,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 67, 0, 44 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .water1 },
            .evolutions = &.{
                .{ .method = .level_up, .target = 9 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 79,
                .attack = 83,
                .defense = 100,
                .sp_attack = 85,
                .sp_defense = 105,
                .speed = 78,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 67, 0, 44 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .water1 },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 45,
                .attack = 30,
                .defense = 35,
                .sp_attack = 20,
                .sp_defense = 20,
                .speed = 45,
            },
            .types = .{ 6, 6 },
            .abilities = .{ 19, 0, 50 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .bug, .bug },
            .evolutions = &.{
                .{ .method = .level_up, .target = 11 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 50,
                .attack = 20,
                .defense = 55,
                .sp_attack = 25,
                .sp_defense = 25,
                .speed = 30,
            },
            .types = .{ 6, 6 },
            .abilities = .{ 61, 0, 61 },
            .gender_ratio = 127,
            .catch_rate = 120,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .bug, .bug },
            .evolutions = &.{
                .{ .method = .level_up, .target = 12 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 45,
                .defense = 50,
                .sp_attack = 80,
                .sp_defense = 80,
                .speed = 70,
            },
            .types = .{ 6, 2 },
            .abilities = .{ 14, 0, 110 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .bug, .bug },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 35,
                .defense = 30,
                .sp_attack = 20,
                .sp_defense = 20,
                .speed = 50,
            },
            .types = .{ 6, 3 },
            .abilities = .{ 19, 0, 50 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .bug, .bug },
            .evolutions = &.{
                .{ .method = .level_up, .target = 14 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 45,
                .attack = 25,
                .defense = 50,
                .sp_attack = 25,
                .sp_defense = 25,
                .speed = 35,
            },
            .types = .{ 6, 3 },
            .abilities = .{ 61, 0, 61 },
            .gender_ratio = 127,
            .catch_rate = 120,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .bug, .bug },
            .evolutions = &.{
                .{ .method = .level_up, .target = 15 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 80,
                .defense = 40,
                .sp_attack = 45,
                .sp_defense = 80,
                .speed = 75,
            },
            .types = .{ 6, 3 },
            .abilities = .{ 68, 0, 97 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .bug, .bug },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 45,
                .defense = 40,
                .sp_attack = 35,
                .sp_defense = 35,
                .speed = 56,
            },
            .types = .{ 0, 2 },
            .abilities = .{ 51, 77, 145 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .flying, .flying },
            .evolutions = &.{
                .{ .method = .level_up, .target = 17 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 63,
                .attack = 60,
                .defense = 55,
                .sp_attack = 50,
                .sp_defense = 50,
                .speed = 71,
            },
            .types = .{ 0, 2 },
            .abilities = .{ 51, 77, 145 },
            .gender_ratio = 127,
            .catch_rate = 120,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .flying, .flying },
            .evolutions = &.{
                .{ .method = .level_up, .target = 18 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 83,
                .attack = 80,
                .defense = 75,
                .sp_attack = 70,
                .sp_defense = 70,
                .speed = 91,
            },
            .types = .{ 0, 2 },
            .abilities = .{ 51, 77, 145 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .flying, .flying },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 30,
                .attack = 56,
                .defense = 35,
                .sp_attack = 25,
                .sp_defense = 35,
                .speed = 72,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 50, 62, 55 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{
                .{ .method = .level_up, .target = 20 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 55,
                .attack = 81,
                .defense = 60,
                .sp_attack = 50,
                .sp_defense = 70,
                .speed = 97,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 50, 62, 55 },
            .gender_ratio = 127,
            .catch_rate = 127,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 60,
                .defense = 30,
                .sp_attack = 31,
                .sp_defense = 31,
                .speed = 70,
            },
            .types = .{ 0, 2 },
            .abilities = .{ 51, 0, 97 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .flying, .flying },
            .evolutions = &.{
                .{ .method = .level_up, .target = 22 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 90,
                .defense = 65,
                .sp_attack = 61,
                .sp_defense = 61,
                .speed = 100,
            },
            .types = .{ 0, 2 },
            .abilities = .{ 51, 0, 97 },
            .gender_ratio = 127,
            .catch_rate = 90,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .flying, .flying },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 35,
                .attack = 60,
                .defense = 44,
                .sp_attack = 40,
                .sp_defense = 54,
                .speed = 55,
            },
            .types = .{ 3, 3 },
            .abilities = .{ 22, 61, 127 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .dragon },
            .evolutions = &.{
                .{ .method = .level_up, .target = 24 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 85,
                .defense = 69,
                .sp_attack = 65,
                .sp_defense = 79,
                .speed = 80,
            },
            .types = .{ 3, 3 },
            .abilities = .{ 22, 61, 127 },
            .gender_ratio = 127,
            .catch_rate = 90,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .dragon },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 35,
                .attack = 55,
                .defense = 30,
                .sp_attack = 50,
                .sp_defense = 40,
                .speed = 90,
            },
            .types = .{ 12, 12 },
            .abilities = .{ 9, 0, 31 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .fairy },
            .evolutions = &.{
                .{ .method = .use_item, .target = 26 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 90,
                .defense = 55,
                .sp_attack = 90,
                .sp_defense = 80,
                .speed = 100,
            },
            .types = .{ 12, 12 },
            .abilities = .{ 9, 0, 31 },
            .gender_ratio = 127,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .fairy },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 50,
                .attack = 75,
                .defense = 85,
                .sp_attack = 20,
                .sp_defense = 30,
                .speed = 40,
            },
            .types = .{ 4, 4 },
            .abilities = .{ 8, 0, 146 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{
                .{ .method = .level_up, .target = 28 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 75,
                .attack = 100,
                .defense = 110,
                .sp_attack = 45,
                .sp_defense = 55,
                .speed = 65,
            },
            .types = .{ 4, 4 },
            .abilities = .{ 8, 0, 146 },
            .gender_ratio = 127,
            .catch_rate = 90,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 55,
                .attack = 47,
                .defense = 52,
                .sp_attack = 40,
                .sp_defense = 40,
                .speed = 41,
            },
            .types = .{ 3, 3 },
            .abilities = .{ 38, 79, 55 },
            .gender_ratio = 254,
            .catch_rate = 235,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .field },
            .evolutions = &.{
                .{ .method = .level_up, .target = 30 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 70,
                .attack = 62,
                .defense = 67,
                .sp_attack = 55,
                .sp_defense = 55,
                .speed = 56,
            },
            .types = .{ 3, 3 },
            .abilities = .{ 38, 79, 55 },
            .gender_ratio = 254,
            .catch_rate = 120,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .undiscovered, .undiscovered },
            .evolutions = &.{
                .{ .method = .use_item, .target = 31 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 90,
                .attack = 82,
                .defense = 87,
                .sp_attack = 75,
                .sp_defense = 85,
                .speed = 76,
            },
            .types = .{ 3, 4 },
            .abilities = .{ 38, 79, 125 },
            .gender_ratio = 254,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .undiscovered, .undiscovered },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 46,
                .attack = 57,
                .defense = 40,
                .sp_attack = 40,
                .sp_defense = 40,
                .speed = 50,
            },
            .types = .{ 3, 3 },
            .abilities = .{ 38, 79, 55 },
            .gender_ratio = 0,
            .catch_rate = 235,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .field },
            .evolutions = &.{
                .{ .method = .level_up, .target = 33 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 61,
                .attack = 72,
                .defense = 57,
                .sp_attack = 55,
                .sp_defense = 55,
                .speed = 65,
            },
            .types = .{ 3, 3 },
            .abilities = .{ 38, 79, 55 },
            .gender_ratio = 0,
            .catch_rate = 120,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .field },
            .evolutions = &.{
                .{ .method = .use_item, .target = 34 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 81,
                .attack = 92,
                .defense = 77,
                .sp_attack = 85,
                .sp_defense = 75,
                .speed = 85,
            },
            .types = .{ 3, 4 },
            .abilities = .{ 38, 79, 125 },
            .gender_ratio = 0,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .monster, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 70,
                .attack = 45,
                .defense = 48,
                .sp_attack = 60,
                .sp_defense = 65,
                .speed = 35,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 56, 98, 132 },
            .gender_ratio = 191,
            .catch_rate = 150,
            .growth_rate = .fast,
            .egg_groups = .{ .fairy, .fairy },
            .evolutions = &.{
                .{ .method = .use_item, .target = 36 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 95,
                .attack = 70,
                .defense = 73,
                .sp_attack = 85,
                .sp_defense = 90,
                .speed = 60,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 56, 98, 109 },
            .gender_ratio = 191,
            .catch_rate = 25,
            .growth_rate = .fast,
            .egg_groups = .{ .fairy, .fairy },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 38,
                .attack = 41,
                .defense = 40,
                .sp_attack = 50,
                .sp_defense = 65,
                .speed = 65,
            },
            .types = .{ 9, 9 },
            .abilities = .{ 18, 0, 70 },
            .gender_ratio = 191,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{
                .{ .method = .use_item, .target = 38 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 73,
                .attack = 76,
                .defense = 75,
                .sp_attack = 81,
                .sp_defense = 100,
                .speed = 100,
            },
            .types = .{ 9, 9 },
            .abilities = .{ 18, 0, 70 },
            .gender_ratio = 191,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 115,
                .attack = 45,
                .defense = 20,
                .sp_attack = 45,
                .sp_defense = 25,
                .speed = 20,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 56, 0, 132 },
            .gender_ratio = 191,
            .catch_rate = 170,
            .growth_rate = .fast,
            .egg_groups = .{ .fairy, .fairy },
            .evolutions = &.{
                .{ .method = .use_item, .target = 40 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 140,
                .attack = 70,
                .defense = 45,
                .sp_attack = 75,
                .sp_defense = 50,
                .speed = 45,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 56, 0, 119 },
            .gender_ratio = 191,
            .catch_rate = 50,
            .growth_rate = .fast,
            .egg_groups = .{ .fairy, .fairy },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 45,
                .defense = 35,
                .sp_attack = 30,
                .sp_defense = 40,
                .speed = 55,
            },
            .types = .{ 3, 2 },
            .abilities = .{ 39, 0, 151 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .flying, .flying },
            .evolutions = &.{
                .{ .method = .level_up, .target = 42 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 75,
                .attack = 80,
                .defense = 70,
                .sp_attack = 65,
                .sp_defense = 75,
                .speed = 90,
            },
            .types = .{ 3, 2 },
            .abilities = .{ 39, 0, 151 },
            .gender_ratio = 127,
            .catch_rate = 90,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .flying, .flying },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 45,
                .attack = 50,
                .defense = 55,
                .sp_attack = 75,
                .sp_defense = 65,
                .speed = 30,
            },
            .types = .{ 11, 3 },
            .abilities = .{ 34, 0, 50 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .grass, .grass },
            .evolutions = &.{
                .{ .method = .level_up, .target = 44 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 65,
                .defense = 70,
                .sp_attack = 85,
                .sp_defense = 75,
                .speed = 40,
            },
            .types = .{ 11, 3 },
            .abilities = .{ 34, 0, 1 },
            .gender_ratio = 127,
            .catch_rate = 120,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .grass, .grass },
            .evolutions = &.{
                .{ .method = .level_up, .target = 45 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 75,
                .attack = 80,
                .defense = 85,
                .sp_attack = 100,
                .sp_defense = 90,
                .speed = 50,
            },
            .types = .{ 11, 3 },
            .abilities = .{ 34, 0, 27 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .grass, .grass },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 35,
                .attack = 70,
                .defense = 55,
                .sp_attack = 45,
                .sp_defense = 55,
                .speed = 25,
            },
            .types = .{ 6, 11 },
            .abilities = .{ 27, 87, 6 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .bug, .grass },
            .evolutions = &.{
                .{ .method = .level_up, .target = 47 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 95,
                .defense = 80,
                .sp_attack = 60,
                .sp_defense = 80,
                .speed = 30,
            },
            .types = .{ 6, 11 },
            .abilities = .{ 27, 87, 6 },
            .gender_ratio = 127,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .bug, .grass },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 55,
                .defense = 50,
                .sp_attack = 40,
                .sp_defense = 55,
                .speed = 45,
            },
            .types = .{ 6, 3 },
            .abilities = .{ 14, 110, 50 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .bug, .bug },
            .evolutions = &.{
                .{ .method = .level_up, .target = 49 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 70,
                .attack = 65,
                .defense = 60,
                .sp_attack = 90,
                .sp_defense = 75,
                .speed = 90,
            },
            .types = .{ 6, 3 },
            .abilities = .{ 19, 110, 147 },
            .gender_ratio = 127,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .bug, .bug },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 10,
                .attack = 55,
                .defense = 25,
                .sp_attack = 35,
                .sp_defense = 45,
                .speed = 95,
            },
            .types = .{ 4, 4 },
            .abilities = .{ 8, 71, 159 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{
                .{ .method = .level_up, .target = 51 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 35,
                .attack = 80,
                .defense = 50,
                .sp_attack = 50,
                .sp_defense = 70,
                .speed = 120,
            },
            .types = .{ 4, 4 },
            .abilities = .{ 8, 71, 159 },
            .gender_ratio = 127,
            .catch_rate = 50,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 45,
                .defense = 35,
                .sp_attack = 40,
                .sp_defense = 40,
                .speed = 90,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 53, 101, 127 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{
                .{ .method = .level_up, .target = 53 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 70,
                .defense = 60,
                .sp_attack = 65,
                .sp_defense = 65,
                .speed = 115,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 7, 101, 127 },
            .gender_ratio = 127,
            .catch_rate = 90,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 50,
                .attack = 52,
                .defense = 48,
                .sp_attack = 65,
                .sp_defense = 50,
                .speed = 55,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 6, 13, 33 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water1, .field },
            .evolutions = &.{
                .{ .method = .level_up, .target = 55 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 80,
                .attack = 82,
                .defense = 78,
                .sp_attack = 95,
                .sp_defense = 80,
                .speed = 85,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 6, 13, 33 },
            .gender_ratio = 127,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water1, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 80,
                .defense = 35,
                .sp_attack = 35,
                .sp_defense = 45,
                .speed = 70,
            },
            .types = .{ 1, 1 },
            .abilities = .{ 72, 83, 128 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{
                .{ .method = .level_up, .target = 57 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 105,
                .defense = 60,
                .sp_attack = 60,
                .sp_defense = 70,
                .speed = 95,
            },
            .types = .{ 1, 1 },
            .abilities = .{ 72, 83, 128 },
            .gender_ratio = 127,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 55,
                .attack = 70,
                .defense = 45,
                .sp_attack = 70,
                .sp_defense = 50,
                .speed = 60,
            },
            .types = .{ 9, 9 },
            .abilities = .{ 22, 18, 154 },
            .gender_ratio = 63,
            .catch_rate = 190,
            .growth_rate = .slow,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{
                .{ .method = .use_item, .target = 59 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 90,
                .attack = 110,
                .defense = 80,
                .sp_attack = 100,
                .sp_defense = 80,
                .speed = 95,
            },
            .types = .{ 9, 9 },
            .abilities = .{ 22, 18, 154 },
            .gender_ratio = 63,
            .catch_rate = 75,
            .growth_rate = .slow,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 50,
                .defense = 40,
                .sp_attack = 40,
                .sp_defense = 40,
                .speed = 90,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 11, 6, 33 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .water1, .water1 },
            .evolutions = &.{
                .{ .method = .level_up, .target = 61 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 65,
                .defense = 65,
                .sp_attack = 50,
                .sp_defense = 50,
                .speed = 90,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 11, 6, 33 },
            .gender_ratio = 127,
            .catch_rate = 120,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .water1, .water1 },
            .evolutions = &.{
                .{ .method = .use_item, .target = 62 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 90,
                .attack = 85,
                .defense = 95,
                .sp_attack = 70,
                .sp_defense = 90,
                .speed = 70,
            },
            .types = .{ 10, 1 },
            .abilities = .{ 11, 6, 33 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .water1, .water1 },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 25,
                .attack = 20,
                .defense = 15,
                .sp_attack = 105,
                .sp_defense = 55,
                .speed = 90,
            },
            .types = .{ 13, 13 },
            .abilities = .{ 28, 39, 98 },
            .gender_ratio = 63,
            .catch_rate = 200,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{
                .{ .method = .level_up, .target = 64 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 35,
                .defense = 30,
                .sp_attack = 120,
                .sp_defense = 70,
                .speed = 105,
            },
            .types = .{ 13, 13 },
            .abilities = .{ 28, 39, 98 },
            .gender_ratio = 63,
            .catch_rate = 100,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{
                .{ .method = .trade, .target = 65 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 55,
                .attack = 50,
                .defense = 45,
                .sp_attack = 135,
                .sp_defense = 85,
                .speed = 120,
            },
            .types = .{ 13, 13 },
            .abilities = .{ 28, 39, 98 },
            .gender_ratio = 63,
            .catch_rate = 50,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 70,
                .attack = 80,
                .defense = 50,
                .sp_attack = 35,
                .sp_defense = 35,
                .speed = 35,
            },
            .types = .{ 1, 1 },
            .abilities = .{ 62, 99, 80 },
            .gender_ratio = 63,
            .catch_rate = 180,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{
                .{ .method = .level_up, .target = 67 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 80,
                .attack = 100,
                .defense = 70,
                .sp_attack = 50,
                .sp_defense = 60,
                .speed = 45,
            },
            .types = .{ 1, 1 },
            .abilities = .{ 62, 99, 80 },
            .gender_ratio = 63,
            .catch_rate = 90,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{
                .{ .method = .trade, .target = 68 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 90,
                .attack = 130,
                .defense = 80,
                .sp_attack = 65,
                .sp_defense = 85,
                .speed = 55,
            },
            .types = .{ 1, 1 },
            .abilities = .{ 62, 99, 80 },
            .gender_ratio = 63,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 50,
                .attack = 75,
                .defense = 35,
                .sp_attack = 70,
                .sp_defense = 30,
                .speed = 40,
            },
            .types = .{ 11, 3 },
            .abilities = .{ 34, 0, 82 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .grass, .grass },
            .evolutions = &.{
                .{ .method = .level_up, .target = 70 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 90,
                .defense = 50,
                .sp_attack = 85,
                .sp_defense = 45,
                .speed = 55,
            },
            .types = .{ 11, 3 },
            .abilities = .{ 34, 0, 82 },
            .gender_ratio = 127,
            .catch_rate = 120,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .grass, .grass },
            .evolutions = &.{
                .{ .method = .use_item, .target = 71 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 80,
                .attack = 105,
                .defense = 65,
                .sp_attack = 100,
                .sp_defense = 60,
                .speed = 70,
            },
            .types = .{ 11, 3 },
            .abilities = .{ 34, 0, 82 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .grass, .grass },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 40,
                .defense = 35,
                .sp_attack = 50,
                .sp_defense = 100,
                .speed = 70,
            },
            .types = .{ 10, 3 },
            .abilities = .{ 29, 64, 44 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .slow,
            .egg_groups = .{ .water3, .water3 },
            .evolutions = &.{
                .{ .method = .level_up, .target = 73 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 80,
                .attack = 70,
                .defense = 65,
                .sp_attack = 80,
                .sp_defense = 120,
                .speed = 100,
            },
            .types = .{ 10, 3 },
            .abilities = .{ 29, 64, 44 },
            .gender_ratio = 127,
            .catch_rate = 60,
            .growth_rate = .slow,
            .egg_groups = .{ .water3, .water3 },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 80,
                .defense = 100,
                .sp_attack = 30,
                .sp_defense = 30,
                .speed = 20,
            },
            .types = .{ 5, 4 },
            .abilities = .{ 69, 5, 8 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .mineral, .mineral },
            .evolutions = &.{
                .{ .method = .level_up, .target = 75 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 55,
                .attack = 95,
                .defense = 115,
                .sp_attack = 45,
                .sp_defense = 45,
                .speed = 35,
            },
            .types = .{ 5, 4 },
            .abilities = .{ 69, 5, 8 },
            .gender_ratio = 127,
            .catch_rate = 120,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .mineral, .mineral },
            .evolutions = &.{
                .{ .method = .trade, .target = 76 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 80,
                .attack = 110,
                .defense = 130,
                .sp_attack = 55,
                .sp_defense = 65,
                .speed = 45,
            },
            .types = .{ 5, 4 },
            .abilities = .{ 69, 5, 8 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .mineral, .mineral },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 50,
                .attack = 85,
                .defense = 55,
                .sp_attack = 65,
                .sp_defense = 65,
                .speed = 90,
            },
            .types = .{ 9, 9 },
            .abilities = .{ 50, 18, 49 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{
                .{ .method = .level_up, .target = 78 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 100,
                .defense = 70,
                .sp_attack = 80,
                .sp_defense = 80,
                .speed = 105,
            },
            .types = .{ 9, 9 },
            .abilities = .{ 50, 18, 49 },
            .gender_ratio = 127,
            .catch_rate = 60,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 90,
                .attack = 65,
                .defense = 65,
                .sp_attack = 40,
                .sp_defense = 40,
                .speed = 15,
            },
            .types = .{ 10, 13 },
            .abilities = .{ 12, 20, 144 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .monster, .water1 },
            .evolutions = &.{
                .{ .method = .level_up, .target = 80 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 95,
                .attack = 75,
                .defense = 110,
                .sp_attack = 100,
                .sp_defense = 80,
                .speed = 30,
            },
            .types = .{ 10, 13 },
            .abilities = .{ 12, 20, 144 },
            .gender_ratio = 127,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .monster, .water1 },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 25,
                .attack = 35,
                .defense = 70,
                .sp_attack = 95,
                .sp_defense = 55,
                .speed = 45,
            },
            .types = .{ 12, 8 },
            .abilities = .{ 42, 5, 148 },
            .gender_ratio = 255,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .mineral, .mineral },
            .evolutions = &.{
                .{ .method = .level_up, .target = 82 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 50,
                .attack = 60,
                .defense = 95,
                .sp_attack = 120,
                .sp_defense = 70,
                .speed = 70,
            },
            .types = .{ 12, 8 },
            .abilities = .{ 42, 5, 148 },
            .gender_ratio = 255,
            .catch_rate = 60,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .mineral, .mineral },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 52,
                .attack = 65,
                .defense = 55,
                .sp_attack = 58,
                .sp_defense = 62,
                .speed = 60,
            },
            .types = .{ 0, 2 },
            .abilities = .{ 51, 39, 128 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .flying, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 35,
                .attack = 85,
                .defense = 45,
                .sp_attack = 35,
                .sp_defense = 35,
                .speed = 75,
            },
            .types = .{ 0, 2 },
            .abilities = .{ 50, 48, 77 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .flying, .flying },
            .evolutions = &.{
                .{ .method = .level_up, .target = 85 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 110,
                .defense = 70,
                .sp_attack = 60,
                .sp_defense = 60,
                .speed = 100,
            },
            .types = .{ 0, 2 },
            .abilities = .{ 50, 48, 77 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .flying, .flying },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 45,
                .defense = 55,
                .sp_attack = 45,
                .sp_defense = 70,
                .speed = 45,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 47, 93, 115 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water1, .field },
            .evolutions = &.{
                .{ .method = .level_up, .target = 87 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 90,
                .attack = 70,
                .defense = 80,
                .sp_attack = 70,
                .sp_defense = 95,
                .speed = 70,
            },
            .types = .{ 10, 14 },
            .abilities = .{ 47, 93, 115 },
            .gender_ratio = 127,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water1, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 80,
                .attack = 80,
                .defense = 50,
                .sp_attack = 40,
                .sp_defense = 50,
                .speed = 25,
            },
            .types = .{ 3, 3 },
            .abilities = .{ 1, 60, 143 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .amorphous, .amorphous },
            .evolutions = &.{
                .{ .method = .level_up, .target = 89 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 105,
                .attack = 105,
                .defense = 75,
                .sp_attack = 65,
                .sp_defense = 100,
                .speed = 50,
            },
            .types = .{ 3, 3 },
            .abilities = .{ 1, 60, 143 },
            .gender_ratio = 127,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .amorphous, .amorphous },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 30,
                .attack = 65,
                .defense = 100,
                .sp_attack = 45,
                .sp_defense = 25,
                .speed = 40,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 75, 92, 142 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .slow,
            .egg_groups = .{ .water3, .water3 },
            .evolutions = &.{
                .{ .method = .level_up, .target = 91 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 50,
                .attack = 95,
                .defense = 180,
                .sp_attack = 85,
                .sp_defense = 45,
                .speed = 70,
            },
            .types = .{ 10, 14 },
            .abilities = .{ 75, 92, 142 },
            .gender_ratio = 127,
            .catch_rate = 60,
            .growth_rate = .slow,
            .egg_groups = .{ .water3, .water3 },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 30,
                .attack = 35,
                .defense = 30,
                .sp_attack = 100,
                .sp_defense = 35,
                .speed = 80,
            },
            .types = .{ 7, 3 },
            .abilities = .{ 26, 0, 0 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .amorphous, .amorphous },
            .evolutions = &.{
                .{ .method = .level_up, .target = 93 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 45,
                .attack = 50,
                .defense = 45,
                .sp_attack = 115,
                .sp_defense = 55,
                .speed = 95,
            },
            .types = .{ 7, 3 },
            .abilities = .{ 26, 0, 0 },
            .gender_ratio = 127,
            .catch_rate = 90,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .amorphous, .amorphous },
            .evolutions = &.{
                .{ .method = .trade, .target = 94 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 65,
                .defense = 60,
                .sp_attack = 130,
                .sp_defense = 75,
                .speed = 110,
            },
            .types = .{ 7, 3 },
            .abilities = .{ 26, 0, 0 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .amorphous, .amorphous },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 35,
                .attack = 45,
                .defense = 160,
                .sp_attack = 30,
                .sp_defense = 45,
                .speed = 70,
            },
            .types = .{ 5, 4 },
            .abilities = .{ 69, 5, 133 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .mineral, .mineral },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 48,
                .defense = 45,
                .sp_attack = 43,
                .sp_defense = 90,
                .speed = 42,
            },
            .types = .{ 13, 13 },
            .abilities = .{ 15, 108, 39 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{
                .{ .method = .level_up, .target = 97 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 85,
                .attack = 73,
                .defense = 70,
                .sp_attack = 73,
                .sp_defense = 115,
                .speed = 67,
            },
            .types = .{ 13, 13 },
            .abilities = .{ 15, 108, 39 },
            .gender_ratio = 127,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 30,
                .attack = 105,
                .defense = 90,
                .sp_attack = 25,
                .sp_defense = 25,
                .speed = 50,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 52, 75, 125 },
            .gender_ratio = 127,
            .catch_rate = 225,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water3, .water3 },
            .evolutions = &.{
                .{ .method = .level_up, .target = 99 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 55,
                .attack = 130,
                .defense = 115,
                .sp_attack = 50,
                .sp_defense = 50,
                .speed = 75,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 52, 75, 125 },
            .gender_ratio = 127,
            .catch_rate = 60,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water3, .water3 },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 30,
                .defense = 50,
                .sp_attack = 55,
                .sp_defense = 55,
                .speed = 100,
            },
            .types = .{ 12, 12 },
            .abilities = .{ 43, 9, 106 },
            .gender_ratio = 255,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .mineral, .mineral },
            .evolutions = &.{
                .{ .method = .level_up, .target = 101 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 50,
                .defense = 70,
                .sp_attack = 80,
                .sp_defense = 80,
                .speed = 140,
            },
            .types = .{ 12, 12 },
            .abilities = .{ 43, 9, 106 },
            .gender_ratio = 255,
            .catch_rate = 60,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .mineral, .mineral },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 40,
                .defense = 80,
                .sp_attack = 60,
                .sp_defense = 45,
                .speed = 40,
            },
            .types = .{ 11, 13 },
            .abilities = .{ 34, 0, 139 },
            .gender_ratio = 127,
            .catch_rate = 90,
            .growth_rate = .slow,
            .egg_groups = .{ .grass, .grass },
            .evolutions = &.{
                .{ .method = .level_up, .target = 103 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 95,
                .attack = 95,
                .defense = 85,
                .sp_attack = 125,
                .sp_defense = 65,
                .speed = 55,
            },
            .types = .{ 11, 13 },
            .abilities = .{ 34, 0, 139 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .slow,
            .egg_groups = .{ .grass, .grass },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 50,
                .attack = 50,
                .defense = 95,
                .sp_attack = 40,
                .sp_defense = 50,
                .speed = 35,
            },
            .types = .{ 4, 4 },
            .abilities = .{ 69, 31, 4 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .monster, .monster },
            .evolutions = &.{
                .{ .method = .level_up, .target = 105 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 80,
                .defense = 110,
                .sp_attack = 50,
                .sp_defense = 80,
                .speed = 45,
            },
            .types = .{ 4, 4 },
            .abilities = .{ 69, 31, 4 },
            .gender_ratio = 127,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .monster, .monster },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 50,
                .attack = 120,
                .defense = 53,
                .sp_attack = 35,
                .sp_defense = 110,
                .speed = 87,
            },
            .types = .{ 1, 1 },
            .abilities = .{ 7, 120, 84 },
            .gender_ratio = 0,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 50,
                .attack = 105,
                .defense = 79,
                .sp_attack = 35,
                .sp_defense = 110,
                .speed = 76,
            },
            .types = .{ 1, 1 },
            .abilities = .{ 51, 89, 39 },
            .gender_ratio = 0,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 90,
                .attack = 55,
                .defense = 75,
                .sp_attack = 60,
                .sp_defense = 75,
                .speed = 30,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 20, 12, 13 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .monster, .monster },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 65,
                .defense = 95,
                .sp_attack = 60,
                .sp_defense = 45,
                .speed = 35,
            },
            .types = .{ 3, 3 },
            .abilities = .{ 26, 0, 0 },
            .gender_ratio = 127,
            .catch_rate = 190,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .amorphous, .amorphous },
            .evolutions = &.{
                .{ .method = .level_up, .target = 110 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 90,
                .defense = 120,
                .sp_attack = 85,
                .sp_defense = 70,
                .speed = 60,
            },
            .types = .{ 3, 3 },
            .abilities = .{ 26, 0, 0 },
            .gender_ratio = 127,
            .catch_rate = 60,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .amorphous, .amorphous },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 80,
                .attack = 85,
                .defense = 95,
                .sp_attack = 30,
                .sp_defense = 30,
                .speed = 25,
            },
            .types = .{ 4, 5 },
            .abilities = .{ 31, 69, 120 },
            .gender_ratio = 127,
            .catch_rate = 120,
            .growth_rate = .slow,
            .egg_groups = .{ .monster, .field },
            .evolutions = &.{
                .{ .method = .level_up, .target = 112 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 105,
                .attack = 130,
                .defense = 120,
                .sp_attack = 45,
                .sp_defense = 45,
                .speed = 40,
            },
            .types = .{ 4, 5 },
            .abilities = .{ 31, 69, 120 },
            .gender_ratio = 127,
            .catch_rate = 60,
            .growth_rate = .slow,
            .egg_groups = .{ .monster, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 250,
                .attack = 5,
                .defense = 5,
                .sp_attack = 35,
                .sp_defense = 105,
                .speed = 50,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 30, 32, 131 },
            .gender_ratio = 254,
            .catch_rate = 30,
            .growth_rate = .fast,
            .egg_groups = .{ .fairy, .fairy },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 55,
                .defense = 115,
                .sp_attack = 100,
                .sp_defense = 40,
                .speed = 60,
            },
            .types = .{ 11, 11 },
            .abilities = .{ 34, 102, 144 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .grass, .grass },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 105,
                .attack = 95,
                .defense = 80,
                .sp_attack = 40,
                .sp_defense = 80,
                .speed = 90,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 48, 113, 39 },
            .gender_ratio = 254,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .monster, .monster },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 30,
                .attack = 40,
                .defense = 70,
                .sp_attack = 70,
                .sp_defense = 25,
                .speed = 60,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 33, 97, 6 },
            .gender_ratio = 127,
            .catch_rate = 225,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water1, .dragon },
            .evolutions = &.{
                .{ .method = .level_up, .target = 117 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 55,
                .attack = 65,
                .defense = 95,
                .sp_attack = 95,
                .sp_defense = 45,
                .speed = 85,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 38, 97, 6 },
            .gender_ratio = 127,
            .catch_rate = 75,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water1, .dragon },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 45,
                .attack = 67,
                .defense = 60,
                .sp_attack = 35,
                .sp_defense = 50,
                .speed = 63,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 33, 41, 31 },
            .gender_ratio = 127,
            .catch_rate = 225,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water2, .water2 },
            .evolutions = &.{
                .{ .method = .level_up, .target = 119 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 80,
                .attack = 92,
                .defense = 65,
                .sp_attack = 65,
                .sp_defense = 80,
                .speed = 68,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 33, 41, 31 },
            .gender_ratio = 127,
            .catch_rate = 60,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water2, .water2 },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 30,
                .attack = 45,
                .defense = 55,
                .sp_attack = 70,
                .sp_defense = 55,
                .speed = 85,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 35, 30, 148 },
            .gender_ratio = 255,
            .catch_rate = 225,
            .growth_rate = .slow,
            .egg_groups = .{ .water3, .water3 },
            .evolutions = &.{
                .{ .method = .level_up, .target = 121 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 75,
                .defense = 85,
                .sp_attack = 100,
                .sp_defense = 85,
                .speed = 115,
            },
            .types = .{ 10, 13 },
            .abilities = .{ 35, 30, 148 },
            .gender_ratio = 255,
            .catch_rate = 60,
            .growth_rate = .slow,
            .egg_groups = .{ .water3, .water3 },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 40,
                .attack = 45,
                .defense = 65,
                .sp_attack = 100,
                .sp_defense = 120,
                .speed = 90,
            },
            .types = .{ 13, 13 },
            .abilities = .{ 43, 111, 101 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 70,
                .attack = 110,
                .defense = 80,
                .sp_attack = 55,
                .sp_defense = 80,
                .speed = 105,
            },
            .types = .{ 6, 2 },
            .abilities = .{ 68, 101, 80 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .bug, .bug },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 50,
                .defense = 35,
                .sp_attack = 115,
                .sp_defense = 95,
                .speed = 95,
            },
            .types = .{ 14, 13 },
            .abilities = .{ 12, 108, 87 },
            .gender_ratio = 254,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 83,
                .defense = 57,
                .sp_attack = 95,
                .sp_defense = 85,
                .speed = 105,
            },
            .types = .{ 12, 12 },
            .abilities = .{ 9, 0, 72 },
            .gender_ratio = 63,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 95,
                .defense = 57,
                .sp_attack = 100,
                .sp_defense = 85,
                .speed = 93,
            },
            .types = .{ 9, 9 },
            .abilities = .{ 49, 0, 72 },
            .gender_ratio = 63,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .human_like, .human_like },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 125,
                .defense = 100,
                .sp_attack = 55,
                .sp_defense = 70,
                .speed = 85,
            },
            .types = .{ 6, 6 },
            .abilities = .{ 52, 104, 153 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .slow,
            .egg_groups = .{ .bug, .bug },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 75,
                .attack = 100,
                .defense = 95,
                .sp_attack = 40,
                .sp_defense = 70,
                .speed = 110,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 22, 83, 125 },
            .gender_ratio = 0,
            .catch_rate = 45,
            .growth_rate = .slow,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 20,
                .attack = 10,
                .defense = 55,
                .sp_attack = 15,
                .sp_defense = 20,
                .speed = 80,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 33, 0, 155 },
            .gender_ratio = 127,
            .catch_rate = 255,
            .growth_rate = .slow,
            .egg_groups = .{ .water2, .dragon },
            .evolutions = &.{
                .{ .method = .level_up, .target = 130 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 95,
                .attack = 125,
                .defense = 79,
                .sp_attack = 60,
                .sp_defense = 100,
                .speed = 81,
            },
            .types = .{ 10, 2 },
            .abilities = .{ 22, 0, 153 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .slow,
            .egg_groups = .{ .water2, .dragon },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 130,
                .attack = 85,
                .defense = 80,
                .sp_attack = 85,
                .sp_defense = 95,
                .speed = 60,
            },
            .types = .{ 10, 14 },
            .abilities = .{ 11, 75, 93 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .slow,
            .egg_groups = .{ .monster, .water1 },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 48,
                .attack = 48,
                .defense = 48,
                .sp_attack = 48,
                .sp_defense = 48,
                .speed = 48,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 7, 0, 150 },
            .gender_ratio = 255,
            .catch_rate = 35,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .ditto, .ditto },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 55,
                .attack = 55,
                .defense = 50,
                .sp_attack = 45,
                .sp_defense = 65,
                .speed = 55,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 50, 91, 107 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{
                .{ .method = .use_item, .target = 134 },
                .{ .method = .use_item, .target = 135 },
                .{ .method = .use_item, .target = 136 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 130,
                .attack = 65,
                .defense = 60,
                .sp_attack = 110,
                .sp_defense = 95,
                .speed = 65,
            },
            .types = .{ 10, 10 },
            .abilities = .{ 11, 11, 93 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 65,
                .defense = 60,
                .sp_attack = 110,
                .sp_defense = 95,
                .speed = 130,
            },
            .types = .{ 12, 12 },
            .abilities = .{ 10, 10, 95 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 130,
                .defense = 60,
                .sp_attack = 95,
                .sp_defense = 110,
                .speed = 65,
            },
            .types = .{ 9, 9 },
            .abilities = .{ 18, 18, 62 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .field, .field },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 65,
                .attack = 60,
                .defense = 70,
                .sp_attack = 85,
                .sp_defense = 75,
                .speed = 40,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 36, 88, 148 },
            .gender_ratio = 255,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .mineral, .mineral },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 35,
                .attack = 40,
                .defense = 100,
                .sp_attack = 90,
                .sp_defense = 55,
                .speed = 35,
            },
            .types = .{ 5, 10 },
            .abilities = .{ 33, 75, 133 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water1, .water3 },
            .evolutions = &.{
                .{ .method = .level_up, .target = 139 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 70,
                .attack = 60,
                .defense = 125,
                .sp_attack = 115,
                .sp_defense = 70,
                .speed = 55,
            },
            .types = .{ 5, 10 },
            .abilities = .{ 33, 75, 133 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water1, .water3 },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 30,
                .attack = 80,
                .defense = 90,
                .sp_attack = 55,
                .sp_defense = 45,
                .speed = 55,
            },
            .types = .{ 5, 10 },
            .abilities = .{ 33, 4, 133 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water1, .water3 },
            .evolutions = &.{
                .{ .method = .level_up, .target = 141 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 60,
                .attack = 115,
                .defense = 105,
                .sp_attack = 65,
                .sp_defense = 70,
                .speed = 80,
            },
            .types = .{ 5, 10 },
            .abilities = .{ 33, 4, 133 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .medium_fast,
            .egg_groups = .{ .water1, .water3 },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 80,
                .attack = 105,
                .defense = 65,
                .sp_attack = 60,
                .sp_defense = 75,
                .speed = 130,
            },
            .types = .{ 5, 2 },
            .abilities = .{ 69, 46, 127 },
            .gender_ratio = 31,
            .catch_rate = 45,
            .growth_rate = .slow,
            .egg_groups = .{ .flying, .flying },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 160,
                .attack = 110,
                .defense = 65,
                .sp_attack = 65,
                .sp_defense = 110,
                .speed = 30,
            },
            .types = .{ 0, 0 },
            .abilities = .{ 17, 47, 82 },
            .gender_ratio = 31,
            .catch_rate = 25,
            .growth_rate = .slow,
            .egg_groups = .{ .monster, .monster },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 90,
                .attack = 85,
                .defense = 100,
                .sp_attack = 95,
                .sp_defense = 125,
                .speed = 85,
            },
            .types = .{ 14, 2 },
            .abilities = .{ 46, 0, 81 },
            .gender_ratio = 255,
            .catch_rate = 3,
            .growth_rate = .slow,
            .egg_groups = .{ .undiscovered, .undiscovered },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 90,
                .attack = 90,
                .defense = 85,
                .sp_attack = 125,
                .sp_defense = 90,
                .speed = 100,
            },
            .types = .{ 12, 2 },
            .abilities = .{ 46, 0, 31 },
            .gender_ratio = 255,
            .catch_rate = 3,
            .growth_rate = .slow,
            .egg_groups = .{ .undiscovered, .undiscovered },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 90,
                .attack = 100,
                .defense = 90,
                .sp_attack = 125,
                .sp_defense = 85,
                .speed = 90,
            },
            .types = .{ 9, 2 },
            .abilities = .{ 46, 0, 49 },
            .gender_ratio = 255,
            .catch_rate = 3,
            .growth_rate = .slow,
            .egg_groups = .{ .undiscovered, .undiscovered },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 41,
                .attack = 64,
                .defense = 45,
                .sp_attack = 50,
                .sp_defense = 50,
                .speed = 50,
            },
            .types = .{ 15, 15 },
            .abilities = .{ 61, 0, 63 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .slow,
            .egg_groups = .{ .water1, .dragon },
            .evolutions = &.{
                .{ .method = .level_up, .target = 148 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 61,
                .attack = 84,
                .defense = 65,
                .sp_attack = 70,
                .sp_defense = 70,
                .speed = 70,
            },
            .types = .{ 15, 15 },
            .abilities = .{ 61, 0, 63 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .slow,
            .egg_groups = .{ .water1, .dragon },
            .evolutions = &.{
                .{ .method = .level_up, .target = 149 },
            },
        }),
        .init(.{
            .stats = .{
                .hp = 91,
                .attack = 134,
                .defense = 95,
                .sp_attack = 100,
                .sp_defense = 100,
                .speed = 80,
            },
            .types = .{ 15, 2 },
            .abilities = .{ 39, 0, 136 },
            .gender_ratio = 127,
            .catch_rate = 45,
            .growth_rate = .slow,
            .egg_groups = .{ .water1, .dragon },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 106,
                .attack = 110,
                .defense = 90,
                .sp_attack = 154,
                .sp_defense = 90,
                .speed = 130,
            },
            .types = .{ 13, 13 },
            .abilities = .{ 46, 0, 127 },
            .gender_ratio = 255,
            .catch_rate = 3,
            .growth_rate = .slow,
            .egg_groups = .{ .undiscovered, .undiscovered },
            .evolutions = &.{},
        }),
        .init(.{
            .stats = .{
                .hp = 100,
                .attack = 100,
                .defense = 100,
                .sp_attack = 100,
                .sp_defense = 100,
                .speed = 100,
            },
            .types = .{ 13, 13 },
            .abilities = .{ 28, 0, 0 },
            .gender_ratio = 255,
            .catch_rate = 45,
            .growth_rate = .medium_slow,
            .egg_groups = .{ .undiscovered, .undiscovered },
            .evolutions = &.{},
        }),
    },
    .trainers = &.{},
    .trainer_parties = &.{
        .init(.none, &.{
            .{ .base = .{ .level = 5, .species = 1 } },
        }),
        .init(.none, &.{
            .{ .base = .{ .level = 9, .species = 16 } },
            .{ .base = .{ .level = 8, .species = 1 } },
        }),
        .init(.none, &.{
            .{ .base = .{ .level = 18, .species = 17 } },
            .{ .base = .{ .level = 15, .species = 63 } },
            .{ .base = .{ .level = 15, .species = 19 } },
            .{ .base = .{ .level = 17, .species = 1 } },
        }),
        .init(.none, &.{
            .{ .base = .{ .level = 19, .species = 17 } },
            .{ .base = .{ .level = 16, .species = 20 } },
            .{ .base = .{ .level = 18, .species = 64 } },
            .{ .base = .{ .level = 20, .species = 2 } },
        }),
        .init(.none, &.{
            .{ .base = .{ .level = 25, .species = 17 } },
            .{ .base = .{ .level = 23, .species = 130 } },
            .{ .base = .{ .level = 22, .species = 58 } },
            .{ .base = .{ .level = 20, .species = 64 } },
            .{ .base = .{ .level = 25, .species = 2 } },
        }),
        .init(.none, &.{
            .{ .base = .{ .level = 37, .species = 18 } },
            .{ .base = .{ .level = 38, .species = 130 } },
            .{ .base = .{ .level = 35, .species = 58 } },
            .{ .base = .{ .level = 35, .species = 65 } },
            .{ .base = .{ .level = 40, .species = 3 } },
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
    },
    .wild_areas = &.{
        .init(&.{
            .init(16, 2, 5),
            .init(19, 2, 4),
        }),
        .init(&.{
            .init(16, 18, 22),
            .init(17, 23, 25),
            .init(21, 20, 22),
            .init(22, 24, 24),
            .init(84, 18, 22),
        }),
        .init(&.{
            .init(72, 5, 40),
            .init(129, 5, 5),
            .init(60, 10, 10),
            .init(118, 10, 10),
            .init(73, 20, 40),
            .init(90, 15, 15),
            .init(116, 15, 15),
            .init(120, 15, 15),
        }),
    },
};

test {
    _ = common;
}

const gen5 = @import("gen5.zig");
const common = @import("common.zig");
const std = @import("std");
