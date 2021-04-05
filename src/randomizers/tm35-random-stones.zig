const clap = @import("clap");
const format = @import("format");
const std = @import("std");
const util = @import("util");

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
const unicode = std.unicode;

const algo = util.algorithm;

const Utf8 = util.unicode.Utf8View;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help                 Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-r, --replace-cheap-items  Replaces cheap items in pokeballs with stones.") catch unreachable,
        clap.parseParam("-s, --seed <INT>           The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-v, --version              Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-random-stones ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nChanges all Pokémons to evolve using new evolution stones. " ++
        "These stones evolve a Pokémon to a random new Pokémon that upholds the " ++
        "requirements of the stone. Here is a list of all stones:\n" ++
        "* Chance Stone: Evolves a Pokémon into random Pokémon.\n" ++
        "* Stat Stone: Evolves a Pokémon into random Pokémon with the same total stats.\n" ++
        "* Growth Stone: Evolves a Pokémon into random Pokémon with the same growth rate.\n" ++
        "* Form Stone: Evolves a Pokémon into random Pokémon with a common type.\n" ++
        "* Skill Stone: Evolves a Pokémon into random Pokémon with a common ability.\n" ++
        "* Breed Stone: Evolves a Pokémon into random Pokémon in the same egg group.\n" ++
        "* Buddy Stone: Evolves a Pokémon into random Pokémon with the same base friendship.\n" ++
        "\n" ++
        "This command will try to get as many of these stones into the game as possible, " ++
        "but beware, that all stones might not exist. Also beware, that the stones might " ++
        "have different (but simular) names in cases where the game does not support long " ++
        "item names.\n" ++
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
    const seed = try util.getSeed(args);
    const replace_cheap = args.flag("--replace-cheap-items");

    const data = try handleInput(allocator, stdio.in, stdio.out, replace_cheap);
    try randomize(allocator, data, seed);
    try outputData(stdio.out, data);
}

fn handleInput(allocator: *mem.Allocator, reader: anytype, writer: anytype, replace_cheap: bool) !Data {
    var fifo = util.io.Fifo(.Dynamic).init(allocator);
    var data = Data{};
    while (try util.io.readLine(reader, &fifo)) |line| {
        parseLine(allocator, &data, replace_cheap, line) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.InvalidUtf8,
            error.ParserFailed,
            => try writer.print("{}\n", .{line}),
        };
    }
    return data;
}

fn outputData(writer: anytype, data: Data) !void {
    for (data.pokemons.items()) |pokemon| {
        for (pokemon.value.evos.items()) |evo| {
            try format.write(writer, format.Game.pokemon(pokemon.key, format.Pokemon.evo(evo.key, .{ .method = .use_item })));
            try format.write(writer, format.Game.pokemon(pokemon.key, format.Pokemon.evo(evo.key, .{ .param = evo.value.param })));
            try format.write(writer, format.Game.pokemon(pokemon.key, format.Pokemon.evo(evo.key, .{ .target = evo.value.target })));
        }
    }
    for (data.items.items()) |item| {
        if (item.value.name.bytes.len != 0)
            try format.write(writer, format.Game.item(item.key, .{ .name = item.value.name.bytes }));
        if (item.value.description.bytes.len != 0) {
            try format.write(
                writer,
                format.Game.item(item.key, .{ .description = item.value.description.bytes }),
            );
        }
    }
    for (data.pokeball_items.items()) |item|
        try format.write(writer, format.Game.pokeball_item(item.key, .{ .item = item.value }));
}

