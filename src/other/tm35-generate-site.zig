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

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help           Display this help text and exit.") catch unreachable,
        clap.parseParam("-v, --version        Output version information and exit.") catch unreachable,
        clap.parseParam("-o, --output <FILE>  The file to output the file to. (default: site.html)") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-generate-site ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nGenerates a html web site for games. This is very useful " ++
        "for getting an overview of what is in the game after heavy randomization " ++
        "has been apply.\n" ++
        "\n" ++
        "Options:\n");
    try clap.help(writer, &params);
}

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) anyerror!void {
    const out = args.option("--output") orelse "site.html";

    var fifo = util.io.Fifo(.Dynamic).init(allocator);
    var game = Game{};
    while (try util.io.readLine(stdio.in, &fifo)) |line| {
        parseLine(allocator, &game, line) catch |err| switch (err) {
            error.ParserFailed => {},
            error.OutOfMemory => return err,
        };
        try stdio.out.print("{}\n", .{line});
    }

    // We are now completly done with stdout, so we close it. This gives programs further down the
    // pipeline the ability to finish up what they need to do while we generate the site.
    try stdio.out.context.flush();
    stdio.out.context.unbuffered_writer.context.close();

    const out_file = try fs.cwd().createFile(out, .{ .exclusive = false });
    defer out_file.close();

    var writer = io.bufferedWriter(out_file.writer());
    try generate(writer.writer(), game);
    try writer.flush();
}

