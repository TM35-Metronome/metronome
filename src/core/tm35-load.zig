const clap = @import("clap");
const std = @import("std");
const ston = @import("ston");
const util = @import("util");

const common = @import("common.zig");
const format = @import("format.zig");
const gen3 = @import("gen3.zig");
const gen4 = @import("gen4.zig");
const gen5 = @import("gen5.zig");
const rom = @import("rom.zig");

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const log = std.log;
const math = std.math;
const mem = std.mem;
const unicode = std.unicode;

const gba = rom.gba;
const nds = rom.nds;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;

const bit = util.bit;
const escape = util.escape;

const Game = format.Game;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = [_]Param{
    clap.parseParam("-h, --help     Display this help text and exit.    ") catch unreachable,
    clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
    clap.parseParam("<ROM>          The rom to apply the changes to.    ") catch unreachable,
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-load ");
    try clap.usage(writer, &params);
    try writer.writeAll(
        \\
        \\Load data from Pokémon games.
        \\
        \\Options:
        \\
    );
    try clap.help(writer, &params);
}

pub fn main2(
    allocator: *mem.Allocator,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) anyerror!void {
    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else return error.MissingFile;

    const file = try fs.cwd().openFile(file_name, .{});
    defer file.close();

    const gen3_error = if (gen3.Game.fromFile(file, allocator)) |*game| {
        defer game.deinit();
        try outputGen3Data(game.*, stdio.out);
        return;
    } else |err| err;

    try file.seekTo(0);
    if (nds.Rom.fromFile(file, allocator)) |*nds_rom| {
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

        log.info("Successfully loaded '{s}' as a nds rom.\n", .{file_name});
        log.err("Failed to load '{s}' as a gen4 game: {}\n", .{ file_name, gen4_error });
        log.err("Failed to load '{s}' as a gen5 game: {}\n", .{ file_name, gen5_error });
        return gen5_error;
    } else |nds_error| {
        log.err("Failed to load '{s}' as a gen3 game: {}\n", .{ file_name, gen3_error });
        log.err("Failed to load '{s}' as a gen4/gen5 game: {}\n", .{ file_name, nds_error });
        return nds_error;
    }
}

