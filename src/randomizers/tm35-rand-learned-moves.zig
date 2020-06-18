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
        clap.parseParam("-h, --help                      Display this help text and exit.                                                                ") catch unreachable,
        clap.parseParam("-p, --preference <random|stab>  Which moves the randomizer should prefer picking (90% preference, 10% random). (default: random)") catch unreachable,
        clap.parseParam("-s, --seed <NUM>                The seed to use for random numbers. A random seed will be picked if this is not specified.      ") catch unreachable,
        clap.parseParam("-v, --version                   Output version information and exit.                                                            ") catch unreachable,
    };
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-rand-learned-moves ");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Randomizes the moves Pokémons can learn.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

const Preference = enum {
    random,
    stab,
};

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

    const pref = if (args.option("--preference")) |pref|
        if (mem.eql(u8, pref, "random"))
            Preference.random
        else if (mem.eql(u8, pref, "stab"))
            Preference.stab
        else {
            stdio.err.print("--preference does not support '{}'\n", .{pref}) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    else
        Preference.random;

    var line_buf = std.ArrayList(u8).init(allocator);
    var data = Data{
        .strings = std.StringHashMap(usize).init(allocator),
    };

    while (util.readLine(&stdin, &line_buf) catch |err| return errors.readErr(stdio.err, "<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&data, str) catch |err| switch (err) {
            error.OutOfMemory => return errors.allocErr(stdio.err),
            error.ParseError => true,
        };
        if (print_line)
            stdio.out.print("{}\n", .{str}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

        line_buf.resize(0) catch unreachable;
    }

    randomize(data, seed, pref) catch return errors.allocErr(stdio.err);

    for (data.pokemons.values()) |*pokemon, i| {
        const pokemon_index = data.pokemons.at(i).key;
        for (pokemon.tms.span()) |range| {
            var tm = range.start;
            while (tm <= range.end) : (tm += 1) {
                stdio.out.print(".pokemons[{}].tms[{}]={}\n", .{
                    pokemon_index,
                    tm,
                    pokemon.tms_learned.exists(tm),
                }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            }
        }
        for (pokemon.hms.span()) |range| {
            var hm = range.start;
            while (hm <= range.end) : (hm += 1) {
                stdio.out.print(".pokemons[{}].hms[{}]={}\n", .{
                    pokemon_index,
                    hm,
                    pokemon.hms_learned.exists(hm),
                }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            }
        }
    }

    return 0;
}

fn parseLine(data: *Data, str: []const u8) !bool {
    const sw = util.parse.Swhash(8);
    const m = sw.match;
    const c = sw.case;
    const allocator = data.strings.allocator;

    var p = parse.MutParser{ .str = str };
    switch (m(try p.parse(parse.anyField))) {
        c("pokemons") => {
            const pokemon_index = try p.parse(parse.index);
            const pokemon = try data.pokemons.getOrPutValue(allocator, pokemon_index, Pokemon{});

            const field = try p.parse(parse.anyField);
            const index = try p.parse(parse.index);
            switch (m(field)) {
                c("tms") => {
                    _ = try pokemon.tms.put(allocator, index);
                    if (try p.parse(parse.boolv))
                        _ = try pokemon.tms_learned.put(allocator, index);
                },
                c("hms") => {
                    _ = try pokemon.hms.put(allocator, index);
                    if (try p.parse(parse.boolv))
                        _ = try pokemon.hms_learned.put(allocator, index);
                },
                c("types") => {
                    const type_name = try p.parse(parse.strv);
                    _ = try pokemon.types.put(allocator, try data.string(type_name));
                },
                else => return true,
            }
            return c("tms") != m(field) and c("hms") != m(field);
        },
        c("moves") => {
            const index = try p.parse(parse.index);
            const move = try data.moves.getOrPutValue(allocator, index, Move{});

            switch (m(try p.parse(parse.anyField))) {
                c("power") => move.power = try p.parse(parse.usizev),
                c("type") => move.type = try data.string(try p.parse(parse.strv)),
                else => {},
            }
        },
        c("tms") => _ = try data.tms.put(
            allocator,
            try p.parse(parse.index),
            try p.parse(parse.usizev),
        ),
        c("hms") => _ = try data.hms.put(
            allocator,
            try p.parse(parse.index),
            try p.parse(parse.usizev),
        ),
        else => return true,
    }
    return true;
}

fn randomize(data: Data, seed: u64, pref: Preference) !void {
    var random = &rand.DefaultPrng.init(seed).random;

    for (data.pokemons.values()) |*pokemon, i| {
        const pokemon_index = data.pokemons.at(i).key;
        try randomizeMachinesLearned(data, pokemon.*, random, pref, data.tms, pokemon.tms, &pokemon.tms_learned);
        try randomizeMachinesLearned(data, pokemon.*, random, pref, data.hms, pokemon.hms, &pokemon.hms_learned);
    }
}

fn randomizeMachinesLearned(
    data: Data,
    pokemon: Pokemon,
    random: *rand.Random,
    pref: Preference,
    machines: Machines,
    have: Set,
    learned: *Set,
) !void {
    const allocator = data.strings.allocator;
    for (have.span()) |range| {
        var machine = range.start;
        while (machine <= range.end) : (machine += 1) switch (pref) {
            .random => if (random.boolean()) {
                _ = try learned.put(allocator, machine);
            } else {
                _ = try learned.remove(allocator, machine);
            },
            .stab => {
                const low_chance = 0.1;
                const chance: f64 = blk: {
                    const index = machines.get(machine) orelse break :blk low_chance;
                    const move = data.moves.get(index.*) orelse break :blk low_chance;
                    const move_type = move.type orelse break :blk low_chance;
                    if (!pokemon.types.exists(move_type))
                        break :blk low_chance;

                    // Yay the move is stab. Give it a higher chance.
                    break :blk @as(f64, 1.0 - low_chance);
                };

                if (random.float(f64) < chance)
                    _ = try learned.put(allocator, machine)
                else
                    _ = try learned.remove(allocator, machine);
            },
        };
    }
}

const Set = util.container.IntSet.Unmanaged(usize);
const Pokemons = util.container.IntMap.Unmanaged(usize, Pokemon);
const Machines = util.container.IntMap.Unmanaged(usize, usize);
//const LvlUpMoves = std.AutoHashMap(usize, LvlUpMove);
const Moves = util.container.IntMap.Unmanaged(usize, Move);

const Data = struct {
    strings: std.StringHashMap(usize),
    pokemons: Pokemons = Pokemons{},
    moves: Moves = Moves{},
    tms: Machines = Machines{},
    hms: Machines = Machines{},

    fn string(d: *Data, str: []const u8) !usize {
        const res = try d.strings.getOrPut(str);
        if (!res.found_existing) {
            res.kv.key = try mem.dupe(d.strings.allocator, u8, str);
            res.kv.value = d.strings.count() - 1;
        }
        return res.kv.value;
    }
};

const Pokemon = struct {
    types: Set = Set{},
    tms_learned: Set = Set{},
    tms: Set = Set{},
    hms_learned: Set = Set{},
    hms: Set = Set{},
    //lvl_up_moves: LvlUpMoves
};

const LvlUpMove = struct {
    level: ?u16 = null,
    id: ?usize = null,
};

const Move = struct {
    power: ?usize = null,
    type: ?usize = null,
};

test "tm35-rand-learned-moves" {
    const result_prefix =
        \\.moves[0].power=10
        \\.moves[0].type=normal
        \\.moves[1].power=30
        \\.moves[1].type=grass
        \\.moves[2].power=30
        \\.moves[2].type=dragon
        \\.moves[3].power=30
        \\.moves[3].type=fire
        \\.moves[4].power=50
        \\.moves[4].type=normal
        \\.moves[5].power=70
        \\.moves[5].type=normal
        \\.tms[0]=0
        \\.tms[1]=2
        \\.tms[2]=4
        \\.hms[0]=1
        \\.hms[1]=3
        \\.hms[2]=5
        \\.pokemons[0].types[0]=normal
        \\
    ;
    const test_string = result_prefix ++
        \\.pokemons[0].tms[0]=false
        \\.pokemons[0].tms[1]=false
        \\.pokemons[0].tms[2]=false
        \\.pokemons[0].hms[0]=false
        \\.pokemons[0].hms[1]=false
        \\.pokemons[0].hms[2]=false
        \\
    ;
    util.testing.testProgram(main2, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.pokemons[0].tms[0]=true
        \\.pokemons[0].tms[1]=false
        \\.pokemons[0].tms[2]=true
        \\.pokemons[0].hms[0]=false
        \\.pokemons[0].hms[1]=true
        \\.pokemons[0].hms[2]=false
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--preference=stab" }, test_string, result_prefix ++
        \\.pokemons[0].tms[0]=true
        \\.pokemons[0].tms[1]=true
        \\.pokemons[0].tms[2]=true
        \\.pokemons[0].hms[0]=false
        \\.pokemons[0].hms[1]=false
        \\.pokemons[0].hms[2]=true
        \\
    );
}
