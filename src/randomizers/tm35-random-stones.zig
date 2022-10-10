const clap = @import("clap");
const format = @import("format");
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

const escape = util.escape.default;

const Utf8 = util.unicode.Utf8View;

const Program = @This();

allocator: mem.Allocator,
options: struct {
    seed: u64,
    replace_cheap: bool,
},
max_evolutions: usize = 0,
pokedex: Set = Set{},
items: Items = Items{},
pokeball_items: PokeballItems = PokeballItems{},
pokemons: Pokemons = Pokemons{},

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Changes all Pokémons to evolve using new evolution stones. These stones evolve a Pokémon
    \\to a random new Pokémon that upholds the requirements of the stone. Here is a list of all
    \\stones:
    \\* Chance Stone: Evolves a Pokémon into random Pokémon.
    \\* Stat Stone: Evolves a Pokémon into random Pokémon with the same total stats.
    \\* Growth Stone: Evolves a Pokémon into random Pokémon with the same growth rate.
    \\* Form Stone: Evolves a Pokémon into random Pokémon with a common type.
    \\* Skill Stone: Evolves a Pokémon into random Pokémon with a common ability.
    \\* Breed Stone: Evolves a Pokémon into random Pokémon in the same egg group.
    \\* Buddy Stone: Evolves a Pokémon into random Pokémon with the same base friendship.
    \\
    \\This command will try to get as many of these stones into the game as possible, but beware,
    \\that all stones might not exist. Also beware, that the stones might have different (but
    \\simular) names in cases where the game does not support long item names.
    \\
;

pub const parsers = .{
    .INT = clap.parsers.int(u64, 0),
};

pub const params = clap.parseParamsComptime(
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\-r, --replace-cheap-items
    \\        Replaces cheap items in pokeballs with stones.
    \\
    \\-s, --seed <INT>
    \\        The seed to use for random numbers. A random seed will be picked if this is not
    \\        specified.
    \\
    \\-v, --version
    \\        Output version information and exit.
    \\
);

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    return Program{
        .allocator = allocator,
        .options = .{
            .seed = args.args.seed orelse std.crypto.random.int(u64),
            .replace_cheap = args.args.@"replace-cheap-items",
        },
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    try format.io(program.allocator, stdio.in, stdio.out, program, useGame);
    try program.randomize();
    try program.output(stdio.out);
}

fn output(program: *Program, writer: anytype) !void {
    for (program.pokemons.values()) |pokemon, i| {
        const species = program.pokemons.keys()[i];
        try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
            .evos = pokemon.evos,
        }) });
    }
    for (program.items.values()) |item, i| {
        const item_id = program.items.keys()[i];
        try ston.serialize(writer, .{ .items = ston.index(item_id, .{
            .name = ston.string(escape.escapeFmt(item.name)),
            .description = ston.string(escape.escapeFmt(item.desc)),
        }) });
    }

    try ston.serialize(writer, .{ .pokeball_items = program.pokeball_items });
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try program.pokedex.put(allocator, pokedex.index, {});
            return error.DidNotConsumeData;
        },
        .pokemons => |pokemons| {
            const pokemon = (try program.pokemons.getOrPutValue(allocator, pokemons.index, .{})).value_ptr;
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
                    program.max_evolutions = math.max(program.max_evolutions, evos.index + 1);
                    const evo = (try pokemon.evos.getOrPutValue(allocator, evos.index, .{})).value_ptr;
                    format.setField(evo, evos.value);
                    return;
                },
                .base_exp_yield,
                .items,
                .gender_ratio,
                .egg_cycles,
                .moves,
                .tms,
                .hms,
                .name,
                => return error.DidNotConsumeData,
            }
            return error.DidNotConsumeData;
        },
        .items => |items| {
            const item = (try program.items.getOrPutValue(allocator, items.index, .{})).value_ptr;
            switch (items.value) {
                .name => |str| {
                    const name = try escape.unescapeAlloc(allocator, str);
                    item.name = try Utf8.init(name);
                    return;
                },
                .description => |str| {
                    const desc = try escape.unescapeAlloc(allocator, str);
                    item.desc = try Utf8.init(desc);
                    return;
                },
                .price => |price| item.price = price,
                .battle_effect,
                .pocket,
                => return error.DidNotConsumeData,
            }
            return error.DidNotConsumeData;
        },
        .pokeball_items => |items| switch (items.value) {
            .item => |item| if (program.options.replace_cheap) {
                _ = try program.pokeball_items.put(allocator, items.index, .{ .item = item });
                return;
            } else return error.DidNotConsumeData,
            .amount => return error.DidNotConsumeData,
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
        => return error.DidNotConsumeData,
    }
    unreachable;
}