fn outputGen3Data(game: gen3.Game, writer: anytype) !void {
    var buf: [mem.page_size]u8 = undefined;

    for (game.starters) |starter, index| {
        if (starter.value() != game.starters_repeat[index].value())
            debug.warn("warning: repeated starters don't match.\n", .{});
    }

    try ston.serialize(writer, .{
        .version = game.version,
        .game_title = ston.string(escape.default.escapeFmt(game.header.game_title.span())),
        .gamecode = ston.string(escape.default.escapeFmt(&game.header.gamecode)),
        .starters = game.starters,
        .text_delays = game.text_delays,
        .tms = game.tms,
        .hms = game.hms,
        .static_pokemons = game.static_pokemons,
        .given_pokemons = game.given_pokemons,
        .pokeball_items = game.pokeball_items,
    });

    for (game.trainers) |trainer, i| {
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &trainer.name, fbs.writer());
        const name = fbs.getWritten();

        const party = game.trainer_parties[i];
        try ston.serialize(writer, .{ .trainers = ston.index(i, .{
            .class = trainer.class,
            .encounter_music = trainer.encounter_music.music,
            .trainer_picture = trainer.trainer_picture,
            .name = ston.string(escape.default.escapeFmt(name)),
            .items = trainer.items,
            .party_type = trainer.party_type,
            .party_size = trainer.partyLen(),
        }) });

        for (party.members[0..party.size]) |member, j| {
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
                for (member.moves) |move, k| {
                    try ston.serialize(writer, .{ .trainers = ston.index(i, .{ .party = ston.index(j, .{
                        .moves = ston.index(k, move),
                    }) }) });
                }
            }
        }
    }

    for (game.moves) |move, i| {
        try ston.serialize(writer, .{ .moves = ston.index(i, .{
            .effect = move.effect,
            .power = move.power,
            .type = move.@"type",
            .accuracy = move.accuracy,
            .pp = move.pp,
            .target = move.target,
            .priority = move.priority,
            .category = move.category,
        }) });
    }

    for (game.pokemons) |pokemon, i| {
        // Wonna crash the compiler? Follow this one simple trick!!!
        // Remove these variables and do the initialization directly in `ston.serialize`
        const stats = pokemon.stats;
        const ev_yield = .{
            .hp = pokemon.ev_yield.hp,
            .attack = pokemon.ev_yield.attack,
            .defense = pokemon.ev_yield.defense,
            .speed = pokemon.ev_yield.speed,
            .sp_attack = pokemon.ev_yield.sp_attack,
            .sp_defense = pokemon.ev_yield.sp_defense,
        };
        try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
            .stats = stats,
            .catch_rate = pokemon.catch_rate,
            .base_exp_yield = pokemon.base_exp_yield,
            .ev_yield = ev_yield,
            .gender_ratio = pokemon.gender_ratio,
            .egg_cycles = pokemon.egg_cycles,
            .base_friendship = pokemon.base_friendship,
            .growth_rate = pokemon.growth_rate,
            .color = pokemon.color.color,
            .types = pokemon.types,
            .items = pokemon.items,
            .egg_groups = pokemon.egg_groups,
            .abilities = pokemon.abilities,
        }) });
    }

    for (game.species_to_national_dex) |dex_entry, i| {
        try ston.serialize(writer, .{ .pokemons = ston.index(i + 1, .{
            .pokedex_entry = dex_entry,
        }) });
    }

    for (game.evolutions) |evos, i| {
        for (evos) |evo, j| {
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

    for (game.level_up_learnset_pointers) |lvl_up_learnset, i| {
        const learnset = try lvl_up_learnset.toSliceEnd(game.data);
        for (learnset) |l, j| {
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

    for (game.machine_learnsets) |machine_learnset, i| {
        var j: u6 = 0;
        while (j < game.tms.len) : (j += 1) {
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .tms = ston.index(j, bit.isSet(u64, machine_learnset.value(), j)),
            }) });
        }
        while (j < game.tms.len + game.hms.len) : (j += 1) {
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .hms = ston.index(j - game.tms.len, bit.isSet(u64, machine_learnset.value(), j)),
            }) });
        }
    }

    for (game.pokemon_names) |name, i| {
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &name, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
            .name = ston.string(escape.default.escapeFmt(decoded_name)),
        }) });
    }

    for (game.ability_names) |name, i| {
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &name, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, .{ .abilities = ston.index(i, .{
            .name = ston.string(escape.default.escapeFmt(decoded_name)),
        }) });
    }

    for (game.move_names) |name, i| {
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &name, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, .{ .moves = ston.index(i, .{
            .name = ston.string(escape.default.escapeFmt(decoded_name)),
        }) });
    }

    for (game.type_names) |name, i| {
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &name, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, .{ .types = ston.index(i, .{
            .name = ston.string(escape.default.escapeFmt(decoded_name)),
        }) });
    }

    for (game.items) |item, i| {
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
            const name = fbs.getWritten();

            try ston.serialize(writer, .{ .items = ston.index(i, .{
                .name = ston.string(escape.default.escapeFmt(name)),
            }) });
        }

        if (item.description.toSliceZ(game.data)) |description| {
            var fbs = io.fixedBufferStream(&buf);
            try gen3.encodings.decode(.en_us, description, fbs.writer());
            const decoded_description = fbs.getWritten();

            try ston.serialize(writer, .{ .items = ston.index(i, .{
                .description = ston.string(escape.default.escapeFmt(decoded_description)),
            }) });
        } else |_| {}
    }

    switch (game.version) {
        .emerald => for (game.pokedex.emerald) |entry, i| {
            try ston.serialize(writer, .{ .pokedex = ston.index(i, .{
                .height = entry.height,
                .weight = entry.weight,
            }) });
        },
        .ruby,
        .sapphire,
        .fire_red,
        .leaf_green,
        => for (game.pokedex.rsfrlg) |entry, i| {
            try ston.serialize(writer, .{ .pokedex = ston.index(i, .{
                .height = entry.height,
                .weight = entry.weight,
            }) });
        },
        else => unreachable,
    }

    for (game.map_headers) |header, i| {
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

    for (game.wild_pokemon_headers) |header, i| {
        if (header.land.toPtr(game.data)) |land| {
            const wilds = try land.wild_pokemons.toPtr(game.data);
            // Wonna see a bug with result locations in the compiler? Try lining this variable
            // into `ston.serialize` :)
            const area = .{
                .encounter_rate = land.encounter_rate,
                .pokemons = wilds,
            };
            try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{ .land = area }) });
        } else |_| {}
        if (header.surf.toPtr(game.data)) |surf| {
            const wilds = try surf.wild_pokemons.toPtr(game.data);
            const area = .{
                .encounter_rate = surf.encounter_rate,
                .pokemons = wilds,
            };
            try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{ .surf = area }) });
        } else |_| {}
        if (header.rock_smash.toPtr(game.data)) |rock| {
            const wilds = try rock.wild_pokemons.toPtr(game.data);
            const area = .{
                .encounter_rate = rock.encounter_rate,
                .pokemons = wilds,
            };
            try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{ .rock_smash = area }) });
        } else |_| {}
        if (header.fishing.toPtr(game.data)) |fish| {
            const wilds = try fish.wild_pokemons.toPtr(game.data);
            const area = .{
                .encounter_rate = fish.encounter_rate,
                .pokemons = wilds,
            };
            try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{ .fishing = area }) });
        } else |_| {}
    }

    for (game.text) |text_ptr, i| {
        const text = try text_ptr.toSliceZ(game.data);
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, text, fbs.writer());
        const decoded_text = fbs.getWritten();

        try ston.serialize(writer, .{
            .text = ston.index(i, ston.string(escape.default.escapeFmt(decoded_text))),
        });
    }
}

