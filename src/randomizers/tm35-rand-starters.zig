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
    var stdio_unbuf = util.getStdIo() catch |err| return 1;
    var stdio = stdio_unbuf.getBuffered();
    defer stdio.err.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(&arena.allocator);
    _ = arg_iter.next() catch undefined;

    const res = main2(
        &arena.allocator,
        fs.File.ReadError,
        fs.File.WriteError,
        stdio.getStreams(),
        clap.args.OsIterator,
        &arg_iter,
    );

    stdio.out.flush() catch |err| return errors.writeErr(&stdio.err.stream, "<stdout>", err);
    return res;
}

pub fn main2(
    allocator: *mem.Allocator,
    comptime ReadError: type,
    comptime WriteError: type,
    stdio: util.CustomStdIoStreams(ReadError, WriteError),
    comptime ArgIterator: type,
    arg_iter: *ArgIterator,
) u8 {
    var stdin = io.BufferedInStream(ReadError).init(stdio.in);
    var args = Clap.parse(allocator, ArgIterator, arg_iter) catch |err| {
        stdio.err.print("{}\n", err) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    if (args.flag("--help")) {
        usage(stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.print("{}\n", program_version) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    const seed = if (args.option("--seed")) |seed|
        fmt.parseUnsigned(u64, seed, 10) catch |err| {
            stdio.err.print("'{}' could not be parsed as a number to --seed: {}\n", seed, err) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    else blk: {
        var buf: [8]u8 = undefined;
        os.getrandom(buf[0..]) catch break :blk u64(0);
        break :blk mem.readInt(u64, &buf, .Little);
    };

    const evolutions = if (args.option("--evolutions")) |evos|
        fmt.parseUnsigned(usize, evos, 10) catch |err| {
            stdio.err.print("'{}' could not be parsed as a number to --evolutions: {}\n", evos, err) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    else
        0;

    const pick_lowest = args.flag("--pick-lowest-evolution");

    var line_buf = std.Buffer.initSize(allocator, 0) catch |err| return errors.allocErr(stdio.err);
    var data = Data{
        .starters = Starters.init(allocator),
        .pokemons = Set.init(allocator),
        .evolves_from = Evolutions.init(allocator),
        .evolves_to = Evolutions.init(allocator),
    };

    while (util.readLine(&stdin, &line_buf) catch |err| return errors.readErr(stdio.err, "<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&data, str) catch |err| switch (err) {
            error.OutOfMemory => return errors.allocErr(stdio.err),
            error.Overflow,
            error.EndOfString,
            error.InvalidCharacter,
            error.InvalidField,
            => true,
        };
        if (print_line)
            stdio.out.print("{}\n", str) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

        line_buf.shrink(0);
    }

    randomize(data, seed, evolutions, pick_lowest) catch |err| return errors.randErr(stdio.err, err);

    var iter = data.starters.iterator();
    while (iter.next()) |kv| {
        stdio.out.print(".starters[{}]={}\n", kv.key, kv.value) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
    }
    return 0;
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
        _ = try data.pokemons.put(evolves_from, {});
        try p.eatField("evos");

        // We don't care about the evolution index.
        _ = try p.eatIndex();
        try p.eatField("target");
        const evolves_to = try p.eatUnsignedValue(usize, 10);
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
    if (pick_from.len == 0)
        return;

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

test "tm35-rand-starters" {
    const result_prefix =
        \\.pokemons[0].evos[0].target=1
        \\.pokemons[1].evos[0].target=2
        \\.pokemons[2].hp=10
        \\.pokemons[3].evos[0].target=4
        \\.pokemons[4].hp=10
        \\.pokemons[5].hp=10
        \\
    ;
    const test_string = result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=0
        \\.starters[2]=0
        \\
    ;

    testProgram([_][]const u8{"--seed=1"}, test_string, result_prefix ++
        \\.starters[1]=5
        \\.starters[2]=0
        \\.starters[0]=4
        \\
    );
    testProgram([_][]const u8{ "--seed=1", "--pick-lowest-evolution" }, test_string, result_prefix ++
        \\.starters[1]=5
        \\.starters[2]=0
        \\.starters[0]=5
        \\
    );
    testProgram([_][]const u8{ "--seed=1", "--evolutions=1" }, test_string, result_prefix ++
        \\.starters[1]=3
        \\.starters[2]=0
        \\.starters[0]=3
        \\
    );
    testProgram([_][]const u8{ "--seed=1", "--evolutions=2" }, test_string, result_prefix ++
        \\.starters[1]=0
        \\.starters[2]=0
        \\.starters[0]=0
        \\
    );
}

fn testProgram(
    args: []const []const u8,
    in: []const u8,
    out: []const u8,
) void {
    var alloc_buf: [1024 * 50]u8 = undefined;
    var out_buf: [1024 * 10]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&alloc_buf);
    var stdin = io.SliceInStream.init(in);
    var stdout = io.SliceOutStream.init(&out_buf);
    var stderr = io.SliceOutStream.init(&err_buf);
    var arg_iter = clap.args.SliceIterator{ .args = args };

    const StdIo = util.CustomStdIoStreams(anyerror, anyerror);

    const res = main2(
        &fba.allocator,
        anyerror,
        anyerror,
        StdIo{
            .in = @ptrCast(*io.InStream(anyerror), &stdin.stream),
            .out = @ptrCast(*io.OutStream(anyerror), &stdout.stream),
            .err = @ptrCast(*io.OutStream(anyerror), &stderr.stream),
        },
        clap.args.SliceIterator,
        &arg_iter,
    );
    debug.warn("{}", stderr.getWritten());
    testing.expectEqual(u8(0), res);
    testing.expectEqualSlices(u8, "", stderr.getWritten());
    if (!mem.eql(u8, out, stdout.getWritten())) {
        debug.warn("\n====== expected this output: =========\n");
        debug.warn("{}", out);
        debug.warn("\n======== instead found this: =========\n");
        debug.warn("{}", stdout.getWritten());
        debug.warn("\n======================================\n");
        testing.expect(false);
    }
    testing.expectEqualSlices(u8, out, stdout.getWritten());
}
