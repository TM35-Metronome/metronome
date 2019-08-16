const builtin = @import("builtin");
const clap = @import("clap");
const common = @import("common.zig");
const format = @import("format");
const fun = @import("fun");
const gba = @import("gba.zig");
const gen3 = @import("gen3-types.zig");
const gen4 = @import("gen4-types.zig");
const gen5 = @import("gen5-types.zig");
const nds = @import("nds.zig");
const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;

const path = fs.path;

const bits = fun.bits;
const slice = fun.generic.slice;

const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);

const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = [_]Param{
    Param{
        .id = "display this help text and exit",
        .names = Names{ .short = 'h', .long = "help" },
    },
    Param{
        .id = "",
        .takes_value = true,
    },
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-gen3-load [OPTION]... FILE
        \\Prints information about a generation 3 Pokemon rom to stdout in the
        \\tm35 format.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    const stdout_file = io.getStdOut() catch |err| return errPrint("Could not aquire stdout: {}", err);
    const stderr_file = io.getStdErr() catch |err| return errPrint("Could not aquire stderr: {}", err);

    var buf_stdout = BufOutStream.init(&stdout_file.outStream().stream);
    const stderr = &stderr_file.outStream().stream;
    const stdout = &buf_stdout.stream;

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return 1;
    };

    if (args.flag("--help")) {
        usage(stdout) catch |err| return errPrint("Failed to write data to stdout: {}\n", err);
        return 0;
    }

    const file_name = blk: {
        const poss = args.positionals();
        if (poss.len == 0) {
            debug.warn("No file provided\n");
            usage(stderr) catch {};
            return 1;
        }

        break :blk poss[0];
    };

    const file = fs.File.openRead(file_name) catch |err| return errPrint("Unable to open '{}': {}\n", file_name, err);
    defer file.close();

    const gen3_error = if (gen3.Game.fromFile(file, allocator)) |game| {
        outputGen3Data(game, stdout) catch |err| return stdoutWriteError(err);
        buf_stdout.flush() catch |err| return stdoutWriteError(err);
        return 0;
    } else |err| err;

    file.seekTo(0) catch |err| return errPrint("Failure while read from '{}': {}\n", file_name, err);
    if (nds.Rom.fromFile(file, allocator)) |rom| {
        const gen4_error = if (gen4.Game.fromRom(rom)) |game| {
            outputGen4Data(rom, game, stdout) catch |err| return stdoutWriteError(err);
            buf_stdout.flush() catch |err| return stdoutWriteError(err);
            return 0;
        } else |err| err;

        if (gen5.Game.fromRom(allocator, rom)) |game| {
            outputGen5Data(rom, game, stdout) catch |err| return stdoutWriteError(err);
            buf_stdout.flush() catch |err| return stdoutWriteError(err);
            return 0;
        } else |gen5_error| {
            debug.warn("Successfully loaded '{}' as a nds rom.\n", file_name);
            debug.warn("Failed to load '{}' as a gen4 game: {}\n", file_name, gen4_error);
            debug.warn("Failed to load '{}' as a gen5 game: {}\n", file_name, gen5_error);
            return 1;
        }
    } else |nds_error| {
        debug.warn("Failed to load '{}' as a gen3 game: {}\n", file_name, gen3_error);
        debug.warn("Failed to load '{}' as a gen4/gen5 game: {}\n", file_name, nds_error);
        return 1;
    }
}

fn stdoutWriteError(err: anyerror) u8 {
    debug.warn("Failed to write data to stdout: {}\n", err);
    return 1;
}

