const clap = @import("clap");
const common = @import("tm35-common");
const fun = @import("fun");
const gba = @import("gba.zig");
const gen5 = @import("gen5-types.zig");
const nds = @import("nds.zig");
const std = @import("std");

const bits = fun.bits;
const debug = std.debug;
const heap = std.heap;
const io = std.io;
const fs = std.fs;
const math = std.math;
const mem = std.mem;
const os = std.os;
const slice = fun.generic.slice;

const BufInStream = io.BufferedInStream(fs.File.InStream.Error);
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
        \\Usage: tm35-gen5-load [OPTION]... FILE
        \\Prints information about a generation 5 Pokemon rom to stdout in the
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

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
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

    var rom = blk: {
        var file = fs.File.openRead(file_name) catch |err| {
            debug.warn("Couldn't open {}.\n", file_name);
            return err;
        };
        defer file.close();

        break :blk try nds.Rom.fromFile(file, allocator);
    };

    const game = try gen5.Game.fromRom(allocator, rom);

    try outputGameData(rom, game, stdout);
}

pub fn outputGameData(rom: nds.Rom, game: gen5.Game, stream: var) !void {
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
            const base = getMemberBase(trainer.party_type, party_data, j) orelse break;
            try printMemberBase(stream, i, j, base);

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

fn printMemberBase(stream: var, i: usize, j: usize, member: *gen5.PartyMemberBase) !void {
    try stream.print(".trainers[{}].party[{}].iv={}\n", i, j, member.iv);
    try stream.print(".trainers[{}].party[{}].gender={}\n", i, j, member.gender_ability.gender);
    try stream.print(".trainers[{}].party[{}].ability={}\n", i, j, member.gender_ability.ability);
    try stream.print(".trainers[{}].party[{}].level={}\n", i, j, member.level);
    try stream.print(".trainers[{}].party[{}].species={}\n", i, j, member.species.value());
    try stream.print(".trainers[{}].party[{}].form={}\n", i, j, member.form.value());
}

fn nodeAsFile(node: nds.fs.Narc.Node) !*nds.fs.Narc.File {
    switch (node.kind) {
        nds.fs.Narc.Node.Kind.File => |file| return file,
        nds.fs.Narc.Node.Kind.Folder => return error.NotFile,
    }
}

fn nodeAsType(comptime T: type, node: nds.fs.Narc.Node) !*align(1) T {
    const file = try nodeAsFile(node);
    const data = slice.bytesToSliceTrim(T, file.data);
    return slice.at(data, 0) catch return error.FileToSmall;
}

fn getMemberBase(party_type: gen5.PartyType, data: []u8, i: usize) ?*gen5.PartyMemberBase {
    return switch (party_type) {
        gen5.PartyType.None => &(getMember(gen5.PartyMemberNone, data, i) orelse return null).base,
        gen5.PartyType.Item => &(getMember(gen5.PartyMemberItem, data, i) orelse return null).base,
        gen5.PartyType.Moves => &(getMember(gen5.PartyMemberMoves, data, i) orelse return null).base,
        gen5.PartyType.Both => &(getMember(gen5.PartyMemberBoth, data, i) orelse return null).base,
    };
}

fn getMember(comptime T: type, data: []u8, i: usize) ?*T {
    const party = slice.bytesToSliceTrim(T, data);
    if (party.len <= i)
        return null;

    return &party[i];
}