fn parseLine(allocator: *mem.Allocator, game: *Game, str: []const u8) !void {
    switch (try format.parseEscape(allocator, str)) {
        .starters => |starter| _ = try game.starters.put(allocator, starter.index, starter.value),
        .tms => |tm| _ = try game.tms.put(allocator, tm.index, tm.value),
        .hms => |hm| _ = try game.hms.put(allocator, hm.index, hm.value),
        .trainers => |trainers| {
            const trainer = try game.trainers.getOrPutValue(allocator, trainers.index, Trainer{});
            switch (trainers.value) {
                .name => |name| trainer.name = try allocator.dupe(u8, name),
                .class => |class| trainer.class = class,
                .encounter_music => |encounter_music| trainer.encounter_music = encounter_music,
                .trainer_picture => |trainer_picture| trainer.trainer_picture = trainer_picture,
                .party_type => |party_type| trainer.party_type = party_type,
                .party_size => |party_size| trainer.party_size = party_size,
                .items => |items| _ = try trainer.items.put(allocator, items.index, items.value),
                .party => |party| {
                    const member = try trainer.party.getOrPutValue(allocator, party.index, PartyMember{});
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
            const move = try game.moves.getOrPutValue(allocator, moves.index, Move{});
            switch (moves.value) {
                .name => |name| move.name = try allocator.dupe(u8, name),
                .description => |description| move.description = try allocator.dupe(u8, description),
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
            const pokemon = try game.pokemons.getOrPutValue(allocator, pokemons.index, Pokemon{});
            switch (pokemons.value) {
                .name => |name| pokemon.name = try allocator.dupe(u8, name),
                .stats => |stats| switch (stats) {
                    .hp => |hp| pokemon.stats.hp = hp,
                    .attack => |attack| pokemon.stats.attack = attack,
                    .defense => |defense| pokemon.stats.defense = defense,
                    .speed => |speed| pokemon.stats.speed = speed,
                    .sp_attack => |sp_attack| pokemon.stats.sp_attack = sp_attack,
                    .sp_defense => |sp_defense| pokemon.stats.sp_defense = sp_defense,
                },
                .ev_yield => |ev_yield| switch (ev_yield) {
                    .hp => |hp| pokemon.ev_yield.hp = hp,
                    .attack => |attack| pokemon.ev_yield.attack = attack,
                    .defense => |defense| pokemon.ev_yield.defense = defense,
                    .speed => |speed| pokemon.ev_yield.speed = speed,
                    .sp_attack => |sp_attack| pokemon.ev_yield.sp_attack = sp_attack,
                    .sp_defense => |sp_defense| pokemon.ev_yield.sp_defense = sp_defense,
                },
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .base_exp_yield => |base_exp_yield| pokemon.base_exp_yield = base_exp_yield,
                .gender_ratio => |gender_ratio| pokemon.gender_ratio = gender_ratio,
                .egg_cycles => |egg_cycles| pokemon.egg_cycles = egg_cycles,
                .base_friendship => |base_friendship| pokemon.base_friendship = base_friendship,
                .growth_rate => |growth_rate| pokemon.growth_rate = growth_rate,
                .color => |color| pokemon.color = color,
                .pokedex_entry => |pokedex_entry| pokemon.pokedex_entry = pokedex_entry,
                .abilities => |ability| _ = try pokemon.abilities.put(allocator, ability.index, ability.value),
                .egg_groups => |egg_group| _ = try pokemon.egg_groups.put(allocator, egg_group.index, egg_group.value),
                .hms => |hm| _ = try pokemon.hms.put(allocator, hm.index, hm.value),
                .items => |item| _ = try pokemon.items.put(allocator, item.index, item.value),
                .tms => |tm| _ = try pokemon.tms.put(allocator, tm.index, tm.value),
                .types => |_type| _ = try pokemon.types.put(allocator, _type.index, _type.value),
                .moves => |moves| {
                    const move = try pokemon.moves.getOrPutValue(allocator, moves.index, LevelUpMove{});
                    switch (moves.value) {
                        .id => |id| move.id = id,
                        .level => |level| move.level = level,
                    }
                },
                .evos => |evos| {
                    const evo = try pokemon.evos.getOrPutValue(allocator, evos.index, Evolution{});
                    switch (evos.value) {
                        .method => |method| evo.method = method,
                        .param => |param| evo.param = param,
                        .target => |target| evo.target = target,
                    }
                },
            }
        },
        .abilities => |abilities| {
            const ability = try game.abilities.getOrPutValue(allocator, abilities.index, Ability{});
            switch (abilities.value) {
                .name => |name| ability.name = try allocator.dupe(u8, name),
            }
        },
        .types => |types| {
            const _type = try game.types.getOrPutValue(allocator, types.index, Type{});
            switch (types.value) {
                .name => |name| _type.name = try allocator.dupe(u8, name),
            }
        },
        .items => |items| {
            const item = try game.items.getOrPutValue(allocator, items.index, Item{});
            switch (items.value) {
                .name => |name| item.name = try allocator.dupe(u8, name),
                .description => |description| item.description = try allocator.dupe(u8, description),
                .price => |price| item.price = price,
                .battle_effect => |battle_effect| item.battle_effect = battle_effect,
                .pocket => |pocket| item.pocket = pocket,
            }
        },
        .pokedex => |pokedex| {
            const pokedex_entry = try game.pokedex.getOrPutValue(allocator, pokedex.index, Pokedex{});
            switch (pokedex.value) {
                .category => |category| pokedex_entry.category = try allocator.dupe(u8, category),
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
        => return error.ParserFailed,
    }
}

fn generate(writer: anytype, game: Game) !void {
    const unknown = "???";
    const stat_names = [_][2][]const u8{
        .{ "hp", "Hp" },
        .{ "attack", "Attack" },
        .{ "defense", "Defense" },
        .{ "sp_attack", "Sp. Atk" },
        .{ "sp_defense", "Sp. Def" },
        .{ "speed", "Speed" },
    };

    try writer.writeAll("<!DOCTYPE html>\n");
    try writer.writeAll("<html>\n");
    try writer.writeAll("<head>\n");
    try writer.writeAll("<title>Wiki</title>\n");
    try writer.writeAll("<style>\n");

    try writer.writeAll("* {font-family: Arial, Helvetica, sans-serif;}\n");
    try writer.writeAll(".type {border-style: solid; border-width: 1px; border-color: black; color: white;}\n");
    try writer.writeAll(".type_Bug {background-color: #88960e;}\n");
    try writer.writeAll(".type_Dark {background-color: #3c2d23;}\n");
    try writer.writeAll(".type_Dragon {background-color: #4e3ba4;}\n");
    try writer.writeAll(".type_Electric {background-color: #e79302;}\n");
    try writer.writeAll(".type_Fairy {background-color: #e08ee0;}\n");
    try writer.writeAll(".type_Fighting {background-color: #5f2311;}\n");
    try writer.writeAll(".type_Fire {background-color: #c72100;}\n");
    try writer.writeAll(".type_Flying {background-color: #5d73d4;}\n");
    try writer.writeAll(".type_Ghost {background-color: #454593;}\n");
    try writer.writeAll(".type_Grass {background-color: #389a02;}\n");
    try writer.writeAll(".type_Ground {background-color: #ad8c33;}\n");
    try writer.writeAll(".type_Ice {background-color: #6dd3f5;}\n");
    try writer.writeAll(".type_Normal {background-color: #ada594;}\n");
    try writer.writeAll(".type_Poison {background-color: #6b246e;}\n");
    try writer.writeAll(".type_Psychic {background-color: #dc3165;}\n");
    try writer.writeAll(".type_Rock {background-color: #9e863d;}\n");
    try writer.writeAll(".type_Steel {background-color: #8e8e9f;}\n");
    try writer.writeAll(".type_Water {background-color: #0c67c2;}\n");

    try writer.writeAll(".pokemon_stat {width:100%;}\n");
    try writer.writeAll(".pokemon_stat_table {width:50%;}\n");
    try writer.writeAll(".pokemon_stat_hp {background-color: #6ab04c;}\n");
    try writer.writeAll(".pokemon_stat_attack {background-color: #eb4d4b;}\n");
    try writer.writeAll(".pokemon_stat_defense {background-color: #f0932b;}\n");
    try writer.writeAll(".pokemon_stat_sp_attack {background-color:#be2edd;}\n");
    try writer.writeAll(".pokemon_stat_sp_defense {background-color: #686de0;}\n");
    try writer.writeAll(".pokemon_stat_speed {background-color: #f9ca24;}\n");
    try writer.writeAll(".pokemon_stat_total {background-color: #95afc0;}\n");
    for ([_]void{{}} ** 101) |_, i| {
        try writer.print(".pokemon_stat_p{} {{width: {}%;}}\n", .{ i, i });
    }

    try writer.writeAll("</style>\n");
    try writer.writeAll("</head>\n");
    try writer.writeAll("<body>\n");

    try writer.writeAll("<h1>Starters</h1>\n");
    try writer.writeAll("<table>\n");
    for (game.starters.values()) |starter| {
        const starter_name = if (game.pokemons.get(starter)) |p| p.name else unknown;
        try writer.print("<tr><td><a href=\"#pokemon_{}\">{}</a></td></tr>", .{ starter, starter_name });
    }
    try writer.writeAll("</table>\n");

    try writer.writeAll("<h1>Pokedex</h1>\n");
    try writer.writeAll("<table>\n");
    for (game.pokedex.values()) |dex, di| {
        const dex_num = game.pokedex.at(di).key;

        const pokemon = for (game.pokemons.values()) |pokemon, pi| {
            const species = game.pokemons.at(pi).key;
            if (pokemon.pokedex_entry == dex_num)
                break .{ .name = pokemon.name, .species = species };
        } else continue;

        try writer.print("<tr><td><a href=\"#pokemon_{}\">#{} {}</a></td></tr>\n", .{ pokemon.species, dex_num, pokemon.name });
    }
    try writer.writeAll("</table>\n");

    try writer.writeAll("<h1>Pokemons</h1>\n");
    for (game.pokemons.values()) |pokemon, pi| {
        const species = game.pokemons.at(pi).key;
        try writer.print("<h2 id=\"pokemon_{}\">#{} {}</h2>\n", .{ species, species, pokemon.name });

        try writer.writeAll("<table>\n");
        try writer.writeAll("<tr><td>Type:</td><td>");
        outer: for (pokemon.types.values()) |t, ti| {
            // Continue if we have already handle the type before
            for (pokemon.types.values()[0..ti]) |prev| {
                if (t == prev)
                    continue :outer;
            }

            const type_name = humanize(if (game.types.get(t)) |ty| ty.name else unknown);
            if (ti != 0)
                try writer.writeAll(" ");

            try writer.print("<a href=\"#type_{}\" class=\"type type_{}\"><b>{}</b></a>", .{ t, type_name, type_name });
        }
        try writer.writeAll("</td>\n");

        try writer.writeAll("<tr><td>Abilities:</td><td>");
        for (pokemon.abilities.values()) |a, ai| {
            if (a == 0)
                continue;
            if (ai != 0)
                try writer.writeAll(", ");

            const ability_name = if (game.abilities.get(a)) |abil| abil.name else unknown;
            try writer.print("<a href=\"#ability_{}\">{}</a>", .{ a, humanize(ability_name) });
        }
        try writer.writeAll("</td>\n");

        try writer.writeAll("<tr><td>Items:</td><td>");
        for (pokemon.items.values()) |item, ii| {
            if (ii != 0)
                try writer.writeAll(", ");

            const item_name = if (game.items.get(item)) |it| it.name else unknown;
            try writer.print("<a href=\"#item_{}\">{}</a>", .{ item, humanize(item_name) });
        }
        try writer.writeAll("</td>\n");

        try writer.writeAll("<tr><td>Egg Groups:</td><td>");
        outer: for (pokemon.egg_groups.values()) |egg_group, ei| {
            // Continue if we have already handle the type before
            for (pokemon.egg_groups.values()[0..ei]) |prev| {
                if (egg_group == prev)
                    continue :outer;
            }

            if (ei != 0)
                try writer.writeAll(", ");

            try writer.print("{}", .{humanize(@tagName(egg_group))});
        }
        try writer.writeAll("</td>\n");
        try printSimpleFields(writer, pokemon);
        try writer.writeAll("</table>\n");

        try writer.writeAll("<details><summary><b>Evolutions</b></summary>\n");
        try writer.writeAll("<table>\n");
        try writer.writeAll("<tr><th>Evolution</th><th>Method</th></tr>\n");
        for (pokemon.evos.values()) |evo| {
            const target_name = humanize(if (game.pokemons.get(evo.target)) |p| p.name else unknown);
            const param_item_name = humanize(if (game.items.get(evo.param)) |i| i.name else unknown);
            const param_move_name = humanize(if (game.moves.get(evo.param)) |i| i.name else unknown);
            const param_pokemon_name = humanize(if (game.pokemons.get(evo.param)) |i| i.name else unknown);

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
        try writer.writeAll("</table></details>\n");

        try writer.writeAll("<details><summary><b>Stats</b></summary>\n");
        try writer.writeAll("<table class=\"pokemon_stat_table\">\n");

        var total_stats: usize = 0;
        inline for (stat_names) |stat| {
            const value = @field(pokemon.stats, stat[0]);
            const percent = @floatToInt(usize, (@intToFloat(f64, value) / 255) * 100);
            try writer.print("<tr><td>{}:</td><td class=\"pokemon_stat\"><div class=\"pokemon_stat_p{} pokemon_stat_{}\">{}</div></td></tr>\n", .{ stat[1], percent, stat[0], value });
            total_stats += value;
        }

        const percent = @floatToInt(usize, (@intToFloat(f64, total_stats) / 1000) * 100);
        try writer.print("<tr><td>Total:</td><td><div class=\"pokemon_stat pokemon_stat_p{} pokemon_stat_total\">{}</div></td></tr>\n", .{ percent, total_stats });
        try writer.writeAll("</table></details>\n");

        try writer.writeAll("<details><summary><b>Ev Yield</b></summary>\n");
        try writer.writeAll("<table>\n");

        total_stats = 0;
        inline for (stat_names) |stat| {
            const value = @field(pokemon.ev_yield, stat[0]);
            try writer.print("<tr><td>{}:</td><td>{}</td></tr>\n", .{ stat[1], value });
            total_stats += value;
        }

        try writer.print("<tr><td>Total:</td><td>{}</td></tr>\n", .{total_stats});
        try writer.writeAll("</table></details>\n");

        try writer.writeAll("<details><summary><b>Learnset</b></summary>\n");
        try writer.writeAll("<table>\n");
        for (pokemon.moves.values()) |move| {
            const move_name = humanize(if (game.moves.get(move.id)) |m| m.name else unknown);
            try writer.print("<tr><td>Lvl {}</td><td><a href=\"#move_{}\">{}</a></td></tr>\n", .{ move.level, move.id, move_name });
        }
        try writer.writeAll("</table>\n");

        try writer.writeAll("<table>\n");
        for ([_]Array(u8, bool){ pokemon.hms, pokemon.tms }) |machines, i| {
            const prefix = if (i == 0) "TM" else "HM";
            const moves = if (i == 0) game.tms else game.hms;

            for (machines.values()) |is_learned, index| {
                if (is_learned)
                    continue;
                const id = machines.at(index).key;
                const move_id = moves.get(id) orelse continue;
                const move_name = humanize(if (game.moves.get(move_id.*)) |m| m.name else unknown);
                try writer.print(
                    "<tr><td>{}{}</td><td><a href=\"#move_{}\">{}</a></td></tr>\n",
                    .{ prefix, id + 1, move_id, move_name },
                );
            }
        }
        try writer.writeAll("</table>\n");
        try writer.writeAll("</details>\n");
    }

    try writer.writeAll("<h1>Moves</h1>\n");
    for (game.moves.values()) |move, mi| {
        const move_id = game.moves.at(mi).key;
        const move_name = humanize(move.name);
        try writer.print("<h2 id=\"move_{}\">{}</h2>\n", .{ move_id, move_name });
        try writer.print("<p>{}</p>\n", .{move.description});
        try writer.writeAll("<table>\n");

        const type_name = humanize(if (game.types.get(move.type)) |t| t.name else unknown);
        try writer.print(
            "<tr><td>Type:</td><td><a href=\"type_{}\" class=\"type type_{}\"><b>{}</b></a></td></tr>\n",
            .{ move.type, type_name, type_name },
        );
        try writer.print("<tr><td>Category:</td><td>{}</td></tr>\n", .{@tagName(move.category)});
        try printSimpleFields(writer, move);
        try writer.writeAll("</table>\n");
    }

    try writer.writeAll("<h1>Items</h1>\n");
    for (game.items.values()) |item, ii| {
        const item_id = game.items.at(ii).key;
        const item_name = humanize(item.name);
        try writer.print("<h2 id=\"item_{}\">{}</h2>\n", .{ item_id, item_name });
        try writer.print("<p>{}</p>\n", .{item.description});

        try writer.writeAll("<table>\n");
        try printSimpleFields(writer, item);
        try writer.writeAll("</table>\n");
    }

    try writer.writeAll("</body>\n");
    try writer.writeAll("</html>\n");
}

pub fn printSimpleFields(writer: anytype, value: anytype) !void {
    inline for (@typeInfo(@TypeOf(value)).Struct.fields) |field| {
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
        try writeHumanized(writer, self.str);
    }
};

fn humanize(str: []const u8) HumanizeFormatter {
    return HumanizeFormatter{ .str = str };
}

fn writeHumanized(writer: anytype, str: []const u8) !void {
    var first = true;
    var it = mem.tokenize(str, "_ ");
    while (it.next()) |word| : (first = false) {
        if (!first)
            try writer.writeAll(" ");

        try writer.writeByte(ascii.toUpper(word[0]));
        for (word[1..]) |c|
            try writer.writeByte(ascii.toLower(c));
    }
}

const Array = util.container.IntMap.Unmanaged;

const Game = struct {
    starters: Array(u8, u16) = Array(u8, u16){},
    trainers: Array(u16, Trainer) = Array(u16, Trainer){},
    moves: Array(u16, Move) = Array(u16, Move){},
    pokemons: Array(u16, Pokemon) = Array(u16, Pokemon){},
    abilities: Array(u16, Ability) = Array(u16, Ability){},
    types: Array(u8, Type) = Array(u8, Type){},
    tms: Array(u8, u16) = Array(u8, u16){},
    hms: Array(u8, u16) = Array(u8, u16){},
    items: Array(u16, Item) = Array(u16, Item){},
    pokedex: Array(u16, Pokedex) = Array(u16, Pokedex){},
};

const Trainer = struct {
    class: u8 = 0,
    encounter_music: u8 = 0,
    trainer_picture: u8 = 0,
    name: []const u8 = "",
    party_type: format.PartyType = .none,
    party_size: u8 = 0,
    party: Array(u8, PartyMember) = Array(u8, PartyMember){},
    items: Array(u8, u16) = Array(u8, u16){},
};

const PartyMember = struct {
    ability: u4 = 0,
    level: u8 = 0,
    species: u16 = 0,
    item: u16 = 0,
    moves: Array(u8, u16) = Array(u8, u16){},
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
    base_exp_yield: u8 = 0,
    gender_ratio: u8 = 0,
    egg_cycles: u8 = 0,
    base_friendship: u8 = 0,
    pokedex_entry: u16 = 0,
    growth_rate: format.GrowthRate = .medium_fast,
    color: format.Color = .blue,
    tms: Array(u8, bool) = Array(u8, bool){},
    hms: Array(u8, bool) = Array(u8, bool){},
    types: Array(u8, u8) = Array(u8, u8){},
    abilities: Array(u8, u8) = Array(u8, u8){},
    items: Array(u8, u16) = Array(u8, u16){},
    egg_groups: Array(u8, format.EggGroup) = Array(u8, format.EggGroup){},
    evos: Array(u8, Evolution) = Array(u8, Evolution){},
    moves: Array(u8, LevelUpMove) = Array(u8, LevelUpMove){},
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
