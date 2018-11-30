const builtin = @import("builtin");
const clap = @import("zig-clap");
const format = @import("tm35-format");
const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;

const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = []Param{
    Param.flag(
        "display this help text and exit",
        Names.both("help"),
    ),
    Param.flag(
        "ensure, that after randomizing the stats, the total stats are the same",
        Names.long("same-total-stats"),
    ),
    Param.flag(
        "randomized stats should follow the evolution line",
        Names.long("follow-evos"),
    ),
    Param.option(
        "the seed used to randomize stats",
        Names.both("seed"),
    ),
    Param.positional(""),
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-stats [OPTION]...
        \\Reads the tm35 format from stdin and randomizes the stats of pokemons.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    const stdin_file = std.io.getStdIn() catch return 1;
    const stderr_file = std.io.getStdErr() catch return 1;
    const stdout_file = std.io.getStdOut() catch return 1;
    var stdin_stream = stdin_file.inStream();
    var stderr_stream = stderr_file.outStream();
    var stdout_stream = stdout_file.outStream();
    var buf_stdin = io.BufferedInStream(os.File.InStream.Error).init(&stdin_stream.stream);
    var buf_stdout = io.BufferedOutStream(os.File.OutStream.Error).init(&stdout_stream.stream);

    const stdin = &buf_stdin.stream;
    const stdout = &buf_stdout.stream;
    const stderr = &stderr_stream.stream;

    var direct_allocator_state = std.heap.DirectAllocator.init();
    const direct_allocator = &direct_allocator_state.allocator;
    defer direct_allocator_state.deinit();

    // TODO: Other allocator?
    const allocator = direct_allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    const iter = &arg_iter.iter;
    defer arg_iter.deinit();
    _ = iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator.Error, iter) catch |err| {
        debug.warn("error: {}\n", err);
        usage(stderr) catch {};
        return 1;
    };
    defer args.deinit();

    main2(allocator, args, stdin, stdout, stderr) catch |err| {
        debug.warn("error: {}\n", err);
        return 1;
    };

    buf_stdout.flush() catch |err| {
        debug.warn("error: {}\n", err);
        return 1;
    };

    return 0;
}

pub fn main2(allocator: *mem.Allocator, args: Clap, stdin: var, stdout: var, stderr: var) !void {
    if (args.flag("--help"))
        return try usage(stdout);

    const same_total_stats = args.flag("--same-total-stats");
    const follow_evos = args.flag("--follow-evos");
    const seed = blk: {
        const seed_str = args.option("--seed") orelse {
            var buf: [8]u8 = undefined;
            try std.os.getRandomBytes(buf[0..]);
            break :blk mem.readInt(buf[0..8], u64, builtin.Endian.Little);
        };

        break :blk try fmt.parseUnsigned(u64, seed_str, 10);
    };

    var arena = heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const pokemons = try readPokemons(&arena.allocator, stdin, stdout);
    randomize(pokemons, seed, same_total_stats, follow_evos);

    var iter = pokemons.iterator();
    while (iter.next()) |kv| {
        inline for (Pokemon.stats) |stat| {
            if (@field(kv.value, stat)) |s|
                try stdout.print(".pokemons[{}].stats.{}={}\n", kv.key, stat, s);
        }
    }
}

fn readPokemons(allocator: *mem.Allocator, in_stream: var, out_stream: var) !PokemonMap {
    var res = PokemonMap.init(allocator);
    var line_buf = try std.Buffer.initSize(allocator, 0);
    defer line_buf.deinit();

    var line: usize = 1;
    while (in_stream.readUntilDelimiterBuffer(&line_buf, '\n', 10000)) : (line += 1) {
        const str = mem.trimRight(u8, line_buf.toSlice(), "\r\n");
        const print_line = parseLine(&res, str) catch true;
        if (print_line)
            try out_stream.print("{}\n", str);

        line_buf.shrink(0);
    } else |err| switch (err) {
        error.EndOfStream => {
            const str = mem.trimRight(u8, line_buf.toSlice(), "\r\n");
            const print_line = parseLine(&res, str) catch true;
            if (print_line)
                try out_stream.print("{}\n", str);
        },
        else => return err,
    }

    return res;
}

