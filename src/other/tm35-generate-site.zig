const clap = @import("clap");
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

const exit = util.exit;
const escape = util.escape;
const parse = util.parse;

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
    strings: *util.container.StringCache(.{}),
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) u8 {
    const out = args.option("--output") orelse "site.html";

    var fifo = util.read.Fifo(.Dynamic).init(allocator);
    var obj = Object{};
    while (util.read.line(stdio.in, &fifo) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        parseLine(allocator, strings, &obj, line) catch |err| switch (err) {
            error.OutOfMemory => return exit.allocErr(stdio.err),
        };
        stdio.out.print("{}\n", .{line}) catch |err| return exit.stdoutErr(stdio.err, err);
    }

    // We are now completly done with stdout, so we close it. This gives programs further down the
    // pipeline the ability to finish up what they need to do while we generate the site.
    stdio.out.context.flush() catch |err| return exit.stdoutErr(stdio.err, err);
    stdio.out.context.unbuffered_writer.context.close();

    const out_file = fs.cwd().createFile(out, .{ .exclusive = false }) catch |err| return exit.createErr(stdio.err, out, err);
    defer out_file.close();

    var writer = io.bufferedWriter(out_file.writer());
    generate(writer.writer(), obj) catch |err| return exit.writeErr(stdio.err, out, err);
    writer.flush() catch |err| return exit.writeErr(stdio.err, out, err);

    return 0;
}

fn parseLine(allocator: *mem.Allocator, strings: *util.container.StringCache(.{}), obj: *Object, str: []const u8) !void {
    var curr = obj;
    var p = parse.MutParser{ .str = str };
    while (true) {
        if (p.parse(parse.anyField)) |field| {
            const string = try strings.put(field);
            const entry = try curr.fields.getOrPutValue(allocator, strings.get(string), Object{});
            curr = &entry.value;
        } else |_| if (p.parse(parse.index)) |index| {
            curr = try curr.indexs.getOrPutValue(allocator, index, Object{
                .fields = Fields.init(allocator),
            });
        } else |_| if (p.parse(parse.strv)) |value| {
            curr.value = strings.get(try strings.put(value));
            return;
        } else |_| {
            return;
        }
    }
}

