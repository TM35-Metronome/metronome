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

const errors = util.errors;
const parse = util.parse;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help                                                               Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-s, --seed <NUM>                                                         The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-m, --method <random|same-stats|simular-stats|legendary-with-legendary>  The method used to pick the new static Pokémon. (default: random)                         ") catch unreachable,
        clap.parseParam("-t, --types <random|same>                                                Which type each static pokemon should be. (default: random)                               ") catch unreachable,
        clap.parseParam("-v, --version                                                            Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-rand-starters ");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Randomizes static Pokémons.
        \\Only works properly for dppt and b2w2.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

const Method = enum {
    random,
    @"same-stats",
    @"simular-stats",
    @"legendary-with-legendary",
};

const Type = enum {
    random,
    same,
};

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

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime InStream: type,
    comptime OutStream: type,
    stdio: util.CustomStdIoStreams(InStream, OutStream),
    comptime ArgIterator: type,
    arg_iter: *ArgIterator,
) u8 {
    var stdin = io.bufferedInStream(stdio.in);
    var args = Clap.parse(allocator, ArgIterator, arg_iter) catch |err| {
        stdio.err.print("{}\n", .{err}) catch {};
        usage(stdio.err) catch {};
        return 1;
    };
    defer args.deinit();

    if (args.flag("--help")) {
        usage(stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.print("{}\n", .{program_version}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

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

    const type_arg = args.option("--types") orelse "random";
    const types = std.meta.stringToEnum(Type, type_arg) orelse {
        stdio.err.print("--types does not support '{}'\n", .{type_arg}) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const method_arg = args.option("--method") orelse "random";
    const method = std.meta.stringToEnum(Method, method_arg) orelse {
        stdio.err.print("--method does not support '{}'\n", .{method_arg}) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    var line_buf = std.ArrayList(u8).init(allocator);
    var data = Data{
        .pokemons = Pokemons.init(allocator),
        .static_mons = StaticMons.init(allocator),
    };

    while (util.readLine(&stdin, &line_buf) catch |err| return errors.readErr(stdio.err, "<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&data, str) catch |err| switch (err) {
            error.OutOfMemory => return errors.allocErr(stdio.err),
            error.ParseError => true,
        };
        if (print_line)
            stdio.out.print("{}\n", .{str}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

        line_buf.resize(0) catch unreachable;
    }

    randomize(data, seed, method, types) catch |err| return errors.randErr(stdio.err, err);

    var static_it = data.static_mons.iterator();
    while (static_it.next()) |static_kv| {
        const static_i = static_kv.key;
        const static = static_kv.value;
        stdio.out.print(".static_pokemons[{}].species={}\n", .{ static_i, static }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
    }
    return 0;
}

fn parseLine(data: *Data, str: []const u8) !bool {
    const sw = parse.Swhash(16);
    const m = sw.match;
    const c = sw.case;
    const allocator = data.pokemons.allocator;
    var p = parse.MutParser{ .str = str };

    switch (m(try p.parse(parse.anyField))) {
        c("pokemons") => {
            const index = try p.parse(parse.index);
            const poke_entry = try data.pokemons.getOrPutValue(index, Pokemon.init(allocator));
            const pokemon = &poke_entry.value;

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

                    // To keep it simple, we just leak a shit ton of type names here.
                    const type_name = try mem.dupe(allocator, u8, try p.parse(parse.strv));
                    try pokemon.types.append(type_name);
                },
                c("growth_rate") => {
                    const rate = try p.parse(parse.strv);
                    pokemon.growth_rate = try mem.dupe(allocator, u8, rate);
                },
                c("catch_rate") => pokemon.catch_rate = try p.parse(parse.usizev),
                c("gender_ratio") => pokemon.gender_ratio = try p.parse(parse.usizev),
                c("egg_groups") => {
                    // TODO: Should we save both egg groups?
                    if ((try p.parse(parse.index)) == 0) {
                        const group = try p.parse(parse.strv);
                        pokemon.egg_group = try mem.dupe(allocator, u8, group);
                    }
                },
                c("evos") => {
                    _ = try p.parse(parse.index);
                    _ = try p.parse(comptime parse.field("target"));
                    _ = try pokemon.evos.put(allocator, try p.parse(parse.usizev));
                },
                else => return true,
            }
        },
        c("static_pokemons") => {
            const index = try p.parse(parse.index);
            _ = try p.parse(comptime parse.field("species"));
            _ = try data.static_mons.put(index, try p.parse(parse.usizev));
            return false;
        },
        else => return true,
    }

    return true;
}

fn randomize(data: Data, seed: u64, method: Method, _type: Type) !void {
    const allocator = data.pokemons.allocator;
    var random_adapt = rand.DefaultPrng.init(seed);
    const random = &random_adapt.random;

    const species = try data.species();

    switch (method) {
        .random => switch (_type) {
            .random => {
                const max = species.count();
                if (max == 0)
                    return;

                var it = data.static_mons.iterator();
                while (it.next()) |kv|
                    kv.value = species.at(random.intRangeLessThan(usize, 0, max));
            },
            .same => {
                const by_type = try data.speciesByType(&species);
                var it = data.static_mons.iterator();
                while (it.next()) |kv| {
                    const pokemon = data.pokemons.get(kv.value).?.value;
                    if (pokemon.types.items.len == 0)
                        continue;

                    const t = pokemon.types.items[random.intRangeLessThan(usize, 0, pokemon.types.items.len)];
                    const pokemons = by_type.get(t).?.value;
                    const max = pokemons.count();
                    kv.value = pokemons.at(random.intRangeLessThan(usize, 0, max));
                }
            },
        },
        .@"same-stats", .@"simular-stats" => {
            const by_type = switch (_type) {
                // When we do random, we should never actually touch the 'by_type'
                // table, so let's just avoid doing the work of constructing it :)
                .random => undefined,
                .same => try data.speciesByType(&species),
            };

            var simular = std.ArrayList(usize).init(allocator);
            var it = data.static_mons.iterator();
            while (it.next()) |kv| {
                defer simular.resize(0) catch unreachable;

                // If the static Pokémon does not exist in the data
                // we received, then there is no way for us to compare
                // its stats with other Pokémons. The only thing we can
                // assume is that the Pokémon it currently is
                // simular/same as itself.
                const prev_pokemon = (data.pokemons.get(kv.value) orelse continue).value;

                var min = @intCast(i64, sum(u8, &prev_pokemon.stats));
                var max = min;

                // For same-stats, we can just make this loop run once, which will
                // make the simular list only contain pokemons with the same stats.
                const condition = if (method == .@"simular-stats") @as(usize, 25) else @as(usize, 1);
                while (simular.items.len < condition) : ({
                    min -= 5;
                    max += 5;
                }) {
                    switch (_type) {
                        .random => for (species.span()) |range| {
                            var s = range.start;
                            while (s <= range.end) : (s += 1) {
                                const pokemon = data.pokemons.get(s).?.value;

                                const total = @intCast(i64, sum(u8, &pokemon.stats));
                                if (min <= total and total <= max)
                                    try simular.append(s);
                            }
                        },
                        .same => {
                            // If this Pokémon has no type (for some reason), then we
                            // cannot pick a pokemon of the same type. The only thing
                            // we can assume is that the Pokémon is the same type
                            // as it self, and therefor just use that as the simular
                            // Pokémon.
                            if (prev_pokemon.types.items.len == 0) {
                                try simular.append(kv.value);
                                break;
                            }
                            for (prev_pokemon.types.items) |t| {
                                const pokemons_of_type = by_type.get(t).?.value;

                                for (pokemons_of_type.span()) |range| {
                                    var s = range.start;
                                    while (s <= range.end) : (s += 1) {
                                        const pokemon = data.pokemons.get(s).?.value;

                                        const total = @intCast(i64, sum(u8, &pokemon.stats));
                                        if (min <= total and total <= max)
                                            try simular.append(s);
                                    }
                                }
                            }
                        },
                    }
                }

                const pick_from = simular.items;
                kv.value = pick_from[random.intRangeLessThan(usize, 0, pick_from.len)];
            }
        },
        .@"legendary-with-legendary" => {
            // There is no way to specify ingame that a Pokémon is a legendary.
            // There are therefor two methods we can use to pick legendaries
            // 1. Have a table of Pokémons which are legendaries.
            //    - This does not work with roms that have been hacked
            //      in a way that changes which Pokémons should be considered
            //      legendary
            // 2. Find legendaries by looking at their stats, evolution line
            //    and other patterns common for legendaires
            //
            // I have chosen the latter method.

            // First, lets give each Pokémon a "legendary rating" which
            // is a meassure as to how many "legendary" criteria this
            // Pokémon fits into. This rating can be negative.
            var ratings = std.AutoHashMap(usize, isize).init(allocator);
            for (species.span()) |range| {
                var _species = range.start;
                while (_species <= range.end) : (_species += 1) {
                    const pokemon = data.pokemons.get(_species).?.value;
                    const rating_entry = try ratings.getOrPutValue(_species, 0);

                    // Legendaries are generally in the "slow" to "medium_slow"
                    // growth rating
                    if (pokemon.growth_rate) |growth_rate|
                        rating_entry.value += @as(isize, @boolToInt(mem.eql(u8, growth_rate, "slow") or
                            mem.eql(u8, growth_rate, "medium_slow")));

                    // They generally have a catch rate of 45 or less
                    if (pokemon.catch_rate) |catch_rate|
                        rating_entry.value += @as(isize, @boolToInt(catch_rate <= 45));

                    // They tend to not have a gender (255 in gender_ratio means
                    // genderless).
                    if (pokemon.gender_ratio) |gender_ratio|
                        rating_entry.value += @as(isize, @boolToInt(gender_ratio == 255));

                    // Most are part of the "undiscovered" egg group
                    if (pokemon.egg_group) |egg_group|
                        rating_entry.value += @as(isize, @boolToInt(mem.eql(u8, egg_group, "undiscovered")));

                    // And they don't evolve from anything. Suptract
                    // score from this Pokémons evolutions.
                    for (pokemon.evos.span()) |range2| {
                        var evo = range2.start;
                        while (evo <= range2.end) : (evo += 1) {
                            const evo_rating = try ratings.getOrPutValue(evo, 0);
                            evo_rating.value -= 10;
                            rating_entry.value -= 10;
                        }
                    }
                }
            }

            const rating_to_be_legendary = blk: {
                var res: isize = 0;
                var r_it = ratings.iterator();
                while (r_it.next()) |r_kv|
                    res = math.max(res, r_kv.value);

                // Not all legendaries match all criteria.
                break :blk res - 1;
            };

            var legendaries = Set{};
            var rest = Set{};

            var r_it = ratings.iterator();
            while (r_it.next()) |kv| {
                if (kv.value >= rating_to_be_legendary) {
                    _ = try legendaries.put(allocator, kv.key);
                } else {
                    _ = try rest.put(allocator, kv.key);
                }
            }

            const legendaries_by_type = switch (_type) {
                .random => undefined,
                .same => try data.speciesByType(&legendaries),
            };
            const rest_by_type = switch (_type) {
                .random => undefined,
                .same => try data.speciesByType(&rest),
            };

            var s_it = data.static_mons.iterator();
            while (s_it.next()) |kv| {
                const pokemon = (data.pokemons.get(kv.value) orelse continue).value;
                const rating = (ratings.get(kv.value) orelse continue).value;
                const pick_from = switch (_type) {
                    .random => if (rating >= rating_to_be_legendary) legendaries else rest,
                    .same => blk: {
                        if (pokemon.types.items.len == 0)
                            continue;

                        const types = pokemon.types.items;
                        const picked_type = types[random.intRangeLessThan(usize, 0, types.len)];
                        const pick_from_by_type = if (rating >= rating_to_be_legendary) legendaries_by_type else rest_by_type;
                        break :blk (pick_from_by_type.get(picked_type) orelse continue).value;
                    },
                };

                const max = pick_from.count();
                if (max == 0)
                    continue;
                kv.value = pick_from.at(random.intRangeLessThan(usize, 0, max));
            }
        },
    }
}

fn SumReturn(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Int => u64,
        .Float => f64,
        else => unreachable,
    };
}

fn sum(comptime T: type, buf: []const T) SumReturn(T) {
    var res: SumReturn(T) = 0;
    for (buf) |item|
        res += item;

    return res;
}

const Set = util.container.IntSet.Unmanaged(usize);
const SpeciesByType = std.StringHashMap(Set);
const Pokemons = std.AutoHashMap(usize, Pokemon);
const StaticMons = std.AutoHashMap(usize, usize);

const Data = struct {
    pokemons: Pokemons,
    static_mons: StaticMons,

    fn species(d: Data) !Set {
        var res = Set{};
        errdefer res.deinit(d.allocator());

        var p_it = d.pokemons.iterator();
        while (p_it.next()) |kv| {
            // We shouldn't pick Pokemon with 0 catch rate as they tend to be
            // Pokemon not meant to be used in the standard game.
            // Pokemons from the film studio in bw2 have 0 catch rate.
            if ((kv.value.catch_rate orelse 1) == 0)
                continue;
            _ = try res.put(d.allocator(), kv.key);
        }

        return res;
    }

    fn speciesByType(d: Data, _species: *const Set) !SpeciesByType {
        var res = SpeciesByType.init(d.allocator());
        errdefer {
            var it = res.iterator();
            while (it.next()) |kv|
                kv.value.deinit(d.allocator());
            res.deinit();
        }

        for (_species.span()) |range| {
            var s = range.start;
            while (s <= range.end) : (s += 1) {
                const pokemon = (d.pokemons.get(s) orelse continue).value;
                if ((pokemon.catch_rate orelse 1) == 0)
                    continue;

                for (pokemon.types.items) |t| {
                    const entry = try res.getOrPutValue(t, Set{});
                    _ = try entry.value.put(d.allocator(), s);
                }
            }
        }

        return res;
    }

    fn allocator(d: Data) *mem.Allocator {
        return d.pokemons.allocator;
    }
};

const Pokemon = struct {
    stats: [6]u8 = [_]u8{0} ** 6,
    types: std.ArrayList([]const u8),
    growth_rate: ?[]const u8 = null,
    catch_rate: ?usize = null,
    gender_ratio: ?usize = null,
    egg_group: ?[]const u8 = null,
    evos: Set = Set{},

    fn init(allocator: *mem.Allocator) Pokemon {
        return Pokemon{
            .types = std.ArrayList([]const u8).init(allocator),
        };
    }
};

test "tm35-rand-static" {
    const H = struct {
        fn pokemon(
            comptime id: []const u8,
            comptime stat: []const u8,
            comptime t1: []const u8,
            comptime t2: []const u8,
            comptime growth_rate: []const u8,
            comptime catch_rate: []const u8,
            comptime gender_ratio: []const u8,
            comptime egg_groups: []const u8,
            comptime evo: ?[]const u8,
        ) []const u8 {
            return ".pokemons[" ++ id ++ "].stats.hp=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.attack=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.defense=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.speed=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.sp_attack=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.sp_defense=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].types[0]=" ++ t1 ++ "\n" ++
                ".pokemons[" ++ id ++ "].types[1]=" ++ t2 ++ "\n" ++
                ".pokemons[" ++ id ++ "].growth_rate=" ++ growth_rate ++ "\n" ++
                ".pokemons[" ++ id ++ "].catch_rate=" ++ catch_rate ++ "\n" ++
                ".pokemons[" ++ id ++ "].gender_ratio=" ++ gender_ratio ++ "\n" ++
                ".pokemons[" ++ id ++ "].egg_groups[0]=" ++ egg_groups ++ "\n" ++
                if (evo) |e| ".pokemons[" ++ id ++ "].evos[0].target=" ++ e ++ "\n" else "";
        }
        fn static(
            comptime id: []const u8,
            comptime species: []const u8,
        ) []const u8 {
            return ".static_pokemons[" ++ id ++ "].species=" ++ species ++ "\n";
        }
    };

    const legendaries = comptime H.pokemon("0", "10", "ice", "flying", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("1", "10", "electric", "flying", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("2", "10", "fire", "flying", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("3", "10", "electric", "electric", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("4", "11", "water", "water", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("5", "11", "rock", "rock", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("6", "11", "ice", "ice", "slow", "3", "255", "undiscovered", null) ++
        H.pokemon("7", "12", "dragon", "psychic", "slow", "3", "254", "undiscovered", null) ++
        H.pokemon("8", "12", "dragon", "psychic", "slow", "3", "0", "undiscovered", null) ++
        H.pokemon("9", "12", "water", "water", "slow", "3", "255", "water1", null);

    const pseudo_legendaries = comptime H.pokemon("10", "10", "dragon", "dragon", "slow", "45", "127", "water1", "11") ++
        H.pokemon("11", "10", "dragon", "flying", "slow", "45", "127", "water1", null) ++
        H.pokemon("12", "10", "rock", "ground", "slow", "45", "127", "monster", "13") ++
        H.pokemon("13", "10", "rock", "dark", "slow", "45", "127", "monster", null) ++
        H.pokemon("14", "11", "dragon", "dragon", "slow", "45", "127", "dragon", "15") ++
        H.pokemon("15", "11", "dragon", "flying2", "slow", "45", "127", "dragon", null) ++
        H.pokemon("16", "11", "steel", "psychic", "slow", "3", "255", "mineral", "17") ++
        H.pokemon("17", "11", "steel", "psychic", "slow", "3", "255", "mineral", null) ++
        H.pokemon("18", "12", "dragon", "ground", "slow", "45", "127", "monster", "19") ++
        H.pokemon("19", "12", "dragon", "ground", "slow", "45", "127", "monster", null) ++
        H.pokemon("20", "12", "dark", "dragon", "slow", "45", "127", "dragon", "21") ++
        H.pokemon("21", "12", "dark", "dragon", "slow", "45", "127", "dragon", null);

    const pokemons_to_not_pick_ever = comptime H.pokemon("22", "12", "water", "water", "slow", "0", "255", "water1", null) ++
        H.pokemon("23", "12", "dark", "dragon", "slow", "0", "127", "dragon", null);

    const result_prefix = legendaries ++ pseudo_legendaries ++ pokemons_to_not_pick_ever;
    const test_string = comptime result_prefix ++
        H.static("0", "0") ++
        H.static("1", "1") ++
        H.static("2", "2") ++
        H.static("3", "3") ++
        H.static("4", "4") ++
        H.static("5", "21");

    util.testing.testProgram(main2, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.static_pokemons[4].species=6
        \\.static_pokemons[5].species=0
        \\.static_pokemons[3].species=1
        \\.static_pokemons[1].species=5
        \\.static_pokemons[2].species=8
        \\.static_pokemons[0].species=18
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--types=same" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=4
        \\.static_pokemons[5].species=13
        \\.static_pokemons[3].species=3
        \\.static_pokemons[1].species=3
        \\.static_pokemons[2].species=11
        \\.static_pokemons[0].species=11
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=1", "--method=same-stats" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=6
        \\.static_pokemons[5].species=21
        \\.static_pokemons[3].species=0
        \\.static_pokemons[1].species=3
        \\.static_pokemons[2].species=0
        \\.static_pokemons[0].species=2
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=1", "--method=same-stats", "--types=same" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=4
        \\.static_pokemons[5].species=21
        \\.static_pokemons[3].species=1
        \\.static_pokemons[1].species=0
        \\.static_pokemons[2].species=2
        \\.static_pokemons[0].species=0
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=2", "--method=simular-stats" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=16
        \\.static_pokemons[5].species=16
        \\.static_pokemons[3].species=6
        \\.static_pokemons[1].species=13
        \\.static_pokemons[2].species=12
        \\.static_pokemons[0].species=10
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=2", "--method=simular-stats", "--types=same" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=9
        \\.static_pokemons[5].species=14
        \\.static_pokemons[3].species=3
        \\.static_pokemons[1].species=3
        \\.static_pokemons[2].species=2
        \\.static_pokemons[0].species=0
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=3", "--method=legendary-with-legendary" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=8
        \\.static_pokemons[5].species=10
        \\.static_pokemons[3].species=8
        \\.static_pokemons[1].species=3
        \\.static_pokemons[2].species=7
        \\.static_pokemons[0].species=4
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=4", "--method=legendary-with-legendary", "--types=same" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=9
        \\.static_pokemons[5].species=21
        \\.static_pokemons[3].species=3
        \\.static_pokemons[1].species=2
        \\.static_pokemons[2].species=2
        \\.static_pokemons[0].species=0
        \\
    );
}
