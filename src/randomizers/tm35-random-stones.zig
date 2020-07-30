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

const exit = util.exit;
const parse = util.parse;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help                 Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-r, --replace-cheap-items  Replaces cheap items in pokeballs with stones.") catch unreachable,
        clap.parseParam("-s, --seed <NUM>           The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
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
        "* Superior Stone: Evolves a Pokémon into random Pokémon with better overall stats.\n" ++
        "* Poor Stone: Evolves a Pokémon into random Pokémon with worse overall stats.\n" ++
        "* Form Stone: Evolves a Pokémon into random Pokémon with a common type.\n" ++
        "* Skill Stone: Evolves a Pokémon into random Pokémon with a common ability.\n" ++
        "* Breed Stone: Evolves a Pokémon into random Pokémon in the same egg group.\n" ++
        "* Buddy Stone: Evolves a Pokémon into random Pokémon with the same base friendship.\n" ++
        "\n" ++
        "This command will try to get as many of these stones into the game as possible, " ++
        "but beware, that all stones might not exist. Also beware, that the stones might " ++
        "have different (but simular) names in cases wherethe game does not support long " ++
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

    var line_buf = std.ArrayList(u8).init(allocator);
    var stdin = io.bufferedInStream(stdio.in);
    var data = Data{
        .strings = std.StringHashMap(usize).init(allocator),
    };

    while (util.readLine(&stdin, &line_buf) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(allocator, &data, replace_cheap, str) catch |err| switch (err) {
            error.OutOfMemory => return exit.allocErr(stdio.err),
            error.ParseError => true,
        };
        if (print_line)
            stdio.out.print("{}\n", .{str}) catch |err| return exit.stdoutErr(stdio.err, err);

        line_buf.resize(0) catch unreachable;
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
        if (item.name.len != 0)
            stdio.out.print(".items[{}].name={}\n", .{ item_id, item.name }) catch |err| return exit.stdoutErr(stdio.err, err);
        if (item.description.len != 0)
            stdio.out.print(".items[{}].description={}\n", .{ item_id, item.description }) catch |err| return exit.stdoutErr(stdio.err, err);
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
        c("pokemons") => {
            const index = try p.parse(parse.index);
            const pokemon = try data.pokemons.getOrPutValue(allocator, index, Pokemon{});

            switch (m(try p.parse(parse.anyField))) {
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
                    const t = try p.parse(parse.usizev);
                    const set = try data.pokemons_by_type.getOrPutValue(allocator, t, Set{});
                    _ = try set.put(allocator, index);
                    _ = try pokemon.types.put(allocator, t);
                },
                c("abilities") => {
                    _ = try p.parse(parse.index);
                    const ability = try p.parse(parse.usizev);
                    const set = try data.pokemons_by_ability.getOrPutValue(allocator, ability, Set{});
                    _ = try set.put(allocator, index);
                    _ = try pokemon.abilities.put(allocator, ability);
                },
                c("egg_groups") => {
                    _ = try p.parse(parse.index);
                    const group = try data.string(try p.parse(parse.strv));
                    const set = try data.pokemons_by_egg_group.getOrPutValue(allocator, group, Set{});
                    _ = try set.put(allocator, index);
                    _ = try pokemon.egg_groups.put(allocator, group);
                },
                c("base_friendship") => {
                    const friendship = try p.parse(parse.usizev);
                    const set = try data.pokemons_by_base_friendship.getOrPutValue(allocator, friendship, Set{});
                    _ = try set.put(allocator, index);
                    pokemon.base_friendship = friendship;
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
                c("name") => item.name = try mem.dupe(allocator, u8, try p.parse(parse.strv)),
                c("description") => item.description = try mem.dupe(allocator, u8, try p.parse(parse.strv)),
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

    debug.warn("{}\n", .{stones.count()});

    // Make a map from total stats to the Pokémons who have them. This couldn't
    // be done during the parsing of the data as we need all the stats to perform
    // the sum. It is therefor done here.
    var pokemons_by_stats = PokemonBy{};
    for (data.pokemons.values()) |pokemon, i| {
        const id = data.pokemons.at(i).key;
        const set = try pokemons_by_stats.getOrPutValue(allocator, sum(&pokemon.stats), Set{});
        _ = try set.put(allocator, id);
    }

    // Make sure these indexs line up with the array below
    const chance_stone = 0;
    const superior_stone = 1;
    const poor_stone = 2;
    const form_stone = 3;
    const skill_stone = 4;
    const breed_stone = 5;
    const buddy_stone = 6;
    const stone_strings = [_]struct {
        names: []const []const u8,
        descriptions: []const []const u8,
    }{
        .{
            .names = &[_][]const u8{
                "Chance Stone",
                "Chance Rock",
                "Luck Rock",
                "Luck Rck",
                "C Stone",
                "C Rock",
                "C Rck",
            },
            .descriptions = &[_][]const u8{
                "Evolves a Pokémon into random Pokémon.",
                "Evolves a Pokémon into random Pokémon",
                "Evolve a Pokémon into random Pokémon",
                "Evolves a Pokémon to random Pokémon",
                "Evolve a Pokémon to random Pokémon",
                "Evolves to random Pokémon",
                "Evolve to random Pokémon",
                "Into random Pokémon",
                "To random Pokémon",
                "Random Pokémon",
            },
        },
        .{
            .names = &[_][]const u8{
                "Superior Stone",
                "Superior Rock",
                "Better Stone",
                "Better Rock",
                "Good Stone",
                "Good Rock",
                "Good Rck",
                "B Stone",
                "B Rock",
                "B Rck",
            },
            .descriptions = &[_][]const u8{
                "Evolves a Pokémon into random Pokémon with better overall stats.",
                "Evolves a Pokémon into random Pokémon with better overall stats",
                "Evolves a Pokémon into random Pokémon with better stats",
                "Evolve a Pokémon into random Pokémon with better stats",
                "Evolves a Pokémon to random Pokémon with better stats",
                "Evolve a Pokémon to random Pokémon with better stats",
                "Evolves to random Pokémon with better stats",
                "Evolve to random Pokémon with better stats",
                "Into random Pokémon with better stats",
                "To random Pokémon with better stats",
                "Random Pokémon with better stats",
                "Random Pokémon, better stats",
                "Random Pokémon better stats",
                "Random, better stats",
                "Random better stats",
                "Better stats",
            },
        },
        .{
            .names = &[_][]const u8{
                "Poor Stone",
                "Poor Rock",
                "Bad Rock",
                "Bad Rck",
            },
            .descriptions = &[_][]const u8{
                "Evolves a Pokémon into random Pokémon with worse overall stats.",
                "Evolves a Pokémon into random Pokémon with worse overall stats",
                "Evolves a Pokémon into random Pokémon with worse stats",
                "Evolve a Pokémon into random Pokémon with worse stats",
                "Evolves a Pokémon to random Pokémon with worse stats",
                "Evolve a Pokémon to random Pokémon with worse stats",
                "Evolves to random Pokémon with worse stats",
                "Evolve to random Pokémon with worse stats",
                "Into random Pokémon with worse stats",
                "To random Pokémon with worse stats",
                "Random Pokémon with worse stats",
                "Random Pokémon, worse stats",
                "Random Pokémon worse stats",
                "Random, worse stats",
                "Random worse stats",
                "Worse stats",
            },
        },
        .{
            .names = &[_][]const u8{
                "Form Stone",
                "Form Rock",
                "Form Rck",
                "T Stone",
                "T Rock",
                "T Rck",
            },
            .descriptions = &[_][]const u8{
                "Evolves a Pokémon into random Pokémon with a common type.",
                "Evolves a Pokémon into random Pokémon with a common type",
                "Evolve a Pokémon into random Pokémon with a common type",
                "Evolves a Pokémon to random Pokémon with a common type",
                "Evolve a Pokémon to random Pokémon with a common type",
                "Evolves to random Pokémon with a common type",
                "Evolve to random Pokémon with a common type",
                "Evolve to random Pokémon with same type",
                "Into random Pokémon with a common type",
                "Into random Pokémon with same type",
                "To random Pokémon with same type",
                "Random Pokémon, a common type",
                "Random Pokémon a common type",
                "Random Pokémon, same type",
                "Random Pokémon same type",
                "Random, a common type",
                "Random a common type",
                "Random, same type",
                "Random same type",
                "A common type",
                "Same type",
            },
        },
        .{
            .names = &[_][]const u8{
                "Skill Stone",
                "Skill Rock",
                "Skill Rck",
                "S Stone",
                "S Rock",
                "S Rck",
            },
            .descriptions = &[_][]const u8{
                "Evolves a Pokémon into random Pokémon with a common ability.",
                "Evolves a Pokémon into random Pokémon with a common ability",
                "Evolve a Pokémon into random Pokémon with a common ability",
                "Evolves a Pokémon to random Pokémon with a common ability",
                "Evolve a Pokémon to random Pokémon with a common ability",
                "Evolves to random Pokémon with a common ability",
                "Evolve to random Pokémon with a common ability",
                "Evolve to random Pokémon with same ability",
                "Into random Pokémon with a common ability",
                "Into random Pokémon with same ability",
                "To random Pokémon with same ability",
                "Random Pokémon, a common ability",
                "Random Pokémon a common ability",
                "Random Pokémon, same ability",
                "Random Pokémon same ability",
                "Random, a common ability",
                "Random a common ability",
                "Random, same ability",
                "Random same ability",
                "A common ability",
                "Same ability",
            },
        },
        .{
            .names = &[_][]const u8{
                "Breed Stone",
                "Breed Rock",
                "Egg Stone",
                "Egg Rock",
                "Egg Rck",
                "E Stone",
                "E Rock",
                "E Rck",
            },
            .descriptions = &[_][]const u8{
                "Evolves a Pokémon into random Pokémon in the same egg group.",
                "Evolves a Pokémon into random Pokémon in the same egg group",
                "Evolve a Pokémon into random Pokémon in the same egg group",
                "Evolves a Pokémon to random Pokémon in the same egg group",
                "Evolve a Pokémon to random Pokémon in the same egg group",
                "Evolves to random Pokémon in the same egg group",
                "Evolve to random Pokémon in the same egg group",
                "Evolve to random Pokémon with same egg group",
                "Into random Pokémon in the same egg group",
                "Into random Pokémon with same egg group",
                "To random Pokémon with same egg group",
                "Random Pokémon, in same egg group",
                "Random Pokémon in same egg group",
                "Random Pokémon, same egg group",
                "Random Pokémon same egg group",
                "Random, in same egg group",
                "Random in same egg group",
                "Random, same egg group",
                "Random same egg group",
                "In same egg group",
                "Same egg group",
            },
        },
        .{
            .names = &[_][]const u8{
                "Buddy Stone",
                "Buddy Rock",
                "Buddy Rck",
                "F Stone",
                "F Rock",
                "F Rck",
            },
            .descriptions = &[_][]const u8{
                "Evolves a Pokémon into random Pokémon with the same base friendship.",
                "Evolves a Pokémon into random Pokémon with the same base friendship",
                "Evolves a Pokémon into random Pokémon with the same base friendship",
                "Evolves a Pokémon into random Pokémon with the same friendship",
                "Evolves to random Pokémon with the same base friendship",
                "Evolve to random Pokémon with the same base friendship",
                "Evolve to random Pokémon with same base friendship",
                "Evolves to random Pokémon with the same friendship",
                "Evolve to random Pokémon with the same friendship",
                "Evolve to random Pokémon with same friendship",
                "Into random Pokémon with the same friendship",
                "Into random Pokémon with same friendship",
                "To random Pokémon with same friendship",
                "Random Pokémon, with same friendship",
                "Random Pokémon with same friendship",
                "Random Pokémon, same friendship",
                "Random Pokémon same friendship",
                "Random, with same friendship",
                "Random with same friendship",
                "Random, same friendship",
                "Random same friendship",
                "In same friendship",
                "Same friendship",
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

    const num_pokemons = data.pokemons.count();
    for (data.pokemons.values()) |*pokemon, i| {
        const pokemon_id = data.pokemons.at(i).key;

        for (stone_strings) |strings, stone| {
            if (data.max_evolutions <= stone or stones.count() <= stone)
                break;

            const item_id = stones.at(stone);
            const pick = switch (stone) {
                chance_stone => while (num_pokemons > 1) {
                    const pick = random.intRangeLessThan(usize, 0, num_pokemons);
                    if (pick != pokemon_id)
                        break pick;
                } else pokemon_id,

                superior_stone, poor_stone => blk: {
                    const total_stats = sum(&pokemon.stats);

                    // Intmaps/sets have sorted keys. We can therefor pick an index
                    // above or below the current one, to get a set of Pokémons whose
                    // stats are better or worse than the current one.
                    const stat_index = pokemons_by_stats.set.index(total_stats).?;
                    const picked_index = switch (stone) {
                        superior_stone => random.intRangeLessThan(
                            usize,
                            stat_index + @boolToInt(stat_index + 1 < pokemons_by_stats.count()),
                            pokemons_by_stats.count(),
                        ),
                        poor_stone => random.intRangeLessThan(
                            usize,
                            0,
                            (stat_index - @boolToInt(stat_index != 0)) + 1,
                        ),
                        else => unreachable,
                    };

                    const set = pokemons_by_stats.at(picked_index).value;
                    while (set.count() != 1) {
                        const pick = set.at(random.intRangeLessThan(usize, 0, set.count()));
                        if (pick != pokemon_id)
                            break :blk pick;
                    }

                    break :blk set.at(0);
                },

                form_stone, skill_stone, breed_stone => blk: {
                    const map = switch (stone) {
                        form_stone => data.pokemons_by_type,
                        skill_stone => data.pokemons_by_ability,
                        breed_stone => data.pokemons_by_egg_group,
                        else => unreachable,
                    };
                    const set = switch (stone) {
                        form_stone => pokemon.types,
                        skill_stone => pokemon.abilities,
                        breed_stone => pokemon.egg_groups,
                        else => unreachable,
                    };

                    const map_count = map.count();
                    if (map_count == 0)
                        break :blk pokemon_id;

                    const picked_id = set.at(random.intRangeLessThan(usize, 0, set.count()));
                    const pokemon_set = map.get(picked_id).?;
                    const pokemons = pokemon_set.count();
                    while (pokemons != 1) {
                        const pick = pokemon_set.at(random.intRangeLessThan(usize, 0, pokemons));
                        if (pick != pokemon_id)
                            break :blk pick;
                    }
                    break :blk pokemon_id;
                },

                buddy_stone => blk: {
                    const map_count = data.pokemons_by_base_friendship.count();
                    if (map_count == 0)
                        break :blk pokemon_id;

                    const pokemon_set = data.pokemons_by_base_friendship.get(pokemon.base_friendship).?;
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

fn pickString(len: usize, strings: []const []const u8) []const u8 {
    var pick = strings[0];
    for (strings) |str| {
        pick = str;
        if (str.len <= len)
            break;
    }

    return pick[0..math.min(len, pick.len)];
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
    stones: Set = Set{},
    items: Items = Items{},
    pokeball_items: PokeballItems = PokeballItems{},
    pokemons: Pokemons = Pokemons{},
    pokemons_by_ability: PokemonBy = PokemonBy{},
    pokemons_by_type: PokemonBy = PokemonBy{},
    pokemons_by_egg_group: PokemonBy = PokemonBy{},
    pokemons_by_base_friendship: PokemonBy = PokemonBy{},

    fn string(d: *Data, str: []const u8) !usize {
        const res = try d.strings.getOrPut(str);
        if (!res.found_existing) {
            res.kv.key = try mem.dupe(d.strings.allocator, u8, str);
            res.kv.value = d.strings.count() - 1;
        }
        return res.kv.value;
    }
};

const Pokemon = struct {
    evos: Evolutions = Evolutions{},
    stats: [6]u8 = [_]u8{0} ** 6,
    base_friendship: usize = 0,
    abilities: Set = Set{},
    types: Set = Set{},
    egg_groups: Set = Set{},
};

const Item = struct {
    name: []const u8 = "",
    description: []const u8 = "",
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
