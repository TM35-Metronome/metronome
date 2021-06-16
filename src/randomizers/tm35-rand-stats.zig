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
const log = std.log;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-f, --follow-evos       Evolution will use the none evolved form as a base for its own stats.                     ") catch unreachable,
        clap.parseParam("-h, --help              Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-s, --seed <INT>        The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-t, --same-total-stats  Pokémons will have the same total stats after randomization.                              ") catch unreachable,
        clap.parseParam("-v, --version           Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-rand-stats ");
    try clap.usage(writer, &params);
    try writer.writeAll(
        \\
        \\Randomizes Pokémon stats.
        \\
        \\Options:
        \\
    );
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
    const same_total_stats = args.flag("--same-total-stats");
    const follow_evos = args.flag("--follow-evos");

    var pokemons = Pokemons{};
    try format.io(allocator, stdio.in, stdio.out, .{
        .allocator = allocator,
        .pokemons = &pokemons,
    }, useGame);

    randomize(pokemons, seed, same_total_stats, follow_evos);
    try outputData(stdio.out, pokemons);
}

fn outputData(writer: anytype, pokemons: Pokemons) !void {
    for (pokemons.values()) |pokemon, i| {
        const species = pokemons.keys()[i];
        inline for (@typeInfo(format.Stats(u8)).Union.fields) |field, j| {
            if (pokemon.output[j]) {
                try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
                    .stats = ston.field(field.name, pokemon.stats[j]),
                }) });
            }
        }
    }
}

