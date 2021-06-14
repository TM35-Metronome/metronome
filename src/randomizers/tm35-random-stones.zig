const clap = @import("clap");
const format = @import("format");
const it = @import("ziter");
const std = @import("std");
const ston = @import("ston");
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

    var data = Data{ .allocator = allocator };
    try format.io(allocator, stdio.in, stdio.out, .{
        .data = &data,
        .replace_cheap = replace_cheap,
    }, useGame);

    try randomize(data, seed);
    try outputData(stdio.out, data);
}

fn outputData(writer: anytype, data: Data) !void {
    for (data.pokemons.values()) |pokemon, i| {
        const species = data.pokemons.keys()[i];
        for (pokemon.evos.values()) |evo, j| {
            const evo_i = pokemon.evos.keys()[j];
            try ston.serialize(writer, format.Game.pokemon(species, format.Pokemon.evo(evo_i, .{ .method = .use_item })));
            try ston.serialize(writer, format.Game.pokemon(species, format.Pokemon.evo(evo_i, .{ .param = evo.param })));
            try ston.serialize(writer, format.Game.pokemon(species, format.Pokemon.evo(evo_i, .{ .target = evo.target })));
        }
    }
    for (data.items.values()) |item, i| {
        const item_id = data.items.keys()[i];

        if (item.name.bytes.len != 0)
            try ston.serialize(writer, format.Game.item(item_id, .{ .name = item.name.bytes }));
        if (item.description.bytes.len != 0) {
            try ston.serialize(writer, format.Game.item(item_id, .{
                .description = item.description.bytes,
            }));
        }
    }
    for (data.pokeball_items.values()) |item, i| {
        const item_id = data.items.keys()[i];
        try ston.serialize(writer, format.Game.pokeball_item(item_id, .{ .item = item }));
    }
}