fn parseLine(
    allocator: *mem.Allocator,
    data: *Data,
    replace_cheap: bool,
    str: []const u8,
) !void {
    const parsed = try format.parseEscape(allocator, str);
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try data.pokedex.put(allocator, pokedex.index, {});
            return error.ParserFailed;
        },
        .pokemons => |pokemons| {
            const pokemon = &(try data.pokemons.getOrPutValue(allocator, pokemons.index, Pokemon{})).value;
            switch (pokemons.value) {
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .pokedex_entry => |pokedex_entry| pokemon.pokedex_entry = pokedex_entry,
                .base_friendship => |base_friendship| pokemon.base_friendship = base_friendship,
                .growth_rate => |growth_rate| pokemon.growth_rate = growth_rate,
                .stats => |stats| pokemon.stats[@enumToInt(stats)] = stats.value(),
                .types => |types| _ = try pokemon.types.put(allocator, types.value, {}),
                .abilities => |abilities| _ = try pokemon.abilities.put(allocator, abilities.value, {}),
                .egg_groups => |egg_groups| _ = try pokemon.egg_groups.put(allocator, @enumToInt(egg_groups.value), {}),
                .evos => |evos| {
                    data.max_evolutions = math.max(data.max_evolutions, evos.index + 1);
                    const evo = &(try pokemon.evos.getOrPutValue(allocator, evos.index, Evolution{})).value;
                    format.setField(evo, evos.value);
                },
                .base_exp_yield,
                .ev_yield,
                .items,
                .gender_ratio,
                .egg_cycles,
                .color,
                .moves,
                .tms,
                .hms,
                .name,
                => return error.ParserFailed,
            }
            return;
        },
        .items => |items| {
            const item = &(try data.items.getOrPutValue(allocator, items.index, Item{})).value;
            switch (items.value) {
                .name => |name| {
                    item.name = try Utf8.init(try mem.dupe(allocator, u8, name));
                    return;
                },
                .description => |desc| {
                    item.description = try Utf8.init(try mem.dupe(allocator, u8, desc));
                    return;
                },
                .price => |price| item.price = price,
                .battle_effect,
                .pocket,
                => return error.ParserFailed,
            }
            return error.ParserFailed;
        },
        .pokeball_items => |items| switch (items.value) {
            .item => |item| if (replace_cheap) {
                _ = try data.pokeball_items.put(allocator, items.index, item);
                return;
            } else return error.ParserFailed,
            .amount => return error.ParserFailed,
        },
        .version,
        .game_title,
        .gamecode,
        .instant_text,
        .starters,
        .text_delays,
        .trainers,
        .moves,
        .abilities,
        .types,
        .tms,
        .hms,
        .maps,
        .wild_pokemons,
        .static_pokemons,
        .given_pokemons,
        .hidden_hollows,
        .text,
        => return error.ParserFailed,
    }
    unreachable;
}

