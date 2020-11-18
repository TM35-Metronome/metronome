const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const common = @import("common.zig");
const gen3 = @import("gen3.zig");
const gen4 = @import("gen4.zig");
const gen5 = @import("gen5.zig");
const rom = @import("rom.zig");

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const unicode = std.unicode;

const gba = rom.gba;
const nds = rom.nds;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;

const bit = util.bit;
const escape = util.escape;
const exit = util.exit;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = [_]Param{
    clap.parseParam("-h, --help     Display this help text and exit.    ") catch unreachable,
    clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
    clap.parseParam("<ROM>          The rom to apply the changes to.    ") catch unreachable,
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-load");
    try clap.usage(writer, &params);
    try writer.writeAll("\nLoad data from Pokémon games." ++
        "\n" ++
        "Options:\n");
    try clap.help(writer, &params);
}

pub fn main2(
    allocator: *mem.Allocator,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) u8 {
    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else {
        stdio.err.writeAll("No file provided\n") catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const file = fs.cwd().openFile(file_name, .{}) catch |err| return exit.openErr(stdio.err, file_name, err);
    defer file.close();

    const gen3_error = if (gen3.Game.fromFile(file, allocator)) |*game| {
        defer game.deinit();
        outputGen3Data(game.*, stdio.out) catch |err| return exit.stdoutErr(stdio.err, err);
        return 0;
    } else |err| err;

    file.seekTo(0) catch |err| return exit.readErr(stdio.err, file_name, err);
    if (nds.Rom.fromFile(file, allocator)) |*nds_rom| {
        const gen4_error = if (gen4.Game.fromRom(allocator, nds_rom)) |*game| {
            defer game.deinit();
            outputGen4Data(nds_rom.*, game.*, stdio.out) catch |err| return exit.stdoutErr(stdio.err, err);
            return 0;
        } else |err| err;

        _ = gen5.Game.fromRom(allocator, nds_rom) catch unreachable;
        const gen5_error = if (gen5.Game.fromRom(allocator, nds_rom)) |*game| {
            defer game.deinit();
            outputGen5Data(nds_rom.*, game.*, stdio.out) catch |err| return exit.stdoutErr(stdio.err, err);
            return 0;
        } else |err| err;

        stdio.err.print("Successfully loaded '{}' as a nds rom.\n", .{file_name}) catch {};
        stdio.err.print("Failed to load '{}' as a gen4 game: {}\n", .{ file_name, gen4_error }) catch {};
        stdio.err.print("Failed to load '{}' as a gen5 game: {}\n", .{ file_name, gen5_error }) catch {};
        return 1;
    } else |nds_error| {
        stdio.err.print("Failed to load '{}' as a gen3 game: {}\n", .{ file_name, gen3_error }) catch {};
        stdio.err.print("Failed to load '{}' as a gen4/gen5 game: {}\n", .{ file_name, nds_error }) catch {};
        return 1;
    }
}

fn outputGen3Data(game: gen3.Game, writer: anytype) !void {
    try writer.print(".version={}\n", .{@tagName(game.version)});
    try writer.print(".game_title={}\n", .{game.header.game_title});
    try writer.print(".gamecode={}\n", .{game.header.gamecode});

    for (game.starters) |starter, i| {
        if (starter.value() != game.starters_repeat[i].value())
            debug.warn("warning: repeated starters don't match.\n", .{});

        try writer.print(".starters[{}]={}\n", .{ i, starter });
    }

    for (game.text_delays) |delay, i|
        try writer.print(".text_delays[{}]={}\n", .{ i, delay });

    for (game.trainers) |trainer, i| {
        try writer.print(".trainers[{}].class={}\n", .{ i, trainer.class });
        try writer.print(".trainers[{}].gender={}\n", .{ i, @tagName(trainer.encounter_music.gender) });
        try writer.print(".trainers[{}].encounter_music={}\n", .{ i, trainer.encounter_music.music });
        try writer.print(".trainers[{}].trainer_picture={}\n", .{ i, trainer.trainer_picture });
        try writer.print(".trainers[{}].name=", .{i});
        try gen3.encodings.decode(.en_us, &trainer.name, writer);
        try writer.writeByte('\n');

        for (trainer.items) |item, j| {
            try writer.print(".trainers[{}].items[{}]={}\n", .{ i, j, item });
        }

        try writer.print(".trainers[{}].is_double={}\n", .{ i, trainer.is_double });
        try writer.print(".trainers[{}].ai={}\n", .{ i, trainer.ai });

        try writer.print(".trainers[{}].party_type={}\n", .{ i, @tagName(trainer.party_type) });
        try writer.print(".trainers[{}].party_size={}\n", .{ i, trainer.partyLen() });
        switch (trainer.party_type) {
            .none => for (try trainer.party.none.toSlice(game.data)) |member, j| {
                try writer.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, member.base.iv });
                try writer.print(".trainers[{}].party[{}].level={}\n", .{ i, j, member.base.level });
                try writer.print(".trainers[{}].party[{}].species={}\n", .{ i, j, member.base.species });
            },
            .item => for (try trainer.party.item.toSlice(game.data)) |member, j| {
                try writer.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, member.base.iv });
                try writer.print(".trainers[{}].party[{}].level={}\n", .{ i, j, member.base.level });
                try writer.print(".trainers[{}].party[{}].species={}\n", .{ i, j, member.base.species });
                try writer.print(".trainers[{}].party[{}].item={}\n", .{ i, j, member.item });
            },
            .moves => for (try trainer.party.moves.toSlice(game.data)) |member, j| {
                try writer.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, member.base.iv });
                try writer.print(".trainers[{}].party[{}].level={}\n", .{ i, j, member.base.level });
                try writer.print(".trainers[{}].party[{}].species={}\n", .{ i, j, member.base.species });
                for (member.moves) |move, k| {
                    try writer.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ i, j, k, move });
                }
            },
            .both => for (try trainer.party.both.toSlice(game.data)) |member, j| {
                try writer.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, member.base.iv });
                try writer.print(".trainers[{}].party[{}].level={}\n", .{ i, j, member.base.level });
                try writer.print(".trainers[{}].party[{}].species={}\n", .{ i, j, member.base.species });
                try writer.print(".trainers[{}].party[{}].item={}\n", .{ i, j, member.item });
                for (member.moves) |move, k| {
                    try writer.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ i, j, k, move });
                }
            },
        }
    }

    for (game.moves) |move, i| {
        try writer.print(".moves[{}].effect={}\n", .{ i, move.effect });
        try writer.print(".moves[{}].power={}\n", .{ i, move.power });
        try writer.print(".moves[{}].type={}\n", .{ i, move.@"type" });
        try writer.print(".moves[{}].accuracy={}\n", .{ i, move.accuracy });
        try writer.print(".moves[{}].pp={}\n", .{ i, move.pp });
        try writer.print(".moves[{}].side_effect_chance={}\n", .{ i, move.side_effect_chance });
        try writer.print(".moves[{}].target={}\n", .{ i, move.target });
        try writer.print(".moves[{}].priority={}\n", .{ i, move.priority });
        try writer.print(".moves[{}].flags0={}\n", .{ i, move.flags0 });
        try writer.print(".moves[{}].flags1={}\n", .{ i, move.flags1 });
        try writer.print(".moves[{}].flags2={}\n", .{ i, move.flags2 });
        try writer.print(".moves[{}].category={}\n", .{ i, @tagName(move.category) });
    }

    for (game.pokemons) |pokemon, i| {
        try writer.print(".pokemons[{}].stats.hp={}\n", .{ i, pokemon.stats.hp });
        try writer.print(".pokemons[{}].stats.attack={}\n", .{ i, pokemon.stats.attack });
        try writer.print(".pokemons[{}].stats.defense={}\n", .{ i, pokemon.stats.defense });
        try writer.print(".pokemons[{}].stats.speed={}\n", .{ i, pokemon.stats.speed });
        try writer.print(".pokemons[{}].stats.sp_attack={}\n", .{ i, pokemon.stats.sp_attack });
        try writer.print(".pokemons[{}].stats.sp_defense={}\n", .{ i, pokemon.stats.sp_defense });

        for (pokemon.types) |t, j| {
            try writer.print(".pokemons[{}].types[{}]={}\n", .{ i, j, t });
        }

        try writer.print(".pokemons[{}].catch_rate={}\n", .{ i, pokemon.catch_rate });
        try writer.print(".pokemons[{}].base_exp_yield={}\n", .{ i, pokemon.base_exp_yield });
        try writer.print(".pokemons[{}].ev_yield.hp={}\n", .{ i, pokemon.ev_yield.hp });
        try writer.print(".pokemons[{}].ev_yield.attack={}\n", .{ i, pokemon.ev_yield.attack });
        try writer.print(".pokemons[{}].ev_yield.defense={}\n", .{ i, pokemon.ev_yield.defense });
        try writer.print(".pokemons[{}].ev_yield.speed={}\n", .{ i, pokemon.ev_yield.speed });
        try writer.print(".pokemons[{}].ev_yield.sp_attack={}\n", .{ i, pokemon.ev_yield.sp_attack });
        try writer.print(".pokemons[{}].ev_yield.sp_defense={}\n", .{ i, pokemon.ev_yield.sp_defense });

        for (pokemon.items) |item, j| {
            try writer.print(".pokemons[{}].items[{}]={}\n", .{ i, j, item });
        }

        try writer.print(".pokemons[{}].gender_ratio={}\n", .{ i, pokemon.gender_ratio });
        try writer.print(".pokemons[{}].egg_cycles={}\n", .{ i, pokemon.egg_cycles });
        try writer.print(".pokemons[{}].base_friendship={}\n", .{ i, pokemon.base_friendship });
        try writer.print(".pokemons[{}].growth_rate={}\n", .{ i, @tagName(pokemon.growth_rate) });
        for (pokemon.egg_groups) |group, j|
            try writer.print(".pokemons[{}].egg_groups[{}]={}\n", .{ i, j, @tagName(group) });

        for (pokemon.abilities) |ability, j| {
            try writer.print(".pokemons[{}].abilities[{}]={}\n", .{ i, j, ability });
        }

        try writer.print(".pokemons[{}].safari_zone_rate={}\n", .{ i, pokemon.safari_zone_rate });
        try writer.print(".pokemons[{}].color={}\n", .{ i, @tagName(pokemon.color.color) });
        try writer.print(".pokemons[{}].flip={}\n", .{ i, pokemon.color.flip });
    }
    for (game.species_to_national_dex) |dex_entry, i|
        try writer.print(".pokemons[{}].pokedex_entry={}\n", .{ i + 1, dex_entry });

    for (game.evolutions) |evos, i| {
        for (evos) |evo, j| {
            if (evo.method == .unused)
                continue;
            try writer.print(".pokemons[{}].evos[{}].method={}\n", .{ i, j, @tagName(evo.method) });
            try writer.print(".pokemons[{}].evos[{}].param={}\n", .{ i, j, evo.param });
            try writer.print(".pokemons[{}].evos[{}].target={}\n", .{ i, j, evo.target });
        }
    }

    for (game.level_up_learnset_pointers) |lvl_up_learnset, i| {
        const learnset = try lvl_up_learnset.toSliceEnd(game.data);
        for (learnset) |l, j| {
            if (std.meta.eql(l, gen3.LevelUpMove.term))
                break;
            try writer.print(".pokemons[{}].moves[{}].id={}\n", .{ i, j, l.id });
            try writer.print(".pokemons[{}].moves[{}].level={}\n", .{ i, j, l.level });
        }
    }

    for (game.machine_learnsets) |machine_learnset, i| {
        var j: usize = 0;
        while (j < game.tms.len) : (j += 1)
            try writer.print(".pokemons[{}].tms[{}]={}\n", .{ i, j, bit.isSet(u64, machine_learnset.value(), @intCast(u6, j)) });
        while (j < game.tms.len + game.hms.len) : (j += 1)
            try writer.print(".pokemons[{}].hms[{}]={}\n", .{ i, j - game.tms.len, bit.isSet(u64, machine_learnset.value(), @intCast(u6, j)) });
    }

    for (game.pokemon_names) |name, i| {
        try writer.print(".pokemons[{}].name=", .{i});
        try gen3.encodings.decode(.en_us, &name, writer);
        try writer.writeByte('\n');
    }

    for (game.ability_names) |name, i| {
        try writer.print(".abilities[{}].name=", .{i});
        try gen3.encodings.decode(.en_us, &name, writer);
        try writer.writeByte('\n');
    }

    for (game.move_names) |name, i| {
        try writer.print(".moves[{}].name=", .{i});
        try gen3.encodings.decode(.en_us, &name, writer);
        try writer.writeByte('\n');
    }

    for (game.type_names) |name, i| {
        try writer.print(".types[{}].name=", .{i});
        try gen3.encodings.decode(.en_us, &name, writer);
        try writer.writeByte('\n');
    }

    for (game.tms) |tm, i|
        try writer.print(".tms[{}]={}\n", .{ i, tm });
    for (game.hms) |hm, i|
        try writer.print(".hms[{}]={}\n", .{ i, hm });

    for (game.items) |item, i| {
        const pocket = switch (game.version) {
            .ruby, .sapphire, .emerald => @tagName(item.pocket.rse),
            .fire_red, .leaf_green => @tagName(item.pocket.frlg),
            else => unreachable,
        };

        try writer.print(".items[{}].name=", .{i});
        try gen3.encodings.decode(.en_us, &item.name, writer);
        try writer.writeByte('\n');
        try writer.print(".items[{}].price={}\n", .{ i, item.price });
        try writer.print(".items[{}].id={}\n", .{ i, item.id });
        try writer.print(".items[{}].battle_effect={}\n", .{ i, item.battle_effect });
        try writer.print(".items[{}].battle_effect_p={}\n", .{ i, item.battle_effect_param });
        if (item.description.toSliceZ(game.data)) |description| {
            try writer.print(".items[{}].description=", .{i});
            try gen3.encodings.decode(.en_us, description, writer);
            try writer.writeByte('\n');
        } else |_| {}
        // try writer.print(".items[{}].description={}\n", .{i, item.description});
        try writer.print(".items[{}].importance={}\n", .{ i, item.importance });
        // try writer.print(".items[{}].unknown={}\n", .{i, item.unknown});
        try writer.print(".items[{}].pocket={}\n", .{ i, pocket });
        try writer.print(".items[{}].type={}\n", .{ i, item.@"type" });
        // try writer.print(".items[{}].field_use_func={}\n", .{i, item.field_use_func});
        try writer.print(".items[{}].battle_usage={}\n", .{ i, item.battle_usage });
        //try writer.print(".items[{}].battle_use_func={}\n", .{i, item.battle_use_func});
        try writer.print(".items[{}].secondary_id={}\n", .{ i, item.secondary_id });
    }

    switch (game.version) {
        .emerald => for (game.pokedex.emerald) |entry, i| {
            //try writer.print(".pokedex[{}].category_name={}\n", .{ i, entry.category_name});
            try writer.print(".pokedex[{}].height={}\n", .{ i, entry.height });
            try writer.print(".pokedex[{}].weight={}\n", .{ i, entry.weight });
            //try writer.print(".pokedex[{}].description={}\n", .{ i, entry.description});
            try writer.print(".pokedex[{}].pokemon_scale={}\n", .{ i, entry.pokemon_scale });
            try writer.print(".pokedex[{}].pokemon_offset={}\n", .{ i, entry.pokemon_offset });
            try writer.print(".pokedex[{}].trainer_scale={}\n", .{ i, entry.trainer_scale });
            try writer.print(".pokedex[{}].trainer_offset={}\n", .{ i, entry.trainer_offset });
        },
        .ruby,
        .sapphire,
        .fire_red,
        .leaf_green,
        => for (game.pokedex.rsfrlg) |entry, i| {
            //try writer.print(".pokedex[{}].category_name={}\n", .{ i, entry.category_name});
            try writer.print(".pokedex[{}].height={}\n", .{ i, entry.height });
            try writer.print(".pokedex[{}].weight={}\n", .{ i, entry.weight });
            //try writer.print(".pokedex[{}].description={}\n", .{ i, entry.description});
            //try writer.print(".pokedex[{}].unused_description={}\n", .{ i, entry.unused_description});
            try writer.print(".pokedex[{}].pokemon_scale={}\n", .{ i, entry.pokemon_scale });
            try writer.print(".pokedex[{}].pokemon_offset={}\n", .{ i, entry.pokemon_offset });
            try writer.print(".pokedex[{}].trainer_scale={}\n", .{ i, entry.trainer_scale });
            try writer.print(".pokedex[{}].trainer_offset={}\n", .{ i, entry.trainer_offset });
        },
        else => unreachable,
    }

    for (game.map_headers) |header, i| {
        try writer.print(".map[{}].music={}\n", .{ i, header.music });
        try writer.print(".map[{}].cave={}\n", .{ i, header.cave });
        try writer.print(".map[{}].weather={}\n", .{ i, header.weather });
        try writer.print(".map[{}].type={}\n", .{ i, header.map_type });
        try writer.print(".map[{}].escape_rope={}\n", .{ i, header.escape_rope });
        try writer.print(".map[{}].battle_scene={}\n", .{ i, header.map_battle_scene });
        try writer.print(".map[{}].allow_cycling={}\n", .{ i, header.flags.allow_cycling });
        try writer.print(".map[{}].allow_escaping={}\n", .{ i, header.flags.allow_escaping });
        try writer.print(".map[{}].allow_running={}\n", .{ i, header.flags.allow_running });
        try writer.print(".map[{}].show_map_name={}\n", .{ i, header.flags.show_map_name });
    }

    for (game.wild_pokemon_headers) |header, i| {
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

    for (game.static_pokemons) |static_mon, i| {
        try writer.print(".static_pokemons[{}].species={}\n", .{ i, static_mon.species });
        try writer.print(".static_pokemons[{}].level={}\n", .{ i, static_mon.level.* });
    }

    for (game.given_pokemons) |given_mon, i| {
        try writer.print(".given_pokemons[{}].species={}\n", .{ i, given_mon.species });
        try writer.print(".given_pokemons[{}].level={}\n", .{ i, given_mon.level.* });
    }

    for (game.pokeball_items) |given_item, i| {
        try writer.print(".pokeball_items[{}].item={}\n", .{ i, given_item.item });
        try writer.print(".pokeball_items[{}].amount={}\n", .{ i, given_item.amount });
    }

    for (game.text) |text_ptr, i| {
        const text = try text_ptr.toSliceZ(game.data);
        try writer.print(".text[{}]=", .{i});
        try gen3.encodings.decode(.en_us, text, writer);
        try writer.writeByte('\n');
    }
}

