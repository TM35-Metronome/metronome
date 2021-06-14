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
            try outputGen4Data(nds_rom.*, game.*, stdio.out);
            return;
        } else |err| err;

        const gen5_error = if (gen5.Game.fromRom(allocator, nds_rom)) |*game| {
            defer game.deinit();
            try outputGen5Data(nds_rom.*, game.*, stdio.out);
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
    try ston.serialize(writer, Game{ .version = game.version });
    try ston.serialize(writer, Game{ .game_title = game.header.game_title.span() });
    try ston.serialize(writer, Game{ .gamecode = &game.header.gamecode });

    for (game.starters) |starter, index| {
        if (starter.value() != game.starters_repeat[index].value())
            debug.warn("warning: repeated starters don't match.\n", .{});

        const i = @intCast(u8, index);
        try ston.serialize(writer, Game.starter(i, starter.value()));
    }

    for (game.text_delays) |delay, index| {
        const i = @intCast(u8, index);
        try ston.serialize(writer, Game.text_delay(i, delay));
    }

    for (game.trainers) |trainer, index| {
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &trainer.name, fbs.writer());
        const name = fbs.getWritten();

        const i = @intCast(u16, index);
        const party = game.trainer_parties[i];
        try ston.serialize(writer, Game.trainer(i, .{ .class = trainer.class }));
        try ston.serialize(writer, Game.trainer(i, .{ .encounter_music = trainer.encounter_music.music }));
        try ston.serialize(writer, Game.trainer(i, .{ .trainer_picture = trainer.trainer_picture }));
        try ston.serialize(writer, Game.trainer(i, .{ .name = name }));

        for (trainer.items) |item, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.trainer(i, .{ .items = .{ .index = j, .value = item.value() } }));
        }

        try ston.serialize(writer, Game.trainer(i, .{ .party_type = trainer.party_type }));
        try ston.serialize(writer, Game.trainer(i, .{ .party_size = trainer.partyLen() }));
        for (party.members[0..party.size]) |member, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .level = @intCast(u8, member.base.level.value()) } } }));
            try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .species = member.base.species.value() } } }));
            if (trainer.party_type == .item or trainer.party_type == .both)
                try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .item = member.item.value() } } }));
            if (trainer.party_type == .moves or trainer.party_type == .both) {
                for (member.moves) |move, kndex| {
                    const k = @intCast(u8, kndex);
                    try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .moves = .{ .index = k, .value = move.value() } } } }));
                }
            }
        }
    }

    for (game.moves) |move, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.move(i, .{ .effect = move.effect }));
        try ston.serialize(writer, Game.move(i, .{ .power = move.power }));
        try ston.serialize(writer, Game.move(i, .{ .type = move.@"type" }));
        try ston.serialize(writer, Game.move(i, .{ .accuracy = move.accuracy }));
        try ston.serialize(writer, Game.move(i, .{ .pp = move.pp }));
        try ston.serialize(writer, Game.move(i, .{ .target = move.target }));
        try ston.serialize(writer, Game.move(i, .{ .priority = move.priority }));
        try ston.serialize(writer, Game.move(i, .{ .category = move.category }));
    }

    for (game.pokemons) |pokemon, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .hp = pokemon.stats.hp } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .attack = pokemon.stats.attack } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .defense = pokemon.stats.defense } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .speed = pokemon.stats.speed } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .sp_attack = pokemon.stats.sp_attack } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .sp_defense = pokemon.stats.sp_defense } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .catch_rate = pokemon.catch_rate }));
        try ston.serialize(writer, Game.pokemon(i, .{ .base_exp_yield = pokemon.base_exp_yield }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .hp = pokemon.ev_yield.hp } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .attack = pokemon.ev_yield.attack } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .defense = pokemon.ev_yield.defense } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .speed = pokemon.ev_yield.speed } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .sp_attack = pokemon.ev_yield.sp_attack } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .sp_defense = pokemon.ev_yield.sp_defense } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .gender_ratio = pokemon.gender_ratio }));
        try ston.serialize(writer, Game.pokemon(i, .{ .egg_cycles = pokemon.egg_cycles }));
        try ston.serialize(writer, Game.pokemon(i, .{ .base_friendship = pokemon.base_friendship }));
        try ston.serialize(writer, Game.pokemon(i, .{ .growth_rate = pokemon.growth_rate }));
        try ston.serialize(writer, Game.pokemon(i, .{ .color = pokemon.color.color }));

        for (pokemon.types) |t, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .types = .{ .index = j, .value = t } }));
        }
        for (pokemon.items) |item, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .items = .{ .index = j, .value = item.value() } }));
        }
        for (pokemon.egg_groups) |group, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .egg_groups = .{ .index = j, .value = group } }));
        }
        for (pokemon.abilities) |ability, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .abilities = .{ .index = j, .value = ability } }));
        }
    }
    for (game.species_to_national_dex) |dex_entry, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game{ .pokemons = .{ .index = i + 1, .value = .{ .pokedex_entry = dex_entry.value() } } });
    }

    for (game.evolutions) |evos, index| {
        const i = @intCast(u16, index);
        for (evos) |evo, jndex| {
            if (evo.method == .unused)
                continue;
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game{
                .pokemons = .{
                    .index = i,
                    .value = .{
                        .evos = .{
                            .index = j,
                            .value = .{
                                .method = switch (evo.method) {
                                    .unused => .unused,
                                    .friend_ship => .friend_ship,
                                    .friend_ship_during_day => .friend_ship_during_day,
                                    .friend_ship_during_night => .friend_ship_during_night,
                                    .level_up => .level_up,
                                    .trade => .trade,
                                    .trade_holding_item => .trade_holding_item,
                                    .use_item => .use_item,
                                    .attack_gth_defense => .attack_gth_defense,
                                    .attack_eql_defense => .attack_eql_defense,
                                    .attack_lth_defense => .attack_lth_defense,
                                    .personality_value1 => .personality_value1,
                                    .personality_value2 => .personality_value2,
                                    .level_up_may_spawn_pokemon => .level_up_may_spawn_pokemon,
                                    .level_up_spawn_if_cond => .level_up_spawn_if_cond,
                                    .beauty => .beauty,
                                    .use_item_on_male => .use_item_on_male,
                                    .use_item_on_female => .use_item_on_female,
                                    .level_up_holding_item_during_daytime => .level_up_holding_item_during_daytime,
                                    .level_up_holding_item_during_the_night => .level_up_holding_item_during_the_night,
                                    .level_up_knowning_move => .level_up_knowning_move,
                                    .level_up_with_other_pokemon_in_party => .level_up_with_other_pokemon_in_party,
                                    .level_up_male => .level_up_male,
                                    .level_up_female => .level_up_female,
                                    .level_up_in_special_magnetic_field => .level_up_in_special_magnetic_field,
                                    .level_up_near_moss_rock => .level_up_near_moss_rock,
                                    .level_up_near_ice_rock => .level_up_near_ice_rock,
                                    _ => unreachable,
                                },
                            },
                        },
                    },
                },
            });
            try ston.serialize(writer, Game.pokemon(i, .{ .evos = .{ .index = j, .value = .{ .param = evo.param.value() } } }));
            try ston.serialize(writer, Game.pokemon(i, .{ .evos = .{ .index = j, .value = .{ .target = evo.target.value() } } }));
        }
    }

    for (game.level_up_learnset_pointers) |lvl_up_learnset, index| {
        const learnset = try lvl_up_learnset.toSliceEnd(game.data);
        const i = @intCast(u16, index);
        for (learnset) |l, jndex| {
            if (std.meta.eql(l, gen3.LevelUpMove.term))
                break;
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .moves = .{ .index = j, .value = .{ .id = l.id } } }));
            try ston.serialize(writer, Game.pokemon(i, .{ .moves = .{ .index = j, .value = .{ .level = l.level } } }));
        }
    }

    for (game.machine_learnsets) |machine_learnset, index| {
        const i = @intCast(u16, index);
        var j: u8 = 0;
        while (j < game.tms.len) : (j += 1)
            try ston.serialize(writer, Game.pokemon(i, .{ .tms = .{ .index = j, .value = bit.isSet(u64, machine_learnset.value(), @intCast(u6, j)) } }));
        while (j < game.tms.len + game.hms.len) : (j += 1)
            try ston.serialize(writer, Game.pokemon(i, .{ .hms = .{ .index = @intCast(u8, j - game.tms.len), .value = bit.isSet(u64, machine_learnset.value(), @intCast(u6, j)) } }));
    }

    for (game.pokemon_names) |name, index| {
        const i = @intCast(u16, index);
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &name, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, Game.pokemon(i, .{ .name = decoded_name }));
    }

    for (game.ability_names) |name, index| {
        const i = @intCast(u16, index);
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &name, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, Game.ability(i, .{ .name = decoded_name }));
    }

    for (game.move_names) |name, index| {
        const i = @intCast(u16, index);
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &name, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, Game.move(i, .{ .name = decoded_name }));
    }

    for (game.type_names) |name, index| {
        const i = @intCast(u8, index);
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, &name, fbs.writer());
        const decoded_name = fbs.getWritten();

        try ston.serialize(writer, Game.typ(i, .{ .name = decoded_name }));
    }

    for (game.tms) |tm, index| {
        const i = @intCast(u8, index);
        try ston.serialize(writer, Game.tm(i, tm.value()));
    }
    for (game.hms) |hm, index| {
        const i = @intCast(u8, index);
        try ston.serialize(writer, Game.hm(i, hm.value()));
    }

    for (game.items) |item, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.item(i, .{ .price = item.price.value() }));
        try ston.serialize(writer, Game.item(i, .{ .battle_effect = item.battle_effect }));

        const pocket = switch (game.version) {
            .ruby, .sapphire, .emerald => try ston.serialize(writer, Game{
                .items = .{
                    .index = i,
                    .value = .{
                        .pocket = switch (item.pocket.rse) {
                            .none => .none,
                            .items => .items,
                            .key_items => .key_items,
                            .poke_balls => .poke_balls,
                            .tms_hms => .tms_hms,
                            .berries => .berries,
                        },
                    },
                },
            }),
            .fire_red, .leaf_green => try ston.serialize(writer, Game{
                .items = .{
                    .index = i,
                    .value = .{
                        .pocket = switch (item.pocket.frlg) {
                            .none => .none,
                            .items => .items,
                            .key_items => .key_items,
                            .poke_balls => .poke_balls,
                            .tms_hms => .tms_hms,
                            .berries => .berries,
                        },
                    },
                },
            }),
            else => unreachable,
        };

        {
            var fbs = io.fixedBufferStream(&buf);
            try gen3.encodings.decode(.en_us, &item.name, fbs.writer());
            const name = fbs.getWritten();
            try ston.serialize(writer, Game.item(i, .{ .name = name }));
        }

        if (item.description.toSliceZ(game.data)) |description| {
            var fbs = io.fixedBufferStream(&buf);
            try gen3.encodings.decode(.en_us, description, fbs.writer());
            const decoded_description = fbs.getWritten();
            try ston.serialize(writer, Game.item(i, .{ .description = decoded_description }));
        } else |_| {}
    }

    switch (game.version) {
        .emerald => for (game.pokedex.emerald) |entry, index| {
            const i = @intCast(u16, index);
            try ston.serialize(writer, Game{ .pokedex = .{ .index = i, .value = .{ .height = entry.height.value() } } });
            try ston.serialize(writer, Game{ .pokedex = .{ .index = i, .value = .{ .weight = entry.weight.value() } } });
        },
        .ruby,
        .sapphire,
        .fire_red,
        .leaf_green,
        => for (game.pokedex.rsfrlg) |entry, index| {
            const i = @intCast(u16, index);
            try ston.serialize(writer, Game{ .pokedex = .{ .index = i, .value = .{ .height = entry.height.value() } } });
            try ston.serialize(writer, Game{ .pokedex = .{ .index = i, .value = .{ .weight = entry.weight.value() } } });
        },
        else => unreachable,
    }

    for (game.map_headers) |header, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.map(i, .{ .music = header.music.value() }));
        try ston.serialize(writer, Game.map(i, .{ .cave = header.cave }));
        try ston.serialize(writer, Game.map(i, .{ .weather = header.weather }));
        try ston.serialize(writer, Game.map(i, .{ .type = header.map_type }));
        try ston.serialize(writer, Game.map(i, .{ .escape_rope = header.escape_rope }));
        try ston.serialize(writer, Game.map(i, .{ .battle_scene = header.map_battle_scene }));
        try ston.serialize(writer, Game.map(i, .{ .allow_cycling = header.flags.allow_cycling }));
        try ston.serialize(writer, Game.map(i, .{ .allow_escaping = header.flags.allow_escaping }));
        try ston.serialize(writer, Game.map(i, .{ .allow_running = header.flags.allow_running }));
        try ston.serialize(writer, Game.map(i, .{ .show_map_name = header.flags.show_map_name }));
    }

    for (game.wild_pokemon_headers) |header, index| {
        const i = @intCast(u16, index);
        if (header.land.toPtr(game.data)) |land| {
            const wilds = try land.wild_pokemons.toPtr(game.data);
            try outputGen3Area(writer, i, "land", land.encounter_rate, wilds);
        } else |_| {}
        if (header.surf.toPtr(game.data)) |surf| {
            const wilds = try surf.wild_pokemons.toPtr(game.data);
            try outputGen3Area(writer, i, "surf", surf.encounter_rate, wilds);
        } else |_| {}
        if (header.rock_smash.toPtr(game.data)) |rock| {
            const wilds = try rock.wild_pokemons.toPtr(game.data);
            try outputGen3Area(writer, i, "rock_smash", rock.encounter_rate, wilds);
        } else |_| {}
        if (header.fishing.toPtr(game.data)) |fish| {
            const wilds = try fish.wild_pokemons.toPtr(game.data);
            try outputGen3Area(writer, i, "fishing", fish.encounter_rate, wilds);
        } else |_| {}
    }

    for (game.static_pokemons) |static_mon, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.static_pokemon(i, .{ .species = static_mon.species.value() }));
        try ston.serialize(writer, Game.static_pokemon(i, .{ .level = static_mon.level.* }));
    }

    for (game.given_pokemons) |given_mon, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.given_pokemon(i, .{ .species = given_mon.species.value() }));
        try ston.serialize(writer, Game.given_pokemon(i, .{ .level = given_mon.level.* }));
    }

    for (game.pokeball_items) |given_item, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.pokeball_item(i, .{ .item = given_item.item.value() }));
        try ston.serialize(writer, Game.pokeball_item(i, .{ .amount = given_item.amount.value() }));
    }

    for (game.text) |text_ptr, index| {
        const i = @intCast(u16, index);
        const text = try text_ptr.toSliceZ(game.data);
        var fbs = io.fixedBufferStream(&buf);
        try gen3.encodings.decode(.en_us, text, fbs.writer());
        const decoded_text = fbs.getWritten();

        try ston.serialize(writer, Game{ .text = .{ .index = i, .value = decoded_text } });
    }
}