fn randomize(allocator: *mem.Allocator, data: Data, seed: usize) !void {
    const random = &rand.DefaultPrng.init(seed).random;

    // First, let's find items that are used for evolving Pokémons.
    // We will use these items as our stones.
    var stones = Set{};
    for (data.pokemons.items()) |*pokemon| {
        for (pokemon.value.evos.items()) |evo| {
            if (evo.value.method == .use_item)
                _ = try stones.put(allocator, evo.value.param, {});
        }

        // Reset evolutions. We don't need the old anymore.
        pokemon.value.evos.clearRetainingCapacity();
    }

    // Find the maximum length of a line. Used to split descriptions into lines.
    var max_line_len: usize = 0;
    for (data.items.items()) |item| {
        var description = item.value.description;
        while (mem.indexOf(u8, description.bytes, "\n")) |index| {
            const line = Utf8.init(description.bytes[0..index]) catch unreachable;
            max_line_len = math.max(line.len, max_line_len);
            description = Utf8.init(description.bytes[index + 1 ..]) catch unreachable;
        }
        max_line_len = math.max(description.len, max_line_len);
    }

    // HACK: The games does not used mono fonts, so actually, using the
    //       max_line_len to destribute newlines will not actually be totally
    //       correct. The best I can do here is to just reduce the max_line_len
    //       by some amount and hope it is enough for all strings.
    max_line_len = math.sub(usize, max_line_len, 5) catch max_line_len;

    const species = try data.pokedexPokemons(allocator);
    const pokemons_by_stats = try filterBy(allocator, species, data.pokemons, statsFilter);
    const pokemons_by_base_friendship = try filterBy(allocator, species, data.pokemons, friendshipFilter);
    const pokemons_by_type = try filterBy(allocator, species, data.pokemons, typeFilter);
    const pokemons_by_ability = try filterBy(allocator, species, data.pokemons, abilityFilter);
    const pokemons_by_egg_group = try filterBy(allocator, species, data.pokemons, eggGroupFilter);
    const pokemons_by_growth_rate = try filterBy(allocator, species, data.pokemons, growthRateFilter);

    // Make sure these indexs line up with the array below
    const chance_stone = 0;
    const stat_stone = 1;
    const growth_stone = 2;
    const form_stone = 3;
    const skill_stone = 4;
    const breed_stone = 5;
    const buddy_stone = 6;
    const stone_strings = [_]struct {
        names: []const Utf8,
        descriptions: []const Utf8,
    }{
        .{
            .names = &[_]Utf8{
                Utf8.initAscii("Chance Stone"),
                Utf8.initAscii("Chance Rock"),
                Utf8.initAscii("Luck Rock"),
                Utf8.initAscii("Luck Rck"),
                Utf8.initAscii("C Stone"),
                Utf8.initAscii("C Rock"),
                Utf8.initAscii("C Rck"),
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon.")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon into random Pokémon")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon to random Pokémon")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon to random Pokémon")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves to random Pokémon")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Into random Pokémon")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("To random Pokémon")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon")),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.initAscii("Stat Stone"),
                Utf8.initAscii("Stat Rock"),
                Utf8.initAscii("St Stone"),
                Utf8.initAscii("St Rock"),
                Utf8.initAscii("St Rck"),
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with the same total stats.")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with the same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon into random Pokémon with same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon to random Pokémon with same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon to random Pokémon with same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves to random Pokémon with same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon with same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Into random Pokémon with same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("To random Pokémon with same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon with same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon, same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random, same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random same stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Same total stats")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Same stats")),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.initAscii("Growth Stone"),
                Utf8.initAscii("Growth Rock"),
                Utf8.initAscii("Rate Stone"),
                Utf8.initAscii("Rate Rock"),
                Utf8.initAscii("G Stone"),
                Utf8.initAscii("G Rock"),
                Utf8.initAscii("G Rck"),
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with the same growth rate.")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with the same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with same growth rate.")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon into random Pokémon with same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon to random Pokémon with same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon to random Pokémon with same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves to random Pokémon with same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon with same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Into random Pokémon with same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("To random Pokémon with same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon with same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon, same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random, same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random same growth rate")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Same growth rate")),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.initAscii("Form Stone"),
                Utf8.initAscii("Form Rock"),
                Utf8.initAscii("Form Rck"),
                Utf8.initAscii("T Stone"),
                Utf8.initAscii("T Rock"),
                Utf8.initAscii("T Rck"),
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with a common type.")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with a common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon into random Pokémon with a common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon to random Pokémon with a common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon to random Pokémon with a common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves to random Pokémon with a common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon with a common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon with same type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Into random Pokémon with a common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Into random Pokémon with same type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("To random Pokémon with same type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon, a common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon a common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon, same type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon same type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random, a common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random a common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random, same type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random same type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("A common type")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Same type")),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.initAscii("Skill Stone"),
                Utf8.initAscii("Skill Rock"),
                Utf8.initAscii("Skill Rck"),
                Utf8.initAscii("S Stone"),
                Utf8.initAscii("S Rock"),
                Utf8.initAscii("S Rck"),
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with a common ability.")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with a common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon into random Pokémon with a common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon to random Pokémon with a common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon to random Pokémon with a common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves to random Pokémon with a common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon with a common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon with same ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Into random Pokémon with a common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Into random Pokémon with same ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("To random Pokémon with same ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon, a common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon a common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon, same ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon same ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random, a common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random a common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random, same ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random same ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("A common ability")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Same ability")),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.initAscii("Breed Stone"),
                Utf8.initAscii("Breed Rock"),
                Utf8.initAscii("Egg Stone"),
                Utf8.initAscii("Egg Rock"),
                Utf8.initAscii("Egg Rck"),
                Utf8.initAscii("E Stone"),
                Utf8.initAscii("E Rock"),
                Utf8.initAscii("E Rck"),
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon in the same egg group.")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon in the same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon into random Pokémon in the same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon to random Pokémon in the same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve a Pokémon to random Pokémon in the same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves to random Pokémon in the same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon in the same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon with same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Into random Pokémon in the same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Into random Pokémon with same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("To random Pokémon with same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon, in same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon in same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon, same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random, in same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random in same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random, same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("In same egg group")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Same egg group")),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.initAscii("Buddy Stone"),
                Utf8.initAscii("Buddy Rock"),
                Utf8.initAscii("Buddy Rck"),
                Utf8.initAscii("F Stone"),
                Utf8.initAscii("F Rock"),
                Utf8.initAscii("F Rck"),
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with the same base friendship.")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with the same base friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with the same base friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves a Pokémon into random Pokémon with the same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves to random Pokémon with the same base friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon with the same base friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon with same base friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolves to random Pokémon with the same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon with the same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Evolve to random Pokémon with same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Into random Pokémon with the same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Into random Pokémon with same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("To random Pokémon with same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon, with same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon with same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon, same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random Pokémon same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random, with same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random with same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random, same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Random same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("In same friendship")),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.initAscii("Same friendship")),
            },
        },
    };
    for (stone_strings) |strs, stone| {
        if (data.max_evolutions <= stone or stones.count() <= stone)
            break;

        const item_id = stones.items()[stone].key;
        const item = data.items.getEntry(item_id).?;

        // We have no idea as to how long the name/desc can be in the game we
        // are working on. Our best guess will therefor be to use the current
        // items name/desc as the limits and pick something that fits.
        item.value = Item{
            .name = pickString(item.value.name.len, strs.names),
            .description = pickString(item.value.description.len, strs.descriptions),
        };
    }

    const num_pokemons = species.count();
    for (species.items()) |s| {
        const pokemon_id = s.key;
        const pokemon = data.pokemons.getEntry(pokemon_id).?;

        for (stone_strings) |_, stone| {
            if (data.max_evolutions <= stone or stones.count() <= stone)
                break;

            const item_id = stones.items()[stone].key;
            const pick = switch (stone) {
                chance_stone => while (num_pokemons > 1) {
                    const pick = util.random.item(random, species.items()).?.key;
                    if (pick != pokemon_id)
                        break pick;
                } else pokemon_id,

                form_stone, skill_stone, breed_stone => blk: {
                    const map = switch (stone) {
                        form_stone => pokemons_by_type,
                        skill_stone => pokemons_by_ability,
                        breed_stone => pokemons_by_egg_group,
                        else => unreachable,
                    };
                    const set = switch (stone) {
                        form_stone => pokemon.value.types,
                        skill_stone => pokemon.value.abilities,
                        breed_stone => pokemon.value.egg_groups,
                        else => unreachable,
                    };

                    if (map.count() == 0 or set.count() == 0)
                        break :blk pokemon_id;

                    const picked_id = switch (stone) {
                        // Assume that ability 0 means that there is no ability, and
                        // don't pick that.
                        skill_stone => while (set.count() != 1) {
                            const pick = util.random.item(random, set.items()).?.key;
                            if (pick != 0)
                                break pick;
                        } else set.items()[0].key,
                        form_stone, breed_stone => util.random.item(random, set.items()).?.key,
                        else => unreachable,
                    };
                    const pokemon_set = map.get(picked_id).?;
                    const pokemons = pokemon_set.count();
                    while (pokemons != 1) {
                        const pick = util.random.item(random, pokemon_set.items()).?.key;
                        if (pick != pokemon_id)
                            break :blk pick;
                    }
                    break :blk pokemon_id;
                },

                stat_stone, growth_stone, buddy_stone => blk: {
                    const map = switch (stone) {
                        stat_stone => pokemons_by_stats,
                        growth_stone => pokemons_by_growth_rate,
                        buddy_stone => pokemons_by_base_friendship,
                        else => unreachable,
                    };
                    const number = switch (stone) {
                        stat_stone => algo.fold(&pokemon.value.stats, @as(u16, 0), algo.add),
                        growth_stone => @enumToInt(pokemon.value.growth_rate),
                        buddy_stone => pokemon.value.base_friendship,
                        else => unreachable,
                    };
                    if (map.count() == 0)
                        break :blk pokemon_id;

                    const pokemon_set = map.get(number).?;
                    const pokemons = pokemon_set.count();
                    while (pokemons != 1) {
                        const pick = util.random.item(random, pokemon_set.items()).?.key;
                        if (pick != pokemon_id)
                            break :blk pick;
                    }
                    break :blk pokemon_id;
                },
                else => unreachable,
            };

            _ = try pokemon.value.evos.put(allocator, @intCast(u8, stone), Evolution{
                .method = .use_item,
                .param = item_id,
                .target = pick,
            });
        }
    }

    // Replace cheap pokeball items with random stones.
    const number_of_stones = math.min(math.min(stones.count(), stone_strings.len), data.max_evolutions);
    for (data.pokeball_items.items()) |*item_id| {
        const item = data.items.get(item_id.value) orelse continue;
        if (item.price == 0 or item.price > 600)
            continue;
        item_id.value = util.random.item(random, stones.items()).?.key;
    }
}

