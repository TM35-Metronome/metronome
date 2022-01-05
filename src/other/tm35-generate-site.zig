const clap = @import("clap");
const format = @import("format");
const std = @import("std");
const util = @import("util");

const ascii = std.ascii;
const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const escape = util.escape;

const Program = @This();

allocator: mem.Allocator,
out: []const u8,

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Generates a html web site for games. This is very useful for getting an overview of what is
    \\in the game after heavy randomization has been apply.
    \\
;

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam("-h, --help           Display this help text and exit.") catch unreachable,
    clap.parseParam("-v, --version        Output version information and exit.") catch unreachable,
    clap.parseParam("-o, --output <FILE>  The file to output the file to. (default: site.html)") catch unreachable,
};

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    return Program{
        .allocator = allocator,
        .out = args.option("--output") orelse "site.html",
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    var game = Game{ .allocator = program.allocator };
    try format.io(program.allocator, stdio.in, stdio.out, &game, useGame);

    try stdio.out.context.flush();

    // We are now completly done with stdout, so we close it. This gives programs further down the
    // pipeline the ability to finish up what they need to do while we generate the site.
    stdio.out.context.unbuffered_writer.context.close();

    const out_file = try fs.cwd().createFile(program.out, .{
        .exclusive = false,
        .truncate = false,
    });
    defer out_file.close();

    var writer = std.io.bufferedWriter(out_file.writer());
    try generate(writer.writer(), game);
    try writer.flush();
    try out_file.setEndPos(try out_file.getPos());
}

