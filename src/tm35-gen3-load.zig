const clap = @import("zig-clap");
const common = @import("tm35-common");
const fun = @import("fun-with-zig");
const gba = @import("gba.zig");
const gen3 = @import("gen3-types.zig");
const offsets = @import("gen3-offsets.zig");
const std = @import("std");

const bits = fun.bits;
const debug = std.debug;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;

const BufInStream = io.BufferedInStream(os.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(os.File.OutStream.Error);
const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = []Param{
    Param.flag(
        "display this help text and exit",
        Names.both("help"),
    ),
    Param.positional(""),
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

pub fn main() !void {
    const unbuf_stdout = &(try io.getStdOut()).outStream().stream;
    var buf_stdout = BufOutStream.init(unbuf_stdout);
    defer buf_stdout.flush() catch {};

    const stderr = &(try io.getStdErr()).outStream().stream;
    const stdout = &buf_stdout.stream;

    var direct_allocator = heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    var arena = heap.ArenaAllocator.init(&direct_allocator.allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const file_name = blk: {
        const poss = args.positionals();
        if (poss.len == 0) {
            usage(stderr) catch {};
            return error.NoFileProvided;
        }

        break :blk poss[0];
    };

    var game = blk: {
        var file = os.File.openRead(file_name) catch |err| {
            debug.warn("Couldn't open {}.\n", file_name);
            return err;
        };
        defer file.close();

        break :blk try gen3.Game.fromFile(file, allocator);
    };

    try outputGameData(game, stdout);
}

fn outputGameData(game: gen3.Game, stream: var) !void {
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
        try stream.print(".pokemons[{}].color={}\n", i, @tagName(pokemon.color));
        try stream.print(".pokemons[{}].flip={}\n", i, pokemon.flip);

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
        inline for ([][]const u8{
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
}