fn randomize(program: *Program) !void {
    @setEvalBranchQuota(1000000000);
    const allocator = program.allocator;
    var default_random = rand.DefaultPrng.init(program.options.seed);
    const random = default_random.random();

    // First, let's find items that are used for evolving Pokémons.
    // We will use these items as our stones.
    var stones = Set{};
    for (program.pokemons.values()) |*pokemon| {
        for (pokemon.evos.values()) |evo| {
            if (evo.method == .use_item)
                _ = try stones.put(allocator, evo.param, {});
        }

        // Reset evolutions. We don't need the old anymore.
        pokemon.evos.clearRetainingCapacity();
    }

    // Find the maximum length of a line. Used to split descs into lines.
    var max_line_len: usize = 0;
    for (program.items.values()) |item| {
        var desc = item.desc;
        while (mem.indexOf(u8, desc.bytes, "\n")) |index| {
            const line = Utf8.init(desc.bytes[0..index]) catch unreachable;
            max_line_len = math.max(line.len, max_line_len);
            desc = Utf8.init(desc.bytes[index + 1 ..]) catch unreachable;
        }
        max_line_len = math.max(desc.len, max_line_len);
    }

    // HACK: The games does not used mono fonts, so actually, using the
    //       max_line_len to destribute newlines will not actually be totally
    //       correct. The best I can do here is to just reduce the max_line_len
    //       by some amount and hope it is enough for all strings.
    max_line_len = math.sub(usize, max_line_len, 5) catch max_line_len;

    const species = try pokedexPokemons(allocator, program.pokemons, program.pokedex);
    const pokemons_by_stats = try filterBy(allocator, species, program.pokemons, statsFilter);
    const pokemons_by_base_friendship = try filterBy(allocator, species, program.pokemons, friendshipFilter);
    const pokemons_by_type = try filterBy(allocator, species, program.pokemons, typeFilter);
    const pokemons_by_ability = try filterBy(allocator, species, program.pokemons, abilityFilter);
    const pokemons_by_egg_group = try filterBy(allocator, species, program.pokemons, eggGroupFilter);
    const pokemons_by_growth_rate = try filterBy(allocator, species, program.pokemons, growthRateFilter);

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
        descs: []const Utf8,
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
            .descs = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Into random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("To random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon") catch unreachable),
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
            .descs = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same total stats.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("To random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon, same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random, same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random same stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Same stats") catch unreachable),
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
            .descs = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same growth rate.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with same growth rate.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("To random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon, same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random, same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Same growth rate") catch unreachable),
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
            .descs = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with a common type.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Into random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("To random Pokémon with same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon, a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon, same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random, a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random, same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("A common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Same type") catch unreachable),
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
            .descs = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with a common ability.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Into random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("To random Pokémon with same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon, a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon, same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random, a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random, same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("A common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Same ability") catch unreachable),
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
            .descs = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon in the same egg group.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon into random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve a Pokémon to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Into random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("To random Pokémon with same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon, in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon, same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random, in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random, same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("In same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Same egg group") catch unreachable),
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
            .descs = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same base friendship.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves a Pokémon into random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolves to random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Evolve to random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Into random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Into random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("To random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon, with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon, same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random Pokémon same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random, with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random, same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Random same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("In same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, comptime Utf8.init("Same friendship") catch unreachable),
            },
        },
    };
    for (stone_strings) |strs, stone| {
        if (program.max_evolutions <= stone or stones.count() <= stone)
            break;

        const item_id = stones.keys()[stone];
        const item = program.items.getPtr(item_id).?;

        // We have no idea as to how long the name/desc can be in the game we
        // are working on. Our best guess will therefor be to use the current
        // items name/desc as the limits and pick something that fits.
        item.* = Item{
            .name = pickString(item.name.len, strs.names),
            .desc = pickString(item.desc.len, strs.descs),
        };
    }

    const num_pokemons = species.count();
    for (species.keys()) |pokemon_id| {
        const pokemon = program.pokemons.getPtr(pokemon_id).?;

        for (stone_strings) |_, stone| {
            if (program.max_evolutions <= stone or stones.count() <= stone)
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
                        stat_stone => blk2: {
                            var res: u16 = 0;
                            for (pokemon.stats) |item| res += item;
                            break :blk2 res;
                        },
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

            _ = try pokemon.evos.put(allocator, @intCast(u8, stone), Evolution{
                .method = .use_item,
                .param = item_id,
                .target = pick,
            });
        }
    }

    // Replace cheap pokeball items with random stones.
    for (program.pokeball_items.values()) |*ball| {
        const item = program.items.get(ball.item) orelse continue;
        if (item.price == 0 or item.price > 600)
            continue;
        ball.item = util.random.item(random, stones.keys()).?.*;
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
    allocator: mem.Allocator,
    species: Set,
    pokemons: Pokemons,
    filter: std.meta.FnPtr(fn (Pokemon, []u16) []const u16),
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
    buf[0] = 0;
    for (pokemon.stats) |item| buf[0] += item;
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
    const keys = @field(pokemon, field).keys();
    for (keys) |item, i|
        buf[i] = item;

    return buf[0..keys.len];
}

fn foldu8(a: u16, b: u8) u16 {
    return a + b;
}

const Evolutions = std.AutoArrayHashMapUnmanaged(u8, Evolution);
const Items = std.AutoArrayHashMapUnmanaged(u16, Item);
const PokeballItems = std.AutoArrayHashMapUnmanaged(u16, PokeballItem);
const PokemonBy = std.AutoArrayHashMapUnmanaged(u16, Set);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);

fn pokedexPokemons(allocator: mem.Allocator, pokemons: Pokemons, pokedex: Set) !Set {
    var res = Set{};
    errdefer res.deinit(allocator);

    for (pokemons.values()) |pokemon, i| {
        if (pokemon.catch_rate == 0)
            continue;
        if (pokedex.get(pokemon.pokedex_entry) == null)
            continue;

        _ = try res.put(allocator, pokemons.keys()[i], {});
    }

    return res;
}

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
    desc: Utf8 = Utf8.init("") catch unreachable,
    price: usize = 0,
};

const Evolution = struct {
    method: format.Evolution.Method = .unused,
    param: u16 = 0,
    target: u16 = 0,
};

const PokeballItem = struct {
    item: u16,
};

test "tm35-random stones" {
    // TODO: Tests
}
