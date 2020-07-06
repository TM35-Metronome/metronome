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

const gba = rom.gba;
const nds = rom.nds;

const bit = util.bit;
const errors = util.errors;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

const params = [_]Param{
    clap.parseParam("-h, --help     Display this help text and exit.    ") catch unreachable,
    clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
    Param{ .takes_value = true },
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-gen3-disassemble-scripts");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Finds all scripts in a generation 3 Pokemon game, disassembles them
        \\and writes them to stdout.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

pub fn main() u8 {
    var stdio = util.getStdIo();
    defer stdio.err.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(&arena.allocator) catch
        return errors.allocErr(stdio.err.outStream());
    const res = main2(
        &arena.allocator,
        util.StdIo.In.InStream,
        util.StdIo.Out.OutStream,
        stdio.streams(),
        clap.args.OsIterator,
        &arg_iter,
    );

    stdio.out.flush() catch |err| return errors.writeErr(stdio.err.outStream(), "<stdout>", err);
    return res;
}

pub fn main2(
    allocator: *mem.Allocator,
    comptime InStream: type,
    comptime OutStream: type,
    stdio: util.CustomStdIoStreams(InStream, OutStream),
    comptime ArgIterator: type,
    arg_iter: *ArgIterator,
) u8 {
    var args = Clap.parse(allocator, ArgIterator, arg_iter) catch |err| {
        stdio.err.print("{}\n", .{err}) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    if (args.flag("--help")) {
        usage(stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.print("{}\n", .{program_version}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else {
        stdio.err.writeAll("No file provided\n") catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const file = fs.cwd().openFile(file_name, .{}) catch |err| return errors.openErr(stdio.err, file_name, err);
    defer file.close();

    const gen3_error = if (gen3.Game.fromFile(file, allocator)) |*game| {
        defer game.deinit();
        outputGen3Data(game.*, stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    } else |err| err;

    file.seekTo(0) catch |err| return errors.readErr(stdio.err, file_name, err);
    if (nds.Rom.fromFile(file, allocator)) |*nds_rom| {
        const gen4_error = if (gen4.Game.fromRom(allocator, nds_rom)) |*game| {
            defer game.deinit();
            outputGen4Data(nds_rom.*, game.*, stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            return 0;
        } else |err| err;

        const gen5_error = if (gen5.Game.fromRom(allocator, nds_rom)) |*game| {
            defer game.deinit();
            outputGen5Data(nds_rom.*, game.*, stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
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

fn outputGen3Data(game: gen3.Game, stream: var) !void {
    try stream.print(".version={}\n", .{@tagName(game.version)});
    try stream.print(".game_title={}\n", .{game.header.game_title});
    try stream.print(".gamecode={}\n", .{game.header.gamecode});

    for (game.starters) |starter, i| {
        if (starter.value() != game.starters_repeat[i].value())
            debug.warn("warning: repeated starters don't match.\n", .{});

        try stream.print(".starters[{}]={}\n", .{ i, starter.value() });
    }

    for (game.trainers) |trainer, i| {
        // The party type is infered from the party data.
        // try stream.print(".trainers[{}].party_type={}\n", .{i, trainer.party_type});
        try stream.print(".trainers[{}].class={}\n", .{ i, trainer.class });
        try stream.print(".trainers[{}].encounter_music={}\n", .{ i, trainer.encounter_music });
        try stream.print(".trainers[{}].trainer_picture={}\n", .{ i, trainer.trainer_picture });
        try stream.print(".trainers[{}].name=", .{i});
        try gen3.encodings.decode(.en_us, &trainer.name, stream);
        try stream.writeByte('\n');

        for (trainer.items) |item, j| {
            try stream.print(".trainers[{}].items[{}]={}\n", .{ i, j, item.value() });
        }

        try stream.print(".trainers[{}].is_double={}\n", .{ i, trainer.is_double.value() });
        try stream.print(".trainers[{}].ai={}\n", .{ i, trainer.ai.value() });

        switch (trainer.party_type) {
            .none => {
                for (try trainer.party.none.toSlice(game.data)) |member, j| {
                    try stream.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, member.base.iv.value() });
                    try stream.print(".trainers[{}].party[{}].level={}\n", .{ i, j, member.base.level.value() });
                    try stream.print(".trainers[{}].party[{}].species={}\n", .{ i, j, member.base.species.value() });
                }
            },
            .item => {
                for (try trainer.party.item.toSlice(game.data)) |member, j| {
                    try stream.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, member.base.iv.value() });
                    try stream.print(".trainers[{}].party[{}].level={}\n", .{ i, j, member.base.level.value() });
                    try stream.print(".trainers[{}].party[{}].species={}\n", .{ i, j, member.base.species.value() });
                    try stream.print(".trainers[{}].party[{}].item={}\n", .{ i, j, member.item.value() });
                }
            },
            .moves => {
                for (try trainer.party.moves.toSlice(game.data)) |member, j| {
                    try stream.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, member.base.iv.value() });
                    try stream.print(".trainers[{}].party[{}].level={}\n", .{ i, j, member.base.level.value() });
                    try stream.print(".trainers[{}].party[{}].species={}\n", .{ i, j, member.base.species.value() });
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ i, j, k, move.value() });
                    }
                }
            },
            .both => {
                for (try trainer.party.both.toSlice(game.data)) |member, j| {
                    try stream.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, member.base.iv.value() });
                    try stream.print(".trainers[{}].party[{}].level={}\n", .{ i, j, member.base.level.value() });
                    try stream.print(".trainers[{}].party[{}].species={}\n", .{ i, j, member.base.species.value() });
                    try stream.print(".trainers[{}].party[{}].item={}\n", .{ i, j, member.item.value() });
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ i, j, k, move.value() });
                    }
                }
            },
        }
    }

    for (game.moves) |move, i| {
        try stream.print(".moves[{}].effect={}\n", .{ i, move.effect });
        try stream.print(".moves[{}].power={}\n", .{ i, move.power });
        try stream.print(".moves[{}].type={}\n", .{ i, @tagName(move.@"type") });
        try stream.print(".moves[{}].accuracy={}\n", .{ i, move.accuracy });
        try stream.print(".moves[{}].pp={}\n", .{ i, move.pp });
        try stream.print(".moves[{}].side_effect_chance={}\n", .{ i, move.side_effect_chance });
        try stream.print(".moves[{}].target={}\n", .{ i, move.target });
        try stream.print(".moves[{}].priority={}\n", .{ i, move.priority });
        try stream.print(".moves[{}].flags={}\n", .{ i, move.flags.value() });
    }

    for (game.pokemons) |pokemon, i| {
        try stream.print(".pokemons[{}].stats.hp={}\n", .{ i, pokemon.stats.hp });
        try stream.print(".pokemons[{}].stats.attack={}\n", .{ i, pokemon.stats.attack });
        try stream.print(".pokemons[{}].stats.defense={}\n", .{ i, pokemon.stats.defense });
        try stream.print(".pokemons[{}].stats.speed={}\n", .{ i, pokemon.stats.speed });
        try stream.print(".pokemons[{}].stats.sp_attack={}\n", .{ i, pokemon.stats.sp_attack });
        try stream.print(".pokemons[{}].stats.sp_defense={}\n", .{ i, pokemon.stats.sp_defense });

        for (pokemon.types) |t, j| {
            try stream.print(".pokemons[{}].types[{}]={}\n", .{ i, j, @tagName(t) });
        }

        try stream.print(".pokemons[{}].catch_rate={}\n", .{ i, pokemon.catch_rate });
        try stream.print(".pokemons[{}].base_exp_yield={}\n", .{ i, pokemon.base_exp_yield });
        try stream.print(".pokemons[{}].ev_yield.hp={}\n", .{ i, pokemon.ev_yield.hp });
        try stream.print(".pokemons[{}].ev_yield.attack={}\n", .{ i, pokemon.ev_yield.attack });
        try stream.print(".pokemons[{}].ev_yield.defense={}\n", .{ i, pokemon.ev_yield.defense });
        try stream.print(".pokemons[{}].ev_yield.speed={}\n", .{ i, pokemon.ev_yield.speed });
        try stream.print(".pokemons[{}].ev_yield.sp_attack={}\n", .{ i, pokemon.ev_yield.sp_attack });
        try stream.print(".pokemons[{}].ev_yield.sp_defense={}\n", .{ i, pokemon.ev_yield.sp_defense });

        for (pokemon.items) |item, j| {
            try stream.print(".pokemons[{}].items[{}]={}\n", .{ i, j, item.value() });
        }

        try stream.print(".pokemons[{}].gender_ratio={}\n", .{ i, pokemon.gender_ratio });
        try stream.print(".pokemons[{}].egg_cycles={}\n", .{ i, pokemon.egg_cycles });
        try stream.print(".pokemons[{}].base_friendship={}\n", .{ i, pokemon.base_friendship });
        try stream.print(".pokemons[{}].growth_rate={}\n", .{ i, @tagName(pokemon.growth_rate) });
        try stream.print(".pokemons[{}].egg_groups[{}]={}\n", .{ i, @as(usize, 0), @tagName(pokemon.egg_group1) });
        try stream.print(".pokemons[{}].egg_groups[{}]={}\n", .{ i, @as(usize, 1), @tagName(pokemon.egg_group2) });

        for (pokemon.abilities) |ability, j| {
            try stream.print(".pokemons[{}].abilities[{}]={}\n", .{ i, j, ability });
        }

        try stream.print(".pokemons[{}].safari_zone_rate={}\n", .{ i, pokemon.safari_zone_rate });
        try stream.print(".pokemons[{}].color={}\n", .{ i, @tagName(pokemon.color.color) });
        try stream.print(".pokemons[{}].flip={}\n", .{ i, pokemon.color.flip });
    }

    for (game.evolutions) |evos, i| {
        for (evos) |evo, j| {
            if (evo.method == .unused)
                continue;
            try stream.print(".pokemons[{}].evos[{}].method={}\n", .{ i, j, @tagName(evo.method) });
            try stream.print(".pokemons[{}].evos[{}].param={}\n", .{ i, j, evo.param.value() });
            try stream.print(".pokemons[{}].evos[{}].target={}\n", .{ i, j, evo.target.value() });
        }
    }

    for (game.level_up_learnset_pointers) |lvl_up_learnset, i| {
        const learnset = try lvl_up_learnset.toSliceEnd(game.data);
        for (learnset) |l, j| {
            if (std.meta.eql(l, gen3.LevelUpMove.term))
                break;
            try stream.print(".pokemons[{}].moves[{}].id={}\n", .{ i, j, l.id });
            try stream.print(".pokemons[{}].moves[{}].level={}\n", .{ i, j, l.level });
        }
    }

    for (game.machine_learnsets) |machine_learnset, i| {
        var j: usize = 0;
        while (j < game.tms.len) : (j += 1)
            try stream.print(".pokemons[{}].tms[{}]={}\n", .{ i, j, bit.isSet(u64, machine_learnset.value(), @intCast(u6, j)) });
        while (j < game.tms.len + game.hms.len) : (j += 1)
            try stream.print(".pokemons[{}].hms[{}]={}\n", .{ i, j - game.tms.len, bit.isSet(u64, machine_learnset.value(), @intCast(u6, j)) });
    }

    for (game.pokemon_names) |name, i| {
        try stream.print(".pokemons[{}].name=", .{i});
        try gen3.encodings.decode(.en_us, &name, stream);
        try stream.writeByte('\n');
    }

    for (game.tms) |tm, i| {
        try stream.print(".tms[{}]={}\n", .{ i, tm.value() });
    }

    for (game.hms) |hm, i| {
        try stream.print(".hms[{}]={}\n", .{ i, hm.value() });
    }

    for (game.items) |item, i| {
        const pocket = switch (game.version) {
            .ruby, .sapphire, .emerald => @tagName(item.pocket.rse),
            .fire_red, .leaf_green => @tagName(item.pocket.frlg),
            else => unreachable,
        };

        try stream.print(".items[{}].name=", .{i});
        try gen3.encodings.decode(.en_us, &item.name, stream);
        try stream.writeByte('\n');
        try stream.print(".items[{}].id={}\n", .{ i, item.id.value() });
        try stream.print(".items[{}].price={}\n", .{ i, item.price.value() });
        try stream.print(".items[{}].hold_effect={}\n", .{ i, item.hold_effect });
        try stream.print(".items[{}].hold_effect_par={}\n", .{ i, item.hold_effect_param });
        // try stream.print(".items[{}].description={}\n", .{i, item.description});
        try stream.print(".items[{}].importance={}\n", .{ i, item.importance });
        // try stream.print(".items[{}].unknown={}\n", .{i, item.unknown});
        try stream.print(".items[{}].pocket={}\n", .{ i, pocket });
        try stream.print(".items[{}].type={}\n", .{ i, item.@"type" });
        // try stream.print(".items[{}].field_use_func={}\n", .{i, item.field_use_func});
        try stream.print(".items[{}].battle_usage={}\n", .{ i, item.battle_usage.value() });
        //try stream.print(".items[{}].battle_use_func={}\n", .{i, item.battle_use_func});
        try stream.print(".items[{}].secondary_id={}\n", .{ i, item.secondary_id.value() });
    }

    for (game.wild_pokemon_headers) |header, i| {
        if (header.land.toPtr(game.data)) |land| {
            const wilds = try land.wild_pokemons.toPtr(game.data);
            try outputGen3Area(stream, i, "land", land.encounter_rate, wilds);
        } else |_| {}
        if (header.surf.toPtr(game.data)) |surf| {
            const wilds = try surf.wild_pokemons.toPtr(game.data);
            try outputGen3Area(stream, i, "surf", surf.encounter_rate, wilds);
        } else |_| {}
        if (header.rock_smash.toPtr(game.data)) |rock| {
            const wilds = try rock.wild_pokemons.toPtr(game.data);
            try outputGen3Area(stream, i, "rock_smash", rock.encounter_rate, wilds);
        } else |_| {}
        if (header.fishing.toPtr(game.data)) |fish| {
            const wilds = try fish.wild_pokemons.toPtr(game.data);
            try outputGen3Area(stream, i, "fishing", fish.encounter_rate, wilds);
        } else |_| {}
    }

    for (game.static_pokemons) |static_mon, i| {
        const data = static_mon.data();
        try stream.print(".static_pokemons[{}].species={}\n", .{ i, data.setwildbattle.species.value() });
        try stream.print(".static_pokemons[{}].level={}\n", .{ i, data.setwildbattle.level });
        try stream.print(".static_pokemons[{}].item={}\n", .{ i, data.setwildbattle.item.value() });
    }

    for (game.pokeball_items) |given_item, i| {
        try stream.print(".pokeball_items[{}].item={}\n", .{ i, given_item.item.value() });
        try stream.print(".pokeball_items[{}].amount={}\n", .{ i, given_item.amount.value() });
    }

    for (game.text) |text_ptr, i| {
        const text = try text_ptr.toSliceZ(game.data);
        try stream.print(".text[{}]=", .{i});
        try gen3.encodings.decode(.en_us, text, stream);
        try stream.writeByte('\n');
    }
}

