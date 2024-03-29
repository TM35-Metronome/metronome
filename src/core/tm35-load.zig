const clap = @import("clap");
const core = @import("core");
const std = @import("std");
const ston = @import("ston");
const util = @import("util");

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const log = std.log;
const math = std.math;
const mem = std.mem;
const unicode = std.unicode;

const common = core.common;
const format = core.format;
const gen3 = core.gen3;
const gen4 = core.gen4;
const gen5 = core.gen5;
const rom = core.rom;

const gba = rom.gba;
const nds = rom.nds;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;

const bit = util.bit;
const escape = util.escape.default;

const Game = format.Game;

const Program = @This();

allocator: mem.Allocator,
file: []const u8,

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Load data from Pokémon games.
    \\
;

pub const parsers = .{
    .ROM = clap.parsers.string,
};

pub const params = clap.parseParamsComptime(
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\-v, --version
    \\        Output version information and exit.
    \\
    \\<ROM>
    \\        The rom to apply the changes to.
    \\
);

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const pos = args.positionals;
    const file_name = if (pos.len > 0) pos[0] else return error.MissingFile;
    return Program{ .allocator = allocator, .file = file_name };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    const allocator = program.allocator;
    const file = try fs.cwd().openFile(program.file, .{});
    defer file.close();

    const gen3_error = if (gen3.Game.fromFile(file, allocator)) |*game| {
        defer game.deinit();
        try outputGen3Data(game.*, stdio.out);
        return;
    } else |err| err;

    try file.seekTo(0);
    var m_nds_rom = nds.Rom.fromFile(file, allocator);
    if (m_nds_rom) |*nds_rom| {
        const gen4_error = if (gen4.Game.fromRom(allocator, nds_rom)) |*game| {
            defer game.deinit();
            try outputGen4Data(game.*, stdio.out);
            return;
        } else |err| err;

        const gen5_error = if (gen5.Game.fromRom(allocator, nds_rom)) |*game| {
            defer game.deinit();
            try outputGen5Data(game.*, stdio.out);
            return;
        } else |err| err;

        log.info("Successfully loaded '{s}' as a nds rom.", .{program.file});
        log.err("Failed to load '{s}' as a gen4 game: {}", .{ program.file, gen4_error });
        log.err("Failed to load '{s}' as a gen5 game: {}", .{ program.file, gen5_error });
        return gen5_error;
    } else |nds_error| {
        log.err("Failed to load '{s}' as a gen3 game: {}", .{ program.file, gen3_error });
        log.err("Failed to load '{s}' as a gen4/gen5 game: {}", .{ program.file, nds_error });
        return nds_error;
    }
}