fn useGame(ctx: anytype, parsed: format.Game) !void {
    const allocator = ctx.allocator;
    const pokemons = ctx.pokemons;
    switch (parsed) {
        .pokemons => |mons| {
            const pokemon = (try pokemons.getOrPutValue(allocator, mons.index, .{})).value_ptr;
            switch (mons.value) {
                .stats => |stats| {
                    switch (stats) {
                        .hp => |hp| pokemon.stats[0] = hp,
                        .attack => |attack| pokemon.stats[1] = attack,
                        .defense => |defense| pokemon.stats[2] = defense,
                        .speed => |speed| pokemon.stats[3] = speed,
                        .sp_attack => |sp_attack| pokemon.stats[4] = sp_attack,
                        .sp_defense => |sp_defense| pokemon.stats[5] = sp_defense,
                    }
                    pokemon.output[@enumToInt(stats)] = true;
                    return;
                },
                .evos => |evos| switch (evos.value) {
                    .target => |target| {
                        const evo_from = (try pokemons.getOrPutValue(allocator, target, .{})).value_ptr;
                        _ = try evo_from.evolves_from.put(allocator, mons.index, {});
                        return error.ParserFailed;
                    },
                    .method,
                    .param,
                    => return error.ParserFailed,
                },
                .types,
                .catch_rate,
                .base_exp_yield,
                .ev_yield,
                .items,
                .gender_ratio,
                .egg_cycles,
                .base_friendship,
                .growth_rate,
                .egg_groups,
                .abilities,
                .color,
                .moves,
                .tms,
                .hms,
                .name,
                .pokedex_entry,
                => return error.ParserFailed,
            }
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
        .items,
        .pokedex,
        .maps,
        .wild_pokemons,
        .static_pokemons,
        .given_pokemons,
        .pokeball_items,
        .hidden_hollows,
        .text,
        => return error.ParserFailed,
    }

    unreachable;
}

fn randomize(pokemons: Pokemons, seed: u64, same_total_stats: bool, follow_evos: bool) void {
    var random = rand.DefaultPrng.init(seed);
    for (pokemons.values()) |*pokemon| {
        const old_total = it.fold(&pokemon.stats, @as(usize, 0), foldu8);
        const new_random_total = random.random.intRangeAtMost(u64, 0, pokemon.stats.len * math.maxInt(u8));
        const new_total = if (same_total_stats) old_total else new_random_total;

        var weights: [pokemon.stats.len]f32 = undefined;
        randomWithinSum(&random.random, u8, &pokemon.stats, &weights, new_total);
    }

    if (!follow_evos)
        return;

    for (pokemons.values()) |*pokemon, i| {
        const species = pokemons.keys()[i];
        randomizeFromChildren(&random.random, pokemons, pokemon, same_total_stats, species);
    }
}

fn randomizeFromChildren(
    random: *rand.Random,
    pokemons: Pokemons,
    pokemon: *Pokemon,
    same_total_stats: bool,
    curr: usize,
) void {
    if (pokemon.evolves_from.count() == 0)
        return;

    // Get the average stats of all the prevolutions
    var stats = [_]u64{0} ** Pokemon.stats;
    for (pokemon.evolves_from.values()) |*prevolution, i| {
        const key = pokemon.evolves_from.keys()[i];
        // If prevolution == curr, then we have a cycle.
        if (key == curr)
            continue;

        // TODO: Can this ever happen???
        //                                      VVVVVVVV
        const p = pokemons.getEntry(key) orelse continue;

        // We should randomize prevolution by the same rules.
        randomizeFromChildren(random, pokemons, p.value_ptr, same_total_stats, curr);
        for (p.value_ptr.stats) |stat, j|
            stats[j] += stat;
    }

    // Average calculated here
    var average = [_]u8{0} ** Pokemon.stats;
    for (average) |*stat, i| {
        stat.* = math.cast(u8, stats[i] / math.max(pokemon.evolves_from.count(), 1)) catch math.maxInt(u8);
    }

    const old_total = it.fold(&pokemon.stats, @as(usize, 0), foldu8);
    const average_total = it.fold(&average, @as(usize, 0), foldu8);
    const new_random_total = random.intRangeAtMost(u64, average_total, stats.len * math.maxInt(u8));
    const new_total = if (same_total_stats) old_total else new_random_total;

    pokemon.stats = average;
    var weights: [pokemon.stats.len]f32 = undefined;
    randomUntilSum(random, u8, &pokemon.stats, &weights, new_total);

    // After this, the Pokémons stats should be equal or above the average
    for (average) |_, i|
        debug.assert(average[i] <= pokemon.stats[i]);
}

fn randomWithinSum(random: *rand.Random, comptime T: type, buf: []T, weight_buf: []f32, s: u64) void {
    mem.set(T, buf, 0);
    randomUntilSum(random, T, buf, weight_buf, s);
}

fn randomUntilSum(random: *rand.Random, comptime T: type, buf: []T, weight_buf: []f32, s: u64) void {
    // TODO: In this program, we will never pass buf.len > 6, so we can
    //       statically have this buffer. If this function is to be more
    //       general, we problably have to accept an allpocator.
    const weights = blk: {
        for (buf) |_, i|
            weight_buf[i] = random.float(f32);

        break :blk weight_buf[0..buf.len];
    };

    const curr = it.fold(buf, @as(usize, 0), foldu8);
    const max = math.min(s, buf.len * math.maxInt(T));
    if (max < curr)
        return;

    const missing = max - curr;
    const total_weigth = it.fold(weights, @as(f64, 0), foldf32);
    for (buf) |*item, i| {
        const to_add_f = @intToFloat(f64, missing) * (weights[i] / total_weigth);
        const to_add_max = math.min(to_add_f, math.maxInt(u8));
        item.* = math.add(T, item.*, @floatToInt(u8, to_add_max)) catch math.maxInt(T);
    }

    while (it.fold(buf, @as(usize, 0), foldu8) < max) {
        const item = util.random.item(random, buf).?;
        item.* = math.add(T, item.*, 1) catch item.*;
    }
}

fn foldu8(a: usize, b: u8) usize {
    return a + b;
}

fn foldf32(a: f64, b: f32) f64 {
    return a + b;
}

const Evos = std.AutoArrayHashMapUnmanaged(u16, void);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);