fn pickString(len: usize, strings: []const Utf8) Utf8 {
    var pick = strings[0];
    for (strings) |str| {
        pick = str;
        if (str.len <= len)
            break;
    }

    return pick.slice(0, len);
}

fn filterBy(
    allocator: *mem.Allocator,
    species: Set,
    pokemons: Pokemons,
    filter: fn (Pokemon, []u16) []const u16,
) !PokemonBy {
    var buf: [16]u16 = undefined;
    var pokemons_by = PokemonBy{};
    for (species.items()) |id| {
        const pokemon = pokemons.get(id.key).?;
        for (filter(pokemon, &buf)) |key| {
            const set = try pokemons_by.getOrPutValue(allocator, key, Set{});
            _ = try set.value.put(allocator, id.key, {});
        }
    }
    return pokemons_by;
}

fn statsFilter(pokemon: Pokemon, buf: []u16) []const u16 {
    buf[0] = algo.fold(&pokemon.stats, @as(u16, 0), algo.add);
    return buf[0..1];
}

fn friendshipFilter(pokemon: Pokemon, buf: []u16) []const u16 {
    buf[0] = pokemon.base_friendship;
    return buf[0..1];
}

fn growthRateFilter(pokemon: Pokemon, buf: []u16) []const u16 {
    buf[0] = @enumToInt(pokemon.growth_rate);
    return buf[0..1];
}

