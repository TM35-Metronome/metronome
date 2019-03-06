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

const BufInStream = io.BufferedInStream(os.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(os.File.OutStream.Error);
const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = []Param{
    Param.flag(
        "display this help text and exit",
        Names.both("help"),
    ),
    Param.option(
        "which moves should be prefered over others [random, same-type]",
        Names.both("preference"),
    ),
    Param.option(
        "the seed used to randomize stats",
        Names.both("seed"),
    ),
    Param.positional(""),
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-learned-moves [OPTION]...
        \\Reads the tm35 format from stdin and randomizes the moves pokemons can learn.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

const Preference = enum {
    Random,
    SameType,
};

pub fn main() !void {
    const unbuf_stdout = &(try std.io.getStdOut()).outStream().stream;
    var buf_stdout = BufOutStream.init(unbuf_stdout);
    defer buf_stdout.flush() catch {};

    const stderr = &(try std.io.getStdErr()).outStream().stream;
    const stdin = &BufInStream.init(&(try std.io.getStdIn()).inStream().stream).stream;
    const stdout = &buf_stdout.stream;

    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    var arena = heap.ArenaAllocator.init(&direct_allocator.allocator);
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

    const pref = blk: {
        const pref = args.option("--preference") orelse "random";
        if (mem.eql(u8, pref, "random")) {
            break :blk Preference.Random;
        } else if (mem.eql(u8, pref, "same-type")) {
            break :blk Preference.SameType;
        } else {
            return error.@"Invalid argument to --preference.";
        }
    };
    const seed = blk: {
        const seed_str = args.option("--seed") orelse {
            var buf: [8]u8 = undefined;
            try std.os.getRandomBytes(buf[0..]);
            break :blk mem.readInt(u64, &buf, builtin.Endian.Little);
        };

        break :blk try fmt.parseUnsigned(u64, seed_str, 10);
    };

    const data = try readData(allocator, stdin, stdout);
    try randomize(data, seed, pref);

    var poke_iter = data.pokemons.iterator();
    while (poke_iter.next()) |poke_kv| {
        const pokemon_index = poke_kv.key;
        const pokemon = &poke_kv.value;

        var tm_iter = pokemon.tms_learned.iterator();
        while (tm_iter.next()) |tm_kv| {
            try stdout.print(".pokemons[{}].tms[{}]={}\n", pokemon_index, tm_kv.key, tm_kv.value);
        }

        var hm_iter = pokemon.hms_learned.iterator();
        while (hm_iter.next()) |hm_kv| {
            try stdout.print(".pokemons[{}].hms[{}]={}\n", pokemon_index, hm_kv.key, hm_kv.value);
        }
    }
}

fn readData(allocator: *mem.Allocator, in_stream: var, out_stream: var) !Data {
    var res = Data{
        .pokemons = Pokemons.init(allocator),
        .moves = Moves.init(allocator),
        .tms = Machines.init(allocator),
        .hms = Machines.init(allocator),
    };
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

fn parseLine(data: *Data, str: []const u8) !bool {
    const allocator = data.pokemons.allocator;
    var parser = format.StrParser.init(str);

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
            _ = try pokemon.types.put(try mem.dupe(allocator, u8, t), {});
        } else |_| {}
    } else |_| if (parser.eatField("moves")) {
        const move_index = try parser.eatIndex();
        const move_entry = try data.moves.getOrPutValue(move_index, Move{
            .power = null,
            .@"type" = null,
        });
        const move = &move_entry.value;

        if (parser.eatField("power")) {
            move.power = try parser.eatUnsignedValue(usize, 10);
        } else |_| if (parser.eatField("type")) {
            move.@"type" = try mem.dupe(allocator, u8, try parser.eatValue());
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

fn randomize(data: Data, seed: u64, pref: Preference) error{}!void {
    const allocator = data.pokemons.allocator;
    var random = &rand.DefaultPrng.init(seed).random;

    var poke_iter = data.pokemons.iterator();
    while (poke_iter.next()) |poke_kv| {
        const pokemon_index = poke_kv.key;
        const pokemon = &poke_kv.value;

        inline for ([][]const u8{
            "tms",
            "hms",
        }) |f| {
            var iter = @field(pokemon, f ++ "_learned").iterator();
            while (iter.next()) |kv| switch (pref) {
                Preference.Random => kv.value = random.boolean(),
                Preference.SameType => {
                    const low_chance = 0.1;
                    const chance: f64 = blk: {
                        const move_index = @field(data, f).get(kv.key) orelse break :blk low_chance;
                        const move = data.moves.get(move_index.value) orelse break :blk low_chance;
                        const move_type = move.value.@"type" orelse break :blk low_chance;
                        _ = pokemon.types.get(move_type) orelse break :blk low_chance;

                        // Yay the move is stab. Give it a higher chance.
                        break :blk f64(1.0 - low_chance);
                    };

                    kv.value = random.float(f64) < chance;
                },
            };
        }
    }
}

const Pokemons = std.AutoHashMap(usize, Pokemon);
const MachinesLearned = std.AutoHashMap(usize, bool);
const Machines = std.AutoHashMap(usize, usize);
//const LvlUpMoves = std.AutoHashMap(usize, LvlUpMove);
const Moves = std.AutoHashMap(usize, Move);
const Types = std.AutoHashMap([]const u8, void);

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
    @"type": ?[]const u8,
};