const Pokemon = struct {
    stats: [stats]u8 = [_]u8{0} ** stats,
    output: [stats]bool = [_]bool{false} ** stats,
    evolves_from: Evos = Evos{},

    const stats = @typeInfo(format.Stats(u8)).Union.fields.len;
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
    try util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.pokemons[0].stats.hp=89
        \\.pokemons[0].stats.attack=18
        \\.pokemons[0].stats.defense=76
        \\.pokemons[0].stats.speed=117
        \\.pokemons[0].stats.sp_attack=63
        \\.pokemons[0].stats.sp_defense=119
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
        \\.pokemons[3].stats.hp=80
        \\.pokemons[3].stats.attack=4
        \\.pokemons[3].stats.defense=115
        \\.pokemons[3].stats.speed=34
        \\.pokemons[3].stats.sp_attack=82
        \\.pokemons[3].stats.sp_defense=67
        \\
    );
    try util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--follow-evos" }, test_string, result_prefix ++
        \\.pokemons[0].stats.hp=89
        \\.pokemons[0].stats.attack=18
        \\.pokemons[0].stats.defense=76
        \\.pokemons[0].stats.speed=117
        \\.pokemons[0].stats.sp_attack=63
        \\.pokemons[0].stats.sp_defense=119
        \\.pokemons[1].stats.hp=255
        \\.pokemons[1].stats.attack=255
        \\.pokemons[1].stats.defense=185
        \\.pokemons[1].stats.speed=255
        \\.pokemons[1].stats.sp_attack=255
        \\.pokemons[1].stats.sp_defense=255
        \\.pokemons[2].stats.hp=255
        \\.pokemons[2].stats.attack=255
        \\.pokemons[2].stats.defense=191
        \\.pokemons[2].stats.speed=255
        \\.pokemons[2].stats.sp_attack=255
        \\.pokemons[2].stats.sp_defense=255
        \\.pokemons[3].stats.hp=80
        \\.pokemons[3].stats.attack=4
        \\.pokemons[3].stats.defense=115
        \\.pokemons[3].stats.speed=34
        \\.pokemons[3].stats.sp_attack=82
        \\.pokemons[3].stats.sp_defense=67
        \\
    );
    try util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--same-total-stats" }, test_string, result_prefix ++
        \\.pokemons[0].stats.hp=11
        \\.pokemons[0].stats.attack=2
        \\.pokemons[0].stats.defense=9
        \\.pokemons[0].stats.speed=14
        \\.pokemons[0].stats.sp_attack=10
        \\.pokemons[0].stats.sp_defense=14
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
        \\.pokemons[3].stats.hp=14
        \\.pokemons[3].stats.attack=10
        \\.pokemons[3].stats.defense=54
        \\.pokemons[3].stats.speed=34
        \\.pokemons[3].stats.sp_attack=81
        \\.pokemons[3].stats.sp_defense=47
        \\
    );
    try util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--same-total-stats", "--follow-evos" }, test_string, result_prefix ++
        \\.pokemons[0].stats.hp=11
        \\.pokemons[0].stats.attack=2
        \\.pokemons[0].stats.defense=9
        \\.pokemons[0].stats.speed=14
        \\.pokemons[0].stats.sp_attack=10
        \\.pokemons[0].stats.sp_defense=14
        \\.pokemons[1].stats.hp=19
        \\.pokemons[1].stats.attack=13
        \\.pokemons[1].stats.defense=11
        \\.pokemons[1].stats.speed=28
        \\.pokemons[1].stats.sp_attack=27
        \\.pokemons[1].stats.sp_defense=22
        \\.pokemons[2].stats.hp=23
        \\.pokemons[2].stats.attack=24
        \\.pokemons[2].stats.defense=12
        \\.pokemons[2].stats.speed=37
        \\.pokemons[2].stats.sp_attack=49
        \\.pokemons[2].stats.sp_defense=35
        \\.pokemons[3].stats.hp=14
        \\.pokemons[3].stats.attack=10
        \\.pokemons[3].stats.defense=54
        \\.pokemons[3].stats.speed=34
        \\.pokemons[3].stats.sp_attack=81
        \\.pokemons[3].stats.sp_defense=47
        \\
    );
}