fn outputGen3Area(stream: var, i: usize, name: []const u8, rate: u8, wilds: []const gen3.WildPokemon) !void {
    try stream.print(".zones[{}].wild.{}.encounter_rate={}\n", .{ i, name, rate });
    for (wilds) |pokemon, j| {
        try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", .{ i, name, j, pokemon.min_level });
        try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", .{ i, name, j, pokemon.max_level });
        try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", .{ i, name, j, pokemon.species.value() });
    }
}

fn outputGen4Data(nds_rom: nds.Rom, game: gen4.Game, stream: var) !void {
    try stream.print(".version={}\n", .{@tagName(game.version)});

    const header = nds_rom.header();
    const null_index = mem.indexOfScalar(u8, &header.game_title, 0) orelse header.game_title.len;
    try stream.print(".game_title={}\n", .{header.game_title[0..null_index]});
    try stream.print(".gamecode={}\n", .{header.gamecode});

    for (game.starters) |starter, i| {
        try stream.print(".starters[{}]={}\n", .{ i, starter.value() });
    }

    for (game.trainers) |trainer, i| {
        try stream.print(".trainers[{}].class={}\n", .{ i, trainer.class });
        try stream.print(".trainers[{}].battle_type={}\n", .{ i, trainer.battle_type });
        try stream.print(".trainers[{}].battle_type2={}\n", .{ i, trainer.battle_type2 });
        try stream.print(".trainers[{}].ai={}\n", .{ i, trainer.ai.value() });

        for (trainer.items) |item, j| {
            try stream.print(".trainers[{}].items[{}]={}\n", .{ i, j, item.value() });
        }

        const parties = game.parties;
        if (parties.fat.len <= i)
            continue;

        const party_data = parties.fileData(.{ .i = @intCast(u32, i) });
        var j: usize = 0;
        while (j < trainer.party_size) : (j += 1) {
            const base = trainer.partyMember(game.version, party_data, i) orelse continue;
            try stream.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, base.iv });
            try stream.print(".trainers[{}].party[{}].gender={}\n", .{ i, j, base.gender_ability.gender });
            try stream.print(".trainers[{}].party[{}].ability={}\n", .{ i, j, base.gender_ability.ability });
            try stream.print(".trainers[{}].party[{}].level={}\n", .{ i, j, base.level.value() });
            try stream.print(".trainers[{}].party[{}].species={}\n", .{ i, j, base.species.value() });

            switch (trainer.party_type) {
                .none => {},
                .item => {
                    const member = base.toParent(gen4.PartyMemberItem);
                    try stream.print(".trainers[{}].party[{}].item={}\n", .{ i, j, member.item.value() });
                },
                .moves => {
                    const member = base.toParent(gen4.PartyMemberMoves);
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ i, j, k, move.value() });
                    }
                },
                .both => {
                    const member = base.toParent(gen4.PartyMemberBoth);
                    try stream.print(".trainers[{}].party[{}].item={}\n", .{ i, j, member.item.value() });
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ i, j, k, move.value() });
                    }
                },
            }
        }
    }

    for (game.moves) |move, i| {
        try stream.print(".moves[{}].category={}\n", .{ i, @tagName(move.category) });
        try stream.print(".moves[{}].power={}\n", .{ i, move.power });
        try stream.print(".moves[{}].type={}\n", .{ i, @tagName(move.@"type") });
        try stream.print(".moves[{}].accuracy={}\n", .{ i, move.accuracy });
        try stream.print(".moves[{}].pp={}\n", .{ i, move.pp });
    }

    for (game.pokemons) |pokemon, i| {
        try stream.print(".pokemons[{}].stats.hp={}\n", .{ i, pokemon.stats.hp });
        try stream.print(".pokemons[{}].stats.attack={}\n", .{ i, pokemon.stats.attack });
        try stream.print(".pokemons[{}].stats.defense={}\n", .{ i, pokemon.stats.defense });
        try stream.print(".pokemons[{}].stats.speed={}\n", .{ i, pokemon.stats.speed });
        try stream.print(".pokemons[{}].stats.sp_attack={}\n", .{ i, pokemon.stats.sp_attack });
        try stream.print(".pokemons[{}].stats.sp_defense={}\n", .{ i, pokemon.stats.sp_defense });

        for (pokemon.types) |t, j| {
            try stream.print(".pokemons[{}].types[{}]={}\n", .{ i, j, @tagName(t) });
        }

        try stream.print(".pokemons[{}].catch_rate={}\n", .{ i, pokemon.catch_rate });
        try stream.print(".pokemons[{}].base_exp_yield={}\n", .{ i, pokemon.base_exp_yield });
        try stream.print(".pokemons[{}].ev_yield.hp={}\n", .{ i, pokemon.ev_yield.hp });
        try stream.print(".pokemons[{}].ev_yield.attack={}\n", .{ i, pokemon.ev_yield.attack });
        try stream.print(".pokemons[{}].ev_yield.defense={}\n", .{ i, pokemon.ev_yield.defense });
        try stream.print(".pokemons[{}].ev_yield.speed={}\n", .{ i, pokemon.ev_yield.speed });
        try stream.print(".pokemons[{}].ev_yield.sp_attack={}\n", .{ i, pokemon.ev_yield.sp_attack });
        try stream.print(".pokemons[{}].ev_yield.sp_defense={}\n", .{ i, pokemon.ev_yield.sp_defense });

        for (pokemon.items) |item, j| {
            try stream.print(".pokemons[{}].items[{}]={}\n", .{ i, j, item.value() });
        }

        try stream.print(".pokemons[{}].gender_ratio={}\n", .{ i, pokemon.gender_ratio });
        try stream.print(".pokemons[{}].egg_cycles={}\n", .{ i, pokemon.egg_cycles });
        try stream.print(".pokemons[{}].base_friendship={}\n", .{ i, pokemon.base_friendship });
        try stream.print(".pokemons[{}].growth_rate={}\n", .{ i, @tagName(pokemon.growth_rate) });
        try stream.print(".pokemons[{}].egg_groups[{}]={}\n", .{ i, @as(usize, 0), @tagName(pokemon.egg_group1) });
        try stream.print(".pokemons[{}].egg_groups[{}]={}\n", .{ i, @as(usize, 1), @tagName(pokemon.egg_group2) });

        for (pokemon.abilities) |ability, j| {
            try stream.print(".pokemons[{}].abilities[{}]={}\n", .{ i, j, ability });
        }

        try stream.print(".pokemons[{}].flee_rate={}\n", .{ i, pokemon.flee_rate });
        try stream.print(".pokemons[{}].color={}\n", .{ i, @tagName(pokemon.color.color) });
        try stream.print(".pokemons[{}].flip={}\n", .{ i, pokemon.color.flip });

        const machine_learnset = pokemon.machine_learnset.value();
        var j: usize = 0;
        while (j < game.tms.len) : (j += 1)
            try stream.print(".pokemons[{}].tms[{}]={}\n", .{ i, j, bit.isSet(u128, machine_learnset, @intCast(u7, j)) });
        while (j < game.tms.len + game.hms.len) : (j += 1)
            try stream.print(".pokemons[{}].hms[{}]={}\n", .{ i, j - game.tms.len, bit.isSet(u128, machine_learnset, @intCast(u7, j)) });
    }

    {
        var i: usize = 0;
        while (i < game.evolutions.fat.len) : (i += 1) {
            const bytes = game.evolutions.fileData(.{ .i = @intCast(u32, i) });
            const rem = bytes.len % @sizeOf(gen4.Evolution);
            const evos = mem.bytesAsSlice(gen4.Evolution, bytes[0 .. bytes.len - rem]);
            for (evos) |evo, j| {
                if (evo.method == .unused)
                    continue;
                try stream.print(".pokemons[{}].evos[{}].method={}\n", .{ i, j, @tagName(evo.method) });
                try stream.print(".pokemons[{}].evos[{}].param={}\n", .{ i, j, evo.param.value() });
                try stream.print(".pokemons[{}].evos[{}].target={}\n", .{ i, j, evo.target.value() });
            }
        }
    }

    {
        var i: usize = 0;
        while (i < game.level_up_moves.fat.len) : (i += 1) {
            const bytes = game.level_up_moves.fileData(.{ .i = @intCast(u32, i) });
            const rem = bytes.len % @sizeOf(gen4.LevelUpMove);
            const level_up_moves = mem.bytesAsSlice(gen4.LevelUpMove, bytes[0 .. bytes.len - rem]);
            for (level_up_moves) |move, j| {
                try stream.print(".pokemons[{}].moves[{}].id={}\n", .{ i, j, move.id });
                try stream.print(".pokemons[{}].moves[{}].level={}\n", .{ i, j, move.level });
            }
        }
    }

    for (game.tms) |tm, i|
        try stream.print(".tms[{}]={}\n", .{ i, tm.value() });
    for (game.hms) |hm, i|
        try stream.print(".hms[{}]={}\n", .{ i, hm.value() });

    for (game.items) |item, i| {
        var pocket = item.pocket;
        var i_2 = i;

        try stream.print(".items[{}].price={}\n", .{ i, item.price.value() });
        try stream.print(".items[{}].battle_effect={}\n", .{ i, item.battle_effect }); // TODO: Is this the same as gen3 hold_effect?
        try stream.print(".items[{}].gain={}\n", .{ i, item.gain });
        try stream.print(".items[{}].berry={}\n", .{ i, item.berry });
        try stream.print(".items[{}].fling_effect={}\n", .{ i, item.fling_effect });
        try stream.print(".items[{}].fling_power={}\n", .{ i, item.fling_power });
        try stream.print(".items[{}].natural_gift_power={}\n", .{ i, item.natural_gift_power });
        try stream.print(".items[{}].flag={}\n", .{ i, item.flag });
        try stream.print(".items[{}].pocket={}\n", .{ i, @tagName(item.pocket) });
        try stream.print(".items[{}].type={}\n", .{ i, item.type });
        try stream.print(".items[{}].category={}\n", .{ i, item.category });
        try stream.print(".items[{}].category2={}\n", .{ i, item.category2.value() });
        try stream.print(".items[{}].index={}\n", .{ i, item.index });
        //try stream.print(".items[{}].statboosts.hp={}\n", .{ i, item.statboosts.hp });
        //try stream.print(".items[{}].statboosts.level={}\n", .{ i, item.statboosts.level });
        //try stream.print(".items[{}].statboosts.evolution={}\n", .{ i, item.statboosts.evolution });
        //try stream.print(".items[{}].statboosts.attack={}\n", .{ i, item.statboosts.attack });
        //try stream.print(".items[{}].statboosts.defense={}\n", .{ i, item.statboosts.defense });
        //try stream.print(".items[{}].statboosts.sp_attack={}\n", .{ i, item.statboosts.sp_attack });
        //try stream.print(".items[{}].statboosts.sp_defense={}\n", .{ i, item.statboosts.sp_defense });
        //try stream.print(".items[{}].statboosts.speed={}\n", .{ i, item.statboosts.speed });
        //try stream.print(".items[{}].statboosts.accuracy={}\n", .{ i, item.statboosts.accuracy });
        //try stream.print(".items[{}].statboosts.crit={}\n", .{ i, item.statboosts.crit });
        //try stream.print(".items[{}].statboosts.pp={}\n", .{ i, item.statboosts.pp });
        //try stream.print(".items[{}].statboosts.target={}\n", .{ i, item.statboosts.target });
        //try stream.print(".items[{}].statboosts.target2={}\n", .{ i, item.statboosts.target2 });
        try stream.print(".items[{}].ev_yield.hp={}\n", .{ i, item.ev_yield.hp });
        try stream.print(".items[{}].ev_yield.attack={}\n", .{ i, item.ev_yield.attack });
        try stream.print(".items[{}].ev_yield.defense={}\n", .{ i, item.ev_yield.defense });
        try stream.print(".items[{}].ev_yield.speed={}\n", .{ i, item.ev_yield.speed });
        try stream.print(".items[{}].ev_yield.sp_attack={}\n", .{ i, item.ev_yield.sp_attack });
        try stream.print(".items[{}].ev_yield.sp_defense={}\n", .{ i, item.ev_yield.sp_defense });
        try stream.print(".items[{}].hp_restore={}\n", .{ i, item.hp_restore });
        try stream.print(".items[{}].pp_restore={}\n", .{ i, item.pp_restore });
    }

    switch (game.version) {
        .diamond,
        .pearl,
        .platinum,
        => for (game.wild_pokemons.dppt) |wild_mons, i| {
            try stream.print(".zones[{}].wild.grass.encounter_rate={}\n", .{ i, wild_mons.grass_rate.value() });
            for (wild_mons.grass) |grass, j| {
                try stream.print(".zones[{}].wild.grass.pokemons[{}].min_level={}\n", .{ i, j, grass.level });
                try stream.print(".zones[{}].wild.grass.pokemons[{}].max_level={}\n", .{ i, j, grass.level });
                try stream.print(".zones[{}].wild.grass.pokemons[{}].species={}\n", .{ i, j, grass.species.value() });
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
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", .{ i, area_name, k, replacement.species.value() });
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
                try stream.print(".zones[{}].wild.{}.encounter_rate={}\n", .{ i, area_name, @field(wild_mons, area_name).rate.value() });
                for (@field(wild_mons, area_name).mons) |sea, k| {
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", .{ i, area_name, k, sea.min_level });
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", .{ i, area_name, k, sea.max_level });
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", .{ i, area_name, k, sea.species.value() });
                }
            }
        },

        .heart_gold,
        .soul_silver,
        => for (game.wild_pokemons.hgss) |wild_mons, i| {
            // TODO: Get rid of inline for in favor of a function to call
            inline for ([_][]const u8{
                "grass_morning",
                "grass_day",
                "grass_night",
            }) |area_name| {
                try stream.print(".zones[{}].wild.{}.encounter_rate={}\n", .{ i, area_name, wild_mons.grass_rate });
                for (@field(wild_mons, area_name)) |species, j| {
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", .{ i, area_name, j, wild_mons.grass_levels[j] });
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", .{ i, area_name, j, wild_mons.grass_levels[j] });
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", .{ i, area_name, j, species.value() });
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
                try stream.print(".zones[{}].wild.{}.encounter_rate={}\n", .{ i, area_name, wild_mons.sea_rates[j] });
                for (@field(wild_mons, area_name)) |sea, k| {
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", .{ i, area_name, k, sea.min_level });
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", .{ i, area_name, k, sea.max_level });
                    try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", .{ i, area_name, k, sea.species.value() });
                }
            }

            // TODO: radio, swarm
        },

        else => unreachable,
    }

    for (game.static_pokemons) |static_mon, i| {
        const data = static_mon.data();
        try stream.print(".static_pokemons[{}].species={}\n", .{ i, data.wild_battle.species.value() });
        try stream.print(".static_pokemons[{}].level={}\n", .{ i, data.wild_battle.level.value() });
    }

    for (game.pokeball_items) |given_item, i| {
        try stream.print(".pokeball_items[{}].item={}\n", .{ i, given_item.item.value() });
        try stream.print(".pokeball_items[{}].amount={}\n", .{ i, given_item.amount.value() });
    }

    try outputStringTable(stream, "pokemons", "name", game.pokemon_names);
    // Decrompress trainer names
    // try outputStringTable(stream, "trainers", "name", game.trainer_names);
    try outputStringTable(stream, "moves", "name", game.move_names);
    try outputStringTable(stream, "moves", "description", game.move_descriptions);
    try outputStringTable(stream, "abilities", "name", game.ability_names);
    try outputStringTable(stream, "items", "name", game.item_names);
    try outputStringTable(stream, "items", "description", game.item_descriptions);
}