fn outputGen3Area(writer: anytype, i: u16, comptime name: []const u8, rate: u8, wilds: []const gen3.WildPokemon) !void {
    try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, name, .{ .encounter_rate = rate })));
    for (wilds) |pokemon, jndex| {
        const j = @intCast(u8, jndex);
        try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, name, .{ .pokemons = .{ .index = j, .value = .{ .min_level = pokemon.min_level } } })));
        try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, name, .{ .pokemons = .{ .index = j, .value = .{ .max_level = pokemon.max_level } } })));
        try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, name, .{ .pokemons = .{ .index = j, .value = .{ .species = pokemon.species.value() } } })));
    }
}

fn outputGen4Data(nds_rom: nds.Rom, game: gen4.Game, writer: anytype) !void {
    const header = nds_rom.header();
    try ston.serialize(writer, Game{ .version = game.info.version });
    try ston.serialize(writer, Game{ .game_title = header.game_title.span() });
    try ston.serialize(writer, Game{ .gamecode = &header.gamecode });
    try ston.serialize(writer, Game{ .instant_text = false });

    for (game.ptrs.starters) |starter, index| {
        const i = @intCast(u8, index);
        try ston.serialize(writer, Game.starter(i, starter.value()));
    }

    for (game.ptrs.trainers) |trainer, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.trainer(i, .{ .party_size = trainer.party_size }));
        try ston.serialize(writer, Game.trainer(i, .{ .party_type = trainer.party_type }));
        try ston.serialize(writer, Game.trainer(i, .{ .class = trainer.class }));

        for (trainer.items) |item, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.trainer(i, .{ .items = .{ .index = j, .value = item.value() } }));
        }

        const parties = game.owned.trainer_parties;
        if (parties.len <= i)
            continue;

        for (parties[i][0..trainer.party_size]) |member, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .ability = member.base.gender_ability.ability } } }));
            try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .level = @intCast(u8, member.base.level.value()) } } }));
            try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .species = member.base.species.value() } } }));
            try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .item = member.item.value() } } }));
            for (member.moves) |move, kndex| {
                const k = @intCast(u8, kndex);
                try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .moves = .{ .index = k, .value = move.value() } } } }));
            }
        }
    }

    for (game.ptrs.moves) |move, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.move(i, .{ .category = move.category }));
        try ston.serialize(writer, Game.move(i, .{ .power = move.power }));
        try ston.serialize(writer, Game.move(i, .{ .type = move.type }));
        try ston.serialize(writer, Game.move(i, .{ .accuracy = move.accuracy }));
        try ston.serialize(writer, Game.move(i, .{ .pp = move.pp }));
    }

    for (game.ptrs.pokemons) |pokemon, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .hp = pokemon.stats.hp } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .attack = pokemon.stats.attack } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .defense = pokemon.stats.defense } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .speed = pokemon.stats.speed } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .sp_attack = pokemon.stats.sp_attack } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .sp_defense = pokemon.stats.sp_defense } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .catch_rate = pokemon.catch_rate }));
        try ston.serialize(writer, Game.pokemon(i, .{ .base_exp_yield = pokemon.base_exp_yield }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .hp = pokemon.ev_yield.hp } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .attack = pokemon.ev_yield.attack } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .defense = pokemon.ev_yield.defense } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .speed = pokemon.ev_yield.speed } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .sp_attack = pokemon.ev_yield.sp_attack } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .ev_yield = .{ .sp_defense = pokemon.ev_yield.sp_defense } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .gender_ratio = pokemon.gender_ratio }));
        try ston.serialize(writer, Game.pokemon(i, .{ .egg_cycles = pokemon.egg_cycles }));
        try ston.serialize(writer, Game.pokemon(i, .{ .base_friendship = pokemon.base_friendship }));
        try ston.serialize(writer, Game.pokemon(i, .{ .growth_rate = pokemon.growth_rate }));
        try ston.serialize(writer, Game.pokemon(i, .{ .color = pokemon.color.color }));

        for (pokemon.types) |t, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .types = .{ .index = j, .value = t } }));
        }
        for (pokemon.items) |item, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .items = .{ .index = j, .value = item.value() } }));
        }
        for (pokemon.egg_groups) |group, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .egg_groups = .{ .index = j, .value = group } }));
        }
        for (pokemon.abilities) |ability, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .abilities = .{ .index = j, .value = ability } }));
        }

        const machine_learnset = pokemon.machine_learnset;
        var j: u8 = 0;
        while (j < game.ptrs.tms.len) : (j += 1)
            try ston.serialize(writer, Game.pokemon(i, .{ .tms = .{ .index = j, .value = bit.isSet(u128, machine_learnset.value(), @intCast(u7, j)) } }));
        while (j < game.ptrs.tms.len + game.ptrs.hms.len) : (j += 1)
            try ston.serialize(writer, Game.pokemon(i, .{ .hms = .{ .index = @intCast(u8, j - game.ptrs.tms.len), .value = bit.isSet(u128, machine_learnset.value(), @intCast(u7, j)) } }));
    }

    for (game.ptrs.species_to_national_dex) |dex_entry, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game{ .pokemons = .{ .index = i + 1, .value = .{ .pokedex_entry = dex_entry.value() } } });
    }

    for (game.ptrs.evolutions) |evos, index| {
        const i = @intCast(u16, index);
        for (evos.items) |evo, jndex| {
            if (evo.method == .unused)
                continue;
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game{
                .pokemons = .{
                    .index = i,
                    .value = .{
                        .evos = .{
                            .index = j,
                            .value = .{
                                .method = switch (evo.method) {
                                    .unused => .unused,
                                    .friend_ship => .friend_ship,
                                    .friend_ship_during_day => .friend_ship_during_day,
                                    .friend_ship_during_night => .friend_ship_during_night,
                                    .level_up => .level_up,
                                    .trade => .trade,
                                    .trade_holding_item => .trade_holding_item,
                                    .use_item => .use_item,
                                    .attack_gth_defense => .attack_gth_defense,
                                    .attack_eql_defense => .attack_eql_defense,
                                    .attack_lth_defense => .attack_lth_defense,
                                    .personality_value1 => .personality_value1,
                                    .personality_value2 => .personality_value2,
                                    .level_up_may_spawn_pokemon => .level_up_may_spawn_pokemon,
                                    .level_up_spawn_if_cond => .level_up_spawn_if_cond,
                                    .beauty => .beauty,
                                    .use_item_on_male => .use_item_on_male,
                                    .use_item_on_female => .use_item_on_female,
                                    .level_up_holding_item_during_daytime => .level_up_holding_item_during_daytime,
                                    .level_up_holding_item_during_the_night => .level_up_holding_item_during_the_night,
                                    .level_up_knowning_move => .level_up_knowning_move,
                                    .level_up_with_other_pokemon_in_party => .level_up_with_other_pokemon_in_party,
                                    .level_up_male => .level_up_male,
                                    .level_up_female => .level_up_female,
                                    .level_up_in_special_magnetic_field => .level_up_in_special_magnetic_field,
                                    .level_up_near_moss_rock => .level_up_near_moss_rock,
                                    .level_up_near_ice_rock => .level_up_near_ice_rock,
                                    _ => unreachable,
                                },
                            },
                        },
                    },
                },
            });
            try ston.serialize(writer, Game.pokemon(i, .{ .evos = .{ .index = j, .value = .{ .param = evo.param.value() } } }));
            try ston.serialize(writer, Game.pokemon(i, .{ .evos = .{ .index = j, .value = .{ .target = evo.target.value() } } }));
        }
    }

    for (game.ptrs.level_up_moves.fat) |_, index| {
        const i = @intCast(u16, index);
        const bytes = game.ptrs.level_up_moves.fileData(.{ .i = i });
        const level_up_moves = mem.bytesAsSlice(gen4.LevelUpMove, bytes);
        for (level_up_moves) |move, jndex| {
            if (std.meta.eql(move, gen4.LevelUpMove.term))
                break;
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .moves = .{ .index = j, .value = .{ .id = move.id } } }));
            try ston.serialize(writer, Game.pokemon(i, .{ .moves = .{ .index = j, .value = .{ .level = move.level } } }));
        }
    }

    for (game.ptrs.pokedex_heights) |height, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game{ .pokedex = .{ .index = i, .value = .{ .height = height.value() } } });
    }
    for (game.ptrs.pokedex_weights) |weight, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game{ .pokedex = .{ .index = i, .value = .{ .weight = weight.value() } } });
    }
    for (game.ptrs.tms) |tm, index| {
        const i = @intCast(u8, index);
        try ston.serialize(writer, Game.tm(i, tm.value()));
    }
    for (game.ptrs.hms) |hm, index| {
        const i = @intCast(u8, index);
        try ston.serialize(writer, Game.hm(i, hm.value()));
    }

    for (game.ptrs.items) |item, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.item(i, .{ .price = item.price.value() }));
        try ston.serialize(writer, Game.item(i, .{ .battle_effect = item.battle_effect }));
        try ston.serialize(writer, Game{
            .items = .{
                .index = i,
                .value = .{
                    .pocket = switch (item.pocket) {
                        .items => .items,
                        .tms_hms => .tms_hms,
                        .berries => .berries,
                        .key_items => .key_items,
                        .balls => .poke_balls,
                        _ => unreachable,
                    },
                },
            },
        });
    }

    switch (game.info.version) {
        .diamond,
        .pearl,
        .platinum,
        => for (game.ptrs.wild_pokemons.dppt) |wild_mons, index| {
            const i = @intCast(u16, index);
            try ston.serialize(writer, Game.wild_pokemon(i, .{ .grass = .{ .encounter_rate = wild_mons.grass_rate.value() } }));
            for (wild_mons.grass) |grass, jndex| {
                const j = @intCast(u8, jndex);
                try ston.serialize(writer, Game.wild_pokemon(i, .{ .grass = .{ .pokemons = .{ .index = j, .value = .{ .min_level = grass.level } } } }));
                try ston.serialize(writer, Game.wild_pokemon(i, .{ .grass = .{ .pokemons = .{ .index = j, .value = .{ .max_level = grass.level } } } }));
                try ston.serialize(writer, Game.wild_pokemon(i, .{ .grass = .{ .pokemons = .{ .index = j, .value = .{ .species = grass.species.value() } } } }));
            }

            // TODO: Get rid of inline for in favor of a function to call
            inline for ([_][]const u8{
                "swarm_replace",
                "day_replace",
                "night_replace",
                "radar_replace",
                "unknown_replace",
                "gba_replace",
            }) |area_name| {
                for (@field(wild_mons, area_name)) |replacement, jndex| {
                    const j = @intCast(u8, jndex);
                    try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = j, .value = .{ .species = replacement.species.value() } } })));
                }
            }

            // TODO: Get rid of inline for in favor of a function to call
            inline for ([_][]const u8{
                "surf",
                "sea_unknown",
                "old_rod",
                "good_rod",
                "super_rod",
            }) |area_name| {
                try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .encounter_rate = @field(wild_mons, area_name).rate.value() })));
                for (@field(wild_mons, area_name).mons) |sea, jndex| {
                    const j = @intCast(u8, jndex);
                    try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = j, .value = .{ .min_level = sea.min_level } } })));
                    try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = j, .value = .{ .max_level = sea.max_level } } })));
                    try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = j, .value = .{ .species = sea.species.value() } } })));
                }
            }
        },

        .heart_gold,
        .soul_silver,
        => for (game.ptrs.wild_pokemons.hgss) |wild_mons, index| {
            const i = @intCast(u16, index);
            // TODO: Get rid of inline for in favor of a function to call
            inline for ([_][]const u8{
                "grass_morning",
                "grass_day",
                "grass_night",
            }) |area_name| {
                try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .encounter_rate = wild_mons.grass_rate })));
                for (@field(wild_mons, area_name)) |species, jndex| {
                    const j = @intCast(u8, jndex);
                    try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = j, .value = .{ .min_level = wild_mons.grass_levels[j] } } })));
                    try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = j, .value = .{ .max_level = wild_mons.grass_levels[j] } } })));
                    try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = j, .value = .{ .species = species.value() } } })));
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
                try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .encounter_rate = wild_mons.sea_rates[j] })));
                for (@field(wild_mons, area_name)) |sea, kndex| {
                    const k = @intCast(u8, kndex);
                    try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = k, .value = .{ .min_level = sea.min_level } } })));
                    try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = k, .value = .{ .max_level = sea.max_level } } })));
                    try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = k, .value = .{ .species = sea.species.value() } } })));
                }
            }

            // TODO: radio, swarm
        },

        else => unreachable,
    }

    for (game.ptrs.static_pokemons) |static_mon, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.static_pokemon(i, .{ .species = static_mon.species.value() }));
        try ston.serialize(writer, Game.static_pokemon(i, .{ .level = @intCast(u8, static_mon.level.value()) }));
    }

    for (game.ptrs.given_pokemons) |given_mon, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.given_pokemon(i, .{ .species = given_mon.species.value() }));
        try ston.serialize(writer, Game.given_pokemon(i, .{ .level = @intCast(u8, given_mon.level.value()) }));
    }

    for (game.ptrs.pokeball_items) |given_item, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.pokeball_item(i, .{ .item = given_item.item.value() }));
        try ston.serialize(writer, Game.pokeball_item(i, .{ .amount = given_item.amount.value() }));
    }

    try outputGen4StringTable(writer, "pokemons", u16, 0, format.Pokemon, "name", game.owned.strings.pokemon_names);
    try outputGen4StringTable(writer, "moves", u16, 0, format.Move, "name", game.owned.strings.move_names);
    try outputGen4StringTable(writer, "moves", u16, 0, format.Move, "description", game.owned.strings.move_descriptions);
    try outputGen4StringTable(writer, "abilities", u16, 0, format.Ability, "name", game.owned.strings.ability_names);
    try outputGen4StringTable(writer, "items", u16, 0, format.Item, "name", game.owned.strings.item_names);
    try outputGen4StringTable(writer, "items", u16, 0, format.Item, "description", game.owned.strings.item_descriptions);
    try outputGen4StringTable(writer, "types", u8, 0, format.Type, "name", game.owned.strings.type_names);
}

