const clap = @import("clap");
const common = @import("tm35-common");
const fun = @import("fun");
const gba = @import("gba.zig");
const gen5 = @import("gen5-types.zig");
const nds = @import("nds.zig");
const std = @import("std");
const builtin = @import("builtin");
const format = @import("format");

const bits = fun.bits;
const debug = std.debug;
const heap = std.heap;
const io = std.io;
const fs = std.fs;
const math = std.math;
const mem = std.mem;
const fmt = std.fmt;
const os = std.os;
const rand = std.rand;
const slice = fun.generic.slice;

const BufInStream = io.BufferedInStream(fs.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);
const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = [_]Param{
    Param{
        .id = "display this help text and exit",
        .names = Names{ .short = 'h', .long = "help" },
    },
    Param{
        .id = "ensure, that after randomizing the stats, the total stats are the same",
        .names = Names{ .short = 't', .long = "same-total-stats" },
    },
    Param{
        .id = "randomized stats should follow the evolution line",
        .names = Names{ .short = 'f', .long = "follow-evos" },
    },
    Param{
        .id = "the seed used to randomize stats",
        .names = Names{ .short = 's', .long = "seed" },
        .takes_value = true,
    },
    Param{
        .id = "",
        .takes_value = true,
    },
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

pub fn main() !void {
    const unbuf_stdout = &(try io.getStdOut()).outStream().stream;
    var buf_stdout = BufOutStream.init(unbuf_stdout);
    defer buf_stdout.flush() catch {};

    const stderr = &(try io.getStdErr()).outStream().stream;
    const stdin = &BufInStream.init(&(try std.io.getStdIn()).inStream().stream).stream;
    const stdout = &buf_stdout.stream;

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    _ = try arg_iter.next();

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const same_total_stats = args.flag("--same-total-stats");
    const follow_evos = args.flag("--follow-evos");
    const seed = blk: {
        const seed_str = args.option("--seed") orelse {
            var buf: [8]u8 = undefined;
            try std.os.getrandom(buf[0..]);
            break :blk mem.readInt(u64, &buf, builtin.Endian.Little);
        };

        break :blk try fmt.parseUnsigned(u64, seed_str, 10);
    };

    const pokemons = try readPokemons(allocator, stdin, stdout);
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
        const print_line = parseLine(&res, str) catch |err| true;
        if (print_line)
            try out_stream.print("{}\n", str);

        line_buf.shrink(0);
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }

    return res;
}

fn parseLine(pokemons: *PokemonMap, str: []const u8) !bool {
    var parser = format.StrParser.init(str);

    try parser.eatField("pokemons");
    const pokemon_index = try parser.eatIndex();

    if (parser.eatField("stats")) |_| {
        const entry = try pokemons.getOrPutValue(pokemon_index, Pokemon.init(pokemons.allocator));
        const pokemon = &entry.value;

        if (parser.eatField("hp")) |_| {
            pokemon.hp = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("attack")) |_| {
            pokemon.attack = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("defense")) |_| {
            pokemon.defense = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("speed")) |_| {
            pokemon.speed = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("sp_attack")) |_| {
            pokemon.sp_attack = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("sp_defense")) |_| {
            pokemon.sp_defense = try parser.eatUnsignedValue(u8, 10);
        } else |_| {
            return true;
        }

        return false;
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
    var stats = [_]u64{0} ** Pokemon.stats.len;
    var stats_count = [_]u64{0} ** Pokemon.stats.len;
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

    const stats = [_][]const u8{
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
