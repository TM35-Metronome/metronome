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
        clap.parseParam("-f, --follow-evos       Evolution will use the none evolved form as a base for its own stats.                     ") catch unreachable,
        clap.parseParam("-h, --help              Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-s, --seed <NUM>        The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-t, --same-total-stats  Pokémons will have the same total stats after randomization.                              ") catch unreachable,
        clap.parseParam("-v, --version           Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-rand-stats ");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Randomizes Pokémon stats.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

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

    const same_total_stats = args.flag("--same-total-stats");
    const follow_evos = args.flag("--follow-evos");

    var line_buf = std.ArrayList(u8).init(allocator);
    var pokemons = PokemonMap.init(allocator);

    while (util.readLine(&stdin, &line_buf) catch |err| return errors.readErr(stdio.err, "<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&pokemons, str) catch |err| switch (err) {
            error.OutOfMemory => return errors.allocErr(stdio.err),
            error.ParseError => true,
        };
        if (print_line)
            stdio.out.print("{}\n", .{str}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

        line_buf.resize(0) catch unreachable;
    }

    randomize(pokemons, seed, same_total_stats, follow_evos);

    var iter = pokemons.iterator();
    while (iter.next()) |kv| {
        inline for (@typeInfo(Pokemon.Stat).Enum.fields) |stat| {
            const stat_i = @enumToInt(@field(Pokemon.Stat, stat.name));
            if (kv.value.output[stat_i]) {
                stdio.out.print(".pokemons[{}].stats.{}={}\n", .{ kv.key, stat.name, kv.value.stats[stat_i] }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            }
        }
    }
    return 0;
}

fn parseLine(pokemons: *PokemonMap, str: []const u8) !bool {
    const sw = util.parse.Swhash(8);
    const m = sw.match;
    const c = sw.case;
    const allocator = pokemons.allocator;
    var p = parse.MutParser{ .str = str };

    try p.parse(comptime parse.field("pokemons"));
    const index = try p.parse(parse.index);
    switch (m(try p.parse(parse.anyField))) {
        c("stats") => {
            const entry = try pokemons.getOrPutValue(index, Pokemon{});
            const pokemon = &entry.value;

            inline for (@typeInfo(Pokemon.Stat).Enum.fields) |stat| {
                const i = @enumToInt(@field(Pokemon.Stat, stat.name));
                if (p.parse(comptime parse.field(stat.name))) |_| {
                    pokemon.stats[i] = try p.parse(parse.u8v);
                    pokemon.output[i] = true;
                    return false;
                } else |_| {}
            }
        },
        c("evos") => {
            _ = try p.parse(parse.index);
            _ = try p.parse(comptime parse.field("target"));
            const evo_from_i = try p.parse(parse.usizev);

            const evo_entry = try pokemons.getOrPutValue(evo_from_i, Pokemon{});
            const evo_from = &evo_entry.value;
            _ = try evo_from.evolves_from.put(allocator, index);
        },
        else => return true,
    }

    return true;
}

fn randomize(pokemons: PokemonMap, seed: u64, same_total_stats: bool, follow_evos: bool) void {
    var random = rand.DefaultPrng.init(seed);
    var iter = pokemons.iterator();
    while (iter.next()) |kv| {
        const pokemon = &kv.value;
        const old_total = sum(u8, &pokemon.stats);
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
    if (pokemon.evolves_from.count() == 0)
        return;

    // Get the average stats of all the prevolutions
    var stats = [_]u64{0} ** Pokemon.stats;
    for (pokemon.evolves_from.span()) |range| {
        var prevolution = range.start;
        while (prevolution <= range.end) : (prevolution += 1) {
            // If prevolution == curr, then we have a cycle.
            if (prevolution == curr)
                continue;

            // TODO: Can this ever happen???
            //                                         VVVVVVVV
            const p = pokemons.get(prevolution) orelse continue;

            // We should randomize prevolution by the same rules.
            randomizeFromChildren(random, pokemons, &p.value, same_total_stats, curr);
            for (p.value.stats) |stat, i|
                stats[i] += stat;
        }
    }

    // Average calculated here
    var average = [_]u8{0} ** Pokemon.stats;
    for (average) |*stat, i| {
        stat.* = math.cast(u8, stats[i] / math.max(pokemon.evolves_from.count(), 1)) catch math.maxInt(u8);
    }

    const old_total = sum(u8, &pokemon.stats);
    const average_total = sum(u8, &average);
    const new_random_total = random.intRangeAtMost(u64, average_total, stats.len * math.maxInt(u8));
    const new_total = if (same_total_stats) old_total else new_random_total;

    pokemon.stats = average;
    randomUntilSum(random, u8, &pokemon.stats, new_total);

    // After this, the Pokémons stats should be equal or above the average
    for (average) |_, i|
        debug.assert(average[i] <= pokemon.stats[i]);
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

const PokemonMap = std.AutoHashMap(usize, Pokemon);
const Evos = util.container.IntSet.Unmanaged(usize);

const Pokemon = struct {
    stats: [stats]u8 = [_]u8{0} ** stats,
    output: [stats]bool = [_]bool{false} ** stats,
    evolves_from: Evos = Evos{},

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

test "tm35-rand-stats" {
    const result_prefix =
        \\.pokemons[0].evos[0].target=1
        \\.pokemons[1].evos[0].target=2
        \\
    ;

    const test_string = result_prefix ++
        \\.pokemons[0].stats.hp=10
        \\.pokemons[0].stats.attack=10
        \\.pokemons[0].stats.defense=10
        \\.pokemons[0].stats.speed=10
        \\.pokemons[0].stats.sp_attack=10
        \\.pokemons[0].stats.sp_defense=10
        \\.pokemons[1].stats.hp=20
        \\.pokemons[1].stats.attack=20
        \\.pokemons[1].stats.defense=20
        \\.pokemons[1].stats.speed=20
        \\.pokemons[1].stats.sp_attack=20
        \\.pokemons[1].stats.sp_defense=20
        \\.pokemons[2].stats.hp=30
        \\.pokemons[2].stats.attack=30
        \\.pokemons[2].stats.defense=30
        \\.pokemons[2].stats.speed=30
        \\.pokemons[2].stats.sp_attack=30
        \\.pokemons[2].stats.sp_defense=30
        \\.pokemons[3].stats.hp=40
        \\.pokemons[3].stats.attack=40
        \\.pokemons[3].stats.defense=40
        \\.pokemons[3].stats.speed=40
        \\.pokemons[3].stats.sp_attack=40
        \\.pokemons[3].stats.sp_defense=40
        \\
    ;
    util.testing.testProgram(main2, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.pokemons[3].stats.hp=89
        \\.pokemons[3].stats.attack=18
        \\.pokemons[3].stats.defense=76
        \\.pokemons[3].stats.speed=117
        \\.pokemons[3].stats.sp_attack=63
        \\.pokemons[3].stats.sp_defense=119
        \\.pokemons[1].stats.hp=208
        \\.pokemons[1].stats.attack=169
        \\.pokemons[1].stats.defense=255
        \\.pokemons[1].stats.speed=215
        \\.pokemons[1].stats.sp_attack=62
        \\.pokemons[1].stats.sp_defense=255
        \\.pokemons[2].stats.hp=99
        \\.pokemons[2].stats.attack=195
        \\.pokemons[2].stats.defense=196
        \\.pokemons[2].stats.speed=105
        \\.pokemons[2].stats.sp_attack=175
        \\.pokemons[2].stats.sp_defense=150
        \\.pokemons[0].stats.hp=80
        \\.pokemons[0].stats.attack=4
        \\.pokemons[0].stats.defense=115
        \\.pokemons[0].stats.speed=34
        \\.pokemons[0].stats.sp_attack=82
        \\.pokemons[0].stats.sp_defense=67
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--follow-evos" }, test_string, result_prefix ++
        \\.pokemons[3].stats.hp=89
        \\.pokemons[3].stats.attack=18
        \\.pokemons[3].stats.defense=76
        \\.pokemons[3].stats.speed=117
        \\.pokemons[3].stats.sp_attack=63
        \\.pokemons[3].stats.sp_defense=119
        \\.pokemons[1].stats.hp=255
        \\.pokemons[1].stats.attack=255
        \\.pokemons[1].stats.defense=178
        \\.pokemons[1].stats.speed=255
        \\.pokemons[1].stats.sp_attack=255
        \\.pokemons[1].stats.sp_defense=255
        \\.pokemons[2].stats.hp=255
        \\.pokemons[2].stats.attack=255
        \\.pokemons[2].stats.defense=222
        \\.pokemons[2].stats.speed=255
        \\.pokemons[2].stats.sp_attack=255
        \\.pokemons[2].stats.sp_defense=255
        \\.pokemons[0].stats.hp=80
        \\.pokemons[0].stats.attack=4
        \\.pokemons[0].stats.defense=115
        \\.pokemons[0].stats.speed=34
        \\.pokemons[0].stats.sp_attack=82
        \\.pokemons[0].stats.sp_defense=67
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--same-total-stats" }, test_string, result_prefix ++
        \\.pokemons[3].stats.hp=44
        \\.pokemons[3].stats.attack=9
        \\.pokemons[3].stats.defense=37
        \\.pokemons[3].stats.speed=58
        \\.pokemons[3].stats.sp_attack=33
        \\.pokemons[3].stats.sp_defense=59
        \\.pokemons[1].stats.hp=11
        \\.pokemons[1].stats.attack=23
        \\.pokemons[1].stats.defense=17
        \\.pokemons[1].stats.speed=2
        \\.pokemons[1].stats.sp_attack=31
        \\.pokemons[1].stats.sp_defense=36
        \\.pokemons[2].stats.hp=0
        \\.pokemons[2].stats.attack=22
        \\.pokemons[2].stats.defense=49
        \\.pokemons[2].stats.speed=53
        \\.pokemons[2].stats.sp_attack=26
        \\.pokemons[2].stats.sp_defense=30
        \\.pokemons[0].stats.hp=3
        \\.pokemons[0].stats.attack=2
        \\.pokemons[0].stats.defense=13
        \\.pokemons[0].stats.speed=8
        \\.pokemons[0].stats.sp_attack=21
        \\.pokemons[0].stats.sp_defense=13
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--same-total-stats", "--follow-evos" }, test_string, result_prefix ++
        \\.pokemons[3].stats.hp=44
        \\.pokemons[3].stats.attack=9
        \\.pokemons[3].stats.defense=37
        \\.pokemons[3].stats.speed=58
        \\.pokemons[3].stats.sp_attack=33
        \\.pokemons[3].stats.sp_defense=59
        \\.pokemons[1].stats.hp=11
        \\.pokemons[1].stats.attack=13
        \\.pokemons[1].stats.defense=15
        \\.pokemons[1].stats.speed=22
        \\.pokemons[1].stats.sp_attack=38
        \\.pokemons[1].stats.sp_defense=21
        \\.pokemons[2].stats.hp=15
        \\.pokemons[2].stats.attack=24
        \\.pokemons[2].stats.defense=16
        \\.pokemons[2].stats.speed=31
        \\.pokemons[2].stats.sp_attack=60
        \\.pokemons[2].stats.sp_defense=34
        \\.pokemons[0].stats.hp=3
        \\.pokemons[0].stats.attack=2
        \\.pokemons[0].stats.defense=13
        \\.pokemons[0].stats.speed=8
        \\.pokemons[0].stats.sp_attack=21
        \\.pokemons[0].stats.sp_defense=13
        \\
    );
}
