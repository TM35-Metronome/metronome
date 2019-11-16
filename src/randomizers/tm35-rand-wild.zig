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
        clap.parseParam("-h, --help                 Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-s, --seed <NUM>           The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-t, --simular-total-stats  Replaced wild Pokémons should have simular total stats.                                   ") catch unreachable,
        clap.parseParam("-v, --version              Output version information and exit.                                                      ") catch unreachable,
        Param{ .takes_value = true },
    };
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-wild [-htv] [-s <NUM>]
        \\Randomizes wild Pokémon encounters.
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

    const simular_total_stats = args.flag("--simular-total-stats");

    var line_buf = std.Buffer.initSize(allocator, 0) catch |err| return errors.allocErr(stdio.err);
    var data = Data{
        .pokemon_list = std.ArrayList(usize).init(allocator),
        .pokemons = Pokemons.init(allocator),
        .zones = Zones.init(allocator),
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

    randomize(data, seed, simular_total_stats) catch |err| return errors.randErr(stdio.err, err);

    var zone_iter = data.zones.iterator();
    while (zone_iter.next()) |zone_kw| {
        const zone_i = zone_kw.key;
        const zone = zone_kw.value;

        var area_iter = zone.wild_areas.iterator();
        while (area_iter.next()) |area_kw| {
            const area_name = area_kw.key;
            const area = area_kw.value;

            var poke_iter = area.pokemons.iterator();
            while (poke_iter.next()) |poke_kw| {
                const poke_i = poke_kw.key;
                const pokemon = poke_kw.value;

                if (pokemon.min_level) |l|
                    stdio.out.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", zone_i, area_name, poke_i, l) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
                if (pokemon.max_level) |l|
                    stdio.out.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", zone_i, area_name, poke_i, l) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
                if (pokemon.species) |s|
                    stdio.out.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", zone_i, area_name, poke_i, s) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            }
        }
    }

    return 0;
}

fn parseLine(data: *Data, str: []const u8) !bool {
    const allocator = data.pokemons.allocator;
    var parser = format.Parser{ .str = str };

    if (parser.eatField("pokemons")) |_| {
        const poke_index = try parser.eatIndex();
        const poke_entry = try data.pokemons.getOrPut(poke_index);
        if (!poke_entry.found_existing) {
            poke_entry.kv.value = Pokemon.init(allocator);
            try data.pokemon_list.append(poke_index);
        }
        const pokemon = &poke_entry.kv.value;

        if (parser.eatField("stats")) {
            if (parser.eatField("hp")) |_| {
                pokemon.hp = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("attack")) |_| {
                pokemon.attack = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("defense")) |_| {
                pokemon.defense = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("speed")) |_| {
                pokemon.speed = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_attack")) |_| {
                pokemon.sp_attack = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_defense")) |_| {
                pokemon.sp_defense = try parser.eatUnsignedValue(u8, 10);
            } else |_| {}
            // TODO: We're not using type information for anything yet
        } else |_| if (parser.eatField("types")) |_| {
            _ = try parser.eatIndex();

            // To keep it simple, we just leak a shit ton of type names here.
            const type_name = try mem.dupe(allocator, u8, try parser.eatValue());
            try pokemon.types.append(type_name);
        } else |_| {}
    } else |_| if (parser.eatField("zones")) |_| {
        const zone_index = try parser.eatIndex();
        const zone_entry = try data.zones.getOrPutValue(zone_index, Zone.init(allocator));
        const zone = &zone_entry.value;
        try parser.eatField("wild");
        const area_name = try parser.eatAnyField();

        // To keep it simple, we just leak a shit ton of area names here
        const area_name_dupe = try mem.dupe(allocator, u8, area_name);
        const area_entry = try zone.wild_areas.getOrPutValue(area_name_dupe, WildArea.init(allocator));
        const area = &area_entry.value;

        try parser.eatField("pokemons");
        const poke_index = try parser.eatIndex();
        const poke_entry = try area.pokemons.getOrPutValue(poke_index, WildPokemon{
            .min_level = null,
            .max_level = null,
            .species = null,
        });
        const pokemon = &poke_entry.value;

        // TODO: We're not using min/max level for anything yet
        if (parser.eatField("min_level")) |_| {
            pokemon.min_level = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("max_level")) |_| {
            pokemon.max_level = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("species")) |_| {
            pokemon.species = try parser.eatUnsignedValue(usize, 10);
        } else |_| {
            return true;
        }

        return false;
    } else |_| {}

    return true;
}

fn randomize(data: Data, seed: u64, simular_total_stats: bool) !void {
    const allocator = data.pokemons.allocator;
    const random = &rand.DefaultPrng.init(seed).random;
    var simular = std.ArrayList(usize).init(allocator);

    var zone_iter = data.zones.iterator();
    while (zone_iter.next()) |zone_kw| {
        const zone_i = zone_kw.key;
        const zone = zone_kw.value;

        var area_iter = zone.wild_areas.iterator();
        while (area_iter.next()) |area_kw| {
            const area_name = area_kw.key;
            const area = area_kw.value;

            var poke_iter = area.pokemons.iterator();
            while (poke_iter.next()) |poke_kw| {
                const poke_i = poke_kw.key;
                const wild_pokemon = &poke_kw.value;
                const old_species = wild_pokemon.species orelse continue;

                const pick_from = data.pokemon_list.toSlice();
                if (simular_total_stats) blk: {
                    // If we don't know what the old Pokemon was, then we can't do simular_total_stats.
                    // We therefor just pick a random pokemon and continue.
                    const poke_kv = data.pokemons.get(old_species) orelse {
                        wild_pokemon.species = pick_from[random.range(usize, 0, pick_from.len)];
                        break :blk;
                    };
                    const pokemon = poke_kv.value;

                    var stats: [Pokemon.stats.len]u8 = undefined;
                    var min = @intCast(i64, sum(u8, pokemon.toBuf(&stats)));
                    var max = min;

                    simular.resize(0) catch unreachable;
                    while (simular.len < 5) {
                        min -= 5;
                        max += 5;

                        for (pick_from) |s| {
                            const p = data.pokemons.get(s).?.value;
                            const total = @intCast(i64, sum(u8, p.toBuf(&stats)));
                            if (min <= total and total <= max)
                                try simular.append(s);
                        }
                    }

                    wild_pokemon.species = simular.toSlice()[random.range(usize, 0, simular.len)];
                } else {
                    wild_pokemon.species = pick_from[random.range(usize, 0, pick_from.len)];
                }
            }
        }
    }
}

fn SumReturn(comptime T: type) type {
    return switch (@typeId(T)) {
        .Int => u64,
        .Float => f64,
        else => unreachable,
    };
}

fn sum(comptime T: type, buf: []const T) SumReturn(T) {
    var res: SumReturn(T) = 0;
    for (buf) |item|
        res += item;

    return res;
}

const Pokemons = std.AutoHashMap(usize, Pokemon);
const Zones = std.AutoHashMap(usize, Zone);
const WildAreas = std.StringHashMap(WildArea);
const WildPokemons = std.AutoHashMap(usize, WildPokemon);

const Data = struct {
    pokemon_list: std.ArrayList(usize),
    pokemons: Pokemons,
    zones: Zones,
};

const Zone = struct {
    wild_areas: WildAreas,

    fn init(allocator: *mem.Allocator) Zone {
        return Zone{ .wild_areas = WildAreas.init(allocator) };
    }
};

const WildArea = struct {
    pokemons: WildPokemons,

    fn init(allocator: *mem.Allocator) WildArea {
        return WildArea{ .pokemons = WildPokemons.init(allocator) };
    }
};

const WildPokemon = struct {
    min_level: ?u8,
    max_level: ?u8,
    species: ?usize,
};

const Pokemon = struct {
    hp: ?u8,
    attack: ?u8,
    defense: ?u8,
    speed: ?u8,
    sp_attack: ?u8,
    sp_defense: ?u8,
    types: std.ArrayList([]const u8),

    fn init(allocator: *mem.Allocator) Pokemon {
        return Pokemon{
            .hp = null,
            .attack = null,
            .defense = null,
            .speed = null,
            .sp_attack = null,
            .sp_defense = null,
            .types = std.ArrayList([]const u8).init(allocator),
        };
    }

    const stats = [_][]const u8{
        "hp",
        "attack",
        "defense",
        "speed",
        "sp_attack",
        "sp_defense",
    };

    fn toBuf(p: Pokemon, buf: *[stats.len]u8) []u8 {
        var i: usize = 0;
        inline for (stats) |stat_name| {
            if (@field(p, stat_name)) |stat| {
                buf[i] = stat;
                i += 1;
            }
        }

        return buf[0..i];
    }

    fn fromBuf(p: *Pokemon, buf: []u8) void {
        var i: usize = 0;
        inline for (stats) |stat_name| {
            if (@field(p, stat_name)) |*stat| {
                stat.* = buf[i];
                i += 1;
            }
        }
    }
};

test "tm35-rand-wild" {
    const result_prefix =
        \\.pokemons[0].stats.hp=10
        \\.pokemons[0].stats.attack=10
        \\.pokemons[0].stats.defense=10
        \\.pokemons[0].stats.speed=10
        \\.pokemons[0].stats.sp_attack=10
        \\.pokemons[0].stats.sp_defense=10
        \\.pokemons[1].stats.hp=12
        \\.pokemons[1].stats.attack=12
        \\.pokemons[1].stats.defense=12
        \\.pokemons[1].stats.speed=12
        \\.pokemons[1].stats.sp_attack=12
        \\.pokemons[1].stats.sp_defense=12
        \\.pokemons[2].stats.hp=14
        \\.pokemons[2].stats.attack=14
        \\.pokemons[2].stats.defense=14
        \\.pokemons[2].stats.speed=14
        \\.pokemons[2].stats.sp_attack=14
        \\.pokemons[2].stats.sp_defense=14
        \\.pokemons[3].stats.hp=16
        \\.pokemons[3].stats.attack=16
        \\.pokemons[3].stats.defense=16
        \\.pokemons[3].stats.speed=16
        \\.pokemons[3].stats.sp_attack=16
        \\.pokemons[3].stats.sp_defense=16
        \\.pokemons[4].stats.hp=18
        \\.pokemons[4].stats.attack=18
        \\.pokemons[4].stats.defense=18
        \\.pokemons[4].stats.speed=18
        \\.pokemons[4].stats.sp_attack=18
        \\.pokemons[4].stats.sp_defense=18
        \\.pokemons[5].stats.hp=20
        \\.pokemons[5].stats.attack=20
        \\.pokemons[5].stats.defense=20
        \\.pokemons[5].stats.speed=20
        \\.pokemons[5].stats.sp_attack=20
        \\.pokemons[5].stats.sp_defense=20
        \\.pokemons[6].stats.hp=22
        \\.pokemons[6].stats.attack=22
        \\.pokemons[6].stats.defense=22
        \\.pokemons[6].stats.speed=22
        \\.pokemons[6].stats.sp_attack=22
        \\.pokemons[6].stats.sp_defense=22
        \\.pokemons[7].stats.hp=24
        \\.pokemons[7].stats.attack=24
        \\.pokemons[7].stats.defense=24
        \\.pokemons[7].stats.speed=24
        \\.pokemons[7].stats.sp_attack=24
        \\.pokemons[7].stats.sp_defense=24
        \\.pokemons[8].stats.hp=28
        \\.pokemons[8].stats.attack=28
        \\.pokemons[8].stats.defense=28
        \\.pokemons[8].stats.speed=28
        \\.pokemons[8].stats.sp_attack=28
        \\.pokemons[8].stats.sp_defense=28
        \\
    ;

    const test_string = result_prefix ++
        \\.zones[0].wild.grass.pokemons[0].species=0
        \\.zones[0].wild.grass.pokemons[1].species=0
        \\.zones[0].wild.grass.pokemons[2].species=0
        \\.zones[0].wild.grass.pokemons[3].species=0
        \\.zones[1].wild.grass.pokemons[0].species=0
        \\.zones[1].wild.grass.pokemons[1].species=0
        \\.zones[1].wild.grass.pokemons[2].species=0
        \\.zones[1].wild.grass.pokemons[3].species=0
        \\.zones[2].wild.grass.pokemons[0].species=0
        \\.zones[2].wild.grass.pokemons[1].species=0
        \\.zones[2].wild.grass.pokemons[2].species=0
        \\.zones[2].wild.grass.pokemons[3].species=0
        \\.zones[3].wild.grass.pokemons[0].species=0
        \\.zones[3].wild.grass.pokemons[1].species=0
        \\.zones[3].wild.grass.pokemons[2].species=0
        \\.zones[3].wild.grass.pokemons[3].species=0
        \\
    ;
    testProgram([_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.zones[3].wild.grass.pokemons[3].species=2
        \\.zones[3].wild.grass.pokemons[1].species=0
        \\.zones[3].wild.grass.pokemons[2].species=0
        \\.zones[3].wild.grass.pokemons[0].species=2
        \\.zones[1].wild.grass.pokemons[3].species=3
        \\.zones[1].wild.grass.pokemons[1].species=7
        \\.zones[1].wild.grass.pokemons[2].species=1
        \\.zones[1].wild.grass.pokemons[0].species=6
        \\.zones[2].wild.grass.pokemons[3].species=6
        \\.zones[2].wild.grass.pokemons[1].species=6
        \\.zones[2].wild.grass.pokemons[2].species=8
        \\.zones[2].wild.grass.pokemons[0].species=8
        \\.zones[0].wild.grass.pokemons[3].species=0
        \\.zones[0].wild.grass.pokemons[1].species=0
        \\.zones[0].wild.grass.pokemons[2].species=4
        \\.zones[0].wild.grass.pokemons[0].species=7
        \\
    );
    testProgram([_][]const u8{ "--seed=0", "--simular-total-stats" }, test_string, result_prefix ++
        \\.zones[3].wild.grass.pokemons[3].species=0
        \\.zones[3].wild.grass.pokemons[1].species=0
        \\.zones[3].wild.grass.pokemons[2].species=0
        \\.zones[3].wild.grass.pokemons[0].species=0
        \\.zones[1].wild.grass.pokemons[3].species=0
        \\.zones[1].wild.grass.pokemons[1].species=1
        \\.zones[1].wild.grass.pokemons[2].species=0
        \\.zones[1].wild.grass.pokemons[0].species=0
        \\.zones[2].wild.grass.pokemons[3].species=0
        \\.zones[2].wild.grass.pokemons[1].species=0
        \\.zones[2].wild.grass.pokemons[2].species=1
        \\.zones[2].wild.grass.pokemons[0].species=1
        \\.zones[0].wild.grass.pokemons[3].species=0
        \\.zones[0].wild.grass.pokemons[1].species=0
        \\.zones[0].wild.grass.pokemons[2].species=0
        \\.zones[0].wild.grass.pokemons[0].species=1
        \\
    );
}

fn testProgram(
    args: []const []const u8,
    in: []const u8,
    out: []const u8,
) void {
    var alloc_buf: [1024 * 20]u8 = undefined;
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
