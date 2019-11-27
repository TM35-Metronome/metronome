const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const common = @import("common.zig");
const gen3 = @import("gen3-types.zig");
const gen4 = @import("gen4-types.zig");
const gen5 = @import("gen5-types.zig");
const rom = @import("rom.zig");

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;

const gba = rom.gba;
const nds = rom.nds;

const bit = util.bit;
const errors = util.errors;

const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);

const Clap = clap.ComptimeClap(clap.Help, params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

const params = [_]Param{
    clap.parseParam("-h, --help     Display this help text and exit.    ") catch unreachable,
    clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
    Param{ .takes_value = true },
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-load [-hv] <FILE>
        \\Loads data from Pokémon roms.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    var stdio_unbuf = util.getStdIo() catch |err| return 1;
    var stdio = stdio_unbuf.getBuffered();
    defer stdio.err.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(&arena.allocator);
    _ = arg_iter.next() catch undefined;

    const res = main2(
        &arena.allocator,
        fs.File.ReadError,
        fs.File.WriteError,
        stdio.getStreams(),
        clap.args.OsIterator,
        &arg_iter,
    );

    stdio.out.flush() catch |err| return errors.writeErr(&stdio.err.stream, "<stdout>", err);
    return res;
}

pub fn main2(
    allocator: *mem.Allocator,
    comptime ReadError: type,
    comptime WriteError: type,
    stdio: util.CustomStdIoStreams(ReadError, WriteError),
    comptime ArgIterator: type,
    arg_iter: *ArgIterator,
) u8 {
    var args = Clap.parse(allocator, ArgIterator, arg_iter) catch |err| {
        stdio.err.print("{}\n", err) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    if (args.flag("--help")) {
        usage(stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.print("{}\n", program_version) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else {
        stdio.err.write("No file provided\n") catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const file = fs.File.openRead(file_name) catch |err| return errors.openErr(stdio.err, file_name, err);
    defer file.close();

    const gen3_error = if (gen3.Game.fromFile(file, allocator)) |game| {
        outputGen3Data(game, stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    } else |err| err;

    file.seekTo(0) catch |err| return errors.readErr(stdio.err, file_name, err);
    if (nds.Rom.fromFile(file, allocator)) |nds_rom| {
        const gen4_error = if (gen4.Game.fromRom(nds_rom)) |game| {
            outputGen4Data(nds_rom, game, stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            return 0;
        } else |err| err;

        const gen5_error = if (gen5.Game.fromRom(allocator, nds_rom)) |game| {
            outputGen5Data(nds_rom, game, stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            return 0;
        } else |err| err;

        stdio.err.print("Successfully loaded '{}' as a nds rom.\n", file_name) catch {};
        stdio.err.print("Failed to load '{}' as a gen4 game: {}\n", file_name, gen4_error) catch {};
        stdio.err.print("Failed to load '{}' as a gen5 game: {}\n", file_name, gen5_error) catch {};
        return 1;
    } else |nds_error| {
        stdio.err.print("Failed to load '{}' as a gen3 game: {}\n", file_name, gen3_error) catch {};
        stdio.err.print("Failed to load '{}' as a gen4/gen5 game: {}\n", file_name, nds_error) catch {};
        return 1;
    }
}

fn outputGen3Data(game: gen3.Game, stream: var) !void {
    try stream.print(".version={}\n", @tagName(game.version));
    try stream.print(".game_title={}\n", game.header.game_title);
    try stream.print(".gamecode={}\n", game.header.gamecode);

    for (game.starters) |starter, i| {
        if (starter.value() != game.starters_repeat[i].value())
            debug.warn("warning: repeated starters don't match.\n");

        try stream.print(".starters[{}]={}\n", i, starter.value());
    }

    for (game.trainers) |trainer, i| {
        // The party type is infered from the party data.
        // try stream.print(".trainers[{}].party_type={}\n", i, trainer.party_type);
        try stream.print(".trainers[{}].class={}\n", i, trainer.class);
        try stream.print(".trainers[{}].encounter_music={}\n", i, trainer.encounter_music);
        try stream.print(".trainers[{}].trainer_picture={}\n", i, trainer.trainer_picture);
        // TODO: Convert the trainer name to utf-8 and then write out.
        // try stream.print(".trainers[{}].name={}\n", i, trainer.name);

        for (trainer.items) |item, j| {
            try stream.print(".trainers[{}].items[{}]={}\n", i, j, item.value());
        }

        try stream.print(".trainers[{}].is_double={}\n", i, trainer.is_double.value());
        try stream.print(".trainers[{}].ai={}\n", i, trainer.ai.value());

        switch (trainer.party_type) {
            gen3.PartyType.None => {
                for (try trainer.party.None.toSlice(game.data)) |member, j| {
                    try stream.print(".trainers[{}].party[{}].iv={}\n", i, j, member.base.iv.value());
                    try stream.print(".trainers[{}].party[{}].level={}\n", i, j, member.base.level.value());
                    try stream.print(".trainers[{}].party[{}].species={}\n", i, j, member.base.species.value());
                }
            },
            gen3.PartyType.Item => {
                for (try trainer.party.Item.toSlice(game.data)) |member, j| {
                    try stream.print(".trainers[{}].party[{}].iv={}\n", i, j, member.base.iv.value());
                    try stream.print(".trainers[{}].party[{}].level={}\n", i, j, member.base.level.value());
                    try stream.print(".trainers[{}].party[{}].species={}\n", i, j, member.base.species.value());
                    try stream.print(".trainers[{}].party[{}].item={}\n", i, j, member.item.value());
                }
            },
            gen3.PartyType.Moves => {
                for (try trainer.party.Moves.toSlice(game.data)) |member, j| {
                    try stream.print(".trainers[{}].party[{}].iv={}\n", i, j, member.base.iv.value());
                    try stream.print(".trainers[{}].party[{}].level={}\n", i, j, member.base.level.value());
                    try stream.print(".trainers[{}].party[{}].species={}\n", i, j, member.base.species.value());
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", i, j, k, move.value());
                    }
                }
            },
            gen3.PartyType.Both => {
                for (try trainer.party.Both.toSlice(game.data)) |member, j| {
                    try stream.print(".trainers[{}].party[{}].iv={}\n", i, j, member.base.iv.value());
                    try stream.print(".trainers[{}].party[{}].level={}\n", i, j, member.base.level.value());
                    try stream.print(".trainers[{}].party[{}].species={}\n", i, j, member.base.species.value());
                    try stream.print(".trainers[{}].party[{}].item={}\n", i, j, member.item.value());
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", i, j, k, move.value());
                    }
                }
            },
        }
    }

    for (game.moves) |move, i| {
        try stream.print(".moves[{}].effect={}\n", i, move.effect);
        try stream.print(".moves[{}].power={}\n", i, move.power);
        try stream.print(".moves[{}].type={}\n", i, @tagName(move.@"type"));
        try stream.print(".moves[{}].accuracy={}\n", i, move.accuracy);
        try stream.print(".moves[{}].pp={}\n", i, move.pp);
        try stream.print(".moves[{}].side_effect_chance={}\n", i, move.side_effect_chance);
        try stream.print(".moves[{}].target={}\n", i, move.target);
        try stream.print(".moves[{}].priority={}\n", i, move.priority);
        try stream.print(".moves[{}].flags={}\n", i, move.flags.value());
    }

    for (game.pokemons) |pokemon, i| {
        try stream.print(".pokemons[{}].stats.hp={}\n", i, pokemon.stats.hp);
        try stream.print(".pokemons[{}].stats.attack={}\n", i, pokemon.stats.attack);
        try stream.print(".pokemons[{}].stats.defense={}\n", i, pokemon.stats.defense);
        try stream.print(".pokemons[{}].stats.speed={}\n", i, pokemon.stats.speed);
        try stream.print(".pokemons[{}].stats.sp_attack={}\n", i, pokemon.stats.sp_attack);
        try stream.print(".pokemons[{}].stats.sp_defense={}\n", i, pokemon.stats.sp_defense);

        for (pokemon.types) |t, j| {
            try stream.print(".pokemons[{}].types[{}]={}\n", i, j, @tagName(t));
        }

        try stream.print(".pokemons[{}].catch_rate={}\n", i, pokemon.catch_rate);
        try stream.print(".pokemons[{}].base_exp_yield={}\n", i, pokemon.base_exp_yield);
        try stream.print(".pokemons[{}].ev_yield.hp={}\n", i, pokemon.ev_yield.hp);
        try stream.print(".pokemons[{}].ev_yield.attack={}\n", i, pokemon.ev_yield.attack);
        try stream.print(".pokemons[{}].ev_yield.defense={}\n", i, pokemon.ev_yield.defense);
        try stream.print(".pokemons[{}].ev_yield.speed={}\n", i, pokemon.ev_yield.speed);
        try stream.print(".pokemons[{}].ev_yield.sp_attack={}\n", i, pokemon.ev_yield.sp_attack);
        try stream.print(".pokemons[{}].ev_yield.sp_defense={}\n", i, pokemon.ev_yield.sp_defense);

        for (pokemon.items) |item, j| {
            try stream.print(".pokemons[{}].items[{}]={}\n", i, j, item.value());
        }

        try stream.print(".pokemons[{}].gender_ratio={}\n", i, pokemon.gender_ratio);
        try stream.print(".pokemons[{}].egg_cycles={}\n", i, pokemon.egg_cycles);
        try stream.print(".pokemons[{}].base_friendship={}\n", i, pokemon.base_friendship);
        try stream.print(".pokemons[{}].growth_rate={}\n", i, @tagName(pokemon.growth_rate));
        try stream.print(".pokemons[{}].egg_groups[{}]={}\n", i, usize(0), @tagName(pokemon.egg_group1));
        try stream.print(".pokemons[{}].egg_groups[{}]={}\n", i, usize(1), @tagName(pokemon.egg_group2));

        for (pokemon.abilities) |ability, j| {
            try stream.print(".pokemons[{}].abilities[{}]={}\n", i, j, ability);
        }

        try stream.print(".pokemons[{}].safari_zone_rate={}\n", i, pokemon.safari_zone_rate);
        try stream.print(".pokemons[{}].color={}\n", i, @tagName(pokemon.color_flip.color));
        try stream.print(".pokemons[{}].flip={}\n", i, pokemon.color_flip.flip);

        {
            const machine_learnset = game.machine_learnsets[i].value();
            var j: usize = 0;
            while (j < game.tms.len) : (j += 1) {
                try stream.print(".pokemons[{}].tms[{}]={}\n", i, j, bit.isSet(u64, machine_learnset, @intCast(u6, j)));
            }
            while (j < game.tms.len + game.hms.len) : (j += 1) {
                try stream.print(".pokemons[{}].hms[{}]={}\n", i, j - game.tms.len, bit.isSet(u64, machine_learnset, @intCast(u6, j)));
            }
        }

        for (game.evolutions[i]) |evo, j| {
            if (evo.method == .Unused)
                continue;
            try stream.print(".pokemons[{}].evos[{}].method={}\n", i, j, @tagName(evo.method));
            try stream.print(".pokemons[{}].evos[{}].param={}\n", i, j, evo.param.value());
            try stream.print(".pokemons[{}].evos[{}].target={}\n", i, j, evo.target.value());
        }

        const learnset = try game.level_up_learnset_pointers[i].toSliceTerminated(game.data, struct {
            fn isTerm(move: gen3.LevelUpMove) bool {
                return move.id == math.maxInt(u9) and move.level == math.maxInt(u7);
            }
        }.isTerm);
        for (learnset) |l, j| {
            try stream.print(".pokemons[{}].moves[{}].id={}\n", i, j, l.id);
            try stream.print(".pokemons[{}].moves[{}].level={}\n", i, j, l.level);
        }
    }

    for (game.tms) |tm, i| {
        try stream.print(".tms[{}]={}\n", i, tm.value());
    }

    for (game.hms) |hm, i| {
        try stream.print(".hms[{}]={}\n", i, hm.value());
    }

    for (game.items) |item, i| {
        // try stream.print(".items[{}].name={}\n", i, item.name);
        try stream.print(".items[{}].id={}\n", i, item.id.value());
        try stream.print(".items[{}].price={}\n", i, item.price.value());
        try stream.print(".items[{}].hold_effect={}\n", i, item.hold_effect);
        try stream.print(".items[{}].hold_effect_param={}\n", i, item.hold_effect_param);
        // try stream.print(".items[{}].description={}\n", i, item.description);
        try stream.print(".items[{}].importance={}\n", i, item.importance);
        // try stream.print(".items[{}].unknown={}\n", i, item.unknown);
        try stream.print(".items[{}].pocked={}\n", i, item.pocked);
        try stream.print(".items[{}].type={}\n", i, item.@"type");
        // try stream.print(".items[{}].field_use_func={}\n", i, item.field_use_func);
        try stream.print(".items[{}].battle_usage={}\n", i, item.battle_usage.value());
        //try stream.print(".items[{}].battle_use_func={}\n", i, item.battle_use_func);
        try stream.print(".items[{}].secondary_id={}\n", i, item.secondary_id.value());
    }

    for (game.wild_pokemon_headers) |header, i| {
        inline for ([_][]const u8{
            "land",
            "surf",
            "rock_smash",
            "fishing",
        }) |area_name| {
            if (@field(header, area_name).toSingle(game.data)) |area| {
                try stream.print(".zones[{}].wild.{}.encounter_rate={}\n", i, area_name, area.encounter_rate);
                for (try area.wild_pokemons.toSingle(game.data)) |pokemon, j| {
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", i, area_name, j, pokemon.min_level);
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", i, area_name, j, pokemon.max_level);
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", i, area_name, j, pokemon.species.value());
                }
            } else |_| {}
        }
    }

    for (game.static_pokemons) |static_mon, i| {
        const data = static_mon.data;
        try stream.print(".static_pokemons[{}].species={}\n", i, data.setwildbattle.species.value());
        try stream.print(".static_pokemons[{}].level={}\n", i, data.setwildbattle.level);
        try stream.print(".static_pokemons[{}].item={}\n", i, data.setwildbattle.item.value());
    }

    for (game.given_items) |given_item, i| {
        const data = given_item.data;
        try stream.print(".given_items[{}].item={}\n", i, data.giveitem.index.value());
        try stream.print(".given_items[{}].quantity={}\n", i, data.giveitem.quantity.value());
    }
}

fn outputGen4Data(nds_rom: nds.Rom, game: gen4.Game, stream: var) !void {
    try stream.print(".version={}\n", @tagName(game.version));

    const null_index = mem.indexOfScalar(u8, nds_rom.header.game_title, 0) orelse nds_rom.header.game_title.len;
    try stream.print(".game_title={}\n", nds_rom.header.game_title[0..null_index]);
    try stream.print(".gamecode={}\n", nds_rom.header.gamecode);

    for (game.starters) |starter, i| {
        try stream.print(".starters[{}]={}\n", i, starter.value());
    }

    for (game.trainers.nodes.toSlice()) |node, i| {
        const trainer = node.asDataFile(gen4.Trainer) catch continue;

        try stream.print(".trainers[{}].class={}\n", i, trainer.class);
        try stream.print(".trainers[{}].battle_type={}\n", i, trainer.battle_type);
        try stream.print(".trainers[{}].battle_type2={}\n", i, trainer.battle_type2);
        try stream.print(".trainers[{}].ai={}\n", i, trainer.ai.value());

        for (trainer.items) |item, j| {
            try stream.print(".trainers[{}].items[{}]={}\n", i, j, item.value());
        }

        const parties = game.parties.nodes.toSlice();
        if (parties.len <= i)
            continue;

        const party_file = parties[i].asFile() catch continue;
        const party_data = party_file.data;
        var j: usize = 0;
        while (j < trainer.party_size) : (j += 1) {
            const base = trainer.partyMember(game.version, party_data, i) orelse continue;
            try stream.print(".trainers[{}].party[{}].iv={}\n", i, j, base.iv);
            try stream.print(".trainers[{}].party[{}].gender={}\n", i, j, base.gender_ability.gender);
            try stream.print(".trainers[{}].party[{}].ability={}\n", i, j, base.gender_ability.ability);
            try stream.print(".trainers[{}].party[{}].level={}\n", i, j, base.level.value());
            try stream.print(".trainers[{}].party[{}].species={}\n", i, j, base.species.species());
            try stream.print(".trainers[{}].party[{}].form={}\n", i, j, base.species.form());

            switch (trainer.party_type) {
                gen4.PartyType.None => {},
                gen4.PartyType.Item => {
                    const member = base.toParent(gen4.PartyMemberItem);
                    try stream.print(".trainers[{}].party[{}].item={}\n", i, j, member.item.value());
                },
                gen4.PartyType.Moves => {
                    const member = base.toParent(gen4.PartyMemberMoves);
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", i, j, k, move.value());
                    }
                },
                gen4.PartyType.Both => {
                    const member = base.toParent(gen4.PartyMemberBoth);
                    try stream.print(".trainers[{}].party[{}].item={}\n", i, j, member.item.value());
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", i, j, k, move.value());
                    }
                },
            }
        }
    }

    for (game.moves.nodes.toSlice()) |node, i| {
        const move = node.asDataFile(gen4.Move) catch continue;
        try stream.print(".moves[{}].category={}\n", i, @tagName(move.category));
        try stream.print(".moves[{}].power={}\n", i, move.power);
        try stream.print(".moves[{}].type={}\n", i, @tagName(move.@"type"));
        try stream.print(".moves[{}].accuracy={}\n", i, move.accuracy);
        try stream.print(".moves[{}].pp={}\n", i, move.pp);
    }

    for (game.pokemons.nodes.toSlice()) |node, i| {
        const pokemon = node.asDataFile(gen4.BasePokemon) catch continue;
        try stream.print(".pokemons[{}].stats.hp={}\n", i, pokemon.stats.hp);
        try stream.print(".pokemons[{}].stats.attack={}\n", i, pokemon.stats.attack);
        try stream.print(".pokemons[{}].stats.defense={}\n", i, pokemon.stats.defense);
        try stream.print(".pokemons[{}].stats.speed={}\n", i, pokemon.stats.speed);
        try stream.print(".pokemons[{}].stats.sp_attack={}\n", i, pokemon.stats.sp_attack);
        try stream.print(".pokemons[{}].stats.sp_defense={}\n", i, pokemon.stats.sp_defense);

        for (pokemon.types) |t, j| {
            try stream.print(".pokemons[{}].types[{}]={}\n", i, j, @tagName(t));
        }

        try stream.print(".pokemons[{}].catch_rate={}\n", i, pokemon.catch_rate);
        try stream.print(".pokemons[{}].base_exp_yield={}\n", i, pokemon.base_exp_yield);
        try stream.print(".pokemons[{}].ev_yield.hp={}\n", i, pokemon.ev_yield.hp);
        try stream.print(".pokemons[{}].ev_yield.attack={}\n", i, pokemon.ev_yield.attack);
        try stream.print(".pokemons[{}].ev_yield.defense={}\n", i, pokemon.ev_yield.defense);
        try stream.print(".pokemons[{}].ev_yield.speed={}\n", i, pokemon.ev_yield.speed);
        try stream.print(".pokemons[{}].ev_yield.sp_attack={}\n", i, pokemon.ev_yield.sp_attack);
        try stream.print(".pokemons[{}].ev_yield.sp_defense={}\n", i, pokemon.ev_yield.sp_defense);

        for (pokemon.items) |item, j| {
            try stream.print(".pokemons[{}].items[{}]={}\n", i, j, item.value());
        }

        try stream.print(".pokemons[{}].gender_ratio={}\n", i, pokemon.gender_ratio);
        try stream.print(".pokemons[{}].egg_cycles={}\n", i, pokemon.egg_cycles);
        try stream.print(".pokemons[{}].base_friendship={}\n", i, pokemon.base_friendship);
        try stream.print(".pokemons[{}].growth_rate={}\n", i, @tagName(pokemon.growth_rate));
        try stream.print(".pokemons[{}].egg_groups[{}]={}\n", i, usize(0), @tagName(pokemon.egg_group1));
        try stream.print(".pokemons[{}].egg_groups[{}]={}\n", i, usize(1), @tagName(pokemon.egg_group2));

        for (pokemon.abilities) |ability, j| {
            try stream.print(".pokemons[{}].abilities[{}]={}\n", i, j, ability);
        }

        try stream.print(".pokemons[{}].flee_rate={}\n", i, pokemon.flee_rate);
        try stream.print(".pokemons[{}].color={}\n", i, @tagName(pokemon.color));
        {
            const machine_learnset = pokemon.machine_learnset.value();
            var j: usize = 0;
            while (j < game.tms.len) : (j += 1) {
                try stream.print(".pokemons[{}].tms[{}]={}\n", i, j, bit.isSet(u128, machine_learnset, @intCast(u7, j)));
            }
            while (j < game.tms.len + game.hms.len) : (j += 1) {
                try stream.print(".pokemons[{}].hms[{}]={}\n", i, j - game.tms.len, bit.isSet(u128, machine_learnset, @intCast(u7, j)));
            }
        }

        const evos_file = try game.evolutions.nodes.toSlice()[i].asFile();
        const bytes = evos_file.data;
        const rem = bytes.len % @sizeOf(gen4.Evolution);
        const evos = @bytesToSlice(gen4.Evolution, bytes[0 .. bytes.len - rem]);
        for (evos) |evo, j| {
            if (evo.method == .Unused)
                continue;
            try stream.print(".pokemons[{}].evos[{}].method={}\n", i, j, @tagName(evo.method));
            try stream.print(".pokemons[{}].evos[{}].param={}\n", i, j, evo.param.value());
            try stream.print(".pokemons[{}].evos[{}].target={}\n", i, j, evo.target.value());
        }
    }

    for (game.tms) |tm, i| {
        try stream.print(".tms[{}]={}\n", i, tm.value());
    }

    for (game.hms) |hm, i| {
        try stream.print(".hms[{}]={}\n", i, hm.value());
    }

    for (game.wild_pokemons.nodes.toSlice()) |node, i|
        switch (game.version) {
            common.Version.Diamond,
            common.Version.Pearl,
            common.Version.Platinum,
            => {
                const wild_mons = node.asDataFile(gen4.DpptWildPokemons) catch continue;

                try stream.print(".zones[{}].wild.grass.encounter_rate={}\n", i, wild_mons.grass_rate.value());
                for (wild_mons.grass) |grass, j| {
                    try stream.print(".zones[{}].wild.grass.pokemons[{}].min_level={}\n", i, j, grass.level);
                    try stream.print(".zones[{}].wild.grass.pokemons[{}].max_level={}\n", i, j, grass.level);
                    try stream.print(".zones[{}].wild.grass.pokemons[{}].species={}\n", i, j, grass.species.species());
                    try stream.print(".zones[{}].wild.grass.pokemons[{}].form={}\n", i, j, grass.species.form());
                }

                inline for ([_][]const u8{
                    "swarm_replacements",
                    "day_replacements",
                    "night_replacements",
                    "radar_replacements",
                    "unknown_replacements",
                    "gba_replacements",
                }) |area_name| {
                    for (@field(wild_mons, area_name)) |replacement, k| {
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", i, area_name, k, replacement.species.species());
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].form={}\n", i, area_name, k, replacement.species.form());
                    }
                }

                inline for ([_][]const u8{
                    "surf",
                    "sea_unknown",
                    "old_rod",
                    "good_rod",
                    "super_rod",
                }) |area_name| {
                    try stream.print(".zones[{}].wild.{}.encounter_rate={}\n", i, area_name, @field(wild_mons, area_name ++ "_rate").value());
                    for (@field(wild_mons, area_name)) |sea, k| {
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", i, area_name, k, sea.min_level);
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", i, area_name, k, sea.max_level);
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", i, area_name, k, sea.species.species());
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].form={}\n", i, area_name, k, sea.species.form());
                    }
                }
            },

            common.Version.HeartGold,
            common.Version.SoulSilver,
            => {
                const wild_mons = node.asDataFile(gen4.HgssWildPokemons) catch continue;
                inline for ([_][]const u8{
                    "grass_morning",
                    "grass_day",
                    "grass_night",
                }) |area_name| {
                    try stream.print(".zones[{}].wild.{}.encounter_rate={}\n", i, area_name, wild_mons.grass_rate);
                    for (@field(wild_mons, area_name)) |species, j| {
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", i, area_name, j, wild_mons.grass_levels[j]);
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", i, area_name, j, wild_mons.grass_levels[j]);
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", i, area_name, j, species.species());
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].form={}\n", i, area_name, j, species.form());
                    }
                }

                inline for ([_][]const u8{
                    "surf",
                    "sea_unknown",
                    "old_rod",
                    "good_rod",
                    "super_rod",
                }) |area_name, j| {
                    try stream.print(".zones[{}].wild.{}.encounter_rate={}\n", i, area_name, wild_mons.sea_rates[j]);
                    for (@field(wild_mons, area_name)) |sea, k| {
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", i, area_name, k, sea.min_level);
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", i, area_name, k, sea.max_level);
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", i, area_name, k, sea.species.species());
                        try stream.print(".zones[{}].wild.{}.pokemons[{}].form={}\n", i, area_name, k, sea.species.form());
                    }
                }

                // TODO: radio, swarm
            },

            else => unreachable,
        };
}

fn outputGen5Data(nds_rom: nds.Rom, game: gen5.Game, stream: var) !void {
    try stream.print(".version={}\n", @tagName(game.version));

    const null_index = mem.indexOfScalar(u8, nds_rom.header.game_title, 0) orelse nds_rom.header.game_title.len;
    try stream.print(".game_title={}\n", nds_rom.header.game_title[0..null_index]);
    try stream.print(".gamecode={}\n", nds_rom.header.gamecode);

    for (game.starters) |starter_ptrs, i| {
        const first = starter_ptrs[0];
        for (starter_ptrs[1..]) |starter| {
            if (first.value() != starter.value())
                debug.warn("warning: all starter positions are not the same.\n");
        }

        try stream.print(".starters[{}]={}\n", i, first.value());
    }

    for (game.trainers.nodes.toSlice()) |node, i| {
        const trainer = node.asDataFile(gen5.Trainer) catch continue;

        try stream.print(".trainers[{}].class={}\n", i, trainer.class);
        try stream.print(".trainers[{}].battle_type={}\n", i, trainer.battle_type);

        for (trainer.items) |item, j| {
            try stream.print(".trainers[{}].items[{}]={}\n", i, j, item.value());
        }

        try stream.print(".trainers[{}].ai={}\n", i, trainer.ai.value());
        try stream.print(".trainers[{}].is_healer={}\n", i, trainer.healer);
        try stream.print(".trainers[{}].cash={}\n", i, trainer.cash);
        try stream.print(".trainers[{}].post_battle_item={}\n", i, trainer.post_battle_item.value());

        const parties = game.parties.nodes.toSlice();
        if (parties.len <= i)
            continue;

        const party_file = parties[i].asFile() catch continue;
        const party_data = party_file.data;
        var j: usize = 0;
        while (j < trainer.party_size) : (j += 1) {
            const base = trainer.partyMember(party_data, i) orelse continue;
            try stream.print(".trainers[{}].party[{}].iv={}\n", i, j, base.iv);
            try stream.print(".trainers[{}].party[{}].gender={}\n", i, j, base.gender_ability.gender);
            try stream.print(".trainers[{}].party[{}].ability={}\n", i, j, base.gender_ability.ability);
            try stream.print(".trainers[{}].party[{}].level={}\n", i, j, base.level);
            try stream.print(".trainers[{}].party[{}].species={}\n", i, j, base.species.value());
            try stream.print(".trainers[{}].party[{}].form={}\n", i, j, base.form.value());

            switch (trainer.party_type) {
                gen5.PartyType.None => {},
                gen5.PartyType.Item => {
                    const member = base.toParent(gen5.PartyMemberItem);
                    try stream.print(".trainers[{}].party[{}].item={}\n", i, j, member.item.value());
                },
                gen5.PartyType.Moves => {
                    const member = base.toParent(gen5.PartyMemberMoves);
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", i, j, k, move.value());
                    }
                },
                gen5.PartyType.Both => {
                    const member = base.toParent(gen5.PartyMemberBoth);
                    try stream.print(".trainers[{}].party[{}].item={}\n", i, j, member.item.value());
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", i, j, k, move.value());
                    }
                },
            }
        }
    }

    for (game.moves.nodes.toSlice()) |node, i| {
        const move = node.asDataFile(gen5.Move) catch continue;

        try stream.print(".moves[{}].type={}\n", i, @tagName(move.@"type"));
        try stream.print(".moves[{}].effect_category={}\n", i, move.effect_category);
        try stream.print(".moves[{}].category={}\n", i, @tagName(move.category));
        try stream.print(".moves[{}].power={}\n", i, move.power);
        try stream.print(".moves[{}].accuracy={}\n", i, move.accuracy);
        try stream.print(".moves[{}].pp={}\n", i, move.pp);
        try stream.print(".moves[{}].priority={}\n", i, move.priority);
        try stream.print(".moves[{}].min_hits={}\n", i, move.min_max_hits.min);
        try stream.print(".moves[{}].max_hits={}\n", i, move.min_max_hits.max);
        try stream.print(".moves[{}].result_effect={}\n", i, move.result_effect.value());
        try stream.print(".moves[{}].effect_chance={}\n", i, move.effect_chance);
        try stream.print(".moves[{}].status={}\n", i, move.status);
        try stream.print(".moves[{}].min_turns={}\n", i, move.min_turns);
        try stream.print(".moves[{}].max_turns={}\n", i, move.max_turns);
        try stream.print(".moves[{}].crit={}\n", i, move.crit);
        try stream.print(".moves[{}].flinch={}\n", i, move.flinch);
        try stream.print(".moves[{}].effect={}\n", i, move.effect.value());
        try stream.print(".moves[{}].target_hp={}\n", i, move.target_hp);
        try stream.print(".moves[{}].user_hp={}\n", i, move.user_hp);
        try stream.print(".moves[{}].target={}\n", i, move.target);

        const stats_affected = move.stats_affected;
        for (stats_affected) |stat_affected, j|
            try stream.print(".moves[{}].stats_affected[{}]={}\n", i, j, stat_affected);

        const stats_affected_magnetude = move.stats_affected_magnetude;
        for (stats_affected_magnetude) |stat_affected_magnetude, j|
            try stream.print(".moves[{}].stats_affected_magnetude[{}]={}\n", i, j, stat_affected_magnetude);

        const stats_affected_chance = move.stats_affected_chance;
        for (stats_affected_chance) |stat_affected_chance, j|
            try stream.print(".moves[{}].stats_affected_chance[{}]={}\n", i, j, stat_affected_chance);
    }

    for (game.pokemons.nodes.toSlice()) |node, i| {
        const pokemon = node.asDataFile(gen5.BasePokemon) catch continue;

        try stream.print(".pokemons[{}].stats.hp={}\n", i, pokemon.stats.hp);
        try stream.print(".pokemons[{}].stats.attack={}\n", i, pokemon.stats.attack);
        try stream.print(".pokemons[{}].stats.defense={}\n", i, pokemon.stats.defense);
        try stream.print(".pokemons[{}].stats.speed={}\n", i, pokemon.stats.speed);
        try stream.print(".pokemons[{}].stats.sp_attack={}\n", i, pokemon.stats.sp_attack);
        try stream.print(".pokemons[{}].stats.sp_defense={}\n", i, pokemon.stats.sp_defense);

        const types = pokemon.types;
        for (types) |t, j|
            try stream.print(".pokemons[{}].types[{}]={}\n", i, j, @tagName(t));

        try stream.print(".pokemons[{}].catch_rate={}\n", i, pokemon.catch_rate);

        // TODO: Figure out if common.EvYield fits in these 3 bytes
        // evs: [3]u8,

        const items = pokemon.items;
        for (items) |item, j|
            try stream.print(".pokemons[{}].items[{}]={}\n", i, j, item.value());

        try stream.print(".pokemons[{}].gender_ratio={}\n", i, pokemon.gender_ratio);
        try stream.print(".pokemons[{}].egg_cycles={}\n", i, pokemon.egg_cycles);
        try stream.print(".pokemons[{}].base_friendship={}\n", i, pokemon.base_friendship);
        try stream.print(".pokemons[{}].growth_rate={}\n", i, @tagName(pokemon.growth_rate));
        try stream.print(".pokemons[{}].egg_groups[{}]={}\n", i, usize(0), @tagName(pokemon.egg_group1));
        try stream.print(".pokemons[{}].egg_groups[{}]={}\n", i, usize(1), @tagName(pokemon.egg_group2));

        const abilities = pokemon.abilities;
        for (abilities) |ability, j|
            try stream.print(".pokemons[{}].abilities[{}]={}\n", i, j, ability);

        // TODO: The three fields below are kinda unknown
        // flee_rate: u8,
        // form_stats_start: [2]u8,
        // form_sprites_start: [2]u8,
        // form_count: u8,

        try stream.print(".pokemons[{}].color={}\n", i, @tagName(pokemon.color));
        try stream.print(".pokemons[{}].height={}\n", i, pokemon.height.value());
        try stream.print(".pokemons[{}].weight={}\n", i, pokemon.weight.value());

        {
            const machine_learnset = pokemon.machine_learnset.value();
            var j: usize = 0;
            while (j < game.tms1.len) : (j += 1) {
                try stream.print(".pokemons[{}].tms[{}]={}\n", i, j, bit.isSet(u128, machine_learnset, @intCast(u7, j)));
            }
            while (j < game.tms1.len + game.hms.len) : (j += 1) {
                try stream.print(".pokemons[{}].hms[{}]={}\n", i, j - game.tms1.len, bit.isSet(u128, machine_learnset, @intCast(u7, j)));
            }
            while (j < game.tms2.len + game.hms.len + game.tms1.len) : (j += 1) {
                try stream.print(".pokemons[{}].tms[{}]={}\n", i, j - game.hms.len, bit.isSet(u128, machine_learnset, @intCast(u7, j)));
            }
        }

        if (game.evolutions.nodes.len <= i)
            continue;

        const evos_file = try game.evolutions.nodes.toSlice()[i].asFile();
        const bytes = evos_file.data;
        const rem = bytes.len % @sizeOf(gen5.Evolution);
        const evos = @bytesToSlice(gen5.Evolution, bytes[0 .. bytes.len - rem]);
        for (evos) |evo, j| {
            if (evo.method == .Unused)
                continue;
            try stream.print(".pokemons[{}].evos[{}].method={}\n", i, j, @tagName(evo.method));
            try stream.print(".pokemons[{}].evos[{}].param={}\n", i, j, evo.param.value());
            try stream.print(".pokemons[{}].evos[{}].target={}\n", i, j, evo.target.value());
        }
    }

    for (game.tms1) |tm, i|
        try stream.print(".tms[{}]={}\n", i, tm.value());
    for (game.tms2) |tm, i|
        try stream.print(".tms[{}]={}\n", i + game.tms1.len, tm.value());
    for (game.hms) |hm, i|
        try stream.print(".hms[{}]={}\n", i, hm.value());

    for (game.wild_pokemons.nodes.toSlice()) |node, i| {
        const wild_mons = node.asDataFile(gen5.WildPokemons) catch continue;
        inline for ([_][]const u8{
            "grass",
            "dark_grass",
            "rustling_grass",
            "surf",
            "ripple_surf",
            "fishing",
            "ripple_fishing",
        }) |area_name, j| {
            try stream.print(".zones[{}].wild.{}.encounter_rate={}\n", i, area_name, wild_mons.rates[j]);
            const area = @field(wild_mons, area_name);
            for (area) |wild, k| {
                try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", i, area_name, k, wild.species.species());
                try stream.print(".zones[{}].wild.{}.pokemons[{}].form={}\n", i, area_name, k, wild.species.form());
                try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", i, area_name, k, wild.min_level);
                try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", i, area_name, k, wild.max_level);
            }
        }
    }
}

test "" {
    _ = @import("load-apply-test.zig");
}