fn outputGen4StringTable(
    writer: anytype,
    comptime array_name: []const u8,
    comptime Index: type,
    start: Index,
    comptime T: type,
    comptime field_name: []const u8,
    table: gen4.StringTable,
) !void {
    var i: Index = 0;
    while (i < table.number_of_strings) : (i += 1)
        try outputString(writer, array_name, Index, i + start, T, field_name, table.getSpan(i + start));
}

fn outputGen5Data(nds_rom: nds.Rom, game: gen5.Game, writer: anytype) !void {
    const header = nds_rom.header();
    try ston.serialize(writer, Game{ .version = game.info.version });
    try ston.serialize(writer, Game{ .game_title = header.game_title.span() });
    try ston.serialize(writer, Game{ .gamecode = &header.gamecode });
    try ston.serialize(writer, Game{ .instant_text = false });

    for (game.ptrs.starters) |starter_ptrs, index| {
        const i = @intCast(u8, index);
        const first = starter_ptrs[0];
        for (starter_ptrs[1..]) |starter| {
            if (first.value() != starter.value())
                debug.warn("warning: all starter positions are not the same. {} {}\n", .{ first.value(), starter.value() });
        }

        try ston.serialize(writer, Game.starter(i, first.value()));
    }

    for (game.ptrs.trainers) |trainer, index| {
        const i = @intCast(u16, index + 1);
        try ston.serialize(writer, Game.trainer(i, .{ .party_size = trainer.party_size }));
        try ston.serialize(writer, Game.trainer(i, .{ .party_type = trainer.party_type }));
        try ston.serialize(writer, Game.trainer(i, .{ .class = trainer.class }));

        for (trainer.items) |item, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.trainer(i, .{ .items = .{ .index = j, .value = item.value() } }));
        }

        const parties = game.owned.trainer_parties;
        if (parties.len <= i)
            continue;

        for (parties[i][0..trainer.party_size]) |member, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .ability = member.base.gender_ability.ability } } }));
            try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .level = member.base.level } } }));
            try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .species = member.base.species.value() } } }));
            try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .item = member.item.value() } } }));
            for (member.moves) |move, kndex| {
                const k = @intCast(u8, kndex);
                try ston.serialize(writer, Game.trainer(i, .{ .party = .{ .index = j, .value = .{ .moves = .{ .index = k, .value = move.value() } } } }));
            }
        }
    }

    for (game.ptrs.moves) |move, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.move(i, .{ .type = move.type }));
        try ston.serialize(writer, Game.move(i, .{ .category = move.category }));
        try ston.serialize(writer, Game.move(i, .{ .power = move.power }));
        try ston.serialize(writer, Game.move(i, .{ .accuracy = move.accuracy }));
        try ston.serialize(writer, Game.move(i, .{ .pp = move.pp }));
        try ston.serialize(writer, Game.move(i, .{ .priority = move.priority }));
        try ston.serialize(writer, Game.move(i, .{ .target = move.target }));
    }

    const number_of_pokemons = 649;
    for (game.ptrs.pokemons.fat) |_, index| {
        const i = @intCast(u16, index);
        const pokemon = try game.ptrs.pokemons.fileAs(.{ .i = i }, gen5.BasePokemon);
        try ston.serialize(writer, Game.pokemon(i, .{ .pokedex_entry = i }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .hp = pokemon.stats.hp } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .attack = pokemon.stats.attack } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .defense = pokemon.stats.defense } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .speed = pokemon.stats.speed } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .sp_attack = pokemon.stats.sp_attack } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .stats = .{ .sp_defense = pokemon.stats.sp_defense } }));
        try ston.serialize(writer, Game.pokemon(i, .{ .base_exp_yield = pokemon.base_exp_yield.value() }));
        try ston.serialize(writer, Game.pokemon(i, .{ .catch_rate = pokemon.catch_rate }));
        try ston.serialize(writer, Game.pokemon(i, .{ .gender_ratio = pokemon.gender_ratio }));
        try ston.serialize(writer, Game.pokemon(i, .{ .egg_cycles = pokemon.egg_cycles }));
        try ston.serialize(writer, Game.pokemon(i, .{ .base_friendship = pokemon.base_friendship }));
        try ston.serialize(writer, Game.pokemon(i, .{ .growth_rate = pokemon.growth_rate }));

        for (pokemon.types) |t, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .types = .{ .index = j, .value = t } }));
        }
        for (pokemon.items) |item, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .items = .{ .index = j, .value = item.value() } }));
        }
        for (pokemon.abilities) |ability, jndex| {
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .abilities = .{ .index = j, .value = ability } }));
        }

        // HACK: For some reason, a release build segfaults here for Pokémons
        //       with id above 'number_of_pokemons'. You would think this is
        //       because of an index out of bounds during @tagName, but
        //       common.EggGroup is a u4 enum and has a tag for all possible
        //       values, so it really should not.
        if (i < number_of_pokemons) {
            for (pokemon.egg_groups) |group, jndex| {
                const j = @intCast(u8, jndex);
                try ston.serialize(writer, Game.pokemon(i, .{ .egg_groups = .{ .index = j, .value = group } }));
            }
        }

        const machine_learnset = pokemon.machine_learnset;
        var j: u8 = 0;
        while (j < game.ptrs.tms1.len + game.ptrs.tms2.len) : (j += 1)
            try ston.serialize(writer, Game.pokemon(i, .{ .tms = .{ .index = j, .value = bit.isSet(u128, machine_learnset.value(), @intCast(u7, j)) } }));
        while (j < game.ptrs.tms1.len + game.ptrs.tms2.len + game.ptrs.hms.len) : (j += 1)
            try ston.serialize(writer, Game.pokemon(i, .{ .hms = .{ .index = @intCast(u8, j - (game.ptrs.tms1.len + game.ptrs.tms2.len)), .value = bit.isSet(u128, machine_learnset.value(), @intCast(u7, j)) } }));
    }

    for (game.ptrs.evolutions) |evos, index| {
        const i = @intCast(u16, index);
        for (evos.items) |evo, jndex| {
            if (evo.method == .unused)
                continue;
            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game{
                .pokemons = .{
                    .index = i,
                    .value = .{
                        .evos = .{
                            .index = j,
                            .value = .{
                                .method = switch (evo.method) {
                                    .unused => .unused,
                                    .friend_ship => .friend_ship,
                                    .level_up => .level_up,
                                    .trade => .trade,
                                    .trade_holding_item => .trade_holding_item,
                                    .trade_with_pokemon => .trade_with_pokemon,
                                    .use_item => .use_item,
                                    .attack_gth_defense => .attack_gth_defense,
                                    .attack_eql_defense => .attack_eql_defense,
                                    .attack_lth_defense => .attack_lth_defense,
                                    .personality_value1 => .personality_value1,
                                    .personality_value2 => .personality_value2,
                                    .level_up_may_spawn_pokemon => .level_up_may_spawn_pokemon,
                                    .level_up_spawn_if_cond => .level_up_spawn_if_cond,
                                    .beauty => .beauty,
                                    .use_item_on_male => .use_item_on_male,
                                    .use_item_on_female => .use_item_on_female,
                                    .level_up_holding_item_during_daytime => .level_up_holding_item_during_daytime,
                                    .level_up_holding_item_during_the_night => .level_up_holding_item_during_the_night,
                                    .level_up_knowning_move => .level_up_knowning_move,
                                    .level_up_with_other_pokemon_in_party => .level_up_with_other_pokemon_in_party,
                                    .level_up_male => .level_up_male,
                                    .level_up_female => .level_up_female,
                                    .level_up_in_special_magnetic_field => .level_up_in_special_magnetic_field,
                                    .level_up_near_moss_rock => .level_up_near_moss_rock,
                                    .level_up_near_ice_rock => .level_up_near_ice_rock,
                                    .unknown_0x02 => .unknown_0x02,
                                    .unknown_0x03 => .unknown_0x03,
                                    _ => unreachable,
                                },
                            },
                        },
                    },
                },
            });
            try ston.serialize(writer, Game.pokemon(i, .{ .evos = .{ .index = j, .value = .{ .param = evo.param.value() } } }));
            try ston.serialize(writer, Game.pokemon(i, .{ .evos = .{ .index = j, .value = .{ .target = evo.target.value() } } }));
        }
    }

    for (game.ptrs.level_up_moves.fat) |_, index| {
        const i = @intCast(u16, index);
        const bytes = game.ptrs.level_up_moves.fileData(.{ .i = i });
        const level_up_moves = mem.bytesAsSlice(gen5.LevelUpMove, bytes);
        for (level_up_moves) |move, jndex| {
            if (std.meta.eql(move, gen5.LevelUpMove.term))
                break;

            const j = @intCast(u8, jndex);
            try ston.serialize(writer, Game.pokemon(i, .{ .moves = .{ .index = j, .value = .{ .id = move.id.value() } } }));
            try ston.serialize(writer, Game.pokemon(i, .{ .moves = .{ .index = j, .value = .{ .level = @intCast(u8, move.level.value()) } } }));
        }
    }

    for (game.ptrs.tms1) |tm, index| {
        const i = @intCast(u8, index);
        try ston.serialize(writer, Game.tm(i, tm.value()));
    }
    for (game.ptrs.tms2) |tm, index| {
        const i = @intCast(u8, index);
        try ston.serialize(writer, Game{ .tms = .{ .index = @intCast(u8, i + game.ptrs.tms1.len), .value = tm.value() } });
    }
    for (game.ptrs.hms) |hm, index| {
        const i = @intCast(u8, index);
        try ston.serialize(writer, Game.hm(i, hm.value()));
    }

    for (game.ptrs.items) |item, index| {
        // Price in gen5 is actually price * 10. I imagine they where trying to avoid
        // having price be more than a u16
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.item(i, .{ .price = @as(u32, item.price.value()) * 10 }));
        try ston.serialize(writer, Game.item(i, .{ .battle_effect = item.battle_effect }));
        try ston.serialize(writer, Game{
            .items = .{
                .index = i,
                .value = .{
                    .pocket = switch (item.pocket) {
                        .items => .items,
                        .tms_hms => .tms_hms,
                        .key_items => .key_items,
                        .balls => .poke_balls,
                        _ => unreachable,
                    },
                },
            },
        });
    }

    for (game.ptrs.map_headers) |map_header, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.map(i, .{ .music = map_header.music.value() }));
        try ston.serialize(writer, Game.map(i, .{ .battle_scene = map_header.battle_scene }));
    }

    for (game.ptrs.wild_pokemons.fat) |_, index| {
        const i = @intCast(u16, index);
        const wild_mons = try game.ptrs.wild_pokemons.fileAs(.{ .i = i }, gen5.WildPokemons);
        // TODO: Get rid of inline for in favor of a function to call
        inline for ([_][]const u8{
            "grass",
            "dark_grass",
            "rustling_grass",
            "surf",
            "ripple_surf",
            "fishing",
            "ripple_fishing",
        }) |area_name, j| {
            try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .encounter_rate = wild_mons.rates[j] })));
            const area = @field(wild_mons, area_name);
            for (area) |wild, kndex| {
                const k = @intCast(u8, kndex);
                try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = k, .value = .{ .species = wild.species.species() } } })));
                try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = k, .value = .{ .min_level = wild.min_level } } })));
                try ston.serialize(writer, Game.wild_pokemon(i, @unionInit(format.WildPokemons, area_name, .{ .pokemons = .{ .index = k, .value = .{ .max_level = wild.max_level } } })));
            }
        }
    }

    for (game.ptrs.static_pokemons) |static_mon, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.static_pokemon(i, .{ .species = static_mon.species.value() }));
        try ston.serialize(writer, Game.static_pokemon(i, .{ .level = static_mon.level.value() }));
    }

    for (game.ptrs.given_pokemons) |given_mon, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.given_pokemon(i, .{ .species = given_mon.species.value() }));
        try ston.serialize(writer, Game.given_pokemon(i, .{ .level = given_mon.level.value() }));
    }

    for (game.ptrs.pokeball_items) |given_item, index| {
        const i = @intCast(u16, index);
        try ston.serialize(writer, Game.pokeball_item(i, .{ .item = given_item.item.value() }));
        try ston.serialize(writer, Game.pokeball_item(i, .{ .amount = given_item.amount.value() }));
    }

    if (game.ptrs.hidden_hollows) |hidden_hollows| {
        for (hidden_hollows) |hollow, index| {
            const i = @intCast(u16, index);
            for (hollow.pokemons) |version, jndex| {
                const j = @intCast(u8, jndex);
                for (version) |group, kndex| {
                    const k = @intCast(u8, kndex);
                    for (group.species) |_, gndex| {
                        const g = @intCast(u8, gndex);
                        try ston.serialize(writer, Game.hidden_hollow(i, .{ .versions = .{ .index = j, .value = .{ .groups = .{ .index = k, .value = .{ .pokemons = .{ .index = g, .value = .{ .species = group.species[g].value() } } } } } } }));
                    }
                }
            }
            for (hollow.items) |item, jndex| {
                const j = @intCast(u8, jndex);
                try ston.serialize(writer, Game.hidden_hollow(i, .{ .items = .{ .index = j, .value = item.value() } }));
            }
        }
    }

    try outputGen5StringTable(writer, "pokemons", u16, 0, format.Pokemon, "name", game.owned.strings.pokemon_names);
    try outputGen5StringTable(writer, "pokedex", u16, 0, format.Pokedex, "category", game.owned.strings.pokedex_category_names);
    try outputGen5StringTable(writer, "moves", u16, 0, format.Move, "name", game.owned.strings.move_names);
    try outputGen5StringTable(writer, "moves", u16, 0, format.Move, "description", game.owned.strings.move_descriptions);
    try outputGen5StringTable(writer, "abilities", u16, 0, format.Ability, "name", game.owned.strings.ability_names);
    try outputGen5StringTable(writer, "items", u16, 0, format.Item, "name", game.owned.strings.item_names);
    try outputGen5StringTable(writer, "items", u16, 0, format.Item, "description", game.owned.strings.item_descriptions);
    try outputGen5StringTable(writer, "types", u8, 0, format.Type, "name", game.owned.strings.type_names);
    try outputGen5StringTable(writer, "trainers", u16, 1, format.Trainer, "name", game.owned.strings.trainer_names);
}

fn outputGen5StringTable(
    writer: anytype,
    comptime array_name: []const u8,
    comptime Index: type,
    start: Index,
    comptime T: type,
    comptime field_name: []const u8,
    table: gen5.StringTable,
) !void {
    for (table.keys[start..]) |_, i|
        try outputString(writer, array_name, Index, @intCast(Index, i + start), T, field_name, table.getSpan(i + start));
}

fn outputString(
    writer: anytype,
    comptime array_name: []const u8,
    comptime Index: type,
    i: Index,
    comptime T: type,
    comptime field_name: []const u8,
    string: []const u8,
) !void {
    try ston.serialize(writer, @unionInit(Game, array_name, .{ .index = i, .value = @unionInit(T, field_name, string) }));
}

test {
    std.testing.refAllDecls(@This());
}
