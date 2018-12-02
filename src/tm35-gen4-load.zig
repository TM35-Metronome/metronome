const clap = @import("zig-clap");
const common = @import("tm35-common");
const fun = @import("fun-with-zig");
const gba = @import("gba.zig");
const gen4 = @import("gen4-types.zig");
const nds = @import("tm35-nds");
const std = @import("std");

const bits = fun.bits;
const debug = std.debug;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const slice = fun.generic.slice;

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
        \\Usage: tm35-gen4-load [OPTION]... FILE
        \\Prints information about a generation 4 Pokemon rom to stdout in the
        \\tm35 format.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    const stdout_file = std.io.getStdOut() catch return 1;
    const stderr_file = std.io.getStdErr() catch return 1;
    var stdout_out_stream = stdout_file.outStream();
    var stderr_out_stream = stderr_file.outStream();
    const stdout = &stdout_out_stream.stream;
    const stderr = &stderr_out_stream.stream;

    var direct_allocator_state = std.heap.DirectAllocator.init();
    const direct_allocator = &direct_allocator_state.allocator;
    defer direct_allocator_state.deinit();

    // TODO: Other allocator?
    const allocator = direct_allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    const iter = &arg_iter.iter;
    defer arg_iter.deinit();
    _ = iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator.Error, iter) catch |err| {
        debug.warn("error: {}\n", err);
        usage(stderr) catch {};
        return 1;
    };
    defer args.deinit();

    const file_name = blk: {
        const poss = args.positionals();
        if (poss.len == 0) {
            debug.warn("error: No file specified.");
            usage(stderr) catch {};
            return 1;
        }

        break :blk poss[0];
    };

    var buf_out_stream = io.BufferedOutStream(os.File.OutStream.Error).init(stdout);
    main2(allocator, args, file_name, &buf_out_stream.stream) catch |err| {
        debug.warn("error: {}\n", err);
        return 1;
    };
    buf_out_stream.flush() catch |err| {
        debug.warn("error: {}\n", err);
        return 1;
    };

    return 0;
}

