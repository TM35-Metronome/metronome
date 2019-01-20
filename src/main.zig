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
    Param.option(
        "only pick starters with VALUE evolutions",
        Names.both("evolutions"),
    ),
    Param.flag(
        "display this help text and exit",
        Names.both("help"),
    ),
    Param.option(
        "the seed used to randomize stats",
        Names.both("seed"),
    ),
    Param.positional(""),
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-starters [OPTION]...
        \\Reads the tm35 format from stdin and randomizes the starter pokemons.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

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
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const evolutions = blk: {
        const str = args.option("--evolutions") orelse break :blk null;
        break :blk try fmt.parseUnsigned(usize, str, 10);
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
    try randomize(data, seed, evolutions);

    var iter = data.starters.iterator();
    while (iter.next()) |kv| {
        try stdout.print(".starters[{}]={}\n", kv.key, kv.value);
    }
}

fn readData(allocator: *mem.Allocator, in_stream: var, out_stream: var) !Data {
    var res = Data{
        .starters = Starters.init(allocator),
        .pokemons = Set.init(allocator),
        .evolves_from = Evolutions.init(allocator),
        .evolves_to = Evolutions.init(allocator),
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
    var parser = format.StrParser.init(str);
    const allocator = data.starters.allocator;

    if (parser.eatStr(".starters[")) |_| {
        const starter_index = try parser.eatUnsigned(usize, 10);
        try parser.eatStr("]=");
        const starter = try parser.eatUnsigned(usize, 10);

        const get_or_put_result = try data.starters.getOrPut(starter_index);
        get_or_put_result.kv.value = starter;
        return false;
    } else |_| if (parser.eatStr(".pokemons[")) |_| {
        const evolves_from = try parser.eatUnsigned(usize, 10);
        try parser.eatStr("].evos[");

        // We don't care about the evolution index.
        _ = try parser.eatUnsigned(usize, 10);
        try parser.eatStr("].target=");
        const evolves_to = try parser.eatUnsigned(usize, 10);
        _ = try data.pokemons.put(evolves_from, {});
        _ = try data.pokemons.put(evolves_to, {});

        {
            const entry = try data.evolves_from.getOrPutValue(evolves_to, Set.init(allocator));
            _ = try entry.value.put(evolves_from, {});
        }

        {
            const entry = try data.evolves_to.getOrPutValue(evolves_from, Set.init(allocator));
            _ = try entry.value.put(evolves_to, {});
        }

        return true;
    } else |_| {}

    return true;
}

fn randomize(data: Data, seed: u64, evolutions: ?usize) !void {
    const allocator = data.starters.allocator;
    const random = &rand.DefaultPrng.init(seed).random;

    const pick_from = blk: {
        var res = std.ArrayList(usize).init(allocator);
        var iter = data.pokemons.iterator();
        while (iter.next()) |kv| {
            const pokemon = kv.key;
            if (evolutions) |evos| {
                // If the pokemon is not the lowest evo then we won't pick it.
                if (data.evolves_from.get(pokemon) != null)
                    continue;
                if (countEvos(data, pokemon) != evos)
                    continue;

                try res.append(pokemon);
            } else {
                try res.append(pokemon);
            }
        }

        break :blk res.toOwnedSlice();
    };

    var iter = data.starters.iterator();
    while (iter.next()) |kv| {
        kv.value = pick_from[random.range(usize, 0, pick_from.len)];
    }
}

fn countEvos(data: Data, pokemon: usize) usize {
    var res: usize = 0;
    const evolves_to = data.evolves_to.get(pokemon) orelse return 0;

    // TODO: We don't handle cycles here.
    var iter = evolves_to.value.iterator();
    while (iter.next()) |evo| {
        const evos = countEvos(data, evo.key) + 1;
        res = math.max(res, evos);
    }

    return res;
}

const Starters = std.AutoHashMap(usize, usize);
const Set = std.AutoHashMap(usize, void);
const Evolutions = std.AutoHashMap(usize, Set);

const Data = struct {
    starters: Starters,
    pokemons: Set,
    evolves_from: Evolutions,
    evolves_to: Evolutions,
};
