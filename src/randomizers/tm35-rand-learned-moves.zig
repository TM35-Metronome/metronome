const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const os = std.os;
const rand = std.rand;

const format = util.format;

const BufInStream = io.BufferedInStream(fs.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);

const Clap = clap.ComptimeClap(clap.Help, params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help                      Display this help text and exit.                                                                ") catch unreachable,
        clap.parseParam("-p, --preference <random|stab>  Which moves the randomizer should prefer picking (90% preference, 10% random). (default: random)") catch unreachable,
        clap.parseParam("-s, --seed <NUM>                The seed to use for random numbers. A random seed will be picked if this is not specified.      ") catch unreachable,
        clap.parseParam("-v, --version                   Output version information and exit.                                                            ") catch unreachable,
        Param{ .takes_value = true },
    };
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-learned-moves [-hv] [-p <random|stab>] [-s <NUM>]
        \\Randomizes the moves Pokémons can learn.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

const Preference = enum {
    Random,
    Stab,
};

pub fn main() u8 {
    var stdio_unbuf = util.getStdIo() catch |err| return errPrint("Could not aquire stdio: {}\n", err);
    var stdio = stdio_unbuf.getBuffered();

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        debug.warn("{}\n", err);
        stdio.err.flush() catch {};
        return 1;
    };

    if (args.flag("--help")) {
        usage(&stdio.out.stream) catch |err| return failedWriteError("<stdout>", err);
        stdio.out.flush() catch |err| return failedWriteError("<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.stream.print("{}\n", program_version) catch |err| return failedWriteError("<stdout>", err);
        stdio.out.flush() catch |err| return failedWriteError("<stdout>", err);
        return 0;
    }

    const seed = if (args.option("--seed")) |seed|
        fmt.parseUnsigned(u64, seed, 10) catch |err| {
            debug.warn("'{}' could not be parsed as a number to --seed: {}\n", seed, err);
            usage(&stdio.err.stream) catch {};
            stdio.err.flush() catch {};
            return 1;
        }
    else blk: {
        var buf: [8]u8 = undefined;
        os.getrandom(buf[0..]) catch break :blk u64(0);
        break :blk mem.readInt(u64, &buf, .Little);
    };

    const pref = if (args.option("--preference")) |pref|
        if (mem.eql(u8, pref, "random"))
            Preference.Random
        else if (mem.eql(u8, pref, "stab"))
            Preference.Stab
        else {
            debug.warn("--preference does not support '{}'\n", pref);
            usage(&stdio.err.stream) catch {};
            stdio.err.flush() catch {};
            return 1;
        }
    else
        Preference.Random;

    var line_buf = std.Buffer.initSize(allocator, 0) catch |err| return errPrint("Allocation failed: {}", err);
    var data = Data{
        .pokemons = Pokemons.init(allocator),
        .moves = Moves.init(allocator),
        .tms = Machines.init(allocator),
        .hms = Machines.init(allocator),
    };

    while (util.readLine(&stdio.in, &line_buf) catch |err| return failedReadError("<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&data, str) catch true;
        if (print_line)
            stdio.out.stream.print("{}\n", str) catch |err| return failedWriteError("<stdout>", err);

        line_buf.shrink(0);
    }
    stdio.out.flush() catch |err| return failedWriteError("<stdout>", err);

    randomize(data, seed, pref);

    var poke_iter = data.pokemons.iterator();
    while (poke_iter.next()) |poke_kv| {
        const pokemon_index = poke_kv.key;
        const pokemon = &poke_kv.value;

        var tm_iter = pokemon.tms_learned.iterator();
        while (tm_iter.next()) |tm_kv| {
            stdio.out.stream.print(
                ".pokemons[{}].tms[{}]={}\n",
                pokemon_index,
                tm_kv.key,
                tm_kv.value,
            ) catch |err| return failedWriteError("<stdout>", err);
        }

        var hm_iter = pokemon.hms_learned.iterator();
        while (hm_iter.next()) |hm_kv| {
            stdio.out.stream.print(
                ".pokemons[{}].hms[{}]={}\n",
                pokemon_index,
                hm_kv.key,
                hm_kv.value,
            ) catch |err| return failedWriteError("<stdout>", err);
        }
    }

    stdio.out.flush() catch |err| return failedWriteError("<stdout>", err);
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

fn parseLine(data: *Data, str: []const u8) !bool {
    const allocator = data.pokemons.allocator;
    var parser = format.Parser{ .str = str };

    if (parser.eatField("pokemons")) {
        const pokemon_index = try parser.eatIndex();
        const pokemon_entry = try data.pokemons.getOrPutValue(pokemon_index, Pokemon{
            .types = Types.init(allocator),
            .tms_learned = MachinesLearned.init(allocator),
            .hms_learned = MachinesLearned.init(allocator),
        });
        const pokemon = &pokemon_entry.value;

        if (parser.eatField("tms")) {
            const tm = try parser.eatIndex();
            _ = try pokemon.tms_learned.put(tm, try parser.eatBoolValue());
            return false;
        } else |_| if (parser.eatField("hms")) {
            const hm = try parser.eatIndex();
            _ = try pokemon.hms_learned.put(hm, try parser.eatBoolValue());
            return false;
        } else |_| if (parser.eatField("types")) {
            _ = try parser.eatIndex();
            const t = try parser.eatValue();
            _ = try pokemon.types.put(t);
        } else |_| {}
    } else |_| if (parser.eatField("moves")) {
        const move_index = try parser.eatIndex();
        const move_entry = try data.moves.getOrPutValue(move_index, Move{
            .power = null,
            .type = null,
        });
        const move = &move_entry.value;

        if (parser.eatField("power")) {
            move.power = try parser.eatUnsignedValue(usize, 10);
        } else |_| if (parser.eatField("type")) {
            move.type = try mem.dupe(allocator, u8, try parser.eatValue());
        } else |_| {}
    } else |_| if (parser.eatField("tms")) {
        const tm = try parser.eatIndex();
        _ = try data.tms.put(tm, try parser.eatUnsignedValue(usize, 10));
    } else |_| if (parser.eatField("hms")) {
        const hm = try parser.eatIndex();
        _ = try data.hms.put(hm, try parser.eatUnsignedValue(usize, 10));
    } else |_| {}

    return true;
}

fn randomize(data: Data, seed: u64, pref: Preference) void {
    var random = &rand.DefaultPrng.init(seed).random;

    var poke_iter = data.pokemons.iterator();
    while (poke_iter.next()) |poke_kv| {
        const pokemon_index = poke_kv.key;
        const pokemon = poke_kv.value;
        randomizeMachinesLearned(data, pokemon, random, pref, data.tms, @field(pokemon, "tms_learned"));
        randomizeMachinesLearned(data, pokemon, random, pref, data.hms, @field(pokemon, "hms_learned"));
    }
}

fn randomizeMachinesLearned(data: Data, pokemon: Pokemon, random: *rand.Random, pref: Preference, machines: Machines, learned: MachinesLearned) void {
    var iter = learned.iterator();
    while (iter.next()) |kv| switch (pref) {
        .Random => kv.value = random.boolean(),
        .Stab => {
            const low_chance = 0.1;
            const chance: f64 = blk: {
                const move_index = machines.get(kv.key) orelse break :blk low_chance;
                const move = data.moves.get(move_index.value) orelse break :blk low_chance;
                const move_type = move.value.type orelse break :blk low_chance;
                if (!pokemon.types.exists(move_type))
                    break :blk low_chance;

                // Yay the move is stab. Give it a higher chance.
                break :blk f64(1.0 - low_chance);
            };

            kv.value = random.float(f64) < chance;
        },
    };
}

const Pokemons = std.AutoHashMap(usize, Pokemon);
const MachinesLearned = std.AutoHashMap(usize, bool);
const Machines = std.AutoHashMap(usize, usize);
//const LvlUpMoves = std.AutoHashMap(usize, LvlUpMove);
const Moves = std.AutoHashMap(usize, Move);
const Types = std.BufSet;

const Data = struct {
    pokemons: Pokemons,
    moves: Moves,
    tms: Machines,
    hms: Machines,
};

const Pokemon = struct {
    types: Types,
    tms_learned: MachinesLearned,
    hms_learned: MachinesLearned,
    //lvl_up_moves: LvlUpMoves
};

const LvlUpMove = struct {
    level: ?u16,
    id: ?usize,
};

const Move = struct {
    power: ?usize,
    type: ?[]const u8,
};
