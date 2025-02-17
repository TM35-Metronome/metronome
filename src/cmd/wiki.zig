pub const command = Command{
    .name = "wiki",
    .description = "",
    .parameters = Command.Parameter.fromType(Options, .{}),
    .createOptions = Command.Options.createFromType(Options),
    .function = randomize,
};

fn randomize(gpa: std.mem.Allocator, options: Command.Options, game: *core.Game) anyerror!void {
    switch (game.*) {
        inline else => |*g| return generateWiki(gpa, options.cast(Options).*, g),
    }
}

fn generateWiki(gpa: std.mem.Allocator, options: Options, game: anytype) !void {
    _ = options; // autofix
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const header =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
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
        \\.pokemon_stat {width:80%; border-style: solid; border-width: 1px; border-color: black;}
        \\.pokemon_stat_hp {background-color: #6ab04c;}
        \\.pokemon_stat_attack {background-color: #eb4d4b;}
        \\.pokemon_stat_defense {background-color: #f0932b;}
        \\.pokemon_stat_sp_attack {background-color:#be2edd;}
        \\.pokemon_stat_sp_defense {background-color: #686de0;}
        \\.pokemon_stat_speed {background-color: #f9ca24;}
        \\.pokemon_stat_total {background-color: #95afc0;}
        \\.pokemon_stat_p0 {width: 0%}
        \\.pokemon_stat_p1 {width: 1%}
        \\.pokemon_stat_p2 {width: 2%}
        \\.pokemon_stat_p3 {width: 3%}
        \\.pokemon_stat_p4 {width: 4%}
        \\.pokemon_stat_p5 {width: 5%}
        \\.pokemon_stat_p6 {width: 6%}
        \\.pokemon_stat_p7 {width: 7%}
        \\.pokemon_stat_p8 {width: 8%}
        \\.pokemon_stat_p9 {width: 9%}
        \\.pokemon_stat_p10 {width: 10%}
        \\.pokemon_stat_p11 {width: 11%}
        \\.pokemon_stat_p12 {width: 12%}
        \\.pokemon_stat_p13 {width: 13%}
        \\.pokemon_stat_p14 {width: 14%}
        \\.pokemon_stat_p15 {width: 15%}
        \\.pokemon_stat_p16 {width: 16%}
        \\.pokemon_stat_p17 {width: 17%}
        \\.pokemon_stat_p18 {width: 18%}
        \\.pokemon_stat_p19 {width: 19%}
        \\.pokemon_stat_p20 {width: 20%}
        \\.pokemon_stat_p21 {width: 21%}
        \\.pokemon_stat_p22 {width: 22%}
        \\.pokemon_stat_p23 {width: 23%}
        \\.pokemon_stat_p24 {width: 24%}
        \\.pokemon_stat_p25 {width: 25%}
        \\.pokemon_stat_p26 {width: 26%}
        \\.pokemon_stat_p27 {width: 27%}
        \\.pokemon_stat_p28 {width: 28%}
        \\.pokemon_stat_p29 {width: 29%}
        \\.pokemon_stat_p30 {width: 30%}
        \\.pokemon_stat_p31 {width: 31%}
        \\.pokemon_stat_p32 {width: 32%}
        \\.pokemon_stat_p33 {width: 33%}
        \\.pokemon_stat_p34 {width: 34%}
        \\.pokemon_stat_p35 {width: 35%}
        \\.pokemon_stat_p36 {width: 36%}
        \\.pokemon_stat_p37 {width: 37%}
        \\.pokemon_stat_p38 {width: 38%}
        \\.pokemon_stat_p39 {width: 39%}
        \\.pokemon_stat_p40 {width: 40%}
        \\.pokemon_stat_p41 {width: 41%}
        \\.pokemon_stat_p42 {width: 42%}
        \\.pokemon_stat_p43 {width: 43%}
        \\.pokemon_stat_p44 {width: 44%}
        \\.pokemon_stat_p45 {width: 45%}
        \\.pokemon_stat_p46 {width: 46%}
        \\.pokemon_stat_p47 {width: 47%}
        \\.pokemon_stat_p48 {width: 48%}
        \\.pokemon_stat_p49 {width: 49%}
        \\.pokemon_stat_p50 {width: 50%}
        \\.pokemon_stat_p51 {width: 51%}
        \\.pokemon_stat_p52 {width: 52%}
        \\.pokemon_stat_p53 {width: 53%}
        \\.pokemon_stat_p54 {width: 54%}
        \\.pokemon_stat_p55 {width: 55%}
        \\.pokemon_stat_p56 {width: 56%}
        \\.pokemon_stat_p57 {width: 57%}
        \\.pokemon_stat_p58 {width: 58%}
        \\.pokemon_stat_p59 {width: 59%}
        \\.pokemon_stat_p60 {width: 60%}
        \\.pokemon_stat_p61 {width: 61%}
        \\.pokemon_stat_p62 {width: 62%}
        \\.pokemon_stat_p63 {width: 63%}
        \\.pokemon_stat_p64 {width: 64%}
        \\.pokemon_stat_p65 {width: 65%}
        \\.pokemon_stat_p66 {width: 66%}
        \\.pokemon_stat_p67 {width: 67%}
        \\.pokemon_stat_p68 {width: 68%}
        \\.pokemon_stat_p69 {width: 69%}
        \\.pokemon_stat_p70 {width: 70%}
        \\.pokemon_stat_p71 {width: 71%}
        \\.pokemon_stat_p72 {width: 72%}
        \\.pokemon_stat_p73 {width: 73%}
        \\.pokemon_stat_p74 {width: 74%}
        \\.pokemon_stat_p75 {width: 75%}
        \\.pokemon_stat_p76 {width: 76%}
        \\.pokemon_stat_p77 {width: 77%}
        \\.pokemon_stat_p78 {width: 78%}
        \\.pokemon_stat_p79 {width: 79%}
        \\.pokemon_stat_p80 {width: 80%}
        \\.pokemon_stat_p81 {width: 81%}
        \\.pokemon_stat_p82 {width: 82%}
        \\.pokemon_stat_p83 {width: 83%}
        \\.pokemon_stat_p84 {width: 84%}
        \\.pokemon_stat_p85 {width: 85%}
        \\.pokemon_stat_p86 {width: 86%}
        \\.pokemon_stat_p87 {width: 87%}
        \\.pokemon_stat_p88 {width: 88%}
        \\.pokemon_stat_p89 {width: 89%}
        \\.pokemon_stat_p90 {width: 90%}
        \\.pokemon_stat_p91 {width: 91%}
        \\.pokemon_stat_p92 {width: 92%}
        \\.pokemon_stat_p93 {width: 93%}
        \\.pokemon_stat_p94 {width: 94%}
        \\.pokemon_stat_p95 {width: 95%}
        \\.pokemon_stat_p96 {width: 96%}
        \\.pokemon_stat_p97 {width: 97%}
        \\.pokemon_stat_p98 {width: 98%}
        \\.pokemon_stat_p99 {width: 99%}
        \\.pokemon_stat_p100 {width: 100%}
        \\
        \\</style>
        \\</head>
        \\<body>
        \\<main>
        \\
    ;

    const footer =
        \\</main>
        \\</body>
        \\</html>
        \\
    ;

    var content_root = std.ArrayList(u8).init(arena);
    var content_file = std.ArrayList(u8).init(arena);
    const content_root_writer = content_root.writer();
    const content_file_writer = content_file.writer();

    const cwd = std.fs.cwd();
    try cwd.deleteTree("wiki");

    var root_dir = try cwd.makeOpenPath("wiki", .{});
    defer root_dir.close();

    try root_dir.makeDir("pokemons");
    try root_dir.makeDir("trainers");

    try root_dir.writeFile(.{
        .sub_path = "index.html",
        .data = header ++
            \\<a href="./pokemons/index.html">Pokemons</a><br/>
            \\<a href="./trainers/index.html">Trainers</a><br/>
            \\
        ++ footer,
    });

    {
        content_root.shrinkRetainingCapacity(0);
        try content_root_writer.writeAll(header);

        const pokemons = try game.pokemons();
        var species: usize = 0;
        while (species < pokemons.len()) : (species += 1) {
            try content_root_writer.print("<a href=\"{:0>3}.html\">#{:0>3}</a><br/>\n", .{ species, species });

            content_file.shrinkRetainingCapacity(0);
            try content_file_writer.writeAll(header);

            if (pokemons.at(species)) |pokemon| {
                try content_file_writer.writeAll(
                    \\<table>
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Type:</td><td>
                );
                for (pokemon.types, 0..) |t, i| {
                    if (i != 0) try content_file_writer.writeAll(" ");
                    try content_file_writer.print("{}", .{t});
                }
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Abilities:</td><td>
                );
                for (pokemon.abilities, 0..) |a, i| {
                    if (i != 0) try content_file_writer.writeAll(" ");
                    try content_file_writer.print("{}", .{a});
                }
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Items:</td><td>
                );
                for (pokemon.items, 0..) |a, i| {
                    if (i != 0) try content_file_writer.writeAll(" ");
                    try content_file_writer.print("{}", .{a});
                }
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Egg Groups:</td><td>
                );
                for (pokemon.egg_groups, 0..) |e, i| {
                    switch (e) {
                        .invalid,
                        .monster,
                        .water1,
                        .bug,
                        .flying,
                        .field,
                        .fairy,
                        .grass,
                        .human_like,
                        .water3,
                        .mineral,
                        .amorphous,
                        .water2,
                        .ditto,
                        .dragon,
                        .undiscovered,
                        => {},
                        _ => continue,
                    }

                    if (i != 0) try content_file_writer.writeAll(" ");
                    try content_file_writer.print("{s}", .{@tagName(e)});
                }
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Gender ratio:</td><td>
                );
                try content_file_writer.print("{}", .{pokemon.gender_ratio});
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Catch rate:</td><td>
                );
                try content_file_writer.print("{}", .{pokemon.catch_rate});
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                try content_file_writer.writeAll(
                    \\<tr><td>Growth Rate:</td><td>
                );
                try content_file_writer.print("{s}", .{@tagName(pokemon.growth_rate)});
                try content_file_writer.writeAll(
                    \\</td></tr>
                    \\
                );

                const stat_names = [_][2][]const u8{
                    .{ "hp", "Hp" },
                    .{ "attack", "Attack" },
                    .{ "defense", "Defense" },
                    .{ "sp_attack", "Sp. Atk" },
                    .{ "sp_defense", "Sp. Def" },
                    .{ "speed", "Speed" },
                };

                var total_stats: usize = 0;
                inline for (stat_names) |stat| {
                    const value = @field(pokemon.stats, stat[0]);
                    const percent: u8 = @intFromFloat((@as(f64, @floatFromInt(value)) / 255) * 100);
                    try content_file_writer.print("<tr><td>{s}:</td><td class=\"pokemon_stat\"><div class=\"pokemon_stat_p{} pokemon_stat_{s}\">{}</div></td></tr>\n", .{ stat[1], percent, stat[0], value });
                    total_stats += value;
                }

                const percent: u8 = @intFromFloat((@as(f64, @floatFromInt(total_stats)) / 1000) * 100);
                try content_file_writer.print("<tr><td>Total:</td><td class=\"pokemon_stat\"><div class=\"pokemon_stat_p{} pokemon_stat_total\">{}</div></td></tr>\n", .{ percent, total_stats });

                try content_file_writer.writeAll(
                    \\</table>
                    \\
                );
            } else |_| {}

            try content_file_writer.writeAll(footer);

            var buf: [128]u8 = undefined;
            try root_dir.writeFile(.{
                .sub_path = try std.fmt.bufPrint(&buf, "pokemons/{:0>3}.html", .{species}),
                .data = content_file.items,
            });
        }

        try content_root_writer.writeAll(footer);

        try root_dir.writeFile(.{
            .sub_path = "pokemons/index.html",
            .data = content_root.items,
        });
    }

    {
        content_root.shrinkRetainingCapacity(0);
        try content_root_writer.writeAll(header);

        const trainers = try game.trainers();
        const trainer_parties = try game.trainerParties();

        var trainer_id: usize = 0;
        while (trainer_id < trainers.len()) : (trainer_id += 1) {
            try content_root_writer.print("<a href=\"{:0>3}.html\">#{:0>3}</a><br/>\n", .{ trainer_id, trainer_id });

            content_file.shrinkRetainingCapacity(0);
            try content_file_writer.writeAll(header);

            done: {
                const trainer = trainers.at(trainer_id) catch break :done;
                _ = trainer; // autofix
                const party = trainer_parties.at(trainer_id) catch break :done;

                try content_file_writer.writeAll(
                    \\<table>
                );

                for (party.members[0..party.size], 0..) |member, i| {
                    try content_file_writer.print(
                        \\<tr><td>Party Member {}:</td><td>lvl {} <a href="../pokemons/{:0>3}.html">{:0>3}</a></td></tr>
                        \\
                    , .{ i, member.base.level, member.base.species, member.base.species });
                }

                try content_file_writer.writeAll(
                    \\</table>
                    \\
                );
            }

            try content_file_writer.writeAll(footer);

            var buf: [128]u8 = undefined;
            try root_dir.writeFile(.{
                .sub_path = try std.fmt.bufPrint(&buf, "trainers/{:0>3}.html", .{trainer_id}),
                .data = content_file.items,
            });
        }

        try content_root_writer.writeAll(footer);

        try root_dir.writeFile(.{
            .sub_path = "trainers/index.html",
            .data = content_root.items,
        });
    }
}

const Options = packed struct {};

test {
    _ = Command;
    _ = common;
    _ = core;
    _ = util;
}

const This = @This();

const Command = @import("../Command.zig");
const common = @import("common.zig");
const core = @import("../core.zig");
const util = @import("../util.zig");

const std = @import("std");