fn parseLine(pokemoms: *PokemonMap, str: []const u8) !bool {
    @setEvalBranchQuota(100000);

    const m = format.Matcher([][]const u8{
        ".pokemons[*].stats.hp",
        ".pokemons[*].stats.attack",
        ".pokemons[*].stats.defense",
        ".pokemons[*].stats.speed",
        ".pokemons[*].stats.sp_attack",
        ".pokemons[*].stats.sp_defense",
        ".pokemons[*].evos[*].target",
    });

    const match = try m.match(str);
    return switch (match.case) {
        m.case(".pokemons[*].stats.hp"),
        m.case(".pokemons[*].stats.attack"),
        m.case(".pokemons[*].stats.defense"),
        m.case(".pokemons[*].stats.speed"),
        m.case(".pokemons[*].stats.sp_attack"),
        m.case(".pokemons[*].stats.sp_defense"),
        => blk: {
            const value = try fmt.parseUnsigned(u8, mem.trim(u8, match.value.str, "\t "), 10);
            const index = try fmt.parseUnsigned(usize, match.anys[0].str, 10);

            const entry = try pokemoms.getOrPutValue(index, Pokemon.init(pokemoms.allocator));
            const pokemon = &entry.value;

            switch (match.case) {
                m.case(".pokemons[*].stats.hp") => pokemon.hp = value,
                m.case(".pokemons[*].stats.attack") => pokemon.attack = value,
                m.case(".pokemons[*].stats.defense") => pokemon.defense = value,
                m.case(".pokemons[*].stats.speed") => pokemon.speed = value,
                m.case(".pokemons[*].stats.sp_attack") => pokemon.sp_attack = value,
                m.case(".pokemons[*].stats.sp_defense") => pokemon.sp_defense = value,
                else => unreachable,
            }

            break :blk false;
        },
        m.case(".pokemons[*].evos[*].target") => blk: {
            const value = try fmt.parseUnsigned(u8, mem.trim(u8, match.value.str, "\t "), 10);
            const poke_index = try fmt.parseUnsigned(usize, match.anys[0].str, 10);

            const entry = try pokemoms.getOrPutValue(value, Pokemon.init(pokemoms.allocator));
            const pokemon = &entry.value;

            _ = try pokemon.evolves_from.put(poke_index, {});
            break :blk true;
        },
        else => true,
    };
}

fn randomize(pokemons: PokemonMap, seed: u64, same_total_stats: bool, follow_evos: bool) void {
    var random = rand.DefaultPrng.init(seed);
    var iter = pokemons.iterator();
    while (iter.next()) |kv| {
        const pokemon = &kv.value;
        var buf: [Pokemon.stats.len]u8 = undefined;
        const stats = pokemon.toBuf(&buf);

        const old_total = sum(u8, stats);
        const new_random_total = random.random.intRangeAtMost(u64, 0, stats.len * math.maxInt(u8));
        const new_total = if (same_total_stats) old_total else new_random_total;

        _ = randomWithinSum(&random.random, u8, stats, new_total);
        pokemon.fromBuf(stats);
    }

    if (!follow_evos)
        return;

    iter = pokemons.iterator();
    while (iter.next()) |kv| {
        const curr = kv.key;
        const pokemon = &kv.value;
        randomizeFromChildren(&random.random, pokemons, pokemon, same_total_stats, curr);
    }
}

