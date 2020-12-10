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

const exit = util.exit;
const parse = util.parse;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-e, --evolutions <INT>       Only pick starters with NUM or more evolutions. (default: 0)                              ") catch unreachable,
        clap.parseParam("-h, --help                   Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-l, --pick-lowest-evolution  Always pick the lowest evolution of a starter.                                            ") catch unreachable,
        clap.parseParam("-s, --seed <INT>             The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-v, --version                Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-rand-starters ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nRandomizes starter Pokémons.\n" ++
        "\n" ++
        "Options:\n");
    try clap.help(writer, &params);
}

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    strings: *util.container.StringCache(.{}),
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) u8 {
    const seed = util.getSeed(stdio.err, usage, args) catch return 1;
    const evolutions = if (args.option("--evolutions")) |evos|
        fmt.parseUnsigned(usize, evos, 10) catch |err| {
            stdio.err.print("'{}' could not be parsed as a number to --evolutions: {}\n", .{ evos, err }) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    else
        0;

    const pick_lowest = args.flag("--pick-lowest-evolution");

    var fifo = util.read.Fifo(.Dynamic).init(allocator);
    var data = Data{};
    while (util.read.line(stdio.in, &fifo) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        parseLine(allocator, &data, line) catch |err| switch (err) {
            error.OutOfMemory => return exit.allocErr(stdio.err),
            error.ParseError => stdio.out.print("{}\n", .{line}) catch |err2| {
                return exit.stdoutErr(stdio.err, err2);
            },
        };
    }

    const species = data.pokedexPokemons(allocator) catch return exit.allocErr(stdio.err);
    const random = &rand.DefaultPrng.init(seed).random;
    const pick_from = blk: {
        var res = Set{};
        for (species.span()) |range| {
            var pokemon: usize = range.start;
            while (pokemon <= range.end) : (pokemon += 1) {
                // Only pick lowest evo pokemon if pick_lowest is true
                if (pick_lowest and data.evolves_from.get(pokemon) != null)
                    continue;
                if (countEvos(data, pokemon) < evolutions)
                    continue;

                _ = res.put(allocator, pokemon) catch return exit.allocErr(stdio.err);
            }
        }
        if (res.count() == 0)
            _ = res.put(allocator, 0) catch return exit.allocErr(stdio.err);

        break :blk res;
    };

    const ranges = data.starters.span();
    for (ranges) |range| {
        var i: usize = range.start;
        while (i <= range.end) : (i += 1) {
            const index = random.intRangeLessThan(usize, 0, pick_from.count());
            const res = pick_from.at(index);
            stdio.out.print(".starters[{}]={}\n", .{ i, res }) catch |err| return exit.stdoutErr(stdio.err, err);
        }
    }
    return 0;
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !void {
    const sw = parse.Swhash(16);
    const m = sw.match;
    const c = sw.case;

    var p = parse.MutParser{ .str = str };
    switch (m(try p.parse(parse.anyField))) {
        c("pokedex") => {
            const index = try p.parse(parse.index);
            _ = try data.pokedex.put(allocator, index);
            return error.ParseError;
        },
        c("starters") => {
            const starter_index = try p.parse(parse.index);
            _ = try p.parse(parse.usizev);
            _ = try data.starters.put(allocator, starter_index);
            return;
        },
        c("pokemons") => {
            const evolves_from = try p.parse(parse.index);
            const pokemon = try data.pokemons.getOrPutValue(allocator, evolves_from, Pokemon{});
            switch (m(try p.parse(parse.anyField))) {
                c("catch_rate") => pokemon.catch_rate = try p.parse(parse.usizev),
                c("pokedex_entry") => pokemon.pokedex_entry = try p.parse(parse.usizev),
                c("evos") => {
                    _ = try p.parse(parse.index);
                    _ = try p.parse(comptime parse.field("target"));

                    const evolves_to = try p.parse(parse.usizev);
                    const from_set = try data.evolves_from.getOrPutValue(allocator, evolves_to, Set{});
                    const to_set = try data.evolves_to.getOrPutValue(allocator, evolves_from, Set{});
                    _ = try data.pokemons.getOrPutValue(allocator, evolves_to, Pokemon{});
                    _ = try from_set.put(allocator, evolves_from);
                    _ = try to_set.put(allocator, evolves_to);
                },
                else => return error.ParseError,
            }
            return error.ParseError;
        },
        else => return error.ParseError,
    }
    unreachable;
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
const Pokemons = util.container.IntMap.Unmanaged(usize, Pokemon);
const Evolutions = util.container.IntMap.Unmanaged(usize, Set);

const Data = struct {
    pokedex: Set = Set{},
    starters: Set = Set{},
    pokemons: Pokemons = Pokemons{},
    evolves_from: Evolutions = Evolutions{},
    evolves_to: Evolutions = Evolutions{},

    fn pokedexPokemons(d: Data, allocator: *mem.Allocator) !Set {
        var res = Set{};
        errdefer res.deinit(allocator);

        for (d.pokemons.values()) |pokemon, i| {
            const s = d.pokemons.at(i).key;
            if (pokemon.catch_rate == 0 or !d.pokedex.exists(pokemon.pokedex_entry))
                continue;

            _ = try res.put(allocator, s);
        }

        return res;
    }
};

const Pokemon = struct {
    pokedex_entry: usize = math.maxInt(usize),
    catch_rate: usize = 1,
};

test "tm35-rand-starters" {
    const result_prefix =
        \\.pokemons[0].pokedex_entry=0
        \\.pokemons[0].evos[0].target=1
        \\.pokemons[1].pokedex_entry=1
        \\.pokemons[1].evos[0].target=2
        \\.pokemons[2].pokedex_entry=2
        \\.pokemons[3].pokedex_entry=3
        \\.pokemons[3].evos[0].target=4
        \\.pokemons[4].pokedex_entry=4
        \\.pokemons[5].pokedex_entry=5
        \\.pokedex[0].field=
        \\.pokedex[1].field=
        \\.pokedex[2].field=
        \\.pokedex[3].field=
        \\.pokedex[4].field=
        \\.pokedex[5].field=
        \\
    ;
    const test_string = result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=0
        \\.starters[2]=0
        \\
    ;

    util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=1"}, test_string, result_prefix ++
        \\.starters[0]=1
        \\.starters[1]=5
        \\.starters[2]=0
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=1", "--pick-lowest-evolution" }, test_string, result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=5
        \\.starters[2]=0
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=1", "--evolutions=1" }, test_string, result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=3
        \\.starters[2]=0
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=1", "--evolutions=2" }, test_string, result_prefix ++
        \\.starters[0]=0
        \\.starters[1]=0
        \\.starters[2]=0
        \\
    );
}
