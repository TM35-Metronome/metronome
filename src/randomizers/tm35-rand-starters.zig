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
        clap.parseParam("-e, --evolutions <NUM>       Only pick starters with NUM or more evolutions. (default: 0)                              ") catch unreachable,
        clap.parseParam("-h, --help                   Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-l, --pick-lowest-evolution  Always pick the lowest evolution of a starter.                                            ") catch unreachable,
        clap.parseParam("-s, --seed <NUM>             The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-v, --version                Output version information and exit.                                                      ") catch unreachable,
        Param{ .takes_value = true },
    };
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-starters [-hlv] [-e <NUM>] [-s <NUM>]
        \\Randomizes starter Pokémons.
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

    const evolutions = if (args.option("--evolutions")) |evos|
        fmt.parseUnsigned(usize, evos, 10) catch |err| {
            debug.warn("'{}' could not be parsed as a number to --evolutions: {}\n", evos, err);
            usage(stderr) catch |err2| return failedWriteError("<stderr>", err2);
            return 1;
        }
    else
        0;

    const pick_lowest = args.flag("--pick-lowest-evolution");

    var line_buf = std.Buffer.initSize(allocator, 0) catch |err| return errPrint("Allocation failed: {}", err);
    var data = Data{
        .starters = Starters.init(allocator),
        .pokemons = Set.init(allocator),
        .evolves_from = Evolutions.init(allocator),
        .evolves_to = Evolutions.init(allocator),
    };

    while (util.readLine(stdin, &line_buf) catch |err| return failedReadError("<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&data, str) catch true;
        if (print_line)
            stdout.stream.print("{}\n", str) catch |err| return failedWriteError("<stdout>", err);

        line_buf.shrink(0);
    }
    stdout.flush() catch |err| return failedWriteError("<stdout>", err);

    randomize(data, seed, evolutions, pick_lowest) catch |err| return errPrint("Failed to randomize data: {}", err);

    var iter = data.starters.iterator();
    while (iter.next()) |kv| {
        stdout.stream.print(".starters[{}]={}\n", kv.key, kv.value) catch |err| return failedWriteError("<stdout>", err);
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

fn parseLine(data: *Data, str: []const u8) !bool {
    var p = format.Parser{ .str = str };
    const allocator = data.starters.allocator;

    if (p.eatField("starters")) |_| {
        const starter_index = try p.eatIndex();
        const starter = try p.eatUnsignedValue(usize, 10);
        const get_or_put_result = try data.starters.getOrPut(starter_index);
        get_or_put_result.kv.value = starter;
        return false;
    } else |_| if (p.eatField("pokemons")) |_| {
        const evolves_from = try p.eatIndex();
        try p.eatField("evos");

        // We don't care about the evolution index.
        _ = try p.eatIndex();
        try p.eatField("target");
        const evolves_to = try p.eatUnsignedValue(usize, 10);
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

fn randomize(data: Data, seed: u64, evolutions: usize, pick_lowest: bool) !void {
    const allocator = data.starters.allocator;
    const random = &rand.DefaultPrng.init(seed).random;

    const pick_from = blk: {
        var res = std.ArrayList(usize).init(allocator);
        var iter = data.pokemons.iterator();
        while (iter.next()) |kv| {
            const pokemon = kv.key;
            // Only pick lowest evo pokemon if pick_lowest is true
            if (pick_lowest and data.evolves_from.get(pokemon) != null)
                continue;
            if (countEvos(data, pokemon) < evolutions)
                continue;

            try res.append(pokemon);
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
