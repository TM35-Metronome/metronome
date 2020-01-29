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
const format = util.format;

const BufInStream = io.BufferedInStream(fs.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);

const Clap = clap.ComptimeClap(clap.Help, params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

// TODO: Have the tm35-randomizer recognize options with it's help message split onto a new line
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
    try stream.write(
        \\Usage: tm35-rand-parties [-hv] [-s <NUM>] [-m <METHOD>] [-t <random|same>]
        \\Randomizes trainer parties.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
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
    var stdio_unbuf = util.getStdIo() catch |err| return 1;
    var stdio = stdio_unbuf.getBuffered();
    defer stdio.err.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(&arena.allocator) catch
        return errors.allocErr(&stdio.err.stream);
    const res = main2(
        &arena.allocator,
        fs.File.ReadError,
        fs.File.WriteError,
        stdio.getStreams(),
        clap.args.OsIterator,
        &arg_iter,
    );

    stdio.out.flush() catch |err| return errors.writeErr(&stdio.err.stream, "<stdout>", err);
    return res;
}

pub fn main2(
    allocator: *mem.Allocator,
    comptime ReadError: type,
    comptime WriteError: type,
    stdio: util.CustomStdIoStreams(ReadError, WriteError),
    comptime ArgIterator: type,
    arg_iter: *ArgIterator,
) u8 {
    var stdin = io.BufferedInStream(ReadError).init(stdio.in);
    var args = Clap.parse(allocator, ArgIterator, arg_iter) catch |err| {
        stdio.err.print("{}\n", err) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    if (args.flag("--help")) {
        usage(stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.print("{}\n", program_version) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    const seed = if (args.option("--seed")) |seed|
        fmt.parseUnsigned(u64, seed, 10) catch |err| {
            stdio.err.print("'{}' could not be parsed as a number to --seed: {}\n", seed, err) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    else blk: {
        var buf: [8]u8 = undefined;
        os.getrandom(buf[0..]) catch break :blk u64(0);
        break :blk mem.readInt(u64, &buf, .Little);
    };

    const type_arg = args.option("--types") orelse "random";
    const types = std.meta.stringToEnum(Type, type_arg) orelse {
        stdio.err.print("--types does not support '{}'\n", type_arg) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const method_arg = args.option("--method") orelse "random";
    const method = std.meta.stringToEnum(Method, method_arg) orelse {
        stdio.err.print("--method does not support '{}'\n", method_arg) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    var line_buf = std.Buffer.initSize(allocator, 0) catch |err| return errors.allocErr(stdio.err);
    var data = Data{
        .pokemons = Pokemons.init(allocator),
        .static_mons = StaticMons.init(allocator),
    };

    while (util.readLine(&stdin, &line_buf) catch |err| return errors.readErr(stdio.err, "<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&data, str) catch |err| switch (err) {
            error.OutOfMemory => return errors.allocErr(stdio.err),
            error.Overflow,
            error.EndOfString,
            error.InvalidCharacter,
            error.InvalidField,
            => true,
        };
        if (print_line)
            stdio.out.print("{}\n", str) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

        line_buf.shrink(0);
    }

    randomize(data, seed, method, types) catch |err| return errors.randErr(stdio.err, err);

    var static_it = data.static_mons.iterator();
    while (static_it.next()) |static_kv| {
        const static_i = static_kv.key;
        const static = static_kv.value;
        stdio.out.print(".static_pokemons[{}].species={}\n", static_i, static) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
    }
    return 0;
}

fn parseLine(data: *Data, str: []const u8) !bool {
    const allocator = data.pokemons.allocator;
    var parser = format.Parser{ .str = str };

    if (parser.eatField("pokemons")) |_| {
        const poke_index = try parser.eatIndex();
        const poke_entry = try data.pokemons.getOrPutValue(poke_index, Pokemon.init(allocator));
        const pokemon = &poke_entry.value;

        if (parser.eatField("stats")) |_| {
            if (parser.eatField("hp")) |_| {
                pokemon.stats[0] = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("attack")) |_| {
                pokemon.stats[1] = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("defense")) |_| {
                pokemon.stats[2] = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("speed")) |_| {
                pokemon.stats[3] = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_attack")) |_| {
                pokemon.stats[4] = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_defense")) |_| {
                pokemon.stats[5] = try parser.eatUnsignedValue(u8, 10);
            } else |_| {}
        } else |_| if (parser.eatField("types")) |_| {
            _ = try parser.eatIndex();

            // To keep it simple, we just leak a shit ton of type names here.
            const type_name = try mem.dupe(allocator, u8, try parser.eatValue());
            try pokemon.types.append(type_name);
        } else |_| if (parser.eatField("growth_rate")) |_| {
            const rate = try parser.eatValue();
            pokemon.growth_rate = try mem.dupe(allocator, u8, rate);
        } else |_| if (parser.eatField("catch_rate")) |_| {
            pokemon.catch_rate = try parser.eatUnsignedValue(usize, 10);
        } else |_| if (parser.eatField("gender_ratio")) |_| {
            pokemon.gender_ratio = try parser.eatUnsignedValue(usize, 10);
        } else |_| if (parser.eatField("egg_groups")) |_| {
            // TODO: Should we save both egg groups?
            if ((try parser.eatIndex()) == 0) {
                const group = try parser.eatValue();
                pokemon.egg_group = try mem.dupe(allocator, u8, group);
            }
        } else |_| if (parser.eatField("evos")) |_| {
            _ = try parser.eatIndex();
            _ = try parser.eatField("target");
            try pokemon.evos.append(try parser.eatUnsignedValue(usize, 10));
        } else |_| {}
    } else |_| if (parser.eatField("static_pokemons")) |_| {
        const index = try parser.eatIndex();
        _ = try parser.eatField("species");
        _ = try data.static_mons.put(index, try parser.eatUnsignedValue(usize, 10));
        return false;
    } else |_| {}

    return true;
}

fn randomize(data: Data, seed: u64, method: Method, _type: Type) !void {
    const allocator = data.pokemons.allocator;
    var random_adapt = rand.DefaultPrng.init(seed);
    const random = &random_adapt.random;

    switch (method) {
        .random => switch (_type) {
            .random => {
                var pokemons = std.ArrayList(usize).init(allocator);
                var p_it = data.pokemons.iterator();
                while (p_it.next()) |kv|
                    try pokemons.append(kv.key);

                if (pokemons.len == 0)
                    return;

                var s_it = data.static_mons.iterator();
                while (s_it.next()) |kv|
                    kv.value = pokemons.toSlice()[random.range(usize, 0, pokemons.len)];
            },
            .same => {
                const by_type = try data.pokemonsByType();
                var s_it = data.static_mons.iterator();
                while (s_it.next()) |kv| {
                    const pokemon = data.pokemons.get(kv.value).?.value;
                    if (pokemon.types.len == 0)
                        continue;

                    const t = pokemon.types.toSlice()[random.range(usize, 0, pokemon.types.len)];
                    const pokemons = by_type.get(t).?.value.toSlice();
                    kv.value = pokemons[random.range(usize, 0, pokemons.len)];
                }
            },
        },
        .@"same-stats", .@"simular-stats" => {
            const by_type = switch (_type) {
                // When we do random, we should never actually touch the 'by_type'
                // table, so let's just avoid doing the work of constructing it :)
                .random => undefined,
                .same => try data.pokemonsByType(),
            };

            var simular = std.ArrayList(usize).init(allocator);
            var pokemons = std.ArrayList(usize).init(allocator);
            var p_it = data.pokemons.iterator();
            while (p_it.next()) |kv|
                try pokemons.append(kv.key);

            var s_it = data.static_mons.iterator();
            while (s_it.next()) |kv| {
                defer simular.resize(0) catch unreachable;

                const prev_pokemon = (data.pokemons.get(kv.value) orelse continue).value;

                var min = @intCast(i64, sum(u8, prev_pokemon.stats));
                var max = min;

                // For same-stats, we can just make this loop run once, which will
                // make the simular list only contain pokemons with the same stats.
                const condition = if (method == .@"simular-stats") usize(25) else usize(1);
                while (simular.len < condition) : ({
                    min -= 5;
                    max += 5;
                }) {
                    switch (_type) {
                        .random => for (pokemons.toSlice()) |s| {
                            const pokemon = data.pokemons.get(s).?.value;

                            const total = @intCast(i64, sum(u8, pokemon.stats));
                            if (min <= total and total <= max)
                                try simular.append(s);
                        },
                        .same => {
                            // If this Pokémon has no type (for some reason), then we
                            // cannot pick a pokemon of the same type. The only thing
                            // we can assume is that the Pokémon is the same type
                            // as it self, and therefor just use that as the simular
                            // Pokémon.
                            if (prev_pokemon.types.len == 0) {
                                try simular.append(kv.value);
                                break;
                            }
                            for (prev_pokemon.types.toSlice()) |t| {
                                const pokemons_of_type = by_type.get(t).?.value;

                                for (pokemons_of_type.toSlice()) |s| {
                                    const pokemon = data.pokemons.get(s).?.value;

                                    const total = @intCast(i64, sum(u8, pokemon.stats));
                                    if (min <= total and total <= max)
                                        try simular.append(s);
                                }
                            }
                        },
                    }
                }

                const pick_from = simular.toSlice();
                kv.value = pick_from[random.range(usize, 0, pick_from.len)];
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
            //var legendaries = std.ArrayList(usize).init(allocator);
            //var rest = std.ArrayList(usize).init(allocator);
            //var rating_to_be_legendary: i8 = 0;
            //
            //var p_it = data.pokemons.iterator();
            //while (p_it.next()) |kv|
            //    rating_to_be_legendary = math.max(rating_to_be_legendary, kv.value.legendary_rating);
            //
            //rating_to_be_legendary -= 1; // Some legendaries don't match in one area, so let's still accept those
            //p_it = data.pokemons.iterator();
            //while (p_it.next()) |kv| {
            //    if (kv.value.legendary_rating >= rating_to_be_legendary) {
            //        try legendaries.append(kv.key);
            //    } else {
            //        try rest.append(kv.key);
            //    }
            //}
            //
            //var s_it = data.static_mons.iterator();
            //while (s_it.next()) |kv| {
            //    const pokemon = data.pokemons.get(kv.value).?.value;
            //    const pick_from = if (pokemon.legendary_rating >= rating_to_be_legendary) legendaries else rest;
            //    if (pick_from.len == 0)
            //        continue;
            //
            //    switch (_type) {
            //        .random => kv.value = rest.toSlice()[random.range(usize, 0, rest.len)],
            //        .same => unreachable, // TODO: Implement
            //    }
            //}
            unreachable; // TODO: Implement
        },
    }
}

fn SumReturn(comptime T: type) type {
    return switch (@typeId(T)) {
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

const PokemonByType = std.StringHashMap(std.ArrayList(usize));
const Pokemons = std.AutoHashMap(usize, Pokemon);
const StaticMons = std.AutoHashMap(usize, usize);

const Data = struct {
    pokemons: Pokemons,
    static_mons: StaticMons,

    fn pokemonsByType(d: Data) !PokemonByType {
        var res = PokemonByType.init(d.allocator());
        var p_it = d.pokemons.iterator();
        while (p_it.next()) |kv| {
            const species = kv.key;
            const pokemon = kv.value;

            for (pokemon.types.toSlice()) |t| {
                const entry = try res.getOrPut(t);
                if (!entry.found_existing)
                    entry.kv.value = std.ArrayList(usize).init(d.allocator());

                try entry.kv.value.append(species);
            }
        }

        return res;
    }

    fn allocator(d: Data) *mem.Allocator {
        return d.pokemons.allocator;
    }
};

const Pokemon = struct {
    stats: [6]u8,
    types: std.ArrayList([]const u8),
    growth_rate: ?[]const u8, // legendaries are "Slow" or "MediumSlow"
    catch_rate: ?usize, // Legendaries are <= 45
    gender_ratio: ?usize, //  Legendaries are == 255
    egg_group: ?[]const u8, // legendaries are "Undiscovered"
    evos: std.ArrayList(usize), // legendaries have no evos, and are not

    fn init(allocator: *mem.Allocator) Pokemon {
        return Pokemon{
            .stats = [_]u8{0} ** 6,
            .types = std.ArrayList([]const u8).init(allocator),
            .growth_rate = null,
            .catch_rate = null,
            .gender_ratio = null,
            .egg_group = null,
            .evos = std.ArrayList(usize).init(allocator),
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
                ".pokemons[" ++ id ++ "].egg_groups=" ++ egg_groups ++ "\n" ++
                if (evo) |e| ".pokemons[" ++ id ++ "].evos[0]=" ++ e ++ "\n" else "";
        }
        fn static(
            comptime id: []const u8,
            comptime species: []const u8,
        ) []const u8 {
            return ".static_pokemons[" ++ id ++ "].species=" ++ species ++ "\n";
        }
    };

    const legendaries = comptime H.pokemon("0", "10", "Ice", "Flying", "Slow", "3", "255", "Undiscovered", null) ++
        H.pokemon("1", "10", "Electric", "Flying", "Slow", "3", "255", "Undiscovered", null) ++
        H.pokemon("2", "10", "Fire", "Flying", "Slow", "3", "255", "Undiscovered", null) ++
        H.pokemon("3", "10", "Electric", "Electric", "Slow", "3", "255", "Undiscovered", null) ++
        H.pokemon("4", "11", "Water", "Water", "Slow", "3", "255", "Undiscovered", null) ++
        H.pokemon("5", "11", "Rock", "Rock", "Slow", "3", "255", "Undiscovered", null) ++
        H.pokemon("6", "11", "Ice", "Ice", "Slow", "3", "255", "Undiscovered", null) ++
        H.pokemon("7", "12", "Dragon", "Psychic", "Slow", "3", "254", "Undiscovered", null) ++
        H.pokemon("8", "12", "Dragon", "Psychic", "Slow", "3", "0", "Undiscovered", null) ++
        H.pokemon("9", "12", "Water", "Water", "Slow", "3", "255", "Water1", null);

    const pseudo_legendaries = comptime H.pokemon("10", "10", "Dragon", "Dragon", "Slow", "45", "127", "Water1", "11") ++
        H.pokemon("11", "10", "Dragon", "Flying", "Slow", "45", "127", "Water1", null) ++
        H.pokemon("12", "10", "Rock", "Ground", "Slow", "45", "127", "Monster", "13") ++
        H.pokemon("13", "10", "Rock", "Dark", "Slow", "45", "127", "Monster", null) ++
        H.pokemon("14", "11", "Dragon", "Dragon", "Slow", "45", "127", "Dragon", "15") ++
        H.pokemon("15", "11", "Dragon", "Flying2", "Slow", "45", "127", "Dragon", null) ++
        H.pokemon("16", "11", "Steel", "Psychic", "Slow", "3", "255", "Mineral", "17") ++
        H.pokemon("17", "11", "Steel", "Psychic", "Slow", "3", "255", "Mineral", null) ++
        H.pokemon("18", "12", "Dragon", "Ground", "Slow", "45", "127", "Monster", "19") ++
        H.pokemon("19", "12", "Dragon", "Ground", "Slow", "45", "127", "Monster", null) ++
        H.pokemon("20", "12", "Dark", "Dragon", "Slow", "45", "127", "Dragon", "21") ++
        H.pokemon("21", "12", "Dark", "Dragon", "Slow", "45", "127", "Dragon", null);

    const result_prefix = legendaries ++ pseudo_legendaries;
    const test_string = comptime result_prefix ++
        H.static("0", "0") ++
        H.static("1", "1") ++
        H.static("2", "2") ++
        H.static("3", "3") ++
        H.static("4", "4") ++
        H.static("5", "21");

    testProgram([_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.static_pokemons[4].species=20
        \\.static_pokemons[5].species=9
        \\.static_pokemons[3].species=18
        \\.static_pokemons[1].species=1
        \\.static_pokemons[2].species=12
        \\.static_pokemons[0].species=15
        \\
    );
    testProgram([_][]const u8{ "--seed=0", "--types=same" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=9
        \\.static_pokemons[5].species=20
        \\.static_pokemons[3].species=1
        \\.static_pokemons[1].species=1
        \\.static_pokemons[2].species=0
        \\.static_pokemons[0].species=0
        \\
    );
    testProgram([_][]const u8{ "--seed=1", "--method=same-stats" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=4
        \\.static_pokemons[5].species=7
        \\.static_pokemons[3].species=3
        \\.static_pokemons[1].species=2
        \\.static_pokemons[2].species=3
        \\.static_pokemons[0].species=12
        \\
    );
    testProgram([_][]const u8{ "--seed=1", "--method=same-stats", "--types=same" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=4
        \\.static_pokemons[5].species=7
        \\.static_pokemons[3].species=3
        \\.static_pokemons[1].species=1
        \\.static_pokemons[2].species=2
        \\.static_pokemons[0].species=1
        \\
    );
    testProgram([_][]const u8{ "--seed=2", "--method=simular-stats" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=15
        \\.static_pokemons[5].species=4
        \\.static_pokemons[3].species=11
        \\.static_pokemons[1].species=6
        \\.static_pokemons[2].species=0
        \\.static_pokemons[0].species=11
        \\
    );
    testProgram([_][]const u8{ "--seed=2", "--method=simular-stats", "--types=same" }, test_string, result_prefix ++
        \\.static_pokemons[4].species=4
        \\.static_pokemons[5].species=20
        \\.static_pokemons[3].species=3
        \\.static_pokemons[1].species=1
        \\.static_pokemons[2].species=2
        \\.static_pokemons[0].species=0
        \\
    );
    //testProgram([_][]const u8{ "--seed=3", "--method=legendary-with-legendary" }, test_string, result_prefix ++
    //    \\.static_pokemons[4].species=15
    //    \\.static_pokemons[5].species=4
    //    \\.static_pokemons[3].species=11
    //    \\.static_pokemons[1].species=6
    //    \\.static_pokemons[2].species=0
    //    \\.static_pokemons[0].species=11
    //    \\
    //);
}

fn testProgram(
    args: []const []const u8,
    in: []const u8,
    out: []const u8,
) void {
    var alloc_buf: [1024 * 50]u8 = undefined;
    var out_buf: [1024 * 10]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&alloc_buf);
    var stdin = io.SliceInStream.init(in);
    var stdout = io.SliceOutStream.init(&out_buf);
    var stderr = io.SliceOutStream.init(&err_buf);
    var arg_iter = clap.args.SliceIterator{ .args = args };

    const StdIo = util.CustomStdIoStreams(anyerror, anyerror);

    const res = main2(
        &fba.allocator,
        anyerror,
        anyerror,
        StdIo{
            .in = @ptrCast(*io.InStream(anyerror), &stdin.stream),
            .out = @ptrCast(*io.OutStream(anyerror), &stdout.stream),
            .err = @ptrCast(*io.OutStream(anyerror), &stderr.stream),
        },
        clap.args.SliceIterator,
        &arg_iter,
    );
    debug.warn("{}", stderr.getWritten());
    testing.expectEqual(u8(0), res);
    testing.expectEqualSlices(u8, "", stderr.getWritten());
    if (!mem.eql(u8, out, stdout.getWritten())) {
        debug.warn("\n====== expected this output: =========\n");
        debug.warn("{}", out);
        debug.warn("\n======== instead found this: =========\n");
        debug.warn("{}", stdout.getWritten());
        debug.warn("\n======================================\n");
        testing.expect(false);
    }
    testing.expectEqualSlices(u8, out, stdout.getWritten());
}