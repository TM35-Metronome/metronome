pub const Game = struct {
    arena: std.heap.ArenaAllocator,
    m: struct {
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
    evolutions: [3]Evolution,

    pub fn init(values: struct {
        stats: common.Stats,
        types: [2]u8,
        abilities: [3]u8,
        evolutions: []const Evolution,
    }) Pokemon {
        var res = Pokemon{
            .stats = values.stats,
            .types = values.types,
            .abilities = values.abilities,
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

pub const Pokemons = common.IndexableSlice(Pokemon);
pub const Trainers = common.IndexableSlice(Trainer);
pub const Parties = common.IndexableSlice(Party);
pub const WildAreas = common.IndexableSlice(WildArea);

pub const default = Game.Init{
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