fn errPrint(comptime format_str: []const u8, args: ...) u8 {
    debug.warn(format_str, args);
    return 1;
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
                try stream.print(".pokemons[{}].tms[{}]={}\n", i, j, bits.isSet(u64, machine_learnset, @intCast(u6, j)));
            }
            while (j < game.tms.len + game.hms.len) : (j += 1) {
                try stream.print(".pokemons[{}].hms[{}]={}\n", i, j - game.tms.len, bits.isSet(u64, machine_learnset, @intCast(u6, j)));
            }
        }

        for (game.evolutions[i]) |evo, j| {
            if (evo.method == common.Evolution.Method.Unused)
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

fn outputGen4Data(rom: nds.Rom, game: gen4.Game, stream: var) !void {
    try stream.print(".version={}\n", @tagName(game.version));

    const null_index = mem.indexOfScalar(u8, rom.header.game_title, 0) orelse rom.header.game_title.len;
    try stream.print(".game_title={}\n", rom.header.game_title[0..null_index]);
    try stream.print(".gamecode={}\n", rom.header.gamecode);

    for (game.starters) |starter, i| {
        try stream.print(".starters[{}]={}\n", i, starter.value());
    }

    for (game.trainers.nodes.toSlice()) |node, i| {
        const trainer = nodeAsType(gen4.Trainer, node) catch continue;

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

        const party_file = nodeAsFile(parties[i]) catch continue;
        const party_data = party_file.data;
        var j: usize = 0;
        while (j < trainer.party_size) : (j += 1) {
            const base = switch (trainer.party_type) {
                gen4.PartyType.None => &(getGen4Member(gen4.PartyMemberNone, party_data, game.version, i) orelse break).base,
                gen4.PartyType.Item => &(getGen4Member(gen4.PartyMemberItem, party_data, game.version, i) orelse break).base,
                gen4.PartyType.Moves => &(getGen4Member(gen4.PartyMemberMoves, party_data, game.version, i) orelse break).base,
                gen4.PartyType.Both => &(getGen4Member(gen4.PartyMemberBoth, party_data, game.version, i) orelse break).base,
            };

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
        const move = nodeAsType(gen4.Move, node) catch continue;
        try stream.print(".moves[{}].category={}\n", i, @tagName(move.category));
        try stream.print(".moves[{}].power={}\n", i, move.power);
        try stream.print(".moves[{}].type={}\n", i, @tagName(move.@"type"));
        try stream.print(".moves[{}].accuracy={}\n", i, move.accuracy);
        try stream.print(".moves[{}].pp={}\n", i, move.pp);
    }

    for (game.pokemons.nodes.toSlice()) |node, i| {
        const pokemon = nodeAsType(gen4.BasePokemon, node) catch continue;
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
                try stream.print(".pokemons[{}].tms[{}]={}\n", i, j, bits.isSet(u128, machine_learnset, @intCast(u7, j)));
            }
            while (j < game.tms.len + game.hms.len) : (j += 1) {
                try stream.print(".pokemons[{}].hms[{}]={}\n", i, j - game.tms.len, bits.isSet(u128, machine_learnset, @intCast(u7, j)));
            }
        }

        const evos_file = try nodeAsFile(game.evolutions.nodes.toSlice()[i]);
        const evos = slice.bytesToSliceTrim(gen4.Evolution, evos_file.data);
        for (evos) |evo, j| {
            if (evo.method == gen4.Evolution.Method.Unused)
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
                const wild_mons = nodeAsType(gen4.DpptWildPokemons, node) catch continue;

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
                const wild_mons = nodeAsType(gen4.HgssWildPokemons, node) catch continue;
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

fn getGen4MemberBase(party_type: gen4.PartyType, data: []u8, version: common.Version, i: usize) ?*gen4.PartyMemberBase {}

fn getGen4Member(comptime T: type, data: []u8, version: common.Version, i: usize) ?*T {
    switch (version) {
        common.Version.Diamond,
        common.Version.Pearl,
        => {
            const party = slice.bytesToSliceTrim(T, data);
            if (party.len <= i)
                return null;

            return &party[i];
        },

        common.Version.Platinum,
        common.Version.HeartGold,
        common.Version.SoulSilver,
        => {
            const party = slice.bytesToSliceTrim(gen4.HgSsPlatMember(T), data);
            if (party.len <= i)
                return null;

            return &party[i].member;
        },

        else => unreachable,
    }
}

fn outputGen5Data(rom: nds.Rom, game: gen5.Game, stream: var) !void {
    try stream.print(".version={}\n", @tagName(game.version));

    const null_index = mem.indexOfScalar(u8, rom.header.game_title, 0) orelse rom.header.game_title.len;
    try stream.print(".game_title={}\n", rom.header.game_title[0..null_index]);
    try stream.print(".gamecode={}\n", rom.header.gamecode);

    for (game.starters) |starter_ptrs, i| {
        const first = starter_ptrs[0];
        for (starter_ptrs[1..]) |starter| {
            if (first.value() != starter.value())
                debug.warn("warning: all starter positions are not the same.\n");
        }

        try stream.print(".starters[{}]={}\n", i, first.value());
    }

    for (game.trainers.nodes.toSlice()) |node, i| {
        const trainer = nodeAsType(gen5.Trainer, node) catch continue;

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

        const party_file = nodeAsFile(parties[i]) catch continue;
        const party_data = party_file.data;
        var j: usize = 0;
        while (j < trainer.party_size) : (j += 1) {
            const base = switch (trainer.party_type) {
                gen5.PartyType.None => &(getGen5Member(gen5.PartyMemberNone, party_data, i) orelse break).base,
                gen5.PartyType.Item => &(getGen5Member(gen5.PartyMemberItem, party_data, i) orelse break).base,
                gen5.PartyType.Moves => &(getGen5Member(gen5.PartyMemberMoves, party_data, i) orelse break).base,
                gen5.PartyType.Both => &(getGen5Member(gen5.PartyMemberBoth, party_data, i) orelse break).base,
            };
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
        const move = nodeAsType(gen5.Move, node) catch continue;

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
            try stream.print(".moves[{}].stats_affected[{}]={}\n", i, j, stats_affected);

        const stats_affected_magnetude = move.stats_affected_magnetude;
        for (stats_affected_magnetude) |stat_affected_magnetude, j|
            try stream.print(".moves[{}].stats_affected_magnetude[{}]={}\n", i, j, stat_affected_magnetude);

        const stats_affected_chance = move.stats_affected_chance;
        for (stats_affected_chance) |stat_affected_chance, j|
            try stream.print(".moves[{}].stats_affected_chance[{}]={}\n", i, j, stat_affected_chance);
    }

    for (game.pokemons.nodes.toSlice()) |node, i| {
        const pokemon = nodeAsType(gen5.BasePokemon, node) catch continue;

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
                try stream.print(".pokemons[{}].tms[{}]={}\n", i, j, bits.isSet(u128, machine_learnset, @intCast(u7, j)));
            }
            while (j < game.tms1.len + game.hms.len) : (j += 1) {
                try stream.print(".pokemons[{}].hms[{}]={}\n", i, j - game.tms1.len, bits.isSet(u128, machine_learnset, @intCast(u7, j)));
            }
            while (j < game.tms2.len + game.hms.len + game.tms1.len) : (j += 1) {
                try stream.print(".pokemons[{}].tms[{}]={}\n", i, j - game.hms.len, bits.isSet(u128, machine_learnset, @intCast(u7, j)));
            }
        }

        if (game.evolutions.nodes.len <= i)
            continue;

        const evos_file = try nodeAsFile(game.evolutions.nodes.toSlice()[i]);
        const evos = slice.bytesToSliceTrim(gen5.Evolution, evos_file.data);
        for (evos) |evo, j| {
            if (evo.method == gen5.Evolution.Method.Unused)
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
        const wild_mons = nodeAsType(gen5.WildPokemons, node) catch continue;
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

fn getGen5Member(comptime T: type, data: []u8, i: usize) ?*T {
    const party = slice.bytesToSliceTrim(T, data);
    if (party.len <= i)
        return null;

    return &party[i];
}

fn nodeAsFile(node: nds.fs.Narc.Node) !*nds.fs.Narc.File {
    switch (node.kind) {
        nds.fs.Narc.Node.Kind.File => |file| return file,
        nds.fs.Narc.Node.Kind.Folder => return error.NotFile,
    }
}

fn nodeAsType(comptime T: type, node: nds.fs.Narc.Node) !*T {
    const file = try nodeAsFile(node);
    const data = slice.bytesToSliceTrim(T, file.data);
    return slice.at(data, 0) catch error.FileToSmall;
}
