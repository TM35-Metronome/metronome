const clap = @import("clap");
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

const escape = util.escape;
const exit = util.exit;
const parse = util.parse;

const Utf8 = util.unicode.Utf8View;

const Clap = clap.ComptimeClap(clap.Help, &params);
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

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-random-stones ");
    try clap.usage(stream, &params);
    try stream.writeAll("\nChanges all Pokémons to evolve using new evolution stones. " ++
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
    try clap.help(stream, &params);
}

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime InStream: type,
    comptime OutStream: type,
    stdio: util.CustomStdIoStreams(InStream, OutStream),
    args: var,
) u8 {
    const replace_cheap = args.flag("--replace-cheap-items");
    const seed = if (args.option("--seed")) |seed|
        fmt.parseUnsigned(u64, seed, 10) catch |err| {
            stdio.err.print("'{}' could not be parsed as a number to --seed: {}\n", .{ seed, err }) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    else blk: {
        var buf: [8]u8 = undefined;
        os.getrandom(buf[0..]) catch break :blk @as(u64, 0);
        break :blk mem.readInt(u64, &buf, .Little);
    };

    var fifo = util.read.Fifo(.Dynamic).init(allocator);
    var data = Data{
        .strings = std.StringHashMap(usize).init(allocator),
    };
    while (util.read.line(stdio.in, &fifo) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(allocator, &data, replace_cheap, str) catch |err| switch (err) {
            error.OutOfMemory => return exit.allocErr(stdio.err),
            error.ParseError,
            error.InvalidUtf8,
            => true,
        };
        if (print_line)
            stdio.out.print("{}\n", .{str}) catch |err| return exit.stdoutErr(stdio.err, err);
    }

    randomize(allocator, &data, seed) catch return exit.allocErr(stdio.err);

    for (data.pokemons.values()) |pokemon, i| {
        const pokemon_id = data.pokemons.at(i).key;
        for (pokemon.evos.values()) |evo, j| {
            const evo_id = pokemon.evos.at(j).key;
            stdio.out.print(".pokemons[{}].evos[{}].method=use_item\n", .{ pokemon_id, evo_id }) catch |err| return exit.stdoutErr(stdio.err, err);
            stdio.out.print(".pokemons[{}].evos[{}].param={}\n", .{ pokemon_id, evo_id, evo.item }) catch |err| return exit.stdoutErr(stdio.err, err);
            stdio.out.print(".pokemons[{}].evos[{}].target={}\n", .{ pokemon_id, evo_id, evo.target }) catch |err| return exit.stdoutErr(stdio.err, err);
        }
    }
    for (data.items.values()) |item, i| {
        const item_id = data.items.at(i).key;
        if (item.name.bytes.len != 0)
            stdio.out.print(".items[{}].name={}\n", .{ item_id, item.name.bytes }) catch |err| return exit.stdoutErr(stdio.err, err);
        if (item.description.bytes.len != 0) {
            stdio.out.print(".items[{}].description=", .{item_id}) catch |err| return exit.stdoutErr(stdio.err, err);
            escape.writeEscaped(stdio.out, item.description.bytes, escape.zig_escapes) catch |err| return exit.stdoutErr(stdio.err, err);
            stdio.out.writeAll("\n") catch |err| return exit.stdoutErr(stdio.err, err);
        }
    }
    for (data.pokeball_items.values()) |item, i| {
        const ball_id = data.pokeball_items.at(i).key;
        stdio.out.print(".pokeball_items[{}].item={}\n", .{ ball_id, item }) catch |err| return exit.stdoutErr(stdio.err, err);
    }
    return 0;
}

fn parseLine(allocator: *mem.Allocator, data: *Data, replace_cheap: bool, str: []const u8) !bool {
    const sw = parse.Swhash(16);
    const m = sw.match;
    const c = sw.case;

    const unknown_method = try data.string("????");

    var p = parse.MutParser{ .str = str };
    switch (m(try p.parse(parse.anyField))) {
        c("pokedex") => {
            const index = try p.parse(parse.index);
            _ = try data.pokedex.put(allocator, index);
        },
        c("pokemons") => {
            const index = try p.parse(parse.index);
            const pokemon = try data.pokemons.getOrPutValue(allocator, index, Pokemon{});

            switch (m(try p.parse(parse.anyField))) {
                c("catch_rate") => pokemon.catch_rate = try p.parse(parse.usizev),
                c("pokedex_entry") => pokemon.pokedex_entry = try p.parse(parse.usizev),
                c("base_friendship") => pokemon.base_friendship = try p.parse(parse.usizev),
                c("growth_rate") => pokemon.growth_rate = try data.string(try p.parse(parse.strv)),
                c("stats") => switch (m(try p.parse(parse.anyField))) {
                    c("hp") => pokemon.stats[0] = try p.parse(parse.u8v),
                    c("attack") => pokemon.stats[1] = try p.parse(parse.u8v),
                    c("defense") => pokemon.stats[2] = try p.parse(parse.u8v),
                    c("speed") => pokemon.stats[3] = try p.parse(parse.u8v),
                    c("sp_attack") => pokemon.stats[4] = try p.parse(parse.u8v),
                    c("sp_defense") => pokemon.stats[5] = try p.parse(parse.u8v),
                    else => return true,
                },
                c("types") => {
                    _ = try p.parse(parse.index);
                    _ = try pokemon.types.put(allocator, try p.parse(parse.usizev));
                },
                c("abilities") => {
                    _ = try p.parse(parse.index);
                    _ = try pokemon.abilities.put(allocator, try p.parse(parse.usizev));
                },
                c("egg_groups") => {
                    _ = try p.parse(parse.index);
                    _ = try pokemon.egg_groups.put(allocator, try data.string(try p.parse(parse.strv)));
                },
                c("evos") => {
                    const evo_index = try p.parse(parse.index);
                    data.max_evolutions = math.max(data.max_evolutions, evo_index + 1);

                    const evo = try pokemon.evos.getOrPutValue(allocator, evo_index, Evolution{
                        .method = unknown_method,
                    });
                    switch (m(try p.parse(parse.anyField))) {
                        c("target") => evo.target = try p.parse(parse.usizev),
                        c("param") => evo.item = try p.parse(parse.usizev),
                        c("method") => evo.method = try data.string(try p.parse(parse.strv)),
                        else => {},
                    }
                    return false;
                },
                else => return true,
            }
            return true;
        },
        c("items") => {
            const index = try p.parse(parse.index);
            const item = try data.items.getOrPutValue(allocator, index, Item{});

            switch (m(try p.parse(parse.anyField))) {
                c("name") => {
                    const name = try mem.dupe(allocator, u8, try p.parse(parse.strv));
                    item.name = try Utf8.init(name);
                },
                c("description") => {
                    const desc = try escape.unEscape(
                        allocator,
                        try p.parse(parse.strv),
                        escape.zig_escapes,
                    );
                    item.description = try Utf8.init(desc);
                },
                c("price") => {
                    item.price = try p.parse(parse.usizev);
                    return true;
                },
                else => return true,
            }
            return false;
        },
        c("pokeball_items") => if (replace_cheap) {
            const index = try p.parse(parse.index);
            _ = try p.parse(comptime parse.field("item"));
            _ = try data.pokeball_items.put(allocator, index, try p.parse(parse.usizev));
            return false;
        },
        else => return true,
    }
    return true;
}

fn randomize(allocator: *mem.Allocator, data: *Data, seed: usize) !void {
    const random = &rand.DefaultPrng.init(seed).random;
    const use_item_method = try data.string("use_item");

    // First, let's find items that are used for evolving Pokémons.
    // We will use these items as our stones.
    var stones = Set{};
    for (data.pokemons.values()) |*pokemon| {
        for (pokemon.evos.values()) |evo| {
            if (evo.method == use_item_method)
                _ = try stones.put(allocator, evo.item);
        }

        // Reset evolutions. We don't need the old anymore.
        pokemon.evos.deinit(allocator);
        pokemon.evos = Evolutions{};
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
                Utf8.init("Chance Stone") catch unreachable,
                Utf8.init("Chance Rock") catch unreachable,
                Utf8.init("Luck Rock") catch unreachable,
                Utf8.init("Luck Rck") catch unreachable,
                Utf8.init("C Stone") catch unreachable,
                Utf8.init("C Rock") catch unreachable,
                Utf8.init("C Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon into random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Into random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("To random Pokémon") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.init("Stat Stone") catch unreachable,
                Utf8.init("Stat Rock") catch unreachable,
                Utf8.init("St Stone") catch unreachable,
                Utf8.init("St Rock") catch unreachable,
                Utf8.init("St Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with the same total stats.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with the same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon into random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Into random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("To random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon with same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon, same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random, same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random same stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Same total stats") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Same stats") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.init("Growth Stone") catch unreachable,
                Utf8.init("Growth Rock") catch unreachable,
                Utf8.init("Rate Stone") catch unreachable,
                Utf8.init("Rate Rock") catch unreachable,
                Utf8.init("G Stone") catch unreachable,
                Utf8.init("G Rock") catch unreachable,
                Utf8.init("G Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with the same growth rate.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with the same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with same growth rate.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon into random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Into random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("To random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon with same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon, same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random, same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random same growth rate") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Same growth rate") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.init("Form Stone") catch unreachable,
                Utf8.init("Form Rock") catch unreachable,
                Utf8.init("Form Rck") catch unreachable,
                Utf8.init("T Stone") catch unreachable,
                Utf8.init("T Rock") catch unreachable,
                Utf8.init("T Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with a common type.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon into random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon with same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Into random Pokémon with a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Into random Pokémon with same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("To random Pokémon with same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon, a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon, same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random, a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random a common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random, same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random same type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("A common type") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Same type") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.init("Skill Stone") catch unreachable,
                Utf8.init("Skill Rock") catch unreachable,
                Utf8.init("Skill Rck") catch unreachable,
                Utf8.init("S Stone") catch unreachable,
                Utf8.init("S Rock") catch unreachable,
                Utf8.init("S Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with a common ability.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon into random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon with same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Into random Pokémon with a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Into random Pokémon with same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("To random Pokémon with same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon, a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon, same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random, a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random a common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random, same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random same ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("A common ability") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Same ability") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.init("Breed Stone") catch unreachable,
                Utf8.init("Breed Rock") catch unreachable,
                Utf8.init("Egg Stone") catch unreachable,
                Utf8.init("Egg Rock") catch unreachable,
                Utf8.init("Egg Rck") catch unreachable,
                Utf8.init("E Stone") catch unreachable,
                Utf8.init("E Rock") catch unreachable,
                Utf8.init("E Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon in the same egg group.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon into random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve a Pokémon to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon with same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Into random Pokémon in the same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Into random Pokémon with same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("To random Pokémon with same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon, in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon, same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random, in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random in same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random, same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("In same egg group") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Same egg group") catch unreachable),
            },
        },
        .{
            .names = &[_]Utf8{
                Utf8.init("Buddy Stone") catch unreachable,
                Utf8.init("Buddy Rock") catch unreachable,
                Utf8.init("Buddy Rck") catch unreachable,
                Utf8.init("F Stone") catch unreachable,
                Utf8.init("F Rock") catch unreachable,
                Utf8.init("F Rck") catch unreachable,
            },
            .descriptions = &[_]Utf8{
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with the same base friendship.") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves a Pokémon into random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves to random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon with the same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon with same base friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolves to random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Evolve to random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Into random Pokémon with the same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Into random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("To random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon, with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon, same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random Pokémon same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random, with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random with same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random, same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Random same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("In same friendship") catch unreachable),
                try util.unicode.splitIntoLines(allocator, max_line_len, Utf8.init("Same friendship") catch unreachable),
            },
        },
    };
    for (stone_strings) |strings, stone| {
        if (data.max_evolutions <= stone or stones.count() <= stone)
            break;

        const item_id = stones.at(stone);
        const item = data.items.get(item_id).?;

        // We have no idea as to how long the name/desc can be in the game we
        // are working on. Our best guess will therefor be to use the current
        // items name/desc as the limits and pick something that fits.
        item.* = Item{
            .name = pickString(item.name.len, strings.names),
            .description = pickString(item.description.len, strings.descriptions),
        };
    }

    const num_pokemons = species.count();
    for (species.span()) |s_range| {
        var pokemon_id: usize = s_range.start;
        while (pokemon_id <= s_range.end) : (pokemon_id += 1) {
            const pokemon = data.pokemons.get(pokemon_id).?;

            for (stone_strings) |strings, stone| {
                if (data.max_evolutions <= stone or stones.count() <= stone)
                    break;

                const item_id = stones.at(stone);
                const pick = switch (stone) {
                    chance_stone => while (num_pokemons > 1) {
                        const pick = species.at(random.intRangeLessThan(usize, 0, num_pokemons));
                        if (pick != pokemon_id)
                            break pick;
                    } else pokemon_id,

                    form_stone, skill_stone, breed_stone => blk: {
                        const map = switch (stone) {
                            growth_stone => pokemons_by_growth_rate,
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
                                const pick = set.at(random.intRangeLessThan(usize, 0, set.count()));
                                if (pick != 0)
                                    break pick;
                            } else set.at(0),
                            form_stone, breed_stone => set.at(random.intRangeLessThan(usize, 0, set.count())),
                            else => unreachable,
                        };
                        const pokemon_set = map.get(picked_id).?;
                        const pokemons = pokemon_set.count();
                        while (pokemons != 1) {
                            const pick = pokemon_set.at(random.intRangeLessThan(usize, 0, pokemons));
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
                            stat_stone => sum(&pokemon.stats),
                            growth_stone => pokemon.growth_rate,
                            buddy_stone => pokemon.base_friendship,
                            else => unreachable,
                        };
                        if (map.count() == 0)
                            break :blk pokemon_id;

                        const pokemon_set = map.get(number).?;
                        const pokemons = pokemon_set.count();
                        while (pokemons != 1) {
                            const pick = pokemon_set.at(random.intRangeLessThan(usize, 0, pokemons));
                            if (pick != pokemon_id)
                                break :blk pick;
                        }
                        break :blk pokemon_id;
                    },
                    else => unreachable,
                };

                _ = try pokemon.evos.put(allocator, stone, Evolution{
                    .method = use_item_method,
                    .item = item_id,
                    .target = pick,
                });
            }
        }
    }

    const number_of_stones = math.min(math.min(stones.count(), stone_strings.len), data.max_evolutions);
    for (data.pokeball_items.values()) |*item_id| {
        const item = data.items.get(item_id.*) orelse continue;
        if (item.price == 0 or item.price > 600)
            continue;
        const pick = random.intRangeLessThan(usize, 0, number_of_stones);
        item_id.* = stones.at(pick);
    }
}

fn sum(buf: []const u8) usize {
    var res: usize = 0;
    for (buf) |item|
        res += item;

    return res;
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
    filter: fn (Pokemon, []usize) []const usize,
) !PokemonBy {
    var buf: [16]usize = undefined;
    var pokemons_by = PokemonBy{};
    for (species.span()) |s_range| {
        var id: usize = s_range.start;
        while (id <= s_range.end) : (id += 1) {
            const pokemon = pokemons.get(id).?;
            for (filter(pokemon.*, &buf)) |key| {
                const set = try pokemons_by.getOrPutValue(allocator, key, Set{});
                _ = try set.put(allocator, id);
            }
        }
    }
    return pokemons_by;
}

fn statsFilter(pokemon: Pokemon, buf: []usize) []const usize {
    buf[0] = sum(&pokemon.stats);
    return buf[0..1];
}

fn friendshipFilter(pokemon: Pokemon, buf: []usize) []const usize {
    buf[0] = pokemon.base_friendship;
    return buf[0..1];
}

fn growthRateFilter(pokemon: Pokemon, buf: []usize) []const usize {
    buf[0] = pokemon.growth_rate;
    return buf[0..1];
}

fn typeFilter(pokemon: Pokemon, buf: []usize) []const usize {
    return setFilter("types", pokemon, buf);
}

fn abilityFilter(pokemon: Pokemon, buf: []usize) []const usize {
    return setFilter("abilities", pokemon, buf);
}

fn eggGroupFilter(pokemon: Pokemon, buf: []usize) []const usize {
    return setFilter("egg_groups", pokemon, buf);
}

fn setFilter(comptime field: []const u8, pokemon: Pokemon, buf: []usize) []const usize {
    var i: usize = 0;
    for (@field(pokemon, field).span()) |range| {
        var j = range.start;
        while (j <= range.end) {
            buf[i] = j;
            j += 1;
            i += 1;
        }
    }
    return buf[0..i];
}

const Set = util.container.IntSet.Unmanaged(usize);
const PokemonBy = util.container.IntMap.Unmanaged(usize, Set);
const Items = util.container.IntMap.Unmanaged(usize, Item);
const Pokemons = util.container.IntMap.Unmanaged(usize, Pokemon);
const Evolutions = util.container.IntMap.Unmanaged(usize, Evolution);
const PokeballItems = util.container.IntMap.Unmanaged(usize, usize);

const Data = struct {
    strings: std.StringHashMap(usize),
    max_evolutions: usize = 0,
    pokedex: Set = Set{},
    items: Items = Items{},
    pokeball_items: PokeballItems = PokeballItems{},
    pokemons: Pokemons = Pokemons{},

    fn string(d: *Data, str: []const u8) !usize {
        const res = try d.strings.getOrPut(str);
        if (!res.found_existing) {
            res.kv.key = try mem.dupe(d.strings.allocator, u8, str);
            res.kv.value = d.strings.count() - 1;
        }
        return res.kv.value;
    }

    fn pokedexPokemons(d: Data, allocator: *mem.Allocator) !Set {
        var res = Set{};
        errdefer res.deinit(allocator);

        for (d.pokemons.values()) |pokemon, i| {
            const s = d.pokemons.at(i).key;
            if (pokemon.catch_rate == 0 or !d.pokedex.exists(pokemon.pokedex_entry))
                continue;

            _ = try res.put(allocator, s);
        }

        return res;
    }
};

const Pokemon = struct {
    evos: Evolutions = Evolutions{},
    stats: [6]u8 = [_]u8{0} ** 6,
    growth_rate: usize = math.maxInt(usize),
    base_friendship: usize = 0,
    catch_rate: usize = 1,
    pokedex_entry: usize = math.maxInt(usize),
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
    method: usize,
    item: usize = 0,
    target: usize = 0,
};

test "tm35-random stones" {
    // TODO: Tests
}