fn useGame(ctx: anytype, parsed: format.Game) !void {
    const data = ctx.data;
    const allocator = data.allocator;
    const replace_cheap = ctx.replace_cheap;
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try data.pokedex.put(allocator, pokedex.index, {});
            return error.ParserFailed;
        },
        .pokemons => |pokemons| {
            const pokemon = (try data.pokemons.getOrPutValue(allocator, pokemons.index, .{})).value_ptr;
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
                    const evo = (try pokemon.evos.getOrPutValue(allocator, evos.index, .{})).value_ptr;
                    format.setField(evo, evos.value);
                    return;
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
            return error.ParserFailed;
        },
        .items => |items| {
            const item = (try data.items.getOrPutValue(allocator, items.index, .{})).value_ptr;
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

fn randomize(data: Data, seed: usize) !void {
    @setEvalBranchQuota(1000000000);
    const random = &rand.DefaultPrng.init(seed).random;

    // First, let's find items that are used for evolving Pokémons.
    // We will use these items as our stones.
    var stones = Set{};
    for (data.pokemons.values()) |*pokemon| {
        for (pokemon.evos.values()) |evo| {
            if (evo.method == .use_item)
                _ = try stones.put(data.allocator, evo.param, {});
        }

        // Reset evolutions. We don't need the old anymore.
        pokemon.evos.clearRetainingCapacity();
    }

    // Find the maximum length of a line. Used to split descriptions into lines.
    var max_line_len: usize = 0;
    for (data.items.values()) |item| {
        var description = item.description;
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

    const species = try data.pokedexPokemons();
    const pokemons_by_stats = try filterBy(data.allocator, species, data.pokemons, statsFilter);
    const pokemons_by_base_friendship = try filterBy(data.allocator, species, data.pokemons, friendshipFilter);
    const pokemons_by_type = try filterBy(data.allocator, species, data.pokemons, typeFilter);
    const pokemons_by_ability = try filterBy(data.allocator, species, data.pokemons, abilityFilter);
    const pokemons_by_egg_group = try filterBy(data.allocator, species, data.pokemons, eggGroupFilter);
    const pokemons_by_growth_rate = try filterBy(data.allocator, species, data.pokemons, growthRateFilter);

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
                comptime Utf8.init("Chance Stone") catch unreachable,
                comptime Utf8.init("Chance Rock") catch unreachable,
                comptime Utf8.init("Luck Rock") catch unreachable,
                comptime Utf8.init("Luck Rck") catch unreachable,
                comptime Utf8.init("C Stone") catch unreachable,
                comptime Utf8.init("C Rock") catch unreachable,
                comptime Utf8.init("C Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon.") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Into random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("To random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                comptime Utf8.init("Stat Stone") catch unreachable,
                comptime Utf8.init("Stat Rock") catch unreachable,
                comptime Utf8.init("St Stone") catch unreachable,
                comptime Utf8.init("St Rock") catch unreachable,
                comptime Utf8.init("St Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same total stats.") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("To random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon, same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random, same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random same stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Same total stats") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Same stats") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                comptime Utf8.init("Growth Stone") catch unreachable,
                comptime Utf8.init("Growth Rock") catch unreachable,
                comptime Utf8.init("Rate Stone") catch unreachable,
                comptime Utf8.init("Rate Rock") catch unreachable,
                comptime Utf8.init("G Stone") catch unreachable,
                comptime Utf8.init("G Rock") catch unreachable,
                comptime Utf8.init("G Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same growth rate.") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with same growth rate.") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("To random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon, same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random, same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Same growth rate") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                comptime Utf8.init("Form Stone") catch unreachable,
                comptime Utf8.init("Form Rock") catch unreachable,
                comptime Utf8.init("Form Rck") catch unreachable,
                comptime Utf8.init("T Stone") catch unreachable,
                comptime Utf8.init("T Rock") catch unreachable,
                comptime Utf8.init("T Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with a common type.") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Into random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("To random Pokémon with same type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon, a common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon a common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon, same type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon same type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random, a common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random a common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random, same type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random same type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("A common type") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Same type") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                comptime Utf8.init("Skill Stone") catch unreachable,
                comptime Utf8.init("Skill Rock") catch unreachable,
                comptime Utf8.init("Skill Rck") catch unreachable,
                comptime Utf8.init("S Stone") catch unreachable,
                comptime Utf8.init("S Rock") catch unreachable,
                comptime Utf8.init("S Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with a common ability.") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Into random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("To random Pokémon with same ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon, a common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon a common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon, same ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon same ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random, a common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random a common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random, same ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random same ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("A common ability") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Same ability") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                comptime Utf8.init("Breed Stone") catch unreachable,
                comptime Utf8.init("Breed Rock") catch unreachable,
                comptime Utf8.init("Egg Stone") catch unreachable,
                comptime Utf8.init("Egg Rock") catch unreachable,
                comptime Utf8.init("Egg Rck") catch unreachable,
                comptime Utf8.init("E Stone") catch unreachable,
                comptime Utf8.init("E Rock") catch unreachable,
                comptime Utf8.init("E Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon in the same egg group.") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Into random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("To random Pokémon with same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon, in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon, same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random, in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random, same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("In same egg group") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Same egg group") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                comptime Utf8.init("Buddy Stone") catch unreachable,
                comptime Utf8.init("Buddy Rock") catch unreachable,
                comptime Utf8.init("Buddy Rck") catch unreachable,
                comptime Utf8.init("F Stone") catch unreachable,
                comptime Utf8.init("F Rock") catch unreachable,
                comptime Utf8.init("F Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same base friendship.") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Into random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("To random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon, with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon, same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random Pokémon same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random, with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random, same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Random same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("In same friendship") catch unreachable),
                try util.unicode.splitIntoLines(data.allocator, max_line_len, comptime Utf8.init("Same friendship") catch unreachable),
            },
        },
    };
    for (stone_strings) |strs, stone| {
        if (data.max_evolutions <= stone or stones.count() <= stone)
            break;

        const item_id = stones.keys()[stone];
        const item = data.items.getPtr(item_id).?;

        // We have no idea as to how long the name/desc can be in the game we
        // are working on. Our best guess will therefor be to use the current
        // items name/desc as the limits and pick something that fits.
        item.* = Item{
            .name = pickString(item.name.len, strs.names),
            .description = pickString(item.description.len, strs.descriptions),
        };
    }

    const num_pokemons = species.count();
    for (species.keys()) |pokemon_id| {
        const pokemon = data.pokemons.getPtr(pokemon_id).?;

        for (stone_strings) |_, stone| {
            if (data.max_evolutions <= stone or stones.count() <= stone)
                break;

            const item_id = stones.keys()[stone];
            const pick = switch (stone) {
                chance_stone => while (num_pokemons > 1) {
                    const pick = util.random.item(random, species.keys()).?.*;
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
                        form_stone => pokemon.types,
                        skill_stone => pokemon.abilities,
                        breed_stone => pokemon.egg_groups,
                        else => unreachable,
                    };

                    if (map.count() == 0 or set.count() == 0)
                        break :blk pokemon_id;

                    const picked_id = switch (stone) {
                        // Assume that ability 0 means that there is no ability, and
                        // don't pick that.
                        skill_stone => while (set.count() != 1) {
                            const pick = util.random.item(random, set.keys()).?.*;
                            if (pick != 0)
                                break pick;
                        } else set.keys()[0],
                        form_stone, breed_stone => util.random.item(random, set.keys()).?.*,
                        else => unreachable,
                    };
                    const pokemon_set = map.get(picked_id).?;
                    const pokemons = pokemon_set.count();
                    while (pokemons != 1) {
                        const pick = util.random.item(random, pokemon_set.keys()).?.*;
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
                        stat_stone => it.fold(&pokemon.stats, @as(u16, 0), foldu8),
                        growth_stone => @enumToInt(pokemon.growth_rate),
                        buddy_stone => pokemon.base_friendship,
                        else => unreachable,
                    };
                    if (map.count() == 0)
                        break :blk pokemon_id;

                    const pokemon_set = map.get(number).?;
                    const pokemons = pokemon_set.count();
                    while (pokemons != 1) {
                        const pick = util.random.item(random, pokemon_set.keys()).?.*;
                        if (pick != pokemon_id)
                            break :blk pick;
                    }
                    break :blk pokemon_id;
                },
                else => unreachable,
            };

            _ = try pokemon.evos.put(data.allocator, @intCast(u8, stone), Evolution{
                .method = .use_item,
                .param = item_id,
                .target = pick,
            });
        }
    }

    // Replace cheap pokeball items with random stones.
    const number_of_stones = math.min(math.min(stones.count(), stone_strings.len), data.max_evolutions);
    for (data.pokeball_items.values()) |*item_id| {
        const item = data.items.get(item_id.*) orelse continue;
        if (item.price == 0 or item.price > 600)
            continue;
        item_id.* = util.random.item(random, stones.keys()).?.*;
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
    for (species.keys()) |id| {
        const pokemon = pokemons.get(id).?;
        for (filter(pokemon, &buf)) |key| {
            const set = (try pokemons_by.getOrPutValue(allocator, key, .{})).value_ptr;
            _ = try set.put(allocator, id, {});
        }
    }
    return pokemons_by;
}

fn statsFilter(pokemon: Pokemon, buf: []u16) []const u16 {
    buf[0] = it.fold(&pokemon.stats, @as(u16, 0), foldu8);
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
    for (@field(pokemon, field).keys()) |item| {
        buf[i] = item;
        i += 1;
    }
    return buf[0..i];
}

fn foldu8(a: u16, b: u8) u16 {
    return a + b;
}

const Evolutions = std.AutoArrayHashMapUnmanaged(u8, Evolution);
const Items = std.AutoArrayHashMapUnmanaged(u16, Item);
const PokeballItems = std.AutoArrayHashMapUnmanaged(u16, u16);
const PokemonBy = std.AutoArrayHashMapUnmanaged(u16, Set);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);

const Data = struct {
    allocator: *mem.Allocator,
    max_evolutions: usize = 0,
    pokedex: Set = Set{},
    items: Items = Items{},
    pokeball_items: PokeballItems = PokeballItems{},
    pokemons: Pokemons = Pokemons{},

    fn pokedexPokemons(d: Data) !Set {
        var res = Set{};
        errdefer res.deinit(d.allocator);

        for (d.pokemons.values()) |pokemon, i| {
            if (pokemon.catch_rate == 0)
                continue;
            if (d.pokedex.get(pokemon.pokedex_entry) == null)
                continue;

            _ = try res.put(d.allocator, d.pokemons.keys()[i], {});
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
