const builtin = @import("builtin");
const clap = @import("zig-clap");
const format = @import("tm35-format");
const fun = @import("fun-with-zig");
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
    Param.option(
        "the seed used to randomize stats",
        Names.both("seed"),
    ),
    Param.positional(""),
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-stats [OPTION]... FILE
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

const stats = [][]const u8{
    "hp",
    "attack",
    "defense",
    "speed",
    "sp_attack",
    "sp_defense",
};

pub fn main2(allocator: *mem.Allocator, args: Clap, stdin: var, stdout: var, stderr: var) !void {
    if (args.flag("--help"))
        return try usage(stdout);

    const same_total_stats = args.flag("--same-total-stats");
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
    randomize(pokemons, seed, same_total_stats);

    var iter = pokemons.iterator();
    while (iter.next()) |kv| {
        inline for (stats) |stat| {
            if (@field(kv.value, stat)) |s|
                try stdout.print("pokemons[{}].stats.{}={}\n", kv.key, stat, s);
        }
    }
}

fn readPokemons(allocator: *mem.Allocator, in_stream: var, out_stream: var) !PokemonMap {
    @setEvalBranchQuota(100000);

    const m = format.Matcher([][]const u8{
        "pokemons[*].stats.hp",
        "pokemons[*].stats.attack",
        "pokemons[*].stats.defense",
        "pokemons[*].stats.speed",
        "pokemons[*].stats.sp_attack",
        "pokemons[*].stats.sp_defense",
        "pokemons[*].evos[*].target",
    });

    var res = PokemonMap.init(allocator);
    var line_buf = try std.Buffer.initSize(allocator, 0);
    defer line_buf.deinit();

    var line: usize = 1;
    while (readLine(in_stream, &line_buf)) |str| : (line += 1) {
        if (m.match(str)) |match| switch (match.case) {
            m.case("pokemons[*].stats.hp"),
            m.case("pokemons[*].stats.attack"),
            m.case("pokemons[*].stats.defense"),
            m.case("pokemons[*].stats.speed"),
            m.case("pokemons[*].stats.sp_attack"),
            m.case("pokemons[*].stats.sp_defense"),
            => success: {
                err: {
                    const value = fmt.parseUnsigned(u8, mem.trim(u8, match.value.str, "\t "), 10) catch break :err;
                    const index = fmt.parseUnsigned(usize, match.anys[0].str, 10) catch break :err;

                    const entry = try res.getOrPut(index);
                    const pokemon = &entry.kv.value;
                    if (!entry.found_existing) {
                        pokemon.* = Pokemon{
                            .hp = null,
                            .attack = null,
                            .defense = null,
                            .speed = null,
                            .sp_attack = null,
                            .sp_defense = null,
                            .evos = EvoMap.init(allocator),
                        };
                    }

                    switch (match.case) {
                        m.case("pokemons[*].stats.hp") => pokemon.hp = value,
                        m.case("pokemons[*].stats.attack") => pokemon.attack = value,
                        m.case("pokemons[*].stats.defense") => pokemon.defense = value,
                        m.case("pokemons[*].stats.speed") => pokemon.speed = value,
                        m.case("pokemons[*].stats.sp_attack") => pokemon.sp_attack = value,
                        m.case("pokemons[*].stats.sp_defense") => pokemon.sp_defense = value,
                        else => unreachable,
                    }

                    break :success;
                }

                try out_stream.print("{}\n", str);
            },
            m.case("pokemons[*].evos[*].target") => {
                err: {
                    const value = fmt.parseUnsigned(u8, mem.trim(u8, match.value.str, "\t "), 10) catch break :err;
                    const poke_index = fmt.parseUnsigned(usize, match.anys[0].str, 10) catch break :err;
                    const evo_index = fmt.parseUnsigned(usize, match.anys[1].str, 10) catch break :err;

                    const entry = try res.getOrPut(poke_index);
                    const pokemon = &entry.kv.value;
                    if (!entry.found_existing) {
                        pokemon.* = Pokemon{
                            .hp = null,
                            .attack = null,
                            .defense = null,
                            .speed = null,
                            .sp_attack = null,
                            .sp_defense = null,
                            .evos = EvoMap.init(allocator),
                        };
                    }

                    const value_str = mem.trim(u8, match.value.str, "\t ");
                    _ = try pokemon.evos.put(evo_index, value);
                }

                try out_stream.print("{}\n", str);
            },
            else => try out_stream.print("{}\n", str),
        } else |_| {
            try out_stream.print("{}\n", str);
        }

        line_buf.shrink(0);
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }

    return res;
}

fn randomize(pokemons: PokemonMap, seed: u64, same_total_stats: bool) void {
    var random = rand.DefaultPrng.init(seed);
    var iter = pokemons.iterator();
    while (iter.next()) |kv| {
        const pokemon = &kv.value;
        const total = pokemon.totalStats();

        inline for (stats) |stat| {
            if (@field(pokemon, stat)) |*s| {
                s.* = random.random.int(u8);
            }
        }

        if (same_total_stats) {
            const new_total = pokemon.totalStats();
            inline for (stats) |stat| {
                if (@field(pokemon, stat)) |*s| {
                    const norm = @intToFloat(f64, s.*) / @intToFloat(f64, new_total);
                    const new_stat = norm * @intToFloat(f64, total);
                    s.* = math.cast(u8, @floatToInt(u64, new_stat)) catch 255;
                }
            }

            next: while (pokemon.totalStats() < total and pokemon.totalStats() != pokemon.maxStats()) {
                var index = random.random.intRangeLessThan(u16, 0, pokemon.statCount());
                inline for (stats) |stat| {
                    if (@field(pokemon, stat)) |*s| {
                        if (index == 0) {
                            s.* = math.add(u8, s.*, 1) catch s.*;
                            continue :next;
                        } else index -= 1;
                    }
                }
            }

            debug.assert(total == pokemon.totalStats());
        }
    }
}

fn readLine(stream: var, buf: *std.Buffer) ![]u8 {
    while (true) {
        const byte = try stream.readByte();
        switch (byte) {
            '\n' => return buf.toSlice(),
            else => try buf.appendByte(byte),
        }
    }
}

const PokemonMap = std.AutoHashMap(usize, Pokemon);
const EvoMap = std.AutoHashMap(usize, usize);

const Pokemon = struct {
    hp: ?u8,
    attack: ?u8,
    defense: ?u8,
    speed: ?u8,
    sp_attack: ?u8,
    sp_defense: ?u8,
    evos: EvoMap,

    fn totalStats(p: Pokemon) u16 {
        return u16(p.hp orelse 0) +
            (p.attack orelse 0) +
            (p.defense orelse 0) +
            (p.speed orelse 0) +
            (p.sp_attack orelse 0) +
            (p.sp_defense orelse 0);
    }

    fn statCount(p: Pokemon) u16 {
        var res: u8 = 0;
        if (p.hp) |_|
            res += 1;
        if (p.attack) |_|
            res += 1;
        if (p.speed) |_|
            res += 1;
        if (p.sp_attack) |_|
            res += 1;
        if (p.sp_defense) |_|
            res += 1;

        return res;
    }

    fn maxStats(p: Pokemon) u16 {
        return p.statCount() * math.maxInt(u8);
    }
};