fn outputGen3Area(writer: anytype, i: usize, name: []const u8, rate: u8, wilds: []const gen3.WildPokemon) !void {
    try writer.print(".wild_pokemons[{}].{}.encounter_rate={}\n", .{ i, name, rate });
    for (wilds) |pokemon, j| {
        try writer.print(".wild_pokemons[{}].{}.pokemons[{}].min_level={}\n", .{ i, name, j, pokemon.min_level });
        try writer.print(".wild_pokemons[{}].{}.pokemons[{}].max_level={}\n", .{ i, name, j, pokemon.max_level });
        try writer.print(".wild_pokemons[{}].{}.pokemons[{}].species={}\n", .{ i, name, j, pokemon.species });
    }
}

fn outputGen4Data(nds_rom: nds.Rom, game: gen4.Game, writer: anytype) !void {
    try writer.print(".version={}\n", .{@tagName(game.info.version)});

    const header = nds_rom.header();
    const null_index = mem.indexOfScalar(u8, &header.game_title, 0) orelse header.game_title.len;
    try writer.print(".game_title={}\n", .{header.game_title[0..null_index]});
    try writer.print(".gamecode={}\n", .{header.gamecode});
    try writer.print(".instant_text=false\n", .{});

    for (game.ptrs.starters) |starter, i| {
        try writer.print(".starters[{}]={}\n", .{ i, starter });
    }

    for (game.ptrs.trainers) |trainer, i| {
        try writer.print(".trainers[{}].party_size={}\n", .{ i, trainer.party_size });
        try writer.print(".trainers[{}].party_type={}\n", .{ i, @tagName(trainer.party_type) });
        try writer.print(".trainers[{}].class={}\n", .{ i, trainer.class });
        try writer.print(".trainers[{}].battle_type={}\n", .{ i, trainer.battle_type });
        try writer.print(".trainers[{}].battle_type2={}\n", .{ i, trainer.battle_type2 });
        try writer.print(".trainers[{}].ai={}\n", .{ i, trainer.ai });

        for (trainer.items) |item, j| {
            try writer.print(".trainers[{}].items[{}]={}\n", .{ i, j, item });
        }

        const parties = game.owned.trainer_parties;
        if (parties.len <= i)
            continue;

        for (parties[i][0..trainer.party_size]) |member, j| {
            try writer.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, member.base.iv });
            try writer.print(".trainers[{}].party[{}].gender={}\n", .{ i, j, member.base.gender_ability.gender });
            try writer.print(".trainers[{}].party[{}].ability={}\n", .{ i, j, member.base.gender_ability.ability });
            try writer.print(".trainers[{}].party[{}].level={}\n", .{ i, j, member.base.level });
            try writer.print(".trainers[{}].party[{}].species={}\n", .{ i, j, member.base.species });
            try writer.print(".trainers[{}].party[{}].item={}\n", .{ i, j, member.item });
            for (member.moves) |move, k| {
                try writer.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ i, j, k, move });
            }
        }
    }

    for (game.ptrs.moves) |move, i| {
        try writer.print(".moves[{}].category={}\n", .{ i, @tagName(move.category) });
        try writer.print(".moves[{}].power={}\n", .{ i, move.power });
        try writer.print(".moves[{}].type={}\n", .{ i, move.@"type" });
        try writer.print(".moves[{}].accuracy={}\n", .{ i, move.accuracy });
        try writer.print(".moves[{}].pp={}\n", .{ i, move.pp });
    }

    for (game.ptrs.pokemons) |pokemon, i| {
        try writer.print(".pokemons[{}].stats.hp={}\n", .{ i, pokemon.stats.hp });
        try writer.print(".pokemons[{}].stats.attack={}\n", .{ i, pokemon.stats.attack });
        try writer.print(".pokemons[{}].stats.defense={}\n", .{ i, pokemon.stats.defense });
        try writer.print(".pokemons[{}].stats.speed={}\n", .{ i, pokemon.stats.speed });
        try writer.print(".pokemons[{}].stats.sp_attack={}\n", .{ i, pokemon.stats.sp_attack });
        try writer.print(".pokemons[{}].stats.sp_defense={}\n", .{ i, pokemon.stats.sp_defense });

        for (pokemon.types) |t, j| {
            try writer.print(".pokemons[{}].types[{}]={}\n", .{ i, j, t });
        }

        try writer.print(".pokemons[{}].catch_rate={}\n", .{ i, pokemon.catch_rate });
        try writer.print(".pokemons[{}].base_exp_yield={}\n", .{ i, pokemon.base_exp_yield });
        try writer.print(".pokemons[{}].ev_yield.hp={}\n", .{ i, pokemon.ev_yield.hp });
        try writer.print(".pokemons[{}].ev_yield.attack={}\n", .{ i, pokemon.ev_yield.attack });
        try writer.print(".pokemons[{}].ev_yield.defense={}\n", .{ i, pokemon.ev_yield.defense });
        try writer.print(".pokemons[{}].ev_yield.speed={}\n", .{ i, pokemon.ev_yield.speed });
        try writer.print(".pokemons[{}].ev_yield.sp_attack={}\n", .{ i, pokemon.ev_yield.sp_attack });
        try writer.print(".pokemons[{}].ev_yield.sp_defense={}\n", .{ i, pokemon.ev_yield.sp_defense });

        for (pokemon.items) |item, j| {
            try writer.print(".pokemons[{}].items[{}]={}\n", .{ i, j, item });
        }

        try writer.print(".pokemons[{}].gender_ratio={}\n", .{ i, pokemon.gender_ratio });
        try writer.print(".pokemons[{}].egg_cycles={}\n", .{ i, pokemon.egg_cycles });
        try writer.print(".pokemons[{}].base_friendship={}\n", .{ i, pokemon.base_friendship });
        try writer.print(".pokemons[{}].growth_rate={}\n", .{ i, @tagName(pokemon.growth_rate) });
        for (pokemon.egg_groups) |group, j|
            try writer.print(".pokemons[{}].egg_groups[{}]={}\n", .{ i, j, @tagName(group) });

        for (pokemon.abilities) |ability, j| {
            try writer.print(".pokemons[{}].abilities[{}]={}\n", .{ i, j, ability });
        }

        try writer.print(".pokemons[{}].flee_rate={}\n", .{ i, pokemon.flee_rate });
        try writer.print(".pokemons[{}].color={}\n", .{ i, @tagName(pokemon.color.color) });
        try writer.print(".pokemons[{}].flip={}\n", .{ i, pokemon.color.flip });

        const machine_learnset = pokemon.machine_learnset;
        var j: usize = 0;
        while (j < game.ptrs.tms.len) : (j += 1)
            try writer.print(".pokemons[{}].tms[{}]={}\n", .{ i, j, bit.isSet(u128, machine_learnset.value(), @intCast(u7, j)) });
        while (j < game.ptrs.tms.len + game.ptrs.hms.len) : (j += 1)
            try writer.print(".pokemons[{}].hms[{}]={}\n", .{ i, j - game.ptrs.tms.len, bit.isSet(u128, machine_learnset.value(), @intCast(u7, j)) });
    }
    for (game.ptrs.species_to_national_dex) |dex_entry, i|
        try writer.print(".pokemons[{}].pokedex_entry={}\n", .{ i + 1, dex_entry });

    for (game.ptrs.evolutions) |evos, i| {
        for (evos.items) |evo, j| {
            if (evo.method == .unused)
                continue;
            try writer.print(".pokemons[{}].evos[{}].method={}\n", .{ i, j, @tagName(evo.method) });
            try writer.print(".pokemons[{}].evos[{}].param={}\n", .{ i, j, evo.param });
            try writer.print(".pokemons[{}].evos[{}].target={}\n", .{ i, j, evo.target });
        }
    }

    {
        var i: u32 = 0;
        while (i < game.ptrs.level_up_moves.fat.len) : (i += 1) {
            const bytes = game.ptrs.level_up_moves.fileData(.{ .i = i });
            const level_up_moves = mem.bytesAsSlice(gen4.LevelUpMove, bytes);
            for (level_up_moves) |move, j| {
                if (std.meta.eql(move, gen4.LevelUpMove.term))
                    break;
                try writer.print(".pokemons[{}].moves[{}].id={}\n", .{ i, j, move.id });
                try writer.print(".pokemons[{}].moves[{}].level={}\n", .{ i, j, move.level });
            }
        }
    }

    for (game.ptrs.pokedex_heights) |height, i|
        try writer.print(".pokedex[{}].height={}\n", .{ i, height });
    for (game.ptrs.pokedex_weights) |weight, i|
        try writer.print(".pokedex[{}].weight={}\n", .{ i, weight });
    for (game.ptrs.tms) |tm, i|
        try writer.print(".tms[{}]={}\n", .{ i, tm });
    for (game.ptrs.hms) |hm, i|
        try writer.print(".hms[{}]={}\n", .{ i, hm });

    for (game.ptrs.items) |item, i| {
        try writer.print(".items[{}].price={}\n", .{ i, item.price });
        try writer.print(".items[{}].battle_effect={}\n", .{ i, item.battle_effect });
        try writer.print(".items[{}].gain={}\n", .{ i, item.gain });
        try writer.print(".items[{}].berry={}\n", .{ i, item.berry });
        try writer.print(".items[{}].fling_effect={}\n", .{ i, item.fling_effect });
        try writer.print(".items[{}].fling_power={}\n", .{ i, item.fling_power });
        try writer.print(".items[{}].natural_gift_power={}\n", .{ i, item.natural_gift_power });
        try writer.print(".items[{}].flag={}\n", .{ i, item.flag });
        try writer.print(".items[{}].pocket={}\n", .{ i, @tagName(item.pocket) });
        try writer.print(".items[{}].type={}\n", .{ i, item.type });
        try writer.print(".items[{}].category={}\n", .{ i, item.category });
        //try writer.print(".items[{}].category2={}\n", .{ i, item.category2 });
        try writer.print(".items[{}].index={}\n", .{ i, item.index });
        //try writer.print(".items[{}].statboosts.hp={}\n", .{ i, item.statboosts.hp });
        //try writer.print(".items[{}].statboosts.level={}\n", .{ i, item.statboosts.level });
        //try writer.print(".items[{}].statboosts.evolution={}\n", .{ i, item.statboosts.evolution });
        //try writer.print(".items[{}].statboosts.attack={}\n", .{ i, item.statboosts.attack });
        //try writer.print(".items[{}].statboosts.defense={}\n", .{ i, item.statboosts.defense });
        //try writer.print(".items[{}].statboosts.sp_attack={}\n", .{ i, item.statboosts.sp_attack });
        //try writer.print(".items[{}].statboosts.sp_defense={}\n", .{ i, item.statboosts.sp_defense });
        //try writer.print(".items[{}].statboosts.speed={}\n", .{ i, item.statboosts.speed });
        //try writer.print(".items[{}].statboosts.accuracy={}\n", .{ i, item.statboosts.accuracy });
        //try writer.print(".items[{}].statboosts.crit={}\n", .{ i, item.statboosts.crit });
        //try writer.print(".items[{}].statboosts.pp={}\n", .{ i, item.statboosts.pp });
        //try writer.print(".items[{}].statboosts.target={}\n", .{ i, item.statboosts.target });
        //try writer.print(".items[{}].statboosts.target2={}\n", .{ i, item.statboosts.target2 });
        try writer.print(".items[{}].ev_yield.hp={}\n", .{ i, item.ev_yield.hp });
        try writer.print(".items[{}].ev_yield.attack={}\n", .{ i, item.ev_yield.attack });
        try writer.print(".items[{}].ev_yield.defense={}\n", .{ i, item.ev_yield.defense });
        try writer.print(".items[{}].ev_yield.speed={}\n", .{ i, item.ev_yield.speed });
        try writer.print(".items[{}].ev_yield.sp_attack={}\n", .{ i, item.ev_yield.sp_attack });
        try writer.print(".items[{}].ev_yield.sp_defense={}\n", .{ i, item.ev_yield.sp_defense });
        try writer.print(".items[{}].hp_restore={}\n", .{ i, item.hp_restore });
        try writer.print(".items[{}].pp_restore={}\n", .{ i, item.pp_restore });
    }

    switch (game.info.version) {
        .diamond,
        .pearl,
        .platinum,
        => for (game.ptrs.wild_pokemons.dppt) |wild_mons, i| {
            try writer.print(".wild_pokemons[{}].grass.encounter_rate={}\n", .{ i, wild_mons.grass_rate });
            for (wild_mons.grass) |grass, j| {
                try writer.print(".wild_pokemons[{}].grass.pokemons[{}].min_level={}\n", .{ i, j, grass.level });
                try writer.print(".wild_pokemons[{}].grass.pokemons[{}].max_level={}\n", .{ i, j, grass.level });
                try writer.print(".wild_pokemons[{}].grass.pokemons[{}].species={}\n", .{ i, j, grass.species });
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
                for (@field(wild_mons, area_name)) |replacement, k| {
                    try writer.print(".wild_pokemons[{}].{}.pokemons[{}].species={}\n", .{ i, area_name, k, replacement.species });
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
                try writer.print(".wild_pokemons[{}].{}.encounter_rate={}\n", .{ i, area_name, @field(wild_mons, area_name).rate });
                for (@field(wild_mons, area_name).mons) |sea, k| {
                    try writer.print(".wild_pokemons[{}].{}.pokemons[{}].min_level={}\n", .{ i, area_name, k, sea.min_level });
                    try writer.print(".wild_pokemons[{}].{}.pokemons[{}].max_level={}\n", .{ i, area_name, k, sea.max_level });
                    try writer.print(".wild_pokemons[{}].{}.pokemons[{}].species={}\n", .{ i, area_name, k, sea.species });
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
                try writer.print(".wild_pokemons[{}].{}.encounter_rate={}\n", .{ i, area_name, wild_mons.grass_rate });
                for (@field(wild_mons, area_name)) |species, j| {
                    try writer.print(".wild_pokemons[{}].{}.pokemons[{}].min_level={}\n", .{ i, area_name, j, wild_mons.grass_levels[j] });
                    try writer.print(".wild_pokemons[{}].{}.pokemons[{}].max_level={}\n", .{ i, area_name, j, wild_mons.grass_levels[j] });
                    try writer.print(".wild_pokemons[{}].{}.pokemons[{}].species={}\n", .{ i, area_name, j, species });
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
                try writer.print(".wild_pokemons[{}].{}.encounter_rate={}\n", .{ i, area_name, wild_mons.sea_rates[j] });
                for (@field(wild_mons, area_name)) |sea, k| {
                    try writer.print(".wild_pokemons[{}].{}.pokemons[{}].min_level={}\n", .{ i, area_name, k, sea.min_level });
                    try writer.print(".wild_pokemons[{}].{}.pokemons[{}].max_level={}\n", .{ i, area_name, k, sea.max_level });
                    try writer.print(".wild_pokemons[{}].{}.pokemons[{}].species={}\n", .{ i, area_name, k, sea.species });
                }
            }

            // TODO: radio, swarm
        },

        else => unreachable,
    }

    for (game.ptrs.static_pokemons) |static_mon, i| {
        try writer.print(".static_pokemons[{}].species={}\n", .{ i, static_mon.species });
        try writer.print(".static_pokemons[{}].level={}\n", .{ i, static_mon.level });
    }

    for (game.ptrs.given_pokemons) |given_mon, i| {
        try writer.print(".given_pokemons[{}].species={}\n", .{ i, given_mon.species });
        try writer.print(".given_pokemons[{}].level={}\n", .{ i, given_mon.level });
    }

    for (game.ptrs.pokeball_items) |given_item, i| {
        try writer.print(".pokeball_items[{}].item={}\n", .{ i, given_item.item });
        try writer.print(".pokeball_items[{}].amount={}\n", .{ i, given_item.amount });
    }

    for (game.owned.pokemon_names) |*str, i|
        try outputString(writer, "pokemons", i, "name", str.span());
    for (game.owned.move_names) |*str, i|
        try outputString(writer, "moves", i, "name", str.span());
    for (game.owned.move_descriptions) |*str, i|
        try outputString(writer, "moves", i, "description", str.span());
    for (game.owned.ability_names) |*str, i|
        try outputString(writer, "abilities", i, "name", str.span());
    for (game.owned.item_names) |*str, i|
        try outputString(writer, "items", i, "name", str.span());
    //for (game.owned.item_names_on_the_ground) |*str, i| try outputGen5String(writer, "items", i, "name_on_ground", str);
    for (game.owned.item_descriptions) |*str, i|
        try outputString(writer, "items", i, "description", str.span());
    for (game.owned.type_names) |*str, i|
        try outputString(writer, "types", i, "name", str.span());
    //for (game.owned.map_names) |*str, i| try outputGen5String(writer, "map", i, "name", str);
    //for (game.owned.trainer_names) |*str, i|
    //    try outputString(writer, "trainers", i + 1, "name", str.span());

    // This snippet of code can be uncommented to output all strings in gen4 games.
    // This is useful when looking for new strings to expose.
    //    var buf: [1024]u8 = undefined;
    //    for (game.ptrs.text.fat) |_, i| {
    //        const file = nds.fs.File{ .i = @intCast(u16, i) };
    //        const table = gen4.StringTable{ .data = game.ptrs.text.fileData(file) };
    //        const name = try std.fmt.bufPrint(&buf, "{}", .{i});
    //        outputGen4StringTable(writer, name, "", table) catch continue;
    //    }
}

fn outputGen4StringTable(
    writer: anytype,
    array_name: []const u8,
    field_name: []const u8,
    est: gen4.StringTable,
) !void {
    var i: u32 = 10;
    while (i < est.count()) : (i += 1) {
        try writer.print(".{}[{}].{}=", .{ array_name, i, field_name });
        try gen4.encodings.decode(est.getStringStream(i).reader(), writer);
        try writer.writeAll("\n");
    }
}

fn outputGen5Data(nds_rom: nds.Rom, game: gen5.Game, writer: anytype) !void {
    try writer.print(".version={}\n", .{@tagName(game.info.version)});

    const header = nds_rom.header();
    const null_index = mem.indexOfScalar(u8, &header.game_title, 0) orelse header.game_title.len;
    try writer.print(".game_title={}\n", .{header.game_title[0..null_index]});
    try writer.print(".gamecode={}\n", .{header.gamecode});
    try writer.print(".instant_text=false\n", .{});

    for (game.ptrs.starters) |starter_ptrs, i| {
        const first = starter_ptrs[0];
        for (starter_ptrs[1..]) |starter| {
            if (first != starter)
                debug.warn("warning: all starter positions are not the same.\n", .{});
        }

        try writer.print(".starters[{}]={}\n", .{ i, first });
    }

    for (game.ptrs.trainers) |trainer, index| {
        const i = index + 1;
        try writer.print(".trainers[{}].party_size={}\n", .{ i, trainer.party_size });
        try writer.print(".trainers[{}].party_type={}\n", .{ i, @tagName(trainer.party_type) });
        try writer.print(".trainers[{}].class={}\n", .{ i, trainer.class });
        try writer.print(".trainers[{}].battle_type={}\n", .{ i, trainer.battle_type });

        for (trainer.items) |item, j| {
            try writer.print(".trainers[{}].items[{}]={}\n", .{ i, j, item });
        }

        try writer.print(".trainers[{}].ai={}\n", .{ i, trainer.ai });
        try writer.print(".trainers[{}].is_healer={}\n", .{ i, trainer.healer });
        try writer.print(".trainers[{}].cash={}\n", .{ i, trainer.cash });
        try writer.print(".trainers[{}].post_battle_item={}\n", .{ i, trainer.post_battle_item });

        const parties = game.owned.trainer_parties;
        if (parties.len <= i)
            continue;

        for (parties[i][0..trainer.party_size]) |member, j| {
            try writer.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, member.base.iv });
            try writer.print(".trainers[{}].party[{}].gender={}\n", .{ i, j, member.base.gender_ability.gender });
            try writer.print(".trainers[{}].party[{}].ability={}\n", .{ i, j, member.base.gender_ability.ability });
            try writer.print(".trainers[{}].party[{}].level={}\n", .{ i, j, member.base.level });
            try writer.print(".trainers[{}].party[{}].species={}\n", .{ i, j, member.base.species });
            try writer.print(".trainers[{}].party[{}].form={}\n", .{ i, j, member.base.form });
            try writer.print(".trainers[{}].party[{}].item={}\n", .{ i, j, member.item });
            for (member.moves) |move, k| {
                try writer.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ i, j, k, move });
            }
        }
    }

    for (game.ptrs.moves) |move, i| {
        try writer.print(".moves[{}].type={}\n", .{ i, move.@"type" });
        try writer.print(".moves[{}].effect_category={}\n", .{ i, move.effect_category });
        try writer.print(".moves[{}].category={}\n", .{ i, @tagName(move.category) });
        try writer.print(".moves[{}].power={}\n", .{ i, move.power });
        try writer.print(".moves[{}].accuracy={}\n", .{ i, move.accuracy });
        try writer.print(".moves[{}].pp={}\n", .{ i, move.pp });
        try writer.print(".moves[{}].priority={}\n", .{ i, move.priority });
        try writer.print(".moves[{}].min_hits={}\n", .{ i, move.min_hits });
        try writer.print(".moves[{}].max_hits={}\n", .{ i, move.max_hits });
        try writer.print(".moves[{}].result_effect={}\n", .{ i, move.result_effect });
        try writer.print(".moves[{}].effect_chance={}\n", .{ i, move.effect_chance });
        try writer.print(".moves[{}].status={}\n", .{ i, move.status });
        try writer.print(".moves[{}].min_turns={}\n", .{ i, move.min_turns });
        try writer.print(".moves[{}].max_turns={}\n", .{ i, move.max_turns });
        try writer.print(".moves[{}].crit={}\n", .{ i, move.crit });
        try writer.print(".moves[{}].flinch={}\n", .{ i, move.flinch });
        try writer.print(".moves[{}].effect={}\n", .{ i, move.effect });
        try writer.print(".moves[{}].target_hp={}\n", .{ i, move.target_hp });
        try writer.print(".moves[{}].user_hp={}\n", .{ i, move.user_hp });
        try writer.print(".moves[{}].target={}\n", .{ i, move.target });

        //const stats_affected = move.stats_affected;
        //for (stats_affected) |stat_affected, j|
        //    try writer.print(".moves[{}].stats_affected[{}]={}\n", .{ i, j, stat_affected });

        //const stats_affected_magnetude = move.stats_affected_magnetude;
        //for (stats_affected_magnetude) |stat_affected_magnetude, j|
        //    try writer.print(".moves[{}].stats_affected_magnetude[{}]={}\n", .{ i, j, stat_affected_magnetude });

        //const stats_affected_chance = move.stats_affected_chance;
        //for (stats_affected_chance) |stat_affected_chance, j|
        //    try writer.print(".moves[{}].stats_affected_chance[{}]={}\n", .{ i, j, stat_affected_chance });
    }

    const number_of_pokemons = 649;

    {
        var i: u32 = 0;
        while (i < game.ptrs.pokemons.fat.len) : (i += 1) {
            const pokemon = try game.ptrs.pokemons.fileAs(.{ .i = i }, gen5.BasePokemon);
            try writer.print(".pokemons[{}].pokedex_entry={}\n", .{ i, i });
            try writer.print(".pokemons[{}].stats.hp={}\n", .{ i, pokemon.stats.hp });
            try writer.print(".pokemons[{}].stats.attack={}\n", .{ i, pokemon.stats.attack });
            try writer.print(".pokemons[{}].stats.defense={}\n", .{ i, pokemon.stats.defense });
            try writer.print(".pokemons[{}].stats.speed={}\n", .{ i, pokemon.stats.speed });
            try writer.print(".pokemons[{}].stats.sp_attack={}\n", .{ i, pokemon.stats.sp_attack });
            try writer.print(".pokemons[{}].stats.sp_defense={}\n", .{ i, pokemon.stats.sp_defense });

            const types = pokemon.types;
            for (types) |t, j|
                try writer.print(".pokemons[{}].types[{}]={}\n", .{ i, j, t });

            try writer.print(".pokemons[{}].catch_rate={}\n", .{ i, pokemon.catch_rate });

            // TODO: Figure out if common.EvYield fits in these 3 bytes
            // evs: [3]u8,

            const items = pokemon.items;
            for (items) |item, j|
                try writer.print(".pokemons[{}].items[{}]={}\n", .{ i, j, item });

            try writer.print(".pokemons[{}].gender_ratio={}\n", .{ i, pokemon.gender_ratio });
            try writer.print(".pokemons[{}].egg_cycles={}\n", .{ i, pokemon.egg_cycles });
            try writer.print(".pokemons[{}].base_friendship={}\n", .{ i, pokemon.base_friendship });
            try writer.print(".pokemons[{}].growth_rate={}\n", .{ i, @tagName(pokemon.growth_rate) });

            // HACK: For some reason, a release build segfaults here for Pokémons
            //       with id above 'number_of_pokemons'. You would think this is
            //       because of an index out of bounds during @tagName, but
            //       common.EggGroup is a u4 enum and has a tag for all possible
            //       values, so it really should not.
            if (i < number_of_pokemons) {
                for (pokemon.egg_groups) |group, j|
                    try writer.print(".pokemons[{}].egg_groups[{}]={}\n", .{ i, j, @tagName(group) });
            }

            const abilities = pokemon.abilities;
            for (abilities) |ability, j|
                try writer.print(".pokemons[{}].abilities[{}]={}\n", .{ i, j, ability });

            // TODO: The three fields below are kinda unknown
            // flee_rate: u8,
            // form_stats_start: [2]u8,
            // form_sprites_start: [2]u8,
            // form_count: u8,

            //try writer.print(".pokemons[{}].color={}\n", .{ i, @tagName(pokemon.color.color) });
            try writer.print(".pokemons[{}].flip={}\n", .{ i, pokemon.color.flip });
            try writer.print(".pokemons[{}].height={}\n", .{ i, pokemon.height });
            try writer.print(".pokemons[{}].weight={}\n", .{ i, pokemon.weight });

            const machine_learnset = pokemon.machine_learnset;
            var j: usize = 0;
            while (j < game.ptrs.tms1.len + game.ptrs.tms2.len) : (j += 1)
                try writer.print(".pokemons[{}].tms[{}]={}\n", .{ i, j, bit.isSet(u128, machine_learnset.value(), @intCast(u7, j)) });
            while (j < game.ptrs.tms1.len + game.ptrs.tms2.len + game.ptrs.hms.len) : (j += 1)
                try writer.print(".pokemons[{}].hms[{}]={}\n", .{ i, j - (game.ptrs.tms1.len + game.ptrs.tms2.len), bit.isSet(u128, machine_learnset.value(), @intCast(u7, j)) });
        }
    }

    for (game.ptrs.evolutions) |evos, i| {
        for (evos.items) |evo, j| {
            if (evo.method == .unused)
                continue;
            try writer.print(".pokemons[{}].evos[{}].method={}\n", .{ i, j, @tagName(evo.method) });
            try writer.print(".pokemons[{}].evos[{}].param={}\n", .{ i, j, evo.param });
            try writer.print(".pokemons[{}].evos[{}].target={}\n", .{ i, j, evo.target });
        }
    }

    {
        var i: usize = 0;
        while (i < game.ptrs.level_up_moves.fat.len) : (i += 1) {
            const bytes = game.ptrs.level_up_moves.fileData(.{ .i = @intCast(u32, i) });
            const level_up_moves = mem.bytesAsSlice(gen5.LevelUpMove, bytes);
            for (level_up_moves) |move, j| {
                if (std.meta.eql(move, gen5.LevelUpMove.term))
                    break;
                try writer.print(".pokemons[{}].moves[{}].id={}\n", .{ i, j, move.id });
                try writer.print(".pokemons[{}].moves[{}].level={}\n", .{ i, j, move.level });
            }
        }
    }

    for (game.ptrs.tms1) |tm, i|
        try writer.print(".tms[{}]={}\n", .{ i, tm });
    for (game.ptrs.tms2) |tm, i|
        try writer.print(".tms[{}]={}\n", .{ i + game.ptrs.tms1.len, tm });
    for (game.ptrs.hms) |hm, i|
        try writer.print(".hms[{}]={}\n", .{ i, hm });

    for (game.ptrs.items) |item, i| {
        // Price in gen5 is actually price * 10. I imagine they where trying to avoid
        // having price be more than a u16
        try writer.print(".items[{}].price={}\n", .{ i, @as(u32, item.price.value()) * 10 });
        try writer.print(".items[{}].battle_effect={}\n", .{ i, item.battle_effect });
        try writer.print(".items[{}].gain={}\n", .{ i, item.gain });
        try writer.print(".items[{}].berry={}\n", .{ i, item.berry });
        try writer.print(".items[{}].fling_effect={}\n", .{ i, item.fling_effect });
        try writer.print(".items[{}].fling_power={}\n", .{ i, item.fling_power });
        try writer.print(".items[{}].natural_gift_power={}\n", .{ i, item.natural_gift_power });
        try writer.print(".items[{}].flag={}\n", .{ i, item.flag });
        try writer.print(".items[{}].pocket={}\n", .{ i, @tagName(item.pocket) });
        try writer.print(".items[{}].type={}\n", .{ i, item.type });
        try writer.print(".items[{}].category={}\n", .{ i, item.category });
        //try writer.print(".items[{}].category2={}\n", .{ i, item.category2 });
        //try writer.print(".items[{}].category3={}\n", .{ i, item.category3 });
        try writer.print(".items[{}].index={}\n", .{ i, item.index });
        try writer.print(".items[{}].anti_index={}\n", .{ i, item.anti_index });
        //try writer.print(".items[{}].statboosts.hp={}\n", .{ i, item.statboosts.hp });
        //try writer.print(".items[{}].statboosts.level={}\n", .{ i, item.statboosts.level });
        //try writer.print(".items[{}].statboosts.evolution={}\n", .{ i, item.statboosts.evolution });
        //try writer.print(".items[{}].statboosts.attack={}\n", .{ i, item.statboosts.attack });
        //try writer.print(".items[{}].statboosts.defense={}\n", .{ i, item.statboosts.defense });
        //try writer.print(".items[{}].statboosts.sp_attack={}\n", .{ i, item.statboosts.sp_attack });
        //try writer.print(".items[{}].statboosts.sp_defense={}\n", .{ i, item.statboosts.sp_defense });
        //try writer.print(".items[{}].statboosts.speed={}\n", .{ i, item.statboosts.speed });
        //try writer.print(".items[{}].statboosts.accuracy={}\n", .{ i, item.statboosts.accuracy });
        //try writer.print(".items[{}].statboosts.crit={}\n", .{ i, item.statboosts.crit });
        //try writer.print(".items[{}].statboosts.pp={}\n", .{ i, item.statboosts.pp });
        //try writer.print(".items[{}].statboosts.target={}\n", .{ i, item.statboosts.target });
        //try writer.print(".items[{}].statboosts.target2={}\n", .{ i, item.statboosts.target2 });
        try writer.print(".items[{}].ev_yield.hp={}\n", .{ i, item.ev_yield.hp });
        try writer.print(".items[{}].ev_yield.attack={}\n", .{ i, item.ev_yield.attack });
        try writer.print(".items[{}].ev_yield.defense={}\n", .{ i, item.ev_yield.defense });
        try writer.print(".items[{}].ev_yield.speed={}\n", .{ i, item.ev_yield.speed });
        try writer.print(".items[{}].ev_yield.sp_attack={}\n", .{ i, item.ev_yield.sp_attack });
        try writer.print(".items[{}].ev_yield.sp_defense={}\n", .{ i, item.ev_yield.sp_defense });
        try writer.print(".items[{}].hp_restore={}\n", .{ i, item.hp_restore });
        try writer.print(".items[{}].pp_restore={}\n", .{ i, item.pp_restore });
    }

    for (game.ptrs.map_headers) |map_header, i| {
        try writer.print(".map[{}].music={}\n", .{ i, map_header.music });
        try writer.print(".map[{}].battle_scene={}\n", .{ i, map_header.battle_scene });
    }

    for (game.ptrs.wild_pokemons.fat) |_, i| {
        const wild_mons = try game.ptrs.wild_pokemons.fileAs(.{ .i = @intCast(u32, i) }, gen5.WildPokemons);
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
            try writer.print(".wild_pokemons[{}].{}.encounter_rate={}\n", .{ i, area_name, wild_mons.rates[j] });
            const area = @field(wild_mons, area_name);
            for (area) |wild, k| {
                try writer.print(".wild_pokemons[{}].{}.pokemons[{}].species={}\n", .{ i, area_name, k, wild.species.species() });
                try writer.print(".wild_pokemons[{}].{}.pokemons[{}].form={}\n", .{ i, area_name, k, wild.species.form() });
                try writer.print(".wild_pokemons[{}].{}.pokemons[{}].min_level={}\n", .{ i, area_name, k, wild.min_level });
                try writer.print(".wild_pokemons[{}].{}.pokemons[{}].max_level={}\n", .{ i, area_name, k, wild.max_level });
            }
        }
    }

    for (game.ptrs.static_pokemons) |static_mon, i| {
        try writer.print(".static_pokemons[{}].species={}\n", .{ i, static_mon.species });
        try writer.print(".static_pokemons[{}].level={}\n", .{ i, static_mon.level });
    }

    for (game.ptrs.given_pokemons) |given_mon, i| {
        try writer.print(".given_pokemons[{}].species={}\n", .{ i, given_mon.species });
        try writer.print(".given_pokemons[{}].level={}\n", .{ i, given_mon.level });
    }

    for (game.ptrs.pokeball_items) |given_item, i| {
        try writer.print(".pokeball_items[{}].item={}\n", .{ i, given_item.item });
        try writer.print(".pokeball_items[{}].amount={}\n", .{ i, given_item.amount });
    }

    if (game.ptrs.hidden_hollows) |hidden_hollows| {
        for (hidden_hollows) |hollow, i| {
            for (hollow.pokemons) |version, j| {
                for (version) |group, k| {
                    for (group.species) |_, g| {
                        try writer.print(
                            ".hidden_hollows[{}].versions[{}].groups[{}].pokemons[{}].species={}\n",
                            .{ i, j, k, g, group.species[g] },
                        );
                        try writer.print(
                            ".hidden_hollows[{}].versions[{}].groups[{}].pokemons[{}].gender={}\n",
                            .{ i, j, k, g, group.genders[g] },
                        );
                        try writer.print(
                            ".hidden_hollows[{}].versions[{}].groups[{}].pokemons[{}].form={}\n",
                            .{ i, j, k, g, group.forms[g] },
                        );
                    }
                }
            }
            for (hollow.items) |item, j| {
                try writer.print(".hidden_hollows[{}].items[{}]={}\n", .{ i, j, item });
            }
        }
    }

    for (game.owned.pokemon_names) |*str, i|
        try outputString(writer, "pokemons", i, "name", str.span());
    for (game.owned.pokedex_category_names) |*str, i|
        try outputString(writer, "pokedex", i, "category", str.span());
    for (game.owned.move_names) |*str, i|
        try outputString(writer, "moves", i, "name", str.span());
    for (game.owned.move_descriptions) |*str, i|
        try outputString(writer, "moves", i, "description", str.span());
    for (game.owned.ability_names) |*str, i|
        try outputString(writer, "abilities", i, "name", str.span());
    for (game.owned.item_names) |*str, i|
        try outputString(writer, "items", i, "name", str.span());
    //for (game.owned.item_names_on_the_ground) |*str, i| try outputGen5String(writer, "items", i, "name_on_ground", str);
    for (game.owned.item_descriptions) |*str, i|
        try outputString(writer, "items", i, "description", str.span());
    for (game.owned.type_names) |*str, i|
        try outputString(writer, "types", i, "name", str.span());
    //for (game.owned.map_names) |*str, i| try outputGen5String(writer, "map", i, "name", str);
    for (game.owned.trainer_names[1..]) |*str, i|
        try outputString(writer, "trainers", i + 1, "name", str.span());

    // This snippet of code can be uncommented to output all strings in gen5 game.ptrs..
    // This is useful when looking for new strings to expose.
    //    var buf: [1024]u8 = undefined;
    //    for (game.ptrs.text.fat) |_, i| {
    //        const file = nds.fs.File{ .i = @intCast(u16, i) };
    //        const table = gen5.StringTable{ .data = game.ptrs.text.fileData(file) };
    //        const name = try std.fmt.bufPrint(&buf, "{}", .{i});
    //        outputGen5StringTable(writer, name, "", table) catch continue;
    //    }
}

fn outputString(
    writer: anytype,
    array_name: []const u8,
    i: usize,
    field_name: []const u8,
    string: []const u8,
) !void {
    try writer.print(".{}[{}].{}=", .{ array_name, i, field_name });
    try escape.writeEscaped(writer, string, escape.zig_escapes);
    try writer.writeAll("\n");
}

test "" {
    std.testing.refAllDecls(@This());
}