fn generate(writer: anytype, root: Object) !void {
    const unknown = "???";
    const escapes = comptime blk: {
        var res: [255][]const u8 = undefined;
        mem.copy([]const u8, res[0..], &escape.default_escapes);
        res['\r'] = "\\r";
        res['\n'] = "\\n";
        res['\\'] = "\\\\";
        break :blk res;
    };
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

    if (root.fields.get("starters")) |starters| {
        try writer.writeAll("<h1>Starters</h1>\n");
        try writer.writeAll("<table>\n");
        for (starters.indexs.values()) |starter_v, si| {
            const starter = fmt.parseInt(usize, starter_v.value orelse continue, 10) catch continue;
            const starter_name = humanize(root.getArrayFieldValue("pokemons", starter, "name") orelse unknown);
            try writer.print("<tr><td><a href=\"#pokemon_{}\">{}</a></td></tr>", .{ starter, starter_name });
        }
        try writer.writeAll("</table>\n");
    }

    const m_pokemons = root.fields.get("pokemons");
    const m_pokedex = root.fields.get("pokedex");
    if (m_pokemons != null and m_pokedex != null) {
        const pokemons = m_pokemons.?;
        const pokedex = m_pokedex.?;
        try writer.writeAll("<h1>Pokedex</h1>\n");
        try writer.writeAll("<table>\n");
        for (pokedex.indexs.values()) |dex, di| {
            const dex_num = pokemons.indexs.at(di).key;

            const species = for (pokemons.indexs.values()) |pokemon, pi| {
                const species = pokemons.indexs.at(pi).key;
                const dex_entry_str = pokemon.getFieldValue("pokedex_entry") orelse continue;
                const dex_entry = fmt.parseInt(usize, dex_entry_str, 10) catch continue;
                if (dex_entry == dex_num)
                    break species;
            } else continue;

            const pokemon_name = humanize(root.getArrayFieldValue("pokemons", species, "name") orelse unknown);
            try writer.print("<tr><td><a href=\"#pokemon_{}\">#{} {}</a></td></tr>\n", .{ species, dex_num, pokemon_name });
        }
        try writer.writeAll("</table>\n");
    }

    if (m_pokemons) |pokemons| {
        try writer.writeAll("<h1>Pokemons</h1>\n");

        for (pokemons.indexs.values()) |pokemon, pi| {
            const species = pokemons.indexs.at(pi).key;
            const pokemon_name = humanize(pokemon.getFieldValue("name") orelse unknown);
            try writer.print("<h2 id=\"pokemon_{}\">#{} {}</h2>\n", .{ species, species, pokemon_name });

            try writer.writeAll("<table>\n");
            if (pokemon.fields.get("types")) |types| {
                try writer.writeAll("<tr><td>Type:</td><td>");
                outer: for (types.indexs.values()) |t, ti| {
                    const type_str = t.value orelse continue;
                    for (types.indexs.values()[0..ti]) |prev| {
                        const prev_str = prev.value orelse continue;
                        if (mem.eql(u8, prev_str, type_str))
                            continue :outer;
                    }

                    const type_i = fmt.parseInt(usize, type_str, 10) catch continue;
                    const type_name = humanize(root.getArrayFieldValue("types", type_i, "name") orelse unknown);
                    if (ti != 0)
                        try writer.writeAll(" ");

                    try writer.print("<a href=\"#type_{}\" class=\"type type_{}\"><b>{}</b></a>", .{ type_i, type_name, type_name });
                }
                try writer.writeAll("</td>\n");
            }

            if (pokemon.fields.get("abilities")) |abilities| {
                try writer.writeAll("<tr><td>Abilities:</td><td>");
                for (abilities.indexs.values()) |ability_v, ai| {
                    const ability = fmt.parseInt(usize, ability_v.value orelse continue, 10) catch continue;
                    const ability_name = root.getArrayFieldValue("abilities", ability, "name") orelse unknown;
                    if (ability == 0)
                        continue;
                    if (ai != 0)
                        try writer.writeAll(", ");

                    try writer.print("<a href=\"#ability_{}\">{}</a>", .{ ability, humanize(ability_name) });
                }
                try writer.writeAll("</td>\n");
            }

            if (pokemon.fields.get("items")) |abilities| {
                try writer.writeAll("<tr><td>Items:</td><td>");
                for (abilities.indexs.values()) |item_v, ii| {
                    const item = fmt.parseInt(usize, item_v.value orelse continue, 10) catch continue;
                    const item_name = root.getArrayFieldValue("items", item, "name") orelse unknown;
                    if (ii != 0)
                        try writer.writeAll(", ");

                    try writer.print("<a href=\"#item_{}\">{}</a>", .{ item, humanize(item_name) });
                }
                try writer.writeAll("</td>\n");
            }

            if (pokemon.fields.get("egg_groups")) |egg_groups| {
                try writer.writeAll("<tr><td>Egg Groups:</td><td>");
                outer: for (egg_groups.indexs.values()) |egg_group_v, ei| {
                    const egg_group = egg_group_v.value orelse continue;
                    for (egg_groups.indexs.values()[0..ei]) |prev| {
                        const prev_str = prev.value orelse continue;
                        if (mem.eql(u8, prev_str, egg_group))
                            continue :outer;
                    }

                    if (ei != 0)
                        try writer.writeAll(", ");

                    try writer.print("{}", .{humanize(egg_group)});
                }
                try writer.writeAll("</td>\n");
            }

            var it = pokemon.fields.iterator();
            while (it.next()) |field| {
                const field_name = field.key;
                if (mem.eql(u8, field_name, "name"))
                    continue;

                const value = field.value.value orelse continue;
                try writer.print("<tr><td>{}:</td><td>{}</td></tr>\n", .{ humanize(field_name), humanize(value) });
            }

            try writer.writeAll("</table>\n");

            if (pokemon.fields.get("evos")) |evos| {
                try writer.writeAll("<details><summary><b>Evolutions</b></summary>\n");
                try writer.writeAll("<table>\n");
                try writer.writeAll("<tr><th>Evolution</th><th>Method</th></tr>\n");
                for (evos.indexs.values()) |evo| {
                    const method = evo.getFieldValue("method") orelse continue;
                    const param = fmt.parseInt(usize, evo.getFieldValue("param") orelse continue, 10) catch continue;
                    const target = fmt.parseInt(usize, evo.getFieldValue("target") orelse continue, 10) catch continue;

                    const target_name = humanize(root.getArrayFieldValue("pokemons", target, "name") orelse unknown);
                    const param_item_name = humanize(root.getArrayFieldValue("items", param, "name") orelse unknown);
                    const param_move_name = humanize(root.getArrayFieldValue("moves", param, "name") orelse unknown);
                    const param_pokemon_name = humanize(root.getArrayFieldValue("pokemons", param, "name") orelse unknown);

                    try writer.print("<tr><td><a href=\"#pokemon_{}\">{}</a></td><td>", .{ target, target_name });
                    if (mem.eql(u8, method, "friend_ship")) {
                        try writer.print("Level up with friendship high", .{});
                    } else if (mem.eql(u8, method, "friend_ship_during_day")) {
                        try writer.print("Level up with friendship high during daytime", .{});
                    } else if (mem.eql(u8, method, "friend_ship_during_night")) {
                        try writer.print("Level up with friendship high during night", .{});
                    } else if (mem.eql(u8, method, "level_up")) {
                        try writer.print("Level {}", .{param});
                    } else if (mem.eql(u8, method, "trade")) {
                        try writer.print("Trade", .{});
                    } else if (mem.eql(u8, method, "trade_holding_item")) {
                        try writer.print("Trade holding <a href=\"#item_{}\">{}</a>", .{ param, param_item_name });
                    } else if (mem.eql(u8, method, "use_item")) {
                        try writer.print("Using <a href=\"#item_{}\">{}</a>", .{ param, param_item_name });
                    } else if (mem.eql(u8, method, "attack_gth_defense")) {
                        try writer.print("Level {} when Attack > Defense", .{param});
                    } else if (mem.eql(u8, method, "attack_eql_defense")) {
                        try writer.print("Level {} when Attack = Defense", .{param});
                    } else if (mem.eql(u8, method, "attack_lth_defense")) {
                        try writer.print("Level {} when Attack < Defense", .{param});
                    } else if (mem.eql(u8, method, "personality_value1")) {
                        try writer.print("Level {} when having personallity value type 1", .{param});
                    } else if (mem.eql(u8, method, "personality_value2")) {
                        try writer.print("Level {} when having personallity value type 2", .{param});
                    } else if (mem.eql(u8, method, "level_up_may_spawn_pokemon")) {
                        // TODO: What Pokémon?
                        try writer.print("Level {} (May spawn another Pokémon when evolved)", .{param});
                    } else if (mem.eql(u8, method, "level_up_spawn_if_cond")) {
                        // TODO: What Pokémon? What condition?
                        try writer.print("Level {} (May spawn another Pokémon when evolved if conditions are met)", .{param});
                    } else if (mem.eql(u8, method, "beauty")) {
                        try writer.print("Level up when beauty hits {}", .{param});
                    } else if (mem.eql(u8, method, "use_item_on_male")) {
                        try writer.print("Using <a href=\"#item_{}\">{}</a> on a male", .{ param, param_item_name });
                    } else if (mem.eql(u8, method, "use_item_on_female")) {
                        try writer.print("Using <a href=\"#item_{}\">{}</a> on a female", .{ param, param_item_name });
                    } else if (mem.eql(u8, method, "level_up_holding_item_during_daytime")) {
                        try writer.print("Level up while holding <a href=\"#item_{}\">{}</a> during daytime", .{ param, param_item_name });
                    } else if (mem.eql(u8, method, "level_up_holding_item_during_the_night")) {
                        try writer.print("Level up while holding <a href=\"#item_{}\">{}</a> during night", .{ param, param_item_name });
                    } else if (mem.eql(u8, method, "level_up_knowning_move")) {
                        try writer.print("Level up while knowing <a href=\"#move_{}\">{}</a>", .{ param, param_move_name });
                    } else if (mem.eql(u8, method, "level_up_with_other_pokemon_in_party")) {
                        try writer.print("Level up with <a href=\"#pokemon_{}\">{}</a> in the Party", .{ param, param_pokemon_name });
                    } else if (mem.eql(u8, method, "level_up_male")) {
                        try writer.print("Level {} male", .{param});
                    } else if (mem.eql(u8, method, "level_up_female")) {
                        try writer.print("Level {} female", .{param});
                    } else if (mem.eql(u8, method, "level_up_in_special_magnetic_field")) {
                        try writer.print("Level up in special magnetic field", .{});
                    } else if (mem.eql(u8, method, "level_up_near_moss_rock")) {
                        try writer.print("Level up near moss rock", .{});
                    } else if (mem.eql(u8, method, "level_up_near_ice_rock")) {
                        try writer.print("Level up near ice rock", .{});
                    } else {
                        try writer.print("{}", .{unknown});
                    }
                    try writer.writeAll("</td></tr>\n");
                }
                try writer.writeAll("</table></details>\n");
            }

            if (pokemon.fields.get("stats")) |stats| {
                try writer.writeAll("<details><summary><b>Stats</b></summary>\n");
                try writer.writeAll("<table class=\"pokemon_stat_table\">\n");

                var total_stats: usize = 0;
                for (stat_names) |stat| {
                    const string = stats.getFieldValue(stat[0]) orelse continue;
                    const value = fmt.parseInt(usize, string, 10) catch continue;
                    const percent = @floatToInt(usize, (@intToFloat(f64, value) / 255) * 100);
                    try writer.print("<tr><td>{}:</td><td class=\"pokemon_stat\"><div class=\"pokemon_stat_p{} pokemon_stat_{}\">{}</div></td></tr>\n", .{ stat[1], percent, stat[0], value });
                    total_stats += value;
                }

                const percent = @floatToInt(usize, (@intToFloat(f64, total_stats) / 1000) * 100);
                try writer.print("<tr><td>Total:</td><td><div class=\"pokemon_stat pokemon_stat_p{} pokemon_stat_total\">{}</div></td></tr>\n", .{ percent, total_stats });
                try writer.writeAll("</table></details>\n");
            }

            if (pokemon.fields.get("ev_yield")) |stats| {
                try writer.writeAll("<details><summary><b>Ev Yield</b></summary>\n");
                try writer.writeAll("<table>\n");

                var total_stats: usize = 0;
                for (stat_names) |stat| {
                    const string = stats.getFieldValue(stat[0]) orelse continue;
                    const value = fmt.parseInt(usize, string, 10) catch continue;
                    try writer.print("<tr><td>{}:</td><td>{}</td></tr>\n", .{ stat[1], value });
                    total_stats += value;
                }

                try writer.print("<tr><td>Total:</td><td>{}</td></tr>\n", .{total_stats});
                try writer.writeAll("</table></details>\n");
            }

            const m_tms = pokemon.fields.get("tms");
            const m_hms = pokemon.fields.get("hms");
            const m_moves = pokemon.fields.get("moves");
            if (m_tms != null or m_hms != null or m_moves != null)
                try writer.writeAll("<details><summary><b>Learnset</b></summary>\n");

            if (m_moves) |moves| {
                try writer.writeAll("<table>\n");
                for (moves.indexs.values()) |move| {
                    const level = move.getFieldValue("level") orelse continue;
                    const move_id = fmt.parseInt(usize, move.getFieldValue("id") orelse continue, 10) catch continue;
                    const move_name = humanize(root.getArrayFieldValue("moves", move_id, "name") orelse unknown);
                    try writer.print("<tr><td>Lvl {}</td><td><a href=\"#move_{}\">{}</a></td></tr>\n", .{ level, move_id, move_name });
                }
                try writer.writeAll("</table>\n");
            }

            if (m_tms != null or m_hms != null)
                try writer.writeAll("<table>\n");
            for ([_]?Object{ m_tms, m_hms }) |m_machines, i| {
                const machines = m_machines orelse continue;
                const field = if (i == 0) "tms" else "hms";
                const prefix = if (i == 0) "TM" else "HM";
                for (machines.indexs.values()) |is_learned, index| {
                    if (!mem.eql(u8, is_learned.value orelse continue, "true"))
                        continue;
                    const id = machines.indexs.at(index).key;
                    const move_id = fmt.parseInt(usize, root.getArrayValue(field, id) orelse continue, 10) catch continue;
                    const move_name = humanize(root.getArrayFieldValue("moves", move_id, "name") orelse unknown);
                    try writer.print("<tr><td>{}{}</td><td><a href=\"#move_{}\">{}</a></td></tr>\n", .{ prefix, id + 1, move_id, move_name });
                }
            }
            if (m_tms != null or m_hms != null)
                try writer.writeAll("</table>\n");
            if (m_tms != null or m_hms != null or m_moves != null)
                try writer.writeAll("</details>\n");
        }
    }

    if (root.fields.get("moves")) |moves| {
        try writer.writeAll("<h1>Moves</h1>\n");
        for (moves.indexs.values()) |move, mi| {
            const move_id = moves.indexs.at(mi).key;
            const move_name = humanize(move.getFieldValue("name") orelse unknown);
            try writer.print("<h2 id=\"move_{}\">{}</h2>\n", .{ move_id, move_name });

            if (move.getFieldValue("description")) |description| {
                try writer.writeAll("<p>");
                try escape.writeUnEscaped(writer, description, escapes);
                try writer.writeAll("</p>\n");
            }

            try writer.writeAll("<table>\n");

            if (move.getFieldValue("type")) |t| {
                const type_i = fmt.parseInt(usize, t, 10) catch continue;
                const type_name = humanize(root.getArrayFieldValue("types", type_i, "name") orelse unknown);
                try writer.print("<tr><td>Type:</td><td><a href=\"type_{}\" class=\"type type_{}\"><b>{}</b></a></td></tr>\n", .{ type_i, type_name, type_name });
            }

            var it = move.fields.iterator();
            while (it.next()) |field| {
                const field_name = field.key;
                if (mem.eql(u8, field_name, "name"))
                    continue;
                if (mem.eql(u8, field_name, "description"))
                    continue;

                const value = field.value.value orelse continue;
                try writer.print("<tr><td>{}:</td><td>{}</td></tr>\n", .{ humanize(field_name), humanize(value) });
            }

            try writer.writeAll("</table>\n");
        }
    }

    if (root.fields.get("items")) |items| {
        try writer.writeAll("<h1>Items</h1>\n");
        for (items.indexs.values()) |item, ii| {
            const item_id = items.indexs.at(ii).key;
            const item_name = humanize(item.getFieldValue("name") orelse unknown);
            try writer.print("<h2 id=\"item_{}\">{}</h2>\n", .{ item_id, item_name });

            if (item.getFieldValue("description")) |description| {
                try writer.writeAll("<p>");
                try escape.writeUnEscaped(writer, description, escapes);
                try writer.writeAll("</p>\n");
            }

            try writer.writeAll("<table>\n");

            var it = item.fields.iterator();
            while (it.next()) |field| {
                const field_name = field.key;
                if (mem.eql(u8, field_name, "name"))
                    continue;
                if (mem.eql(u8, field_name, "description"))
                    continue;

                const value = field.value.value orelse continue;
                try writer.print("<tr><td>{}:</td><td>{}</td></tr>\n", .{ humanize(field_name), humanize(value) });
            }

            try writer.writeAll("</table>\n");
        }
    }

    try writer.writeAll("</body>\n");
    try writer.writeAll("</html>\n");
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
    if (fmt.parseInt(isize, str, 10)) |_| {
        try writer.writeAll(str);
    } else |_| {
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
}

const Fields = std.StringHashMapUnmanaged(Object);
const Indexs = util.container.IntMap.Unmanaged(usize, Object);

const Object = struct {
    fields: Fields = Fields{},
    indexs: Indexs = Indexs{},
    value: ?[]const u8 = null,

    fn getFieldValue(obj: Object, field: []const u8) ?[]const u8 {
        if (obj.fields.get(field)) |v|
            return v.value;
        return null;
    }

    fn getArrayValue(obj: Object, array_field: []const u8, index: usize) ?[]const u8 {
        if (obj.fields.get(array_field)) |array|
            if (array.indexs.get(index)) |elem|
                return elem.value;
        return null;
    }

    fn getArrayFieldValue(obj: Object, array_field: []const u8, index: usize, field: []const u8) ?[]const u8 {
        if (obj.fields.get(array_field)) |array|
            if (array.indexs.get(index)) |elem|
                return elem.getFieldValue(field);
        return null;
    }
};