fn useGame(game: *Game, parsed: format.Game) !void {
    const allocator = game.allocator;
    switch (parsed) {
        .starters => |starter| _ = try game.starters.put(allocator, starter.index, starter.value),
        .tms => |tm| _ = try game.tms.put(allocator, tm.index, tm.value),
        .hms => |hm| _ = try game.hms.put(allocator, hm.index, hm.value),
        .trainers => |trainers| {
            const trainer = (try game.trainers.getOrPutValue(allocator, trainers.index, .{})).value_ptr;
            switch (trainers.value) {
                .name => |str| trainer.name = try escape.default.unescapeAlloc(allocator, str),
                .class => |class| trainer.class = class,
                .encounter_music => |encounter_music| trainer.encounter_music = encounter_music,
                .trainer_picture => |trainer_picture| trainer.trainer_picture = trainer_picture,
                .party_type => |party_type| trainer.party_type = party_type,
                .party_size => |party_size| trainer.party_size = party_size,
                .items => |items| _ = try trainer.items.put(allocator, items.index, items.value),
                .party => |party| {
                    const member = (try trainer.party.getOrPutValue(allocator, party.index, .{})).value_ptr;
                    switch (party.value) {
                        .ability => |ability| member.ability = ability,
                        .level => |level| member.level = level,
                        .species => |species| member.species = species,
                        .item => |item| member.item = item,
                        .moves => |moves| _ = try member.moves.put(allocator, moves.index, moves.value),
                    }
                },
            }
        },
        .moves => |moves| {
            const move = (try game.moves.getOrPutValue(allocator, moves.index, .{})).value_ptr;
            switch (moves.value) {
                .name => |str| move.name = try escape.default.unescapeAlloc(allocator, str),
                .description => |str| move.description = try escape.default.unescapeAlloc(allocator, str),
                .effect => |effect| move.effect = effect,
                .power => |power| move.power = power,
                .type => |_type| move.type = _type,
                .accuracy => |accuracy| move.accuracy = accuracy,
                .pp => |pp| move.pp = pp,
                .target => |target| move.target = target,
                .priority => |priority| move.priority = priority,
                .category => |category| move.category = category,
            }
        },
        .pokemons => |pokemons| {
            const pokemon = (try game.pokemons.getOrPutValue(allocator, pokemons.index, .{})).value_ptr;
            switch (pokemons.value) {
                .name => |str| pokemon.name = try escape.default.unescapeAlloc(allocator, str),
                .stats => |stats| format.setField(&pokemon.stats, stats),
                .ev_yield => |ev_yield| format.setField(&pokemon.ev_yield, ev_yield),
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .base_exp_yield => |base_exp_yield| pokemon.base_exp_yield = base_exp_yield,
                .gender_ratio => |gender_ratio| pokemon.gender_ratio = gender_ratio,
                .egg_cycles => |egg_cycles| pokemon.egg_cycles = egg_cycles,
                .base_friendship => |base_friendship| pokemon.base_friendship = base_friendship,
                .growth_rate => |growth_rate| pokemon.growth_rate = growth_rate,
                .color => |color| pokemon.color = color,
                .pokedex_entry => |pokedex_entry| pokemon.pokedex_entry = pokedex_entry,
                .abilities => |ability| _ = try pokemon.abilities.put(allocator, ability.index, ability.value),
                .egg_groups => |egg_group| _ = try pokemon.egg_groups.put(allocator, egg_group.value, {}),
                .hms => |hm| if (hm.value) {
                    _ = try pokemon.hms.put(allocator, hm.index, {});
                },
                .tms => |tm| if (tm.value) {
                    _ = try pokemon.tms.put(allocator, tm.index, {});
                },
                .types => |_type| _ = try pokemon.types.put(allocator, _type.value, {}),
                .items => |item| _ = try pokemon.items.put(allocator, item.index, item.value),
                .moves => |moves| {
                    const move = (try pokemon.moves.getOrPutValue(allocator, moves.index, .{})).value_ptr;
                    format.setField(move, moves.value);
                },
                .evos => |evos| {
                    const evo = (try pokemon.evos.getOrPutValue(allocator, evos.index, .{})).value_ptr;
                    format.setField(evo, evos.value);
                },
            }
        },
        .abilities => |abilities| {
            const ability = (try game.abilities.getOrPutValue(allocator, abilities.index, .{})).value_ptr;
            switch (abilities.value) {
                .name => |str| ability.name = try escape.default.unescapeAlloc(allocator, str),
            }
        },
        .types => |types| {
            const _type = (try game.types.getOrPutValue(allocator, types.index, .{})).value_ptr;
            switch (types.value) {
                .name => |str| _type.name = try escape.default.unescapeAlloc(allocator, str),
            }
        },
        .items => |items| {
            const item = (try game.items.getOrPutValue(allocator, items.index, .{})).value_ptr;
            switch (items.value) {
                .name => |str| item.name = try escape.default.unescapeAlloc(allocator, str),
                .description => |str| item.description = try escape.default.unescapeAlloc(allocator, str),
                .price => |price| item.price = price,
                .battle_effect => |battle_effect| item.battle_effect = battle_effect,
                .pocket => |pocket| item.pocket = pocket,
            }
        },
        .pokedex => |pokedex| {
            const pokedex_entry = (try game.pokedex.getOrPutValue(allocator, pokedex.index, .{})).value_ptr;
            switch (pokedex.value) {
                .category => |category| pokedex_entry.category = try escape.default.unescapeAlloc(allocator, category),
                .height => |height| pokedex_entry.height = height,
                .weight => |weight| pokedex_entry.weight = weight,
            }
        },
        .maps,
        .wild_pokemons,
        .static_pokemons,
        .given_pokemons,
        .pokeball_items,
        .hidden_hollows,
        .text,
        .text_delays,
        .version,
        .game_title,
        .gamecode,
        .instant_text,
        => return error.DidNotConsumeData,
    }
    return error.DidNotConsumeData;
}

