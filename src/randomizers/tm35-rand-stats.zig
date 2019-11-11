const clap = @import("clap");
const format = @import("format");
const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;

const BufInStream = io.BufferedInStream(fs.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);

const Clap = clap.ComptimeClap(clap.Help, params);
const Param = clap.Param(clap.Help);

const readLine = @import("readline").readLine;

// TODO: proper versioning
const program_version = "0.0.0";

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-f, --follow-evos       Evolution will use the none evolved form as a base for its own stats.                     ") catch unreachable,
        clap.parseParam("-h, --help              Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-s, --seed <NUM>        The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-t, --same-total-stats  Pokémons will have the same total stats after randomization.                              ") catch unreachable,
        clap.parseParam("-v, --version           Output version information and exit.                                                      ") catch unreachable,
        Param{ .takes_value = true },
    };
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-stats [-fhtv] [-s <NUM>]
        \\Randomizes Pokémon stats.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    const stdin_file = io.getStdIn() catch |err| return errPrint("Could not aquire stdin: {}\n", err);
    const stdout_file = io.getStdOut() catch |err| return errPrint("Could not aquire stdout: {}\n", err);
    const stderr_file = io.getStdErr() catch |err| return errPrint("Could not aquire stderr: {}\n", err);

    const stdin = &BufInStream.init(&stdin_file.inStream().stream);
    const stdout = &BufOutStream.init(&stdout_file.outStream().stream);
    const stderr = &stderr_file.outStream().stream;

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        debug.warn("{}\n", err);
        usage(stderr) catch |err2| return failedWriteError("<stderr>", err2);
        return 1;
    };

    if (args.flag("--help")) {
        usage(&stdout.stream) catch |err| return failedWriteError("<stdout>", err);
        stdout.flush() catch |err| return failedWriteError("<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdout.stream.print("{}\n", program_version) catch |err| return failedWriteError("<stdout>", err);
        stdout.flush() catch |err| return failedWriteError("<stdout>", err);
        return 0;
    }

    const seed = if (args.option("--seed")) |seed|
        fmt.parseUnsigned(u64, seed, 10) catch |err| {
            debug.warn("'{}' could not be parsed as a number to --seed: {}\n", seed, err);
            usage(stderr) catch |err2| return failedWriteError("<stderr>", err2);
            return 1;
        }
    else blk: {
        var buf: [8]u8 = undefined;
        os.getrandom(buf[0..]) catch break :blk u64(0);
        break :blk mem.readInt(u64, &buf, .Little);
    };

    const same_total_stats = args.flag("--same-total-stats");
    const follow_evos = args.flag("--follow-evos");

    var line_buf = std.Buffer.initSize(allocator, 0) catch |err| return errPrint("Allocation failed: {}", err);
    var pokemons = PokemonMap.init(allocator);

    while (readLine(stdin, &line_buf) catch |err| return failedReadError("<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&pokemons, str) catch true;
        if (print_line)
            stdout.stream.print("{}\n", str) catch |err| return failedWriteError("<stdout>", err);

        line_buf.shrink(0);
    }
    stdout.flush() catch |err| return failedWriteError("<stdout>", err);

    randomize(pokemons, seed, same_total_stats, follow_evos);

    var iter = pokemons.iterator();
    while (iter.next()) |kv| {
        inline for (@typeInfo(Pokemon.Stat).Enum.fields) |stat| {
            const stat_i = @enumToInt(@field(Pokemon.Stat, stat.name));
            if (kv.value.output[stat_i]) {
                stdout.stream.print(".pokemons[{}].stats.{}={}\n", kv.key, stat.name, kv.value.stats[stat_i]) catch |err| return failedWriteError("<stdout>", err);
            }
        }
    }
    stdout.flush() catch |err| return failedWriteError("<stdout>", err);
    return 0;
}

fn failedWriteError(file: []const u8, err: anyerror) u8 {
    debug.warn("Failed to write data to '{}': {}\n", file, err);
    return 1;
}

fn failedReadError(file: []const u8, err: anyerror) u8 {
    debug.warn("Failed to read data from '{}': {}\n", file, err);
    return 1;
}

fn errPrint(comptime format_str: []const u8, args: ...) u8 {
    debug.warn(format_str, args);
    return 1;
}

fn parseLine(pokemons: *PokemonMap, str: []const u8) !bool {
    var parser = format.Parser{ .str = str };

    try parser.eatField("pokemons");
    const pokemon_index = try parser.eatIndex();

    if (parser.eatField("stats")) |_| {
        const entry = try pokemons.getOrPutValue(pokemon_index, Pokemon.init(pokemons.allocator));
        const pokemon = &entry.value;

        inline for (@typeInfo(Pokemon.Stat).Enum.fields) |stat| {
            const stat_i = @enumToInt(@field(Pokemon.Stat, stat.name));
            if (parser.eatField(stat.name)) |_| {
                pokemon.stats[stat_i] = try parser.eatUnsignedValue(u8, 10);
                pokemon.output[stat_i] = true;
                return false;
            } else |_| {}
        }

        return true;
    } else |_| if (parser.eatField("evos")) |_| {
        _ = try parser.eatIndex();
        try parser.eatField("target");
        const evo_from_i = try parser.eatUnsignedValue(usize, 10);

        const evo_entry = try pokemons.getOrPutValue(evo_from_i, Pokemon.init(pokemons.allocator));
        const evo_from = &evo_entry.value;

        _ = try evo_from.evolves_from.put(pokemon_index, {});
    } else |_| {}

    return true;
}

fn randomize(pokemons: PokemonMap, seed: u64, same_total_stats: bool, follow_evos: bool) void {
    var random = rand.DefaultPrng.init(seed);
    var iter = pokemons.iterator();
    while (iter.next()) |kv| {
        const pokemon = &kv.value;
        const old_total = sum(u8, pokemon.stats);
        const new_random_total = random.random.intRangeAtMost(u64, 0, pokemon.stats.len * math.maxInt(u8));
        const new_total = if (same_total_stats) old_total else new_random_total;

        randomWithinSum(&random.random, u8, &pokemon.stats, new_total);
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
    var stats = [_]u64{0} ** Pokemon.stats;
    var iter = pokemon.evolves_from.iterator();

    while (iter.next()) |prevolution| {
        // If prevolution == curr, then we have a cycle.
        if (prevolution.key == curr)
            continue;

        // TODO: Can this ever happen???
        //                                             VVVVVVVV
        const p = pokemons.get(prevolution.key) orelse continue;

        // We should randomize prevolution by the same rules.
        randomizeFromChildren(random, pokemons, &p.value, same_total_stats, curr);
        for (p.value.stats) |stat, i|
            stats[i] += stat;
    }

    // Average calculated here
    var average = [_]u8{0} ** Pokemon.stats;
    for (average) |*stat, i| {
        stat.* = math.cast(u8, stats[i] / math.max(pokemon.evolves_from.count(), 1)) catch math.maxInt(u8);
    }

    const old_total = sum(u8, pokemon.stats);
    const average_total = sum(u8, average);
    const new_random_total = random.intRangeAtMost(u64, average_total, stats.len * math.maxInt(u8));
    const new_total = if (same_total_stats) old_total else new_random_total;

    randomUntilSum(random, u8, &average, new_total);
    mem.copy(u8, &pokemon.stats, average);
}

fn randomWithinSum(random: *rand.Random, comptime T: type, buf: []T, s: u64) void {
    mem.set(T, buf, 0);
    randomUntilSum(random, T, buf, s);
}

fn randomUntilSum(random: *rand.Random, comptime T: type, buf: []T, s: u64) void {
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
        return;

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

const PokemonMap = std.AutoHashMap(usize, Pokemon);
const EvoMap = std.AutoHashMap(usize, void);

const Pokemon = struct {
    stats: [stats]u8,
    output: [stats]bool,
    evolves_from: EvoMap,

    fn init(allocator: *mem.Allocator) Pokemon {
        return Pokemon{
            .stats = [_]u8{0} ** stats,
            .output = [_]bool{false} ** stats,
            .evolves_from = EvoMap.init(allocator),
        };
    }

    const stats = @typeInfo(Stat).Enum.fields.len;
    const Stat = enum {
        hp = 0,
        attack = 1,
        defense = 2,
        speed = 3,
        sp_attack = 4,
        sp_defense = 5,
    };
};