fn randomizeFromChildren(
    random: *rand.Random,
    pokemons: PokemonMap,
    pokemon: *Pokemon,
    same_total_stats: bool,
    curr: usize,
) void {
    if (pokemon.evolves_from.size == 0)
        return;

    // Get the average stats of all the prevolutions
    var stats = []u64{0} ** Pokemon.stats.len;
    var stats_count = []u64{0} ** Pokemon.stats.len;
    var iter = pokemon.evolves_from.iterator();

    while (iter.next()) |prevolution| {
        // If prevolution == curr, then we have a cycle.
        if (prevolution.key == curr)
            continue;

        // TODO: Can this ever happen???
        //                                                   VVVVVVVV
        const p = pokemons.get(prevolution.key) orelse continue;

        // We should randomize prevolution by the same rules.
        randomizeFromChildren(random, pokemons, &p.value, same_total_stats, curr);
        inline for (Pokemon.stats) |stat_name, i| {
            if (@field(p.value, stat_name)) |stat| {
                stats[i] += stat;
                stats_count[i] += 1;
            }
        }
    }

    // Average calculated here
    var average: Pokemon = undefined;
    inline for (Pokemon.stats) |stat_name, i| {
        @field(average, stat_name) = if (@field(pokemon, stat_name)) |_|
            math.cast(u8, stats[i] / math.max(stats_count[i], 1)) catch math.maxInt(u8)
        else
            null;
    }

    var buf: [Pokemon.stats.len]u8 = undefined;
    const old_total = sum(u8, pokemon.toBuf(&buf));
    const average_total = sum(u8, average.toBuf(&buf));
    const new_random_total = random.intRangeAtMost(u64, average_total, stats.len * math.maxInt(u8));
    const new_total = if (same_total_stats) old_total else new_random_total;

    const new_stats = randomUntilSum(random, u8, average.toBuf(&buf), new_total);
    pokemon.fromBuf(new_stats);
}

fn randomWithinSum(random: *rand.Random, comptime T: type, buf: []T, s: u64) []T {
    mem.set(T, buf, 0);
    return randomUntilSum(random, T, buf, s);
}

fn randomUntilSum(random: *rand.Random, comptime T: type, buf: []T, s: u64) []T {
    // TODO: In this program, we will never pass buf.len > 6, so we can
    //       statically have this buffer. If this function is to be more
    //       general, we problably have to accept an allpocator.
    var weight_buf: [10]f32 = undefined;
    const weights: []const f32 = blk: {
        for (buf) |_, i|
            weight_buf[i] = random.float(f32);

        break :blk weight_buf[0..buf.len];
    };

    const curr = sum(T, buf);
    const max = math.min(s, buf.len * math.maxInt(T));
    if (max < curr)
        return buf;

    const missing = max - curr;
    const total_weigth = sum(f32, weights);
    for (buf) |*item, i| {
        const to_add_f = @intToFloat(f64, missing) * (weights[i] / total_weigth);
        const to_add_max = math.min(to_add_f, math.maxInt(u8));
        item.* = math.add(T, item.*, @floatToInt(u8, to_add_max)) catch math.maxInt(T);
    }

    while (sum(T, buf) < max) {
        const index = random.intRangeLessThan(usize, 0, buf.len);
        buf[index] = math.add(T, buf[index], 1) catch buf[index];
    }

    return buf;
}

fn SumReturn(comptime T: type) type {
    return switch (@typeId(T)) {
        builtin.TypeId.Int => u64,
        builtin.TypeId.Float => f64,
        else => unreachable,
    };
}

fn sum(comptime T: type, buf: []const T) SumReturn(T) {
    var res: SumReturn(T) = 0;
    for (buf) |item|
        res += item;

    return res;
}

const PokemonMap = std.AutoHashMap(usize, Pokemon);
const EvoMap = std.AutoHashMap(usize, void);

const Pokemon = struct {
    hp: ?u8,
    attack: ?u8,
    defense: ?u8,
    speed: ?u8,
    sp_attack: ?u8,
    sp_defense: ?u8,
    evolves_from: EvoMap,

    fn init(allocator: *mem.Allocator) Pokemon {
        return Pokemon{
            .hp = null,
            .attack = null,
            .defense = null,
            .speed = null,
            .sp_attack = null,
            .sp_defense = null,
            .evolves_from = EvoMap.init(allocator),
        };
    }

    const stats = [][]const u8{
        "hp",
        "attack",
        "defense",
        "speed",
        "sp_attack",
        "sp_defense",
    };

    fn toBuf(p: Pokemon, buf: *[stats.len]u8) []u8 {
        var i: usize = 0;
        inline for (stats) |stat_name| {
            if (@field(p, stat_name)) |stat| {
                buf[i] = stat;
                i += 1;
            }
        }

        return buf[0..i];
    }

    fn fromBuf(p: *Pokemon, buf: []u8) void {
        var i: usize = 0;
        inline for (stats) |stat_name| {
            if (@field(p, stat_name)) |*stat| {
                stat.* = buf[i];
                i += 1;
            }
        }
    }
};