fn generate(writer: anytype, game: Game) !void {
    @setEvalBranchQuota(1000000);
    const unknown = "???";
    const stat_names = [_][2][]const u8{
        .{ "hp", "Hp" },
        .{ "attack", "Attack" },
        .{ "defense", "Defense" },
        .{ "sp_attack", "Sp. Atk" },
        .{ "sp_defense", "Sp. Def" },
        .{ "speed", "Speed" },
    };

    try writer.writeAll(
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\<title>Wiki</title>
        \\<style>
        \\
        \\* {font-family: Arial, Helvetica, sans-serif;}
        \\.type {border-style: solid; border-width: 1px; border-color: black; color: white;}
        \\.type_Bug {background-color: #88960e;}
        \\.type_Dark {background-color: #3c2d23;}
        \\.type_Dragon {background-color: #4e3ba4;}
        \\.type_Electric {background-color: #e79302;}
        \\.type_Fairy {background-color: #e08ee0;}
        \\.type_Fighting {background-color: #5f2311;}
        \\.type_Fight {background-color: #5f2311;}
        \\.type_Fire {background-color: #c72100;}
        \\.type_Flying {background-color: #5d73d4;}
        \\.type_Ghost {background-color: #454593;}
        \\.type_Grass {background-color: #389a02;}
        \\.type_Ground {background-color: #ad8c33;}
        \\.type_Ice {background-color: #6dd3f5;}
        \\.type_Normal {background-color: #ada594;}
        \\.type_Poison {background-color: #6b246e;}
        \\.type_Psychic {background-color: #dc3165;}
        \\.type_Psychc {background-color: #dc3165;}
        \\.type_Rock {background-color: #9e863d;}
        \\.type_Steel {background-color: #8e8e9f;}
        \\.type_Water {background-color: #0c67c2;}
        \\
        \\.pokemon_stat {width:100%;}
        \\.pokemon_stat_table {width:50%;}
        \\.pokemon_stat_hp {background-color: #6ab04c;}
        \\.pokemon_stat_attack {background-color: #eb4d4b;}
        \\.pokemon_stat_defense {background-color: #f0932b;}
        \\.pokemon_stat_sp_attack {background-color:#be2edd;}
        \\.pokemon_stat_sp_defense {background-color: #686de0;}
        \\.pokemon_stat_speed {background-color: #f9ca24;}
        \\.pokemon_stat_total {background-color: #95afc0;}
        \\
    );

    for ([_]void{{}} ** 101) |_, i| {
        try writer.print(".pokemon_stat_p{} {{width: {}%;}}\n", .{ i, i });
    }

    try writer.writeAll(
        \\</style>
        \\</head>
        \\<body>
        \\
    );

    try writer.writeAll(
        \\<h1>Starters</h1>
        \\<table>
        \\
    );

    for (game.starters.values()) |starter| {
        const starter_name = if (game.pokemons.get(starter)) |p| p.name else unknown;
        try writer.print("<tr><td><a href=\"#pokemon_{}\">{s}</a></td></tr>", .{
            starter,
            starter_name,
        });
    }

    try writer.writeAll(
        \\</table>
        \\<h1>Machines</h1>
        \\<table>
        \\
    );
    for (game.tms.keys()) |tm_id, i| {
        const tm_move = game.tms.values()[i];
        const move_name = humanize(if (game.moves.get(tm_move)) |m| m.name else unknown);
        try writer.print("<tr><td>TM{} - <a href=\"#move_{}\">{s}</a></td></tr>\n", .{ tm_id + 1, tm_move, move_name });
    }
    for (game.hms.keys()) |hm_id, i| {
        const hm_move = game.hms.values()[i];
        const move_name = humanize(if (game.moves.get(hm_move)) |m| m.name else unknown);
        try writer.print("<tr><td>HM{} - <a href=\"#move_{}\">{s}</a></td></tr>\n", .{ hm_id + 1, hm_move, move_name });
    }

    try writer.writeAll(
        \\</table>
        \\<h1>Pokedex</h1>
        \\<table>
        \\
    );
    for (game.pokedex.keys()) |dex| {
        const pokemon = for (game.pokemons.values()) |pokemon, i| {
            if (pokemon.pokedex_entry == dex)
                break .{ .name = pokemon.name, .species = game.pokemons.keys()[i] };
        } else continue;

        try writer.print("<tr><td><a href=\"#pokemon_{}\">#{} {s}</a></td></tr>\n", .{ pokemon.species, dex, pokemon.name });
    }

    try writer.writeAll(
        \\</table>
        \\<h1>Pokemons</h1>
        \\
    );
    for (game.pokemons.values()) |pokemon, i| {
        const species = game.pokemons.keys()[i];
        try writer.print("<h2 id=\"pokemon_{}\">#{} {s}</h2>\n", .{ species, species, pokemon.name });

        try writer.writeAll(
            \\<table>
            \\<tr><td>Type:</td><td>
            \\
        );
        for (pokemon.types.keys()) |t, j| {
            const type_name = humanize(if (game.types.get(t)) |ty| ty.name else unknown);
            if (j != 0)
                try writer.writeAll(" ");

            try writer.print("<a href=\"#type_{}\" class=\"type type_{}\"><b>{}</b></a>", .{
                t,
                type_name,
                type_name,
            });
        }

        try writer.writeAll(
            \\</td>
            \\<tr><td>Abilities:</td><td>
            \\
        );
        for (pokemon.abilities.values()) |a, j| {
            if (a == 0)
                continue;
            if (j != 0)
                try writer.writeAll(", ");

            const ability_name = if (game.abilities.get(a)) |abil| abil.name else unknown;
            try writer.print("<a href=\"#ability_{}\">{}</a>", .{ a, humanize(ability_name) });
        }

        try writer.writeAll(
            \\</td>
            \\<tr><td>Items:</td><td>
            \\
        );
        for (pokemon.items.values()) |item, j| {
            if (j != 0)
                try writer.writeAll(", ");

            const item_name = if (game.items.get(item)) |it| it.name else unknown;
            try writer.print("<a href=\"#item_{}\">{}</a>", .{ item, humanize(item_name) });
        }

        try writer.writeAll(
            \\</td>
            \\<tr><td>Egg Groups:</td><td>
            \\
        );
        for (pokemon.egg_groups.keys()) |egg_group, j| {
            if (j != 0)
                try writer.writeAll(", ");

            try writer.print("{}", .{humanize(@tagName(egg_group))});
        }
        try writer.writeAll("</td>\n");
        try printSimpleFields(writer, pokemon, &[_][]const u8{});
        try writer.writeAll("</table>\n");

        try writer.writeAll(
            \\<details><summary><b>Evolutions</b></summary>
            \\<table>
            \\<tr><th>Evolution</th><th>Method</th></tr>
            \\
        );
        for (pokemon.evos.values()) |evo| {
            const target_name = humanize(if (game.pokemons.get(evo.target)) |p| p.name else unknown);
            const param_item_name = humanize(if (game.items.get(evo.param)) |item| item.name else unknown);
            const param_move_name = humanize(if (game.moves.get(evo.param)) |m| m.name else unknown);
            const param_pokemon_name = humanize(if (game.pokemons.get(evo.param)) |p| p.name else unknown);

            try writer.print("<tr><td><a href=\"#pokemon_{}\">{}</a></td><td>", .{ evo.target, target_name });
            switch (evo.method) {
                .friend_ship => try writer.writeAll("Level up with friendship high"),
                .friend_ship_during_day => try writer.writeAll("Level up with friendship high during daytime"),
                .friend_ship_during_night => try writer.writeAll("Level up with friendship high during night"),
                .level_up => try writer.print("Level {}", .{evo.param}),
                .trade => try writer.writeAll("Trade"),
                .trade_holding_item => try writer.print("Trade holding <a href=\"#item_{}\">{}</a>", .{ evo.param, param_item_name }),
                .trade_with_pokemon => try writer.print("Trade for <a href=\"#pokemon_{}\">{}</a>", .{ evo.param, param_pokemon_name }),
                .use_item => try writer.print("Using <a href=\"#item_{}\">{}</a>", .{ evo.param, param_item_name }),
                .attack_gth_defense => try writer.print("Level {} when Attack > Defense", .{evo.param}),
                .attack_eql_defense => try writer.print("Level {} when Attack = Defense", .{evo.param}),
                .attack_lth_defense => try writer.print("Level {} when Attack < Defense", .{evo.param}),
                .personality_value1 => try writer.print("Level {} when having personallity value type 1", .{evo.param}),
                .personality_value2 => try writer.print("Level {} when having personallity value type 2", .{evo.param}),
                // TODO: What Pokémon?
                .level_up_may_spawn_pokemon => try writer.print("Level {} (May spawn another Pokémon when evolved)", .{evo.param}),
                // TODO: What Pokémon? What condition?
                .level_up_spawn_if_cond => try writer.print("Level {} (May spawn another Pokémon when evolved if conditions are met)", .{evo.param}),
                .beauty => try writer.print("Level up when beauty hits {}", .{evo.param}),
                .use_item_on_male => try writer.print("Using <a href=\"#item_{}\">{}</a> on a male", .{ evo.param, param_item_name }),
                .use_item_on_female => try writer.print("Using <a href=\"#item_{}\">{}</a> on a female", .{ evo.param, param_item_name }),
                .level_up_holding_item_during_daytime => try writer.print("Level up while holding <a href=\"#item_{}\">{}</a> during daytime", .{ evo.param, param_item_name }),
                .level_up_holding_item_during_the_night => try writer.print("Level up while holding <a href=\"#item_{}\">{}</a> during night", .{ evo.param, param_item_name }),
                .level_up_knowning_move => try writer.print("Level up while knowing <a href=\"#move_{}\">{}</a>", .{ evo.param, param_move_name }),
                .level_up_with_other_pokemon_in_party => try writer.print("Level up with <a href=\"#pokemon_{}\">{}</a> in the Party", .{ evo.param, param_pokemon_name }),
                .level_up_male => try writer.print("Level {} male", .{evo.param}),
                .level_up_female => try writer.print("Level {} female", .{evo.param}),
                .level_up_in_special_magnetic_field => try writer.writeAll("Level up in special magnetic field"),
                .level_up_near_moss_rock => try writer.writeAll("Level up near moss rock"),
                .level_up_near_ice_rock => try writer.writeAll("Level up near ice rock"),
                .unknown_0x02,
                .unknown_0x03,
                .unused,
                => try writer.writeAll("Unknown"),
            }
            try writer.writeAll("</td></tr>\n");
        }

        try writer.writeAll(
            \\</table></details>
            \\<details><summary><b>Stats</b></summary>
            \\<table class="pokemon_stat_table">
            \\
        );

        var total_stats: usize = 0;
        inline for (stat_names) |stat| {
            const value = @field(pokemon.stats, stat[0]);
            const percent = @floatToInt(usize, (@intToFloat(f64, value) / 255) * 100);
            try writer.print("<tr><td>{s}:</td><td class=\"pokemon_stat\"><div class=\"pokemon_stat_p{} pokemon_stat_{s}\">{}</div></td></tr>\n", .{ stat[1], percent, stat[0], value });
            total_stats += value;
        }

        const percent = @floatToInt(usize, (@intToFloat(f64, total_stats) / 1000) * 100);
        try writer.print("<tr><td>Total:</td><td><div class=\"pokemon_stat pokemon_stat_p{} pokemon_stat_total\">{}</div></td></tr>\n", .{ percent, total_stats });
        try writer.writeAll(
            \\</table></details>
            \\<details><summary><b>Ev Yield</b></summary>
            \\<table>
            \\
        );

        total_stats = 0;
        inline for (stat_names) |stat| {
            const value = @field(pokemon.ev_yield, stat[0]);
            try writer.print("<tr><td>{s}:</td><td>{}</td></tr>\n", .{ stat[1], value });
            total_stats += value;
        }

        try writer.print("<tr><td>Total:</td><td>{}</td></tr>\n", .{total_stats});
        try writer.writeAll(
            \\</table></details>
            \\<details><summary><b>Learnset</b></summary>
            \\<table>
            \\
        );
        for (pokemon.moves.values()) |move| {
            const move_name = humanize(if (game.moves.get(move.id)) |m| m.name else unknown);
            try writer.print("<tr><td>Lvl {}</td><td><a href=\"#move_{}\">{}</a></td></tr>\n", .{ move.level, move.id, move_name });
        }

        try writer.writeAll(
            \\</table>
            \\<table>
            \\
        );
        for (pokemon.tms.keys()) |tm_id| {
            const move_id = game.tms.get(tm_id) orelse continue;
            const move_name = humanize(if (game.moves.get(move_id)) |m| m.name else unknown);
            try writer.print(
                "<tr><td>TM{}</td><td><a href=\"#move_{}\">{s}</a></td></tr>\n",
                .{ tm_id + 1, move_id, move_name },
            );
        }
        for (pokemon.hms.keys()) |hm_id| {
            const move_id = game.hms.get(hm_id) orelse continue;
            const move_name = humanize(if (game.moves.get(move_id)) |m| m.name else unknown);
            try writer.print(
                "<tr><td>TM{}</td><td><a href=\"#move_{}\">{s}</a></td></tr>\n",
                .{ hm_id + 1, move_id, move_name },
            );
        }

        try writer.writeAll(
            \\</table>
            \\</details>
            \\
        );
    }

    try writer.writeAll("<h1>Trainers</h1>\n");
    for (game.trainers.values()) |trainer, i| {
        const trainer_id = game.trainers.keys()[i];
        try writer.print("<h2 id=\"trainer_{}\">{}</h2>\n", .{ trainer_id, humanize(trainer.name) });

        try writer.writeAll("<table>\n");
        try writer.writeAll("<tr><td>Items:</td><td>");
        for (trainer.items.values()) |item, j| {
            if (j != 0)
                try writer.writeAll(", ");

            const item_name = if (game.items.get(item)) |it| it.name else unknown;
            try writer.print("<a href=\"#item_{}\">{}</a>", .{ item, humanize(item_name) });
        }

        try writer.writeAll(
            \\</td>
            \\</table>
            \\<h3>Party:</h3>
            \\<table>
            \\
        );
        const party = trainer.party.values();
        for (party[0..math.min(party.len, trainer.party_size)]) |member| {
            const pokemon = game.pokemons.get(member.species);
            const pokemon_name = humanize(if (pokemon) |p| p.name else unknown);
            const ability_id = if (pokemon) |p| p.abilities.get(member.ability) else null;
            const ability_id_print = ability_id orelse 0;
            const ability = if (ability_id) |a| game.abilities.get(a) else null;
            const ability_name = humanize(if (ability) |a| a.name else unknown);
            const item_name = humanize(if (game.items.get(member.item)) |it| it.name else unknown);
            try writer.print("<tr><td><a href=\"#pokemon_{}\">{}</a></td>", .{ member.species, pokemon_name });
            try writer.print("<td>lvl {}</td>", .{member.level});
            try writer.print("<td><a href=\"#ability_{}\">{}</a></td>", .{ ability_id_print, ability_name });
            switch (trainer.party_type) {
                .item, .both => try writer.print("<td><a href=\"#item_{}\">{}</a></td>", .{
                    member.item,
                    item_name,
                }),
                .moves, .none => try writer.writeAll("<td>----</td>"),
            }
            switch (trainer.party_type) {
                .moves, .both => for (member.moves.values()) |move| {
                    const move_name = humanize(if (game.moves.get(move)) |m| m.name else unknown);
                    try writer.print("<td><a href=\"#move_{}\">{}</a></td>", .{ move, move_name });
                },
                .item, .none => {},
            }

            try writer.writeAll("</tr>");
        }
        try writer.writeAll("<table>\n");
    }

    try writer.writeAll("<h1>Moves</h1>\n");
    for (game.moves.values()) |move, i| {
        const move_id = game.moves.keys()[i];
        const move_name = humanize(move.name);
        try writer.print("<h2 id=\"move_{}\">{}</h2>\n", .{ move_id, move_name });
        try writer.print("<p>{s}</p>\n", .{move.description});
        try writer.writeAll("<table>\n");

        const type_name = humanize(if (game.types.get(move.type)) |t| t.name else unknown);
        try writer.print(
            "<tr><td>Type:</td><td><a href=\"type_{}\" class=\"type type_{}\"><b>{}</b></a></td></tr>\n",
            .{ move.type, type_name, type_name },
        );
        try printSimpleFields(writer, move, &[_][]const u8{"type"});
        try writer.writeAll("</table>\n");
    }

    try writer.writeAll("<h1>Items</h1>\n");
    for (game.items.values()) |item, i| {
        const item_id = game.items.keys()[i];
        const item_name = humanize(item.name);
        try writer.print("<h2 id=\"item_{}\">{}</h2>\n", .{ item_id, item_name });
        try writer.print("<p>{s}</p>\n", .{item.description});

        try writer.writeAll("<table>\n");
        try printSimpleFields(writer, item, &[_][]const u8{});
        try writer.writeAll("</table>\n");
    }

    try writer.writeAll(
        \\</body>
        \\</html>
        \\
    );
}

pub fn printSimpleFields(writer: anytype, value: anytype, comptime blacklist: []const []const u8) !void {
    outer: inline for (@typeInfo(@TypeOf(value)).Struct.fields) |field| {
        comptime for (blacklist) |blacklist_item| {
            if (mem.eql(u8, field.name, blacklist_item))
                continue :outer;
        };
        switch (@typeInfo(field.field_type)) {
            .Int => {
                try writer.print(
                    "<tr><td>{}:</td><td>{}</td></tr>\n",
                    .{ humanize(field.name), @field(value, field.name) },
                );
            },
            .Enum => {
                try writer.print(
                    "<tr><td>{}:</td><td>{}</td></tr>\n",
                    .{ humanize(field.name), humanize(@tagName(@field(value, field.name))) },
                );
            },
            else => {},
        }
    }
}

const HumanizeFormatter = struct {
    str: []const u8,

    pub fn format(
        self: HumanizeFormatter,
        comptime f: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = f;
        _ = options;
        try writeHumanized(writer, self.str);
    }
};

fn humanize(str: []const u8) HumanizeFormatter {
    return HumanizeFormatter{ .str = str };
}

fn writeHumanized(writer: anytype, str: []const u8) !void {
    var first = true;
    var it = mem.tokenize(u8, str, "_ ");
    while (it.next()) |word| : (first = false) {
        if (!first)
            try writer.writeAll(" ");

        try writer.writeByte(ascii.toUpper(word[0]));
        for (word[1..]) |c|
            try writer.writeByte(ascii.toLower(c));
    }
}

const Map = std.AutoArrayHashMapUnmanaged;

const Game = struct {
    allocator: mem.Allocator,
    starters: Map(u8, u16) = Map(u8, u16){},
    trainers: Map(u16, Trainer) = Map(u16, Trainer){},
    moves: Map(u16, Move) = Map(u16, Move){},
    pokemons: Map(u16, Pokemon) = Map(u16, Pokemon){},
    abilities: Map(u16, Ability) = Map(u16, Ability){},
    types: Map(u8, Type) = Map(u8, Type){},
    tms: Map(u8, u16) = Map(u8, u16){},
    hms: Map(u8, u16) = Map(u8, u16){},
    items: Map(u16, Item) = Map(u16, Item){},
    pokedex: Map(u16, Pokedex) = Map(u16, Pokedex){},
};

const Trainer = struct {
    class: u8 = 0,
    encounter_music: u8 = 0,
    trainer_picture: u8 = 0,
    name: []const u8 = "",
    party_type: format.PartyType = .none,
    party_size: u8 = 0,
    party: Map(u8, PartyMember) = Map(u8, PartyMember){},
    items: Map(u8, u16) = Map(u8, u16){},
};

const PartyMember = struct {
    ability: u4 = 0,
    level: u8 = 0,
    species: u16 = 0,
    item: u16 = 0,
    moves: Map(u8, u16) = Map(u8, u16){},
};

const Move = struct {
    name: []const u8 = "",
    description: []const u8 = "",
    effect: u8 = 0,
    power: u8 = 0,
    type: u8 = 0,
    accuracy: u8 = 0,
    pp: u8 = 0,
    target: u8 = 0,
    priority: u8 = 0,
    category: format.Move.Category = .status,
};

pub fn Stats(comptime T: type) type {
    return struct {
        hp: T = 0,
        attack: T = 0,
        defense: T = 0,
        speed: T = 0,
        sp_attack: T = 0,
        sp_defense: T = 0,
    };
}

const Pokemon = struct {
    name: []const u8 = "",
    stats: Stats(u8) = Stats(u8){},
    ev_yield: Stats(u2) = Stats(u2){},
    catch_rate: u8 = 0,
    base_exp_yield: u16 = 0,
    gender_ratio: u8 = 0,
    egg_cycles: u8 = 0,
    base_friendship: u8 = 0,
    pokedex_entry: u16 = 0,
    growth_rate: format.GrowthRate = .medium_fast,
    color: format.Color = .blue,
    tms: Map(u8, void) = Map(u8, void){},
    hms: Map(u8, void) = Map(u8, void){},
    types: Map(u8, void) = Map(u8, void){},
    abilities: Map(u8, u8) = Map(u8, u8){},
    items: Map(u8, u16) = Map(u8, u16){},
    egg_groups: Map(format.EggGroup, void) = Map(format.EggGroup, void){},
    evos: Map(u8, Evolution) = Map(u8, Evolution){},
    moves: Map(u8, LevelUpMove) = Map(u8, LevelUpMove){},
};

const Evolution = struct {
    method: format.Evolution.Method = .unused,
    param: u16 = 0,
    target: u16 = 0,
};

const LevelUpMove = struct {
    id: u16 = 0,
    level: u16 = 0,
};

const Ability = struct {
    name: []const u8 = "",
};

const Type = struct {
    name: []const u8 = "",
};

const Item = struct {
    name: []const u8 = "",
    description: []const u8 = "",
    price: u32 = 0,
    battle_effect: u8 = 0,
    pocket: format.Pocket = .none,
};

const Pokedex = struct {
    height: u32 = 0,
    weight: u32 = 0,
    category: []const u8 = "",
};