pub fn main2(allocator: *mem.Allocator, args: Clap, file_name: []const u8, stream: var) !void {
    if (args.flag("--help"))
        return try usage(stream);

    var rom = blk: {
        var file = os.File.openRead(file_name) catch |err| {
            debug.warn("Couldn't open {}.\n", file_name);
            return err;
        };
        defer file.close();

        break :blk try nds.Rom.fromFile(file, allocator);
    };
    defer rom.deinit();

    const game = try gen4.Game.fromRom(rom);

    try stream.print(".version={}\n", @tagName(game.version));

    const null_index = mem.indexOfScalar(u8, rom.header.game_title, 0) orelse rom.header.game_title.len;
    try stream.print(".game_title={}\n", rom.header.game_title[0..null_index]);
    try stream.print(".gamecode={}\n", rom.header.gamecode);

    for (game.trainers.nodes.toSlice()) |node, i| {
        const trainer = nodeAsType(gen4.Trainer, node) catch continue;

        try stream.print(".trainers[{}].class={}\n", i, trainer.class);
        try stream.print(".trainers[{}].battle_type={}\n", i, trainer.battle_type);
        try stream.print(".trainers[{}].battle_type2={}\n", i, trainer.battle_type2);
        try stream.print(".trainers[{}].ai={}\n", i, trainer.ai.value());

        for (trainer.items) |item, j| {
            try stream.print(".trainers[{}].items[{}]={}\n", i, j, item.value());
        }

        const parties = game.trainers.nodes.toSlice();
        if (parties.len <= i)
            continue;

        const party_file = nodeAsFile(parties[i]) catch continue;
        const party_data = party_file.data;
        switch (trainer.party_type) {
            gen4.PartyType.None => {
                var j: usize = 0;
                while (j < trainer.party_size) : (j += 1) {
                    const member = getMember(gen4.PartyMemberNone, party_data, game.version, j) orelse break;
                    try printMemberBase(stream, i, j, member.base);
                }
            },
            gen4.PartyType.Item => {
                var j: usize = 0;
                while (j < trainer.party_size) : (j += 1) {
                    const member = getMember(gen4.PartyMemberItem, party_data, game.version, j) orelse break;
                    try printMemberBase(stream, i, j, member.base);
                    try stream.print(".trainers[{}].party[{}].item={}\n", i, j, member.item.value());
                }
            },
            gen4.PartyType.Moves => {
                var j: usize = 0;
                while (j < trainer.party_size) : (j += 1) {
                    const member = getMember(gen4.PartyMemberMoves, party_data, game.version, j) orelse break;
                    try printMemberBase(stream, i, j, member.base);
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", i, j, k, move.value());
                    }
                }
            },
            gen4.PartyType.Both => {
                var j: usize = 0;
                while (j < trainer.party_size) : (j += 1) {
                    const member = getMember(gen4.PartyMemberBoth, party_data, game.version, j) orelse break;
                    try printMemberBase(stream, i, j, member.base);
                    try stream.print(".trainers[{}].party[{}].item={}\n", i, j, member.item.value());
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", i, j, k, move.value());
                    }
                }
            },
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
                try stream.print(".zones[{}].wild.grass.pokemons[{}].species={}\n", i, j, grass.species.value());
            }

            inline for ([][]const u8{
                "swarm_replacements",
                "day_replacements",
                "night_replacements",
                "radar_replacements",
                "unknown_replacements",
                "gba_replacements",
            }) |area_name| {
                for (@field(wild_mons, area_name)) |replacement, k| {
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", i, area_name, k, replacement.species.value());
                }
            }

            inline for ([][]const u8{
                "surf",
                "sea_unknown",
                "old_rod",
                "good_rod",
                "super_rod",
            }) |area_name| {
                for (@field(wild_mons, area_name)) |sea, k| {
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", i, area_name, k, sea.min_level);
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", i, area_name, k, sea.max_level);
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", i, area_name, k, sea.species.value());
                }
            }
        },

        common.Version.HeartGold,
        common.Version.SoulSilver,
        => {
            const wild_mons = nodeAsType(gen4.HgssWildPokemons, node) catch continue;
            inline for ([][]const u8{
                "grass_morning",
                "grass_day",
                "grass_night",
            }) |area_name| {
                try stream.print(".zones[{}].wild.{}.encounter_rate={}\n", i, area_name, wild_mons.grass_rate);
                for (@field(wild_mons, area_name)) |species, j| {
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", i, area_name, j, wild_mons.grass_levels[j]);
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", i, area_name, j, wild_mons.grass_levels[j]);
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", i, area_name, j, species.value());
                }
            }

            inline for ([][]const u8{
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
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", i, area_name, k, sea.species.value());
                }
            }

            // TODO: radio, swarm
        },

        else => unreachable,
    };
}

fn printMemberBase(stream: var, i: usize, j: usize, member: gen4.PartyMemberBase) !void {
    try stream.print(".trainers[{}].party[{}].iv={}\n", i, j, member.iv);
    try stream.print(".trainers[{}].party[{}].gender={}\n", i, j, member.gender);
    try stream.print(".trainers[{}].party[{}].ability={}\n", i, j, member.ability);
    try stream.print(".trainers[{}].party[{}].level={}\n", i, j, member.level.value());
    try stream.print(".trainers[{}].party[{}].species={}\n", i, j, member.species);
    try stream.print(".trainers[{}].party[{}].form={}\n", i, j, member.form);
}

fn getMember(comptime T: type, data: []const u8, version: common.Version, i: usize) ?T {
    switch (version) {
        common.Version.Diamond,
        common.Version.Pearl,
        => {
            const party = slice.bytesToSliceTrim(T, data);
            if (party.len <= i)
                return null;

            return party[i];
        },

        common.Version.Platinum,
        common.Version.HeartGold,
        common.Version.SoulSilver,
        => {
            const party = slice.bytesToSliceTrim(gen4.HgSsPlatMember(T), data);
            if (party.len <= i)
                return null;

            return party[i].member;
        },

        else => unreachable,
    }
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