fn outputGen3Data(game: gen3.Game, writer: anytype) !void {
    var buf: [mem.page_size]u8 = undefined;

    for (game.starters, game.starters_repeat) |starter, starter2| {
        if (starter.value() != starter2.value())
            log.warn("repeated starters don't match.", .{});
    }

    try ston.serialize(writer, .{
        .version = game.version,
        .game_title = ston.string(escape.escapeFmt(game.header.game_title.slice())),
        .gamecode = ston.string(escape.escapeFmt(&game.header.gamecode)),
        .starters = game.starters,
        .text_delays = game.text_delays,
        .tms = game.tms,
        .hms = game.hms,
        .static_pokemons = game.static_pokemons,
        .given_pokemons = game.given_pokemons,
        .pokeball_items = game.pokeball_items,
    });

    for (game.trainers, game.trainer_parties, 0..) |trainer, party, i| {
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &trainer.name, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, .{ .trainers = ston.index(i, .{
            .class = trainer.class,
            .trainer_picture = trainer.trainer_picture,
            .ai = trainer.ai,
            .battle_type = trainer.battle_type,
            .name = ston.string(escape.escapeFmt(decoded_name)),
            .items = trainer.items,
            .party_type = trainer.party_type,
            .party_size = trainer.partyLen(),
        }) });

        for (party.members[0..party.size], 0..) |member, j| {
            try ston.serialize(writer, .{ .trainers = ston.index(i, .{
                .party = ston.index(j, .{
                    .level = member.base.level,
                    .species = member.base.species,
                }),
            }) });

            if (trainer.party_type == .item or trainer.party_type == .both) {
                try ston.serialize(writer, .{ .trainers = ston.index(i, .{
                    .party = ston.index(j, .{ .item = member.item }),
                }) });
            }

            if (trainer.party_type == .moves or trainer.party_type == .both) {
                for (member.moves, 0..) |move, k| {
                    try ston.serialize(writer, .{ .trainers = ston.index(i, .{ .party = ston.index(j, .{
                        .moves = ston.index(k, move),
                    }) }) });
                }
            }
        }
    }

    for (game.moves, 0..) |move, i| {
        try ston.serialize(writer, .{ .moves = ston.index(i, .{
            .effect = move.effect,
            .power = move.power,
            .type = move.type,
            .accuracy = move.accuracy,
            .pp = move.pp,
            .target = move.target,
            .priority = move.priority,
            .category = move.category,
        }) });
    }

    for (game.pokemons, 0..) |pokemon, i| {
        try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
            .stats = pokemon.stats,
            .catch_rate = pokemon.catch_rate,
            .base_exp_yield = pokemon.base_exp_yield,
            .gender_ratio = pokemon.gender_ratio,
            .egg_cycles = pokemon.egg_cycles,
            .base_friendship = pokemon.base_friendship,
            .growth_rate = pokemon.growth_rate,
            .types = pokemon.types,
            .ev_yield = pokemon.ev.yield,
            .items = pokemon.items,
            .egg_groups = pokemon.egg_groups,
            .abilities = pokemon.abilities,
        }) });
    }

    for (game.species_to_national_dex, 0..) |dex_entry, i| {
        try ston.serialize(writer, .{ .pokemons = ston.index(i + 1, .{
            .pokedex_entry = dex_entry,
        }) });
    }

    for (game.evolutions, 0..) |evos, i| {
        for (evos, 0..) |evo, j| {
            if (evo.method == .unused)
                continue;
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .evos = ston.index(j, .{
                    .method = evo.method,
                    .param = evo.param,
                    .target = evo.target,
                }),
            }) });
        }
    }

    for (game.level_up_learnset_pointers, 0..) |lvl_up_learnset, i| {
        const learnset = try lvl_up_learnset.toSliceEnd(game.data);
        for (learnset, 0..) |l, j| {
            if (std.meta.eql(l, gen3.LevelUpMove.term))
                break;

            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .moves = ston.index(j, .{
                    .id = l.id,
                    .level = l.level,
                }),
            }) });
        }
    }

    for (game.machine_learnsets, 0..) |machine_learnset, i| {
        for (0..game.tms.len) |j| {
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .tms = ston.index(j, bit.isSet(u64, machine_learnset.value(), @as(u6, @intCast(j)))),
            }) });
        }
        for (game.tms.len..game.tms.len + game.hms.len) |j| {
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .hms = ston.index(
                    j - game.tms.len,
                    bit.isSet(u64, machine_learnset.value(), @as(u6, @intCast(j))),
                ),
            }) });
        }
    }

    for (game.pokemon_names, 0..) |str, i| {
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &str, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
            .name = ston.string(escape.escapeFmt(decoded_name)),
        }) });
    }

    for (game.ability_names, 0..) |str, i| {
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &str, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, .{ .abilities = ston.index(i, .{
            .name = ston.string(escape.escapeFmt(decoded_name)),
        }) });
    }

    for (game.move_names, 0..) |str, i| {
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &str, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, .{ .moves = ston.index(i, .{
            .name = ston.string(escape.escapeFmt(decoded_name)),
        }) });
    }

    for (game.type_names, 0..) |str, i| {
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &str, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, .{ .types = ston.index(i, .{
            .name = ston.string(escape.escapeFmt(decoded_name)),
        }) });
    }

    for (game.items, 0..) |item, i| {
        try ston.serialize(writer, .{ .items = ston.index(i, .{
            .price = item.price,
            .battle_effect = item.battle_effect,
        }) });

        switch (game.version) {
            .ruby, .sapphire, .emerald => try ston.serialize(writer, .{ .items = ston.index(i, .{
                .pocket = item.pocket.rse,
            }) }),
            .fire_red, .leaf_green => try ston.serialize(writer, .{ .items = ston.index(i, .{
                .pocket = item.pocket.frlg,
            }) }),
            else => unreachable,
        }

        {
            var fbs = io.fixedBufferStream(&buf);
            try gen3.encodings.decode(.en_us, &item.name, fbs.writer());
            const decoded_name = fbs.getWritten();

            try ston.serialize(writer, .{ .items = ston.index(i, .{
                .name = ston.string(escape.escapeFmt(decoded_name)),
            }) });
        }

        if (item.description.toSliceZ(game.data)) |str| {
            var fbs = io.fixedBufferStream(&buf);
            try gen3.encodings.decode(.en_us, str, fbs.writer());
            const decoded_description = fbs.getWritten();

            try ston.serialize(writer, .{ .items = ston.index(i, .{
                .description = ston.string(escape.escapeFmt(decoded_description)),
            }) });
        } else |_| {}
    }

    switch (game.version) {
        .emerald => for (game.pokedex.emerald, 0..) |entry, i| {
            try ston.serialize(writer, .{ .pokedex = ston.index(i, .{
                .height = entry.height,
                .weight = entry.weight,
            }) });
        },
        .ruby,
        .sapphire,
        .fire_red,
        .leaf_green,
        => for (game.pokedex.rsfrlg, 0..) |entry, i| {
            try ston.serialize(writer, .{ .pokedex = ston.index(i, .{
                .height = entry.height,
                .weight = entry.weight,
            }) });
        },
        else => unreachable,
    }

    for (game.map_headers, 0..) |header, i| {
        try ston.serialize(writer, .{ .maps = ston.index(i, .{
            .music = header.music,
            .cave = header.cave,
            .weather = header.weather,
            .type = header.map_type,
            .escape_rope = header.escape_rope,
            .battle_scene = header.map_battle_scene,
            .allow_cycling = header.flags.allow_cycling,
            .allow_escaping = header.flags.allow_escaping,
            .allow_running = header.flags.allow_running,
            .show_map_name = header.flags.show_map_name,
        }) });
    }

    for (game.wild_pokemon_headers, 0..) |header, i| {
        if (header.land.toPtr(game.data)) |land| {
            try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{ .grass_0 = .{
                .encounter_rate = land.encounter_rate,
                .pokemons = try land.wild_pokemons.toPtr(game.data),
            } }) });
        } else |_| {}
        if (header.surf.toPtr(game.data)) |surf| {
            try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{ .surf_0 = .{
                .encounter_rate = surf.encounter_rate,
                .pokemons = try surf.wild_pokemons.toPtr(game.data),
            } }) });
        } else |_| {}
        if (header.rock_smash.toPtr(game.data)) |rock| {
            try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{ .rock_smash = .{
                .encounter_rate = rock.encounter_rate,
                .pokemons = try rock.wild_pokemons.toPtr(game.data),
            } }) });
        } else |_| {}
        if (header.fishing.toPtr(game.data)) |fish| {
            try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{ .fishing_0 = .{
                .encounter_rate = fish.encounter_rate,
                .pokemons = try fish.wild_pokemons.toPtr(game.data),
            } }) });
        } else |_| {}
    }

    for (game.text, 0..) |text_ptr, i| {
        const text = try text_ptr.toSliceZ(game.data);
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, text, fbs.writer());
        const decoded_text = fbs.getWritten();

        try ston.serialize(writer, .{
            .text = ston.index(i, ston.string(escape.escapeFmt(decoded_text))),
        });
    }
}