fn outputGen5Data(nds_rom: nds.Rom, game: gen5.Game, stream: var) !void {
    try stream.print(".version={}\n", .{@tagName(game.version)});

    const header = nds_rom.header();
    const null_index = mem.indexOfScalar(u8, &header.game_title, 0) orelse header.game_title.len;
    try stream.print(".game_title={}\n", .{header.game_title[0..null_index]});
    try stream.print(".gamecode={}\n", .{header.gamecode});

    for (game.starters) |starter_ptrs, i| {
        const first = starter_ptrs[0];
        for (starter_ptrs[1..]) |starter| {
            if (first.value() != starter.value())
                debug.warn("warning: all starter positions are not the same.\n", .{});
        }

        try stream.print(".starters[{}]={}\n", .{ i, first.value() });
    }

    for (game.trainers) |trainer, i| {
        try stream.print(".trainers[{}].class={}\n", .{ i, trainer.class });
        try stream.print(".trainers[{}].battle_type={}\n", .{ i, trainer.battle_type });

        for (trainer.items) |item, j| {
            try stream.print(".trainers[{}].items[{}]={}\n", .{ i, j, item.value() });
        }

        try stream.print(".trainers[{}].ai={}\n", .{ i, trainer.ai.value() });
        try stream.print(".trainers[{}].is_healer={}\n", .{ i, trainer.healer });
        try stream.print(".trainers[{}].cash={}\n", .{ i, trainer.cash });
        try stream.print(".trainers[{}].post_battle_item={}\n", .{ i, trainer.post_battle_item.value() });

        const parties = game.parties;
        if (parties.fat.len <= i)
            continue;

        const party_data = parties.fileData(.{ .i = @intCast(u32, i) });
        var j: usize = 0;
        while (j < trainer.party_size) : (j += 1) {
            const base = trainer.partyMember(party_data, j) orelse continue;
            try stream.print(".trainers[{}].party[{}].iv={}\n", .{ i, j, base.iv });
            try stream.print(".trainers[{}].party[{}].gender={}\n", .{ i, j, base.gender_ability.gender });
            try stream.print(".trainers[{}].party[{}].ability={}\n", .{ i, j, base.gender_ability.ability });
            try stream.print(".trainers[{}].party[{}].level={}\n", .{ i, j, base.level });
            try stream.print(".trainers[{}].party[{}].species={}\n", .{ i, j, base.species.value() });
            try stream.print(".trainers[{}].party[{}].form={}\n", .{ i, j, base.form.value() });

            switch (trainer.party_type) {
                .none => {},
                .item => {
                    const member = base.toParent(gen5.PartyMemberItem);
                    try stream.print(".trainers[{}].party[{}].item={}\n", .{ i, j, member.item.value() });
                },
                .moves => {
                    const member = base.toParent(gen5.PartyMemberMoves);
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ i, j, k, move.value() });
                    }
                },
                .both => {
                    const member = base.toParent(gen5.PartyMemberBoth);
                    try stream.print(".trainers[{}].party[{}].item={}\n", .{ i, j, member.item.value() });
                    for (member.moves) |move, k| {
                        try stream.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ i, j, k, move.value() });
                    }
                },
            }
        }
    }

    for (game.moves) |move, i| {
        try stream.print(".moves[{}].type={}\n", .{ i, @tagName(move.@"type") });
        try stream.print(".moves[{}].effect_category={}\n", .{ i, move.effect_category });
        try stream.print(".moves[{}].category={}\n", .{ i, @tagName(move.category) });
        try stream.print(".moves[{}].power={}\n", .{ i, move.power });
        try stream.print(".moves[{}].accuracy={}\n", .{ i, move.accuracy });
        try stream.print(".moves[{}].pp={}\n", .{ i, move.pp });
        try stream.print(".moves[{}].priority={}\n", .{ i, move.priority });
        try stream.print(".moves[{}].min_hits={}\n", .{ i, move.min_hits });
        try stream.print(".moves[{}].max_hits={}\n", .{ i, move.max_hits });
        try stream.print(".moves[{}].result_effect={}\n", .{ i, move.result_effect.value() });
        try stream.print(".moves[{}].effect_chance={}\n", .{ i, move.effect_chance });
        try stream.print(".moves[{}].status={}\n", .{ i, move.status });
        try stream.print(".moves[{}].min_turns={}\n", .{ i, move.min_turns });
        try stream.print(".moves[{}].max_turns={}\n", .{ i, move.max_turns });
        try stream.print(".moves[{}].crit={}\n", .{ i, move.crit });
        try stream.print(".moves[{}].flinch={}\n", .{ i, move.flinch });
        try stream.print(".moves[{}].effect={}\n", .{ i, move.effect.value() });
        try stream.print(".moves[{}].target_hp={}\n", .{ i, move.target_hp });
        try stream.print(".moves[{}].user_hp={}\n", .{ i, move.user_hp });
        try stream.print(".moves[{}].target={}\n", .{ i, move.target });

        //const stats_affected = move.stats_affected;
        //for (stats_affected) |stat_affected, j|
        //    try stream.print(".moves[{}].stats_affected[{}]={}\n", .{ i, j, stat_affected });

        //const stats_affected_magnetude = move.stats_affected_magnetude;
        //for (stats_affected_magnetude) |stat_affected_magnetude, j|
        //    try stream.print(".moves[{}].stats_affected_magnetude[{}]={}\n", .{ i, j, stat_affected_magnetude });

        //const stats_affected_chance = move.stats_affected_chance;
        //for (stats_affected_chance) |stat_affected_chance, j|
        //    try stream.print(".moves[{}].stats_affected_chance[{}]={}\n", .{ i, j, stat_affected_chance });
    }

    // HACK: Pokemon bw2 have these movie pokemons that are not allowed to appear
    //       in normal trainer battles and wild encounters. The real fix to this problem
    //       is to expose the pokedex and have commands that pick pokemon pick from
    //       the pokedex. This requires some effort though, so for now, we just don't
    //       emit these Pokémons.
    const number_of_pokemons = 649;

    {
        var i: u32 = 0;
        while (i < number_of_pokemons) : (i += 1) {
            const pokemon = try game.pokemons.fileAs(.{ .i = i }, gen5.BasePokemon);
            try stream.print(".pokemons[{}].stats.hp={}\n", .{ i, pokemon.stats.hp });
            try stream.print(".pokemons[{}].stats.attack={}\n", .{ i, pokemon.stats.attack });
            try stream.print(".pokemons[{}].stats.defense={}\n", .{ i, pokemon.stats.defense });
            try stream.print(".pokemons[{}].stats.speed={}\n", .{ i, pokemon.stats.speed });
            try stream.print(".pokemons[{}].stats.sp_attack={}\n", .{ i, pokemon.stats.sp_attack });
            try stream.print(".pokemons[{}].stats.sp_defense={}\n", .{ i, pokemon.stats.sp_defense });

            const types = pokemon.types;
            for (types) |t, j|
                try stream.print(".pokemons[{}].types[{}]={}\n", .{ i, j, @tagName(t) });

            try stream.print(".pokemons[{}].catch_rate={}\n", .{ i, pokemon.catch_rate });

            // TODO: Figure out if common.EvYield fits in these 3 bytes
            // evs: [3]u8,

            const items = pokemon.items;
            for (items) |item, j|
                try stream.print(".pokemons[{}].items[{}]={}\n", .{ i, j, item.value() });

            try stream.print(".pokemons[{}].gender_ratio={}\n", .{ i, pokemon.gender_ratio });
            try stream.print(".pokemons[{}].egg_cycles={}\n", .{ i, pokemon.egg_cycles });
            try stream.print(".pokemons[{}].base_friendship={}\n", .{ i, pokemon.base_friendship });
            try stream.print(".pokemons[{}].growth_rate={}\n", .{ i, @tagName(pokemon.growth_rate) });
            try stream.print(".pokemons[{}].egg_groups[{}]={}\n", .{ i, @as(usize, 0), @tagName(pokemon.egg_group1) });
            try stream.print(".pokemons[{}].egg_groups[{}]={}\n", .{ i, @as(usize, 1), @tagName(pokemon.egg_group2) });

            const abilities = pokemon.abilities;
            for (abilities) |ability, j|
                try stream.print(".pokemons[{}].abilities[{}]={}\n", .{ i, j, ability });

            // TODO: The three fields below are kinda unknown
            // flee_rate: u8,
            // form_stats_start: [2]u8,
            // form_sprites_start: [2]u8,
            // form_count: u8,

            //try stream.print(".pokemons[{}].color={}\n", .{ i, @tagName(pokemon.color.color) });
            try stream.print(".pokemons[{}].flip={}\n", .{ i, pokemon.color.flip });
            try stream.print(".pokemons[{}].height={}\n", .{ i, pokemon.height.value() });
            try stream.print(".pokemons[{}].weight={}\n", .{ i, pokemon.weight.value() });

            const machine_learnset = pokemon.machine_learnset.value();
            var j: usize = 0;
            while (j < game.tms1.len) : (j += 1)
                try stream.print(".pokemons[{}].tms[{}]={}\n", .{ i, j, bit.isSet(u128, machine_learnset, @intCast(u7, j)) });
            while (j < game.tms1.len + game.hms.len) : (j += 1)
                try stream.print(".pokemons[{}].hms[{}]={}\n", .{ i, j - game.tms1.len, bit.isSet(u128, machine_learnset, @intCast(u7, j)) });
            while (j < game.tms2.len + game.hms.len + game.tms1.len) : (j += 1)
                try stream.print(".pokemons[{}].tms[{}]={}\n", .{ i, j - game.hms.len, bit.isSet(u128, machine_learnset, @intCast(u7, j)) });
        }
    }

    {
        var i: usize = 0;
        while (i < number_of_pokemons) : (i += 1) {
            const bytes = game.evolutions.fileData(.{ .i = @intCast(u32, i) });
            const rem = bytes.len % @sizeOf(gen5.Evolution);
            const evos = mem.bytesAsSlice(gen5.Evolution, bytes[0 .. bytes.len - rem]);
            for (evos) |evo, j| {
                if (evo.method == .unused)
                    continue;
                try stream.print(".pokemons[{}].evos[{}].method={}\n", .{ i, j, @tagName(evo.method) });
                try stream.print(".pokemons[{}].evos[{}].param={}\n", .{ i, j, evo.param.value() });
                try stream.print(".pokemons[{}].evos[{}].target={}\n", .{ i, j, evo.target.value() });
            }
        }
    }

    {
        var i: usize = 0;
        while (i < number_of_pokemons) : (i += 1) {
            const bytes = game.level_up_moves.fileData(.{ .i = @intCast(u32, i) });
            const rem = bytes.len % @sizeOf(gen5.LevelUpMove);
            const level_up_moves = mem.bytesAsSlice(gen5.LevelUpMove, bytes[0 .. bytes.len - rem]);
            for (level_up_moves) |move, j| {
                try stream.print(".pokemons[{}].moves[{}].id={}\n", .{ i, j, move.id.value() });
                try stream.print(".pokemons[{}].moves[{}].level={}\n", .{ i, j, move.level.value() });
            }
        }
    }

    for (game.tms1) |tm, i|
        try stream.print(".tms[{}]={}\n", .{ i, tm.value() });
    for (game.tms2) |tm, i|
        try stream.print(".tms[{}]={}\n", .{ i + game.tms1.len, tm.value() });
    for (game.hms) |hm, i|
        try stream.print(".hms[{}]={}\n", .{ i, hm.value() });

    for (game.items) |item, i| {
        try stream.print(".items[{}].price={}\n", .{ i, item.price.value() });
        try stream.print(".items[{}].battle_effect={}\n", .{ i, item.battle_effect }); // TODO: Is this the same as gen3 hold_effect?
        try stream.print(".items[{}].gain={}\n", .{ i, item.gain });
        try stream.print(".items[{}].berry={}\n", .{ i, item.berry });
        try stream.print(".items[{}].fling_effect={}\n", .{ i, item.fling_effect });
        try stream.print(".items[{}].fling_power={}\n", .{ i, item.fling_power });
        try stream.print(".items[{}].natural_gift_power={}\n", .{ i, item.natural_gift_power });
        try stream.print(".items[{}].flag={}\n", .{ i, item.flag });
        try stream.print(".items[{}].pocket={}\n", .{ i, @tagName(item.pocket) });
        try stream.print(".items[{}].type={}\n", .{ i, item.type });
        try stream.print(".items[{}].category={}\n", .{ i, item.category });
        try stream.print(".items[{}].category2={}\n", .{ i, item.category2.value() });
        try stream.print(".items[{}].category3={}\n", .{ i, item.category3 });
        try stream.print(".items[{}].index={}\n", .{ i, item.index });
        try stream.print(".items[{}].anti_index={}\n", .{ i, item.anti_index });
        //try stream.print(".items[{}].statboosts.hp={}\n", .{ i, item.statboosts.hp });
        //try stream.print(".items[{}].statboosts.level={}\n", .{ i, item.statboosts.level });
        //try stream.print(".items[{}].statboosts.evolution={}\n", .{ i, item.statboosts.evolution });
        //try stream.print(".items[{}].statboosts.attack={}\n", .{ i, item.statboosts.attack });
        //try stream.print(".items[{}].statboosts.defense={}\n", .{ i, item.statboosts.defense });
        //try stream.print(".items[{}].statboosts.sp_attack={}\n", .{ i, item.statboosts.sp_attack });
        //try stream.print(".items[{}].statboosts.sp_defense={}\n", .{ i, item.statboosts.sp_defense });
        //try stream.print(".items[{}].statboosts.speed={}\n", .{ i, item.statboosts.speed });
        //try stream.print(".items[{}].statboosts.accuracy={}\n", .{ i, item.statboosts.accuracy });
        //try stream.print(".items[{}].statboosts.crit={}\n", .{ i, item.statboosts.crit });
        //try stream.print(".items[{}].statboosts.pp={}\n", .{ i, item.statboosts.pp });
        //try stream.print(".items[{}].statboosts.target={}\n", .{ i, item.statboosts.target });
        //try stream.print(".items[{}].statboosts.target2={}\n", .{ i, item.statboosts.target2 });
        try stream.print(".items[{}].ev_yield.hp={}\n", .{ i, item.ev_yield.hp });
        try stream.print(".items[{}].ev_yield.attack={}\n", .{ i, item.ev_yield.attack });
        try stream.print(".items[{}].ev_yield.defense={}\n", .{ i, item.ev_yield.defense });
        try stream.print(".items[{}].ev_yield.speed={}\n", .{ i, item.ev_yield.speed });
        try stream.print(".items[{}].ev_yield.sp_attack={}\n", .{ i, item.ev_yield.sp_attack });
        try stream.print(".items[{}].ev_yield.sp_defense={}\n", .{ i, item.ev_yield.sp_defense });
        try stream.print(".items[{}].hp_restore={}\n", .{ i, item.hp_restore });
        try stream.print(".items[{}].pp_restore={}\n", .{ i, item.pp_restore });
    }

    for (game.wild_pokemons.fat) |_, i| {
        const wild_mons = try game.wild_pokemons.fileAs(.{ .i = @intCast(u32, i) }, gen5.WildPokemons);
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
            try stream.print(".zones[{}].wild.{}.encounter_rate={}\n", .{ i, area_name, wild_mons.rates[j] });
            const area = @field(wild_mons, area_name);
            for (area) |wild, k| {
                try stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", .{ i, area_name, k, wild.species.species() });
                try stream.print(".zones[{}].wild.{}.pokemons[{}].form={}\n", .{ i, area_name, k, wild.species.form() });
                try stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", .{ i, area_name, k, wild.min_level });
                try stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", .{ i, area_name, k, wild.max_level });
            }
        }
    }

    for (game.static_pokemons) |static_mon, i| {
        const data = static_mon.data();
        try stream.print(".static_pokemons[{}].species={}\n", .{ i, data.wild_battle.species.value() });
        try stream.print(".static_pokemons[{}].level={}\n", .{ i, data.wild_battle.level });
    }

    for (game.pokeball_items) |given_item, i| {
        try stream.print(".pokeball_items[{}].item={}\n", .{ i, given_item.item.value() });
        try stream.print(".pokeball_items[{}].amount={}\n", .{ i, given_item.amount.value() });
    }
}

fn outputStringTable(
    stream: var,
    array_name: []const u8,
    field_name: []const u8,
    est: nds.fs.EncryptedStringTable,
) !void {
    var buf: [1024]u8 = undefined;
    var i: u32 = 0;
    while (i < est.count()) : (i += 1) {
        try stream.print(".{}[{}].{}=", .{ array_name, i, field_name });
        const len = try est.getStringStream(i).read(&buf);
        try gen4.encodings.decode(buf[0..len], stream);
        try stream.writeAll("\n");
    }
}

test "" {
    std.meta.refAllDecls(@This());
}