fn outputGen4Data(game: gen4.Game, writer: anytype) !void {
    const header = game.rom.header();
    try ston.serialize(writer, .{
        .version = game.info.version,
        .game_title = ston.string(escape.default.escapeFmt(header.game_title.span())),
        .gamecode = ston.string(escape.default.escapeFmt(&header.gamecode)),
        .instant_text = false,
        .starters = game.ptrs.starters,
        .tms = game.ptrs.tms,
        .hms = game.ptrs.hms,
        .static_pokemons = game.ptrs.static_pokemons,
        .given_pokemons = game.ptrs.given_pokemons,
        .pokeball_items = game.ptrs.pokeball_items,
    });

    for (game.ptrs.trainers) |trainer, i| {
        try ston.serialize(writer, .{ .trainers = ston.index(i, .{
            .party_size = trainer.party_size,
            .party_type = trainer.party_type,
            .class = trainer.class,
            .items = trainer.items,
        }) });

        const parties = game.owned.trainer_parties;
        if (parties.len <= i)
            continue;

        for (parties[i][0..trainer.party_size]) |member, j| {
            try ston.serialize(writer, .{ .trainers = ston.index(i, .{
                .party = ston.index(j, .{
                    .ability = member.base.gender_ability.ability,
                    .level = member.base.level,
                    .species = member.base.species,
                    .item = member.item,
                    .moves = member.moves,
                }),
            }) });
        }
    }

    for (game.ptrs.moves) |move, i| {
        try ston.serialize(writer, .{ .moves = ston.index(i, .{
            .category = move.category,
            .power = move.power,
            .type = move.type,
            .accuracy = move.accuracy,
            .pp = move.pp,
        }) });
    }

    for (game.ptrs.pokemons) |pokemon, i| {
        // Wonna crash the compiler? Follow this one simple trick!!!
        // Remove these variables and do the initialization directly in `ston.serialize`
        const stats = pokemon.stats;
        const ev_yield = .{
            .hp = pokemon.ev_yield.hp,
            .attack = pokemon.ev_yield.attack,
            .defense = pokemon.ev_yield.defense,
            .speed = pokemon.ev_yield.speed,
            .sp_attack = pokemon.ev_yield.sp_attack,
            .sp_defense = pokemon.ev_yield.sp_defense,
        };

        try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
            .stats = stats,
            .catch_rate = pokemon.catch_rate,
            .base_exp_yield = pokemon.base_exp_yield,
            .ev_yield = ev_yield,
            .gender_ratio = pokemon.gender_ratio,
            .egg_cycles = pokemon.egg_cycles,
            .base_friendship = pokemon.base_friendship,
            .growth_rate = pokemon.growth_rate,
            .color = pokemon.color.color,
            .types = pokemon.types,
            .items = pokemon.items,
            .egg_groups = pokemon.egg_groups,
            .abilities = pokemon.abilities,
        }) });

        const machine_learnset = pokemon.machine_learnset;
        var j: u7 = 0;
        while (j < game.ptrs.tms.len) : (j += 1) {
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .tms = ston.index(j, bit.isSet(u128, machine_learnset.value(), j)),
            }) });
        }
        while (j < game.ptrs.tms.len + game.ptrs.hms.len) : (j += 1) {
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .hms = ston.index(j - game.ptrs.tms.len, bit.isSet(u128, machine_learnset.value(), j)),
            }) });
        }
    }

    for (game.ptrs.species_to_national_dex) |dex_entry, i| {
        try ston.serialize(writer, .{ .pokemons = ston.index(i + 1, .{
            .pokedex_entry = dex_entry,
        }) });
    }

    for (game.ptrs.evolutions) |evos, i| {
        for (evos.items) |evo, j| {
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

    for (game.ptrs.level_up_moves.fat) |_, i| {
        const bytes = game.ptrs.level_up_moves.fileData(.{ .i = @intCast(u32, i) });
        const level_up_moves = mem.bytesAsSlice(gen4.LevelUpMove, bytes);

        for (level_up_moves) |move, j| {
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

    for (game.ptrs.pokedex_heights) |height, i| {
        try ston.serialize(writer, .{ .pokedex = ston.index(i, .{
            .height = height,
        }) });
    }
    for (game.ptrs.pokedex_weights) |weight, i| {
        try ston.serialize(writer, .{ .pokedex = ston.index(i, .{
            .weight = weight,
        }) });
    }

    for (game.ptrs.items) |item, i| {
        try ston.serialize(writer, .{ .items = ston.index(i, .{
            .price = item.price,
            .battle_effect = item.battle_effect,
            .pocket = item.pocket.pocket,
        }) });
    }

    switch (game.info.version) {
        .diamond,
        .pearl,
        .platinum,
        => for (game.ptrs.wild_pokemons.dppt) |wild_mons, i| {
            const rate = .{ .encounter_rate = wild_mons.grass_rate }; // Result location crash alert
            try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{
                .grass = rate,
            }) });
            for (wild_mons.grass) |grass, j| {
                const pokemon = .{ .pokemons = ston.index(j, .{
                    .min_level = grass.level,
                    .max_level = grass.level,
                    .species = grass.species,
                }) }; // Result location crash alert
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(i, .{
                    .grass = pokemon,
                }) });
            }

            inline for ([_][]const u8{
                "swarm_replace",
                "day_replace",
                "night_replace",
                "radar_replace",
                "unknown_replace",
                "gba_replace",
            }) |area_name| {
                for (@field(wild_mons, area_name)) |replacement, j| {
                    try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                        i,
                        ston.field(area_name, .{ .pokemons = ston.index(j, .{
                            .species = replacement.species,
                        }) }),
                    ) });
                }
            }

            inline for ([_][]const u8{
                "surf",
                "sea_unknown",
                "old_rod",
                "good_rod",
                "super_rod",
            }) |area_name| {
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                    i,
                    ston.field(area_name, .{
                        .encounter_rate = @field(wild_mons, area_name).rate,
                    }),
                ) });
                for (@field(wild_mons, area_name).mons) |mon, j| {
                    try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                        i,
                        ston.field(area_name, .{ .pokemons = ston.index(j, .{
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
        => for (game.ptrs.wild_pokemons.hgss) |wild_mons, i| {
            // TODO: Get rid of inline for in favor of a function to call
            inline for ([_][]const u8{
                "grass_morning",
                "grass_day",
                "grass_night",
            }) |area_name| {
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                    i,
                    ston.field(area_name, .{
                        .encounter_rate = wild_mons.grass_rate,
                    }),
                ) });
                for (@field(wild_mons, area_name)) |species, j| {
                    try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                        i,
                        ston.field(area_name, .{ .pokemons = ston.index(j, .{
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
                "old_rod",
                "good_rod",
                "super_rod",
            }) |area_name, j| {
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                    i,
                    ston.field(area_name, .{
                        .encounter_rate = wild_mons.sea_rates[j],
                    }),
                ) });
                for (@field(wild_mons, area_name)) |sea, k| {
                    try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                        i,
                        ston.field(area_name, .{ .pokemons = ston.index(k, .{
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

    try outputGen4StringTable(writer, "pokemons", "name", game.owned.strings.pokemon_names);
    try outputGen4StringTable(writer, "moves", "name", game.owned.strings.move_names);
    try outputGen4StringTable(writer, "moves", "description", game.owned.strings.move_descriptions);
    try outputGen4StringTable(writer, "abilities", "name", game.owned.strings.ability_names);
    try outputGen4StringTable(writer, "items", "name", game.owned.strings.item_names);
    try outputGen4StringTable(writer, "items", "description", game.owned.strings.item_descriptions);
    try outputGen4StringTable(writer, "types", "name", game.owned.strings.type_names);
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
        .game_title = ston.string(escape.default.escapeFmt(header.game_title.span())),
        .gamecode = ston.string(escape.default.escapeFmt(&header.gamecode)),
        .instant_text = false,
        .hms = game.ptrs.hms,
        .static_pokemons = game.ptrs.static_pokemons,
        .given_pokemons = game.ptrs.given_pokemons,
        .pokeball_items = game.ptrs.pokeball_items,
    });

    for (game.ptrs.tms1) |tm, i|
        try ston.serialize(writer, .{ .tms = ston.index(i, tm) });
    for (game.ptrs.tms2) |tm, i|
        try ston.serialize(writer, .{ .tms = ston.index(i + game.ptrs.tms1.len, tm) });

    for (game.ptrs.starters) |starter_ptrs, i| {
        const first = starter_ptrs[0];
        for (starter_ptrs[1..]) |starter| {
            if (first.value() != starter.value())
                debug.warn("warning: all starter positions are not the same. {} {}\n", .{ first.value(), starter.value() });
        }

        try ston.serialize(writer, .{ .starters = ston.index(i, first) });
    }

    for (game.ptrs.trainers) |trainer, index| {
        const i = index + 1;
        try ston.serialize(writer, .{ .trainers = ston.index(i, .{
            .party_size = trainer.party_size,
            .party_type = trainer.party_type,
            .class = trainer.class,
            .items = trainer.items,
        }) });

        const parties = game.owned.trainer_parties;
        if (parties.len <= i)
            continue;

        for (parties[i][0..trainer.party_size]) |member, j| {
            try ston.serialize(writer, .{ .trainers = ston.index(i, .{
                .party = ston.index(j, .{
                    .ability = member.base.gender_ability.ability,
                    .level = member.base.level,
                    .species = member.base.species,
                    .item = member.item,
                    .moves = member.moves,
                }),
            }) });
        }
    }

    for (game.ptrs.moves) |move, i| {
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

    const number_of_pokemons = 649;
    for (game.ptrs.pokemons.fat) |_, i| {
        const pokemon = try game.ptrs.pokemons.fileAs(.{ .i = @intCast(u32, i) }, gen5.BasePokemon);

        // Wonna crash the compiler? Follow this one simple trick!!!
        // Remove these variables and do the initialization directly in `ston.serialize`
        const stats = pokemon.stats;
        const ev_yield = .{
            .hp = pokemon.ev_yield.hp,
            .attack = pokemon.ev_yield.attack,
            .defense = pokemon.ev_yield.defense,
            .speed = pokemon.ev_yield.speed,
            .sp_attack = pokemon.ev_yield.sp_attack,
            .sp_defense = pokemon.ev_yield.sp_defense,
        };

        try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
            .pokedex_entry = i,
            .stats = stats,
            .base_exp_yield = pokemon.base_exp_yield,
            .catch_rate = pokemon.catch_rate,
            .ev_yield = ev_yield,
            .gender_ratio = pokemon.gender_ratio,
            .egg_cycles = pokemon.egg_cycles,
            .base_friendship = pokemon.base_friendship,
            .growth_rate = pokemon.growth_rate,
            .types = pokemon.types,
            .items = pokemon.items,
            .abilities = pokemon.abilities,
        }) });

        // HACK: For some reason, a release build segfaults here for Pokémons
        //       with id above 'number_of_pokemons'. You would think this is
        //       because of an index out of bounds during @tagName, but
        //       common.EggGroup is a u4 enum and has a tag for all possible
        //       values, so it really should not.
        if (i < number_of_pokemons) {
            for (pokemon.egg_groups) |group, j| {
                try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                    .egg_groups = ston.index(j, group),
                }) });
            }
        }

        const machine_learnset = pokemon.machine_learnset;
        var j: u7 = 0;
        while (j < game.ptrs.tms1.len + game.ptrs.tms2.len) : (j += 1) {
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .tms = ston.index(j, bit.isSet(u128, machine_learnset.value(), j)),
            }) });
        }
        while (j < game.ptrs.tms1.len + game.ptrs.tms2.len + game.ptrs.hms.len) : (j += 1) {
            try ston.serialize(writer, .{ .pokemons = ston.index(i, .{
                .hms = ston.index(j - (game.ptrs.tms1.len + game.ptrs.tms2.len), bit.isSet(u128, machine_learnset.value(), j)),
            }) });
        }
    }

    for (game.ptrs.evolutions) |evos, i| {
        for (evos.items) |evo, j| {
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

    for (game.ptrs.level_up_moves.fat) |_, i| {
        const bytes = game.ptrs.level_up_moves.fileData(.{ .i = @intCast(u32, i) });
        const level_up_moves = mem.bytesAsSlice(gen5.LevelUpMove, bytes);
        for (level_up_moves) |move, j| {
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

    for (game.ptrs.items) |item, i| {
        // Price in gen5 is actually price * 10. I imagine they where trying to avoid
        // having price be more than a u16
        try ston.serialize(writer, .{ .items = ston.index(i, .{
            .price = @as(usize, item.price.value()) * 10,
            .battle_effect = item.battle_effect,
            .pocket = item.pocket.pocket,
        }) });
    }

    for (game.ptrs.map_headers) |map_header, i| {
        try ston.serialize(writer, .{ .maps = ston.index(i, .{
            .music = map_header.music,
            .battle_scene = map_header.battle_scene,
        }) });
    }

    for (game.ptrs.wild_pokemons.fat) |_, i| {
        const wild_mons = try game.ptrs.wild_pokemons.fileAs(.{ .i = @intCast(u32, i) }, gen5.WildPokemons);
        inline for ([_][]const u8{
            "grass",
            "dark_grass",
            "rustling_grass",
            "surf",
            "ripple_surf",
            "fishing",
            "ripple_fishing",
        }) |area_name, j| {
            try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                i,
                ston.field(area_name, .{
                    .encounter_rate = wild_mons.rates[j],
                }),
            ) });
            for (@field(wild_mons, area_name)) |mon, k| {
                try ston.serialize(writer, .{ .wild_pokemons = ston.index(
                    i,
                    ston.field(area_name, .{ .pokemons = ston.index(k, .{
                        .species = mon.species.species(),
                        .min_level = mon.min_level,
                        .max_level = mon.max_level,
                    }) }),
                ) });
            }
        }
    }

    if (game.ptrs.hidden_hollows) |hidden_hollows| {
        // The nesting is real :)
        for (hidden_hollows) |hollow, i| {
            for (hollow.pokemons) |group, j| {
                for (group.species) |s, k| {
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

    try outputGen5StringTable(writer, "pokemons", 0, "name", game.owned.strings.pokemon_names);
    try outputGen5StringTable(writer, "pokedex", 0, "category", game.owned.strings.pokedex_category_names);
    try outputGen5StringTable(writer, "moves", 0, "name", game.owned.strings.move_names);
    try outputGen5StringTable(writer, "moves", 0, "description", game.owned.strings.move_descriptions);
    try outputGen5StringTable(writer, "abilities", 0, "name", game.owned.strings.ability_names);
    try outputGen5StringTable(writer, "items", 0, "name", game.owned.strings.item_names);
    try outputGen5StringTable(writer, "items", 0, "description", game.owned.strings.item_descriptions);
    try outputGen5StringTable(writer, "types", 0, "name", game.owned.strings.type_names);
    try outputGen5StringTable(writer, "trainers", 1, "name", game.owned.strings.trainer_names);
}

fn outputGen5StringTable(
    writer: anytype,
    array_name: []const u8,
    start: usize,
    field_name: []const u8,
    table: gen5.StringTable,
) !void {
    for (table.keys[start..]) |_, i|
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
        ston.field(field_name, ston.string(escape.default.escapeFmt(string))),
    )));
}

test {
    std.testing.refAllDecls(@This());
}