fn outputGen4Data(game: gen4.Game, writer: anytype) !void {
    const header = game.rom.header();
    try ston.serialize(writer, .{
        .version = game.info.version,
        .game_title = ston.string(escape.escapeFmt(header.game_title.slice())),
        .gamecode = ston.string(escape.escapeFmt(&header.gamecode)),
        .instant_text = false,
        .starters = game.ptrs.starters,
        .tms = game.ptrs.tms,
        .hms = game.ptrs.hms,
        .static_pokemons = game.ptrs.static_pokemons,
        .given_pokemons = game.ptrs.given_pokemons,
        .pokeball_items = game.ptrs.pokeball_items,
    });

    for (game.ptrs.trainers, 0..) |trainer, i| {
        try ston.serialize(writer, .{ .trainers = ston.index(i, .{
            .ai = trainer.ai,
            .battle_type = trainer.battle_type,
            .party_size = trainer.party_size,
            .party_type = trainer.party_type,
            .class = trainer.class,
            .items = trainer.items,
        }) });

        const parties = game.owned.trainer_parties;
        if (parties.len <= i)
            continue;

        for (parties[i][0..trainer.party_size], 0..) |member, j| {
            try ston.serialize(writer, .{ .trainers = ston.index(i, .{
                .party = ston.index(j, .{
                    .ability = member.base.gender_ability.ability,
                    .level = member.base.level,
                    .species = member.base.species,
                }),
            }) });

            if (trainer.party_type == .item or trainer.party_type == .both) {
                try ston.serialize(writer, .{ .trainers = ston.index(i, .{
                    .party = ston.index(j, .{ .item = member.item }),
                }) });
            }

            if (trainer.party_type == .moves or trainer.party_type == .both) {
                for (member.moves, 0..) |move, k| {
                    try ston.serialize(writer, .{ .trainers = ston.index(i, .{ .party = ston.index(j, .{
                        .moves = ston.index(k, move),
                    }) }) });
                }
            }
        }
    }

    for (game.ptrs.moves, 0..) |move, i| {
        try ston.serialize(writer, .{ .moves = ston.index(i, .{
            .category = move.category,
            .power = move.power,
            .type = move.type,
            .accuracy = move.accuracy,
            .pp = move.pp,
        }) });
    }

    for (game.ptrs.pokemons, 0..) |*pokemon, i| {
        try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
            .stats = pokemon.stats,
            .catch_rate = pokemon.catch_rate,
            .base_exp_yield = pokemon.base_exp_yield,
            .gender_ratio = pokemon.gender_ratio,
            .egg_cycles = pokemon.egg_cycles,
            .base_friendship = pokemon.base_friendship,
            .growth_rate = pokemon.growth_rate,
            .types = pokemon.types,
            .ev_yield = pokemon.ev.yield,
            .items = pokemon.items,
            .egg_groups = pokemon.egg_groups,
            .abilities = pokemon.abilities,
        }) });

        const machine_learnset = pokemon.machine_learnset;
        for (0..game.ptrs.tms.len) |j| {
            const is_set = bit.isSet(u128, machine_learnset.value(), @as(u7, @intCast(j)));
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .tms = ston.index(j, is_set),
            }) });
        }
        for (game.ptrs.tms.len..game.ptrs.tms.len + game.ptrs.hms.len) |j| {
            const is_set = bit.isSet(u128, machine_learnset.value(), @as(u7, @intCast(j)));
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .hms = ston.index(j - game.ptrs.tms.len, is_set),
            }) });
        }
    }

    for (game.ptrs.species_to_national_dex, 1..) |dex_entry, i| {
        try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
            .pokedex_entry = dex_entry,
        }) });
    }

    for (game.ptrs.evolutions, 0..) |evos, i| {
        for (evos.items, 0..) |evo, j| {
            if (evo.method == .unused)
                continue;
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .evos = ston.index(j, .{
                    .method = evo.method,
                    .param = evo.param,
                    .target = evo.target,
                }),
            }) });
        }
    }

    for (game.ptrs.level_up_moves.fat, 0..) |_, i| {
        const bytes = game.ptrs.level_up_moves.fileData(.{ .i = @intCast(i) });
        const level_up_moves = mem.bytesAsSlice(gen4.LevelUpMove, bytes);

        for (level_up_moves, 0..) |move, j| {
            if (std.meta.eql(move, gen4.LevelUpMove.term))
                break;

            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .moves = ston.index(j, .{
                    .id = move.id,
                    .level = move.level,
                }),
            }) });
        }
    }

    for (game.ptrs.pokedex_heights, 0..) |height, i| {
        try ston.serialize(writer, .{ .pokedex = ston.index(i, .{
            .height = height,
        }) });
    }
    for (game.ptrs.pokedex_weights, 0..) |weight, i| {
        try ston.serialize(writer, .{ .pokedex = ston.index(i, .{
            .weight = weight,
        }) });
    }

    for (game.ptrs.items, 0..) |*item, i| {
        try ston.serialize(writer, .{ .items = ston.index(i, .{
            .price = item.price,
            .battle_effect = item.battle_effect,
            .pocket = item.pocket(),
        }) });
    }

    switch (game.info.version) {
        .diamond,
        .pearl,
        .platinum,
        => for (game.ptrs.wild_pokemons.dppt, 0..) |wild_mons, i| {
            try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{
                .grass_0 = .{ .encounter_rate = wild_mons.grass_rate },
            }) });
            for (wild_mons.grass, 0..) |grass, j| {
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{
                    .grass_0 = .{ .pokemons = ston.index(j, .{
                        .min_level = grass.level,
                        .max_level = grass.level,
                        .species = grass.species,
                    }) },
                }) });
            }

            inline for ([_][]const u8{
                "swarm_replace",
                "day_replace",
                "night_replace",
                "radar_replace",
                "unknown_replace",
                "gba_replace",
            }, 0..) |area_name, area_i| {
                for (@field(wild_mons, area_name), 0..) |replacement, j| {
                    const out_name = std.fmt.comptimePrint("grass_{}", .{area_i + 1});
                    try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                        i,
                        ston.field(out_name, .{ .pokemons = ston.index(j, .{
                            .species = replacement.species,
                        }) }),
                    ) });
                }
            }

            inline for ([_][]const u8{
                "surf",
                "sea_unknown",
            }, 0..) |area_name, area_i| {
                const out_name = std.fmt.comptimePrint("surf_{}", .{area_i});
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                    i,
                    ston.field(out_name, .{
                        .encounter_rate = @field(wild_mons, area_name).rate,
                    }),
                ) });
                for (@field(wild_mons, area_name).mons, 0..) |mon, j| {
                    try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                        i,
                        ston.field(out_name, .{ .pokemons = ston.index(j, .{
                            .min_level = mon.min_level,
                            .max_level = mon.max_level,
                            .species = mon.species,
                        }) }),
                    ) });
                }
            }

            inline for ([_][]const u8{
                "old_rod",
                "good_rod",
                "super_rod",
            }, 0..) |area_name, area_i| {
                const out_name = std.fmt.comptimePrint("fishing_{}", .{area_i});
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                    i,
                    ston.field(out_name, .{
                        .encounter_rate = @field(wild_mons, area_name).rate,
                    }),
                ) });
                for (@field(wild_mons, area_name).mons, 0..) |mon, j| {
                    try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                        i,
                        ston.field(out_name, .{ .pokemons = ston.index(j, .{
                            .min_level = mon.min_level,
                            .max_level = mon.max_level,
                            .species = mon.species,
                        }) }),
                    ) });
                }
            }
        },

        .heart_gold,
        .soul_silver,
        => for (game.ptrs.wild_pokemons.hgss, 0..) |wild_mons, i| {
            // TODO: Get rid of inline for in favor of a function to call
            inline for ([_][]const u8{
                "grass_morning",
                "grass_day",
                "grass_night",
            }, 0..) |area_name, area_i| {
                const out_name = std.fmt.comptimePrint("grass_{}", .{area_i});
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                    i,
                    ston.field(out_name, .{
                        .encounter_rate = wild_mons.grass_rate,
                    }),
                ) });
                for (@field(wild_mons, area_name), 0..) |species, j| {
                    try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                        i,
                        ston.field(out_name, .{ .pokemons = ston.index(j, .{
                            .min_level = wild_mons.grass_levels[j],
                            .max_level = wild_mons.grass_levels[j],
                            .species = species,
                        }) }),
                    ) });
                }
            }

            // TODO: Get rid of inline for in favor of a function to call
            inline for ([_][]const u8{
                "surf",
                "sea_unknown",
            }, 0..) |area_name, j| {
                const out_name = std.fmt.comptimePrint("surf_{}", .{j});
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                    i,
                    ston.field(out_name, .{
                        .encounter_rate = wild_mons.sea_rates[j],
                    }),
                ) });
                for (@field(wild_mons, area_name), 0..) |sea, k| {
                    try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                        i,
                        ston.field(out_name, .{ .pokemons = ston.index(k, .{
                            .min_level = sea.min_level,
                            .max_level = sea.max_level,
                            .species = sea.species,
                        }) }),
                    ) });
                }
            }

            inline for ([_][]const u8{
                "old_rod",
                "good_rod",
                "super_rod",
            }, 0..) |area_name, j| {
                const out_name = std.fmt.comptimePrint("fishing_{}", .{j});
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                    i,
                    ston.field(out_name, .{
                        .encounter_rate = wild_mons.sea_rates[j + 2],
                    }),
                ) });
                for (@field(wild_mons, area_name), 0..) |sea, k| {
                    try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                        i,
                        ston.field(out_name, .{ .pokemons = ston.index(k, .{
                            .min_level = sea.min_level,
                            .max_level = sea.max_level,
                            .species = sea.species,
                        }) }),
                    ) });
                }
            }

            // TODO: radio, swarm
        },

        else => unreachable,
    }

    try outputGen4StringTable(writer, "pokemons", "name", game.owned.text.pokemon_names);
    try outputGen4StringTable(writer, "moves", "name", game.owned.text.move_names);
    try outputGen4StringTable(writer, "moves", "description", game.owned.text.move_descriptions);
    try outputGen4StringTable(writer, "abilities", "name", game.owned.text.ability_names);
    try outputGen4StringTable(writer, "items", "name", game.owned.text.item_names);
    try outputGen4StringTable(writer, "items", "description", game.owned.text.item_descriptions);
    try outputGen4StringTable(writer, "types", "name", game.owned.text.type_names);
}

