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

pub const main = util.generateMain(main2);

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
    };
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-rand-starters ");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Randomizes starter Pokémons.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
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

    const evolutions = if (args.option("--evolutions")) |evos|
        fmt.parseUnsigned(usize, evos, 10) catch |err| {
            stdio.err.print("'{}' could not be parsed as a number to --evolutions: {}\n", .{ evos, err }) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    else
        0;

    const pick_lowest = args.flag("--pick-lowest-evolution");

    var line_buf = std.ArrayList(u8).init(allocator);
    var data = Data{};

    while (util.readLine(&stdin, &line_buf) catch |err| return errors.readErr(stdio.err, "<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(allocator, &data, str) catch |err| switch (err) {
            error.OutOfMemory => return errors.allocErr(stdio.err),
            error.ParseError => true,
        };
        if (print_line)
            stdio.out.print("{}\n", .{str}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

        line_buf.resize(0) catch unreachable;
    }

    const random = &rand.DefaultPrng.init(seed).random;
    const pick_from = blk: {
        var res = Set{};
        const ranges = data.pokemons.span();
        for (ranges) |range| {
            var pokemon: usize = range.start;
            while (pokemon <= range.end) : (pokemon += 1) {
                // Only pick lowest evo pokemon if pick_lowest is true
                if (pick_lowest and data.evolves_from.get(pokemon) != null)
                    continue;
                if (countEvos(data, pokemon) < evolutions)
                    continue;

                _ = res.put(allocator, pokemon) catch return errors.allocErr(stdio.err);
            }
        }
        if (res.count() == 0)
            _ = res.put(allocator, 0) catch return errors.allocErr(stdio.err);

        break :blk res;
    };

    const ranges = data.starters.span();
    for (ranges) |range| {
        var i: usize = range.start;
        while (i <= range.end) : (i += 1) {
            const index = random.intRangeLessThan(usize, 0, pick_from.count());
            const res = pick_from.at(index);
            stdio.out.print(".starters[{}]={}\n", .{ i, res }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        }
    }
    return 0;
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !bool {
    const sw = parse.Swhash(8);
    const m = sw.match;
    const c = sw.case;

    var p = parse.MutParser{ .str = str };
    switch (m(try p.parse(parse.anyField))) {
        c("starters") => {
            const starter_index = try p.parse(parse.index);
            _ = try p.parse(parse.usizev);
            _ = try data.starters.put(allocator, starter_index);
            return false;
        },
        c("pokemons") => {
            const evolves_from = try p.parse(parse.index);
            _ = try data.pokemons.put(allocator, evolves_from);
            _ = try p.parse(comptime parse.field("evos"));
            _ = try p.parse(parse.index);
            _ = try p.parse(comptime parse.field("target"));

            const evolves_to = try p.parse(parse.usizev);
            const from_set = try data.evolves_from.getOrPutValue(allocator, evolves_to, Set{});
            const to_set = try data.evolves_to.getOrPutValue(allocator, evolves_from, Set{});
            _ = try data.pokemons.put(allocator, evolves_to);
            _ = try from_set.put(allocator, evolves_from);
            _ = try to_set.put(allocator, evolves_to);

            return true;
        },
        else => return true,
    }
}

fn countEvos(data: Data, pokemon: usize) usize {
    var res: usize = 0;
    const evolves_to = data.evolves_to.get(pokemon) orelse return 0;

    // TODO: We don't handle cycles here.
    for (evolves_to.span()) |range| {
        var evo = range.start;
        while (evo <= range.end) : (evo += 1) {
            const evos = countEvos(data, evo) + 1;
            res = math.max(res, evos);
        }
    }

    return res;
}

const Set = util.container.IntSet.Unmanaged(usize);
const Evolutions = util.container.IntMap.Unmanaged(usize, Set);

const Data = struct {
    starters: Set = Set{},
    pokemons: Set = Set{},
    evolves_from: Evolutions = Evolutions{},
    evolves_to: Evolutions = Evolutions{},
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

    util.testing.testProgram(main2, &[_][]const u8{"--seed=1"}, test_string, result_prefix ++
        \\.starters[0]=1
        \\.starters[1]=5
        \\.starters[2]=0
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=1", "--pick-lowest-evolution" }, test_string, result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=5
        \\.starters[2]=0
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=1", "--evolutions=1" }, test_string, result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=3
        \\.starters[2]=0
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=1", "--evolutions=2" }, test_string, result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=0
        \\.starters[2]=0
        \\
    );
}