fn typeFilter(pokemon: Pokemon, buf: []u16) []const u16 {
    return setFilter("types", pokemon, buf);
}

fn abilityFilter(pokemon: Pokemon, buf: []u16) []const u16 {
    return setFilter("abilities", pokemon, buf);
}

fn eggGroupFilter(pokemon: Pokemon, buf: []u16) []const u16 {
    return setFilter("egg_groups", pokemon, buf);
}

fn setFilter(comptime field: []const u8, pokemon: Pokemon, buf: []u16) []const u16 {
    var i: usize = 0;
    for (@field(pokemon, field).items()) |item| {
        buf[i] = item.key;
        i += 1;
    }
    return buf[0..i];
}

const Evolutions = std.AutoArrayHashMapUnmanaged(u8, Evolution);
const Items = std.AutoArrayHashMapUnmanaged(u16, Item);
const PokeballItems = std.AutoArrayHashMapUnmanaged(u16, u16);
const PokemonBy = std.AutoArrayHashMapUnmanaged(u16, Set);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);

const Data = struct {
    max_evolutions: usize = 0,
    pokedex: Set = Set{},
    items: Items = Items{},
    pokeball_items: PokeballItems = PokeballItems{},
    pokemons: Pokemons = Pokemons{},

    fn pokedexPokemons(d: Data, allocator: *mem.Allocator) !Set {
        var res = Set{};
        errdefer res.deinit(allocator);

        for (d.pokemons.items()) |pokemon, i| {
            if (pokemon.value.catch_rate == 0)
                continue;
            if (d.pokedex.get(pokemon.value.pokedex_entry) == null)
                continue;

            _ = try res.put(allocator, pokemon.key, {});
        }

        return res;
    }
};

const Pokemon = struct {
    evos: Evolutions = Evolutions{},
    stats: [6]u8 = [_]u8{0} ** 6,
    growth_rate: format.GrowthRate = .fast,
    base_friendship: u16 = 0,
    catch_rate: u16 = 1,
    pokedex_entry: u16 = math.maxInt(u16),
    abilities: Set = Set{},
    types: Set = Set{},
    egg_groups: Set = Set{},
};

const Item = struct {
    name: Utf8 = Utf8.init("") catch unreachable,
    description: Utf8 = Utf8.init("") catch unreachable,
    price: usize = 0,
};

const Evolution = struct {
    method: format.Evolution.Method = .unused,
    param: u16 = 0,
    target: u16 = 0,
};

test "tm35-random stones" {
    // TODO: Tests
}