fn outputGen4StringTable(
    writer: anytype,
    array_name: []const u8,
    field_name: []const u8,
    table: gen4.StringTable,
) !void {
    var i: usize = 0;
    while (i < table.number_of_strings) : (i += 1)
        try outputString(writer, array_name, i, field_name, table.getSpan(i));
}

fn outputGen5Data(game: gen5.Game, writer: anytype) !void {
    const header = game.rom.header();
    try ston.serialize(writer, .{
        .version = game.info.version,
        .game_title = ston.string(escape.escapeFmt(header.game_title.slice())),
        .gamecode = ston.string(escape.escapeFmt(&header.gamecode)),
        .instant_text = false,
        .hms = game.ptrs.hms,
        .static_pokemons = game.ptrs.static_pokemons,
        .given_pokemons = game.ptrs.given_pokemons,
        .pokeball_items = game.ptrs.pokeball_items,
    });

    for (game.ptrs.tms1, 0..) |tm, i|
        try ston.serialize(writer, .{ .tms = ston.index(i, tm) });
    for (game.ptrs.tms2, 0..) |tm, i|
        try ston.serialize(writer, .{ .tms = ston.index(i + game.ptrs.tms1.len, tm) });

    for (game.ptrs.starters, 0..) |starter_ptrs, i| {
        const first = starter_ptrs[0];
        for (starter_ptrs[1..]) |starter| {
            if (first.value() != starter.value())
                log.warn("all starter positions are not the same. {} {}\n", .{ first.value(), starter.value() });
        }

        try ston.serialize(writer, .{ .starters = ston.index(i, first) });
    }

    for (game.ptrs.trainers, 0..) |trainer, index| {
        const i = index + 1;
        try ston.serialize(writer, .{ .trainers = ston.index(i, .{
            .ai = trainer.ai,
            .battle_type = trainer.battle_type,
            .party_size = trainer.party_size,
            .party_type = trainer.party_type,
            .class = trainer.class,
            .items = trainer.items,
        }) });

        const parties = game.owned.trainer_parties;
        if (parties.len <= i)
            continue;

        for (parties[i][0..trainer.party_size], 0..) |member, j| {
            try ston.serialize(writer, .{ .trainers = ston.index(i, .{
                .party = ston.index(j, .{
                    .ability = member.base.gender_ability.ability,
                    .level = member.base.level,
                    .species = member.base.species,
                }),
            }) });

            if (trainer.party_type == .item or trainer.party_type == .both) {
                try ston.serialize(writer, .{ .trainers = ston.index(i, .{
                    .party = ston.index(j, .{ .item = member.item }),
                }) });
            }

            if (trainer.party_type == .moves or trainer.party_type == .both) {
                for (member.moves, 0..) |move, k| {
                    try ston.serialize(writer, .{ .trainers = ston.index(i, .{ .party = ston.index(j, .{
                        .moves = ston.index(k, move),
                    }) }) });
                }
            }
        }
    }

    for (game.ptrs.moves, 0..) |move, i| {
        try ston.serialize(writer, .{ .moves = ston.index(i, .{
            .type = move.type,
            .category = move.category,
            .power = move.power,
            .accuracy = move.accuracy,
            .pp = move.pp,
            .priority = move.priority,
            .target = move.target,
        }) });
    }

    for (game.ptrs.pokemons.fat, 0..) |_, i| {
        const pokemon = try game.ptrs.pokemons.fileAs(.{ .i = @intCast(i) }, gen5.BasePokemon);

        try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
            .pokedex_entry = i,
            .stats = pokemon.stats,
            .base_exp_yield = pokemon.base_exp_yield,
            .catch_rate = pokemon.catch_rate,
            .gender_ratio = pokemon.gender_ratio,
            .egg_cycles = pokemon.egg_cycles,
            .base_friendship = pokemon.base_friendship,
            .growth_rate = pokemon.growth_rate,
            .types = pokemon.types,
            .ev_yield = pokemon.ev.yield,
            .items = pokemon.items,
            .abilities = pokemon.abilities,
        }) });

        for (pokemon.egg_groups, 0..) |group, j| {
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .egg_groups = ston.index(j, group),
            }) });
        }

        const machine_learnset = pokemon.machine_learnset;
        var j: u7 = 0;
        while (j < game.ptrs.tms1.len + game.ptrs.tms2.len) : (j += 1) {
            const is_set = bit.isSet(u128, machine_learnset.value(), j);
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .tms = ston.index(j, is_set),
            }) });
        }
        while (j < game.ptrs.tms1.len + game.ptrs.tms2.len + game.ptrs.hms.len) : (j += 1) {
            const is_set = bit.isSet(u128, machine_learnset.value(), j);
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .hms = ston.index(j - (game.ptrs.tms1.len + game.ptrs.tms2.len), is_set),
            }) });
        }
    }

    for (game.ptrs.evolutions, 0..) |evos, i| {
        for (evos.items, 0..) |evo, j| {
            if (evo.method == .unused)
                continue;
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .evos = ston.index(j, .{
                    .method = evo.method,
                    .param = evo.param,
                    .target = evo.target,
                }),
            }) });
        }
    }

    for (game.ptrs.level_up_moves.fat, 0..) |_, i| {
        const bytes = game.ptrs.level_up_moves.fileData(.{ .i = @intCast(i) });
        const level_up_moves = mem.bytesAsSlice(gen5.LevelUpMove, bytes);
        for (level_up_moves, 0..) |move, j| {
            if (std.meta.eql(move, gen5.LevelUpMove.term))
                break;

            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .moves = ston.index(j, .{
                    .id = move.id,
                    .level = move.level,
                }),
            }) });
        }
    }

    for (game.ptrs.items, 0..) |*item, i| {
        // Price in gen5 is actually price * 10. I imagine they where trying to avoid
        // having price be more than a u16
        try ston.serialize(writer, .{ .items = ston.index(i, .{
            .price = @as(usize, item.price.value()) * 10,
            .battle_effect = item.battle_effect,
            .pocket = item.pocket(),
        }) });
    }

    for (game.ptrs.map_headers, 0..) |map_header, i| {
        try ston.serialize(writer, .{ .maps = ston.index(i, .{
            .music = map_header.music,
            .battle_scene = map_header.battle_scene,
        }) });
    }

    for (game.ptrs.wild_pokemons.fat, 0..) |_, i| {
        const file = nds.fs.File{ .i = @intCast(i) };
        const wilds: []align(1) gen5.WildPokemons =
            game.ptrs.wild_pokemons.fileAs(file, [4]gen5.WildPokemons) catch
            try game.ptrs.wild_pokemons.fileAs(file, [1]gen5.WildPokemons);

        for (wilds, 0..) |wild_mons, wild_i| {
            inline for ([_][]const u8{
                "grass",
                "dark_grass",
                "rustling_grass",
                "surf",
                "ripple_surf",
                "fishing",
                "ripple_fishing",
            }, 0..) |area_name, j| {
                var buf: [20]u8 = undefined;
                const out_name = std.fmt.bufPrint(&buf, "{s}_{}", .{ area_name, wild_i }) catch
                    unreachable;
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                    i,
                    ston.field(out_name, .{
                        .encounter_rate = wild_mons.rates[j],
                    }),
                ) });
                for (@field(wild_mons, area_name), 0..) |mon, k| {
                    try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                        i,
                        ston.field(out_name, .{ .pokemons = ston.index(k, .{
                            .species = mon.species.species(),
                            .min_level = mon.min_level,
                            .max_level = mon.max_level,
                        }) }),
                    ) });
                }
            }
        }
    }

    if (game.ptrs.hidden_hollows) |hidden_hollows| {
        // The nesting is real :)
        for (hidden_hollows, 0..) |hollow, i| {
            for (hollow.pokemons, 0..) |group, j| {
                for (group.species, 0..) |s, k| {
                    try ston.serialize(writer, .{
                        .hidden_hollows = ston.index(i, .{
                            .groups = ston.index(j, .{
                                .pokemons = ston.index(k, .{
                                    .species = s,
                                }),
                            }),
                        }),
                    });
                }
            }
            try ston.serialize(writer, .{
                .hidden_hollows = ston.index(i, .{
                    .items = hollow.items,
                }),
            });
        }
    }

    try outputGen5StringTable(writer, "pokemons", 0, "name", game.owned.text.pokemon_names);
    try outputGen5StringTable(writer, "pokedex", 0, "category", game.owned.text.pokedex_category_names);
    try outputGen5StringTable(writer, "moves", 0, "name", game.owned.text.move_names);
    try outputGen5StringTable(writer, "moves", 0, "description", game.owned.text.move_descriptions);
    try outputGen5StringTable(writer, "abilities", 0, "name", game.owned.text.ability_names);
    try outputGen5StringTable(writer, "items", 0, "name", game.owned.text.item_names);
    try outputGen5StringTable(writer, "items", 0, "description", game.owned.text.item_descriptions);
    try outputGen5StringTable(writer, "types", 0, "name", game.owned.text.type_names);
    try outputGen5StringTable(writer, "trainers", 1, "name", game.owned.text.trainer_names);
}

fn outputGen5StringTable(
    writer: anytype,
    array_name: []const u8,
    start: usize,
    field_name: []const u8,
    table: gen5.StringTable,
) !void {
    for (table.keys[start..], 0..) |_, i|
        try outputString(writer, array_name, i + start, field_name, table.getSpan(i + start));
}

fn outputString(
    writer: anytype,
    array_name: []const u8,
    i: usize,
    field_name: []const u8,
    string: []const u8,
) !void {
    try ston.serialize(writer, ston.field(array_name, ston.index(
        i,
        ston.field(field_name, ston.string(escape.escapeFmt(string))),
    )));
}
