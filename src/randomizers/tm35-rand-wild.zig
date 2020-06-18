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
        clap.parseParam("-h, --help                 Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-s, --seed <NUM>           The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-t, --simular-total-stats  Replaced wild Pokémons should have simular total stats.                                   ") catch unreachable,
        clap.parseParam("-v, --version              Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-rand-wild ");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Randomizes wild Pokémon encounters.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

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

    const simular_total_stats = args.flag("--simular-total-stats");

    var line_buf = std.ArrayList(u8).init(allocator);
    var data = Data{
        .types = std.StringHashMap(usize).init(allocator),
        .areas = std.StringHashMap(usize).init(allocator),
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

    randomize(data, seed, simular_total_stats) catch |err| return errors.randErr(stdio.err, err);

    for (data.zones.values()) |zone, i| {
        const zone_i = data.zones.at(i).key;

        var area_iter = data.areas.iterator();
        while (area_iter.next()) |area_kv| {
            const area_name = area_kv.key;
            const area_id = area_kv.value;
            const area = zone.wild_areas.get(area_id) orelse continue;

            for (area.pokemons.values()) |*pokemon, j| {
                const poke_i = area.pokemons.at(j).key;
                if (pokemon.min_level) |l|
                    stdio.out.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", .{ zone_i, area_name, poke_i, l }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
                if (pokemon.max_level) |l|
                    stdio.out.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", .{ zone_i, area_name, poke_i, l }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
                if (pokemon.species) |s|
                    stdio.out.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", .{ zone_i, area_name, poke_i, s }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            }
        }
    }

    return 0;
}

fn parseLine(data: *Data, str: []const u8) !bool {
    const sw = parse.Swhash(16);
    const m = sw.match;
    const c = sw.case;
    const allocator = data.types.allocator;
    var p = parse.MutParser{ .str = str };

    switch (m(try p.parse(parse.anyField))) {
        c("pokemons") => {
            const index = try p.parse(parse.index);
            const pokemon = try data.pokemons.getOrPutValue(allocator, index, Pokemon{});

            switch (m(try p.parse(parse.anyField))) {
                c("catch_rate") => pokemon.catch_rate = try p.parse(parse.usizev),
                c("stats") => switch (m(try p.parse(parse.anyField))) {
                    c("hp") => pokemon.hp = try p.parse(parse.u8v),
                    c("attack") => pokemon.attack = try p.parse(parse.u8v),
                    c("defense") => pokemon.defense = try p.parse(parse.u8v),
                    c("speed") => pokemon.speed = try p.parse(parse.u8v),
                    c("sp_attack") => pokemon.sp_attack = try p.parse(parse.u8v),
                    c("sp_defense") => pokemon.sp_defense = try p.parse(parse.u8v),
                    else => return true,
                },
                // TODO: We're not using type information for anything yet
                c("types") => {
                    _ = try p.parse(parse.index);
                    const type_name = try p.parse(parse.strv);
                    _ = try pokemon.types.put(allocator, try getStringId(&data.types, type_name));
                },
                else => return true,
            }
        },
        c("zones") => {
            const zone_index = try p.parse(parse.index);
            const zone = try data.zones.getOrPutValue(allocator, zone_index, Zone{});
            try p.parse(comptime parse.field("wild"));
            const area_name = try p.parse(parse.anyField);

            const area_id = try getStringId(&data.areas, area_name);
            const area = try zone.wild_areas.getOrPutValue(allocator, area_id, WildArea{});

            try p.parse(comptime parse.field("pokemons"));
            const poke_index = try p.parse(parse.index);
            const pokemon = try area.pokemons.getOrPutValue(allocator, poke_index, WildPokemon{});

            // TODO: We're not using min/max level for anything yet
            switch (m(try p.parse(parse.anyField))) {
                c("min_level") => pokemon.min_level = try p.parse(parse.u8v),
                c("max_level") => pokemon.max_level = try p.parse(parse.u8v),
                c("species") => pokemon.species = try p.parse(parse.usizev),
                else => return true,
            }

            return false;
        },
        else => return true,
    }

    return true;
}

fn randomize(data: Data, seed: u64, simular_total_stats: bool) !void {
    const allocator = data.types.allocator;
    const random = &rand.DefaultPrng.init(seed).random;
    var simular = std.ArrayList(usize).init(allocator);

    const species = try data.species();
    const species_max = species.count();

    for (data.zones.values()) |zone| {
        for (zone.wild_areas.values()) |area| {
            for (area.pokemons.values()) |*wild_pokemon| {
                const old_species = wild_pokemon.species orelse continue;

                if (simular_total_stats) blk: {
                    // If we don't know what the old Pokemon was, then we can't do simular_total_stats.
                    // We therefor just pick a random pokemon and continue.
                    const pokemon = data.pokemons.get(old_species) orelse {
                        wild_pokemon.species = species.at(random.intRangeLessThan(usize, 0, species_max));
                        break :blk;
                    };

                    var stats: [Pokemon.stats.len]u8 = undefined;
                    var min = @intCast(i64, sum(u8, pokemon.toBuf(&stats)));
                    var max = min;

                    simular.resize(0) catch unreachable;
                    while (simular.items.len < 5) {
                        min -= 5;
                        max += 5;

                        for (species.span()) |range| {
                            var s = range.start;
                            while (s <= range.end) : (s += 1) {
                                const p = data.pokemons.get(s).?;
                                const total = @intCast(i64, sum(u8, p.toBuf(&stats)));
                                if (min <= total and total <= max)
                                    try simular.append(s);
                            }
                        }
                    }

                    wild_pokemon.species = simular.items[random.intRangeLessThan(usize, 0, simular.items.len)];
                } else {
                    wild_pokemon.species = species.at(random.intRangeLessThan(usize, 0, species_max));
                }
            }
        }
    }
}

fn SumReturn(comptime T: type) type {
    return switch (@typeInfo(T)) {
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

const Set = util.container.IntSet.Unmanaged(usize);
const Pokemons = util.container.IntMap.Unmanaged(usize, Pokemon);
const Zones = util.container.IntMap.Unmanaged(usize, Zone);
const WildAreas = util.container.IntMap.Unmanaged(usize, WildArea);
const WildPokemons = util.container.IntMap.Unmanaged(usize, WildPokemon);

fn getStringId(map: *std.StringHashMap(usize), str: []const u8) !usize {
    const res = try map.getOrPut(str);
    if (!res.found_existing) {
        res.kv.key = try mem.dupe(map.allocator, u8, str);
        res.kv.value = map.count() - 1;
    }
    return res.kv.value;
}

const Data = struct {
    areas: std.StringHashMap(usize),
    types: std.StringHashMap(usize),
    pokemons: Pokemons = Pokemons{},
    zones: Zones = Zones{},

    fn species(d: Data) !Set {
        var res = Set{};
        errdefer res.deinit(d.allocator());

        for (d.pokemons.values()) |pokemon, i| {
            // We shouldn't pick Pokemon with 0 catch rate as they tend to be
            // Pokemon not meant to be used in the standard game.
            // Pokemons from the film studio in bw2 have 0 catch rate.
            if (pokemon.catch_rate == 0)
                continue;
            _ = try res.put(d.allocator(), d.pokemons.at(i).key);
        }

        return res;
    }

    fn allocator(d: Data) *mem.Allocator {
        return d.types.allocator;
    }
};

const Zone = struct {
    wild_areas: WildAreas = WildAreas{},
};

const WildArea = struct {
    pokemons: WildPokemons = WildPokemons{},
};

const WildPokemon = struct {
    min_level: ?u8 = null,
    max_level: ?u8 = null,
    species: ?usize = null,
};

const Pokemon = struct {
    hp: ?u8 = null,
    attack: ?u8 = null,
    defense: ?u8 = null,
    speed: ?u8 = null,
    sp_attack: ?u8 = null,
    sp_defense: ?u8 = null,
    catch_rate: usize = 1,
    types: Set = Set{},

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
        \\.pokemons[0].catch_rate=10
        \\.pokemons[1].stats.hp=12
        \\.pokemons[1].stats.attack=12
        \\.pokemons[1].stats.defense=12
        \\.pokemons[1].stats.speed=12
        \\.pokemons[1].stats.sp_attack=12
        \\.pokemons[1].stats.sp_defense=12
        \\.pokemons[1].catch_rate=10
        \\.pokemons[2].stats.hp=14
        \\.pokemons[2].stats.attack=14
        \\.pokemons[2].stats.defense=14
        \\.pokemons[2].stats.speed=14
        \\.pokemons[2].stats.sp_attack=14
        \\.pokemons[2].stats.sp_defense=14
        \\.pokemons[2].catch_rate=10
        \\.pokemons[3].stats.hp=16
        \\.pokemons[3].stats.attack=16
        \\.pokemons[3].stats.defense=16
        \\.pokemons[3].stats.speed=16
        \\.pokemons[3].stats.sp_attack=16
        \\.pokemons[3].stats.sp_defense=16
        \\.pokemons[3].catch_rate=10
        \\.pokemons[4].stats.hp=18
        \\.pokemons[4].stats.attack=18
        \\.pokemons[4].stats.defense=18
        \\.pokemons[4].stats.speed=18
        \\.pokemons[4].stats.sp_attack=18
        \\.pokemons[4].stats.sp_defense=18
        \\.pokemons[4].catch_rate=10
        \\.pokemons[5].stats.hp=20
        \\.pokemons[5].stats.attack=20
        \\.pokemons[5].stats.defense=20
        \\.pokemons[5].stats.speed=20
        \\.pokemons[5].stats.sp_attack=20
        \\.pokemons[5].stats.sp_defense=20
        \\.pokemons[5].catch_rate=10
        \\.pokemons[6].stats.hp=22
        \\.pokemons[6].stats.attack=22
        \\.pokemons[6].stats.defense=22
        \\.pokemons[6].stats.speed=22
        \\.pokemons[6].stats.sp_attack=22
        \\.pokemons[6].stats.sp_defense=22
        \\.pokemons[6].catch_rate=10
        \\.pokemons[7].stats.hp=24
        \\.pokemons[7].stats.attack=24
        \\.pokemons[7].stats.defense=24
        \\.pokemons[7].stats.speed=24
        \\.pokemons[7].stats.sp_attack=24
        \\.pokemons[7].stats.sp_defense=24
        \\.pokemons[7].catch_rate=10
        \\.pokemons[8].stats.hp=28
        \\.pokemons[8].stats.attack=28
        \\.pokemons[8].stats.defense=28
        \\.pokemons[8].stats.speed=28
        \\.pokemons[8].stats.sp_attack=28
        \\.pokemons[8].stats.sp_defense=28
        \\.pokemons[8].catch_rate=10
        \\.pokemons[9].stats.hp=28
        \\.pokemons[9].stats.attack=28
        \\.pokemons[9].stats.defense=28
        \\.pokemons[9].stats.speed=28
        \\.pokemons[9].stats.sp_attack=28
        \\.pokemons[9].stats.sp_defense=28
        \\.pokemons[9].catch_rate=0
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
    util.testing.testProgram(main2, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.zones[0].wild.grass.pokemons[0].species=2
        \\.zones[0].wild.grass.pokemons[1].species=0
        \\.zones[0].wild.grass.pokemons[2].species=0
        \\.zones[0].wild.grass.pokemons[3].species=2
        \\.zones[1].wild.grass.pokemons[0].species=3
        \\.zones[1].wild.grass.pokemons[1].species=7
        \\.zones[1].wild.grass.pokemons[2].species=1
        \\.zones[1].wild.grass.pokemons[3].species=6
        \\.zones[2].wild.grass.pokemons[0].species=6
        \\.zones[2].wild.grass.pokemons[1].species=6
        \\.zones[2].wild.grass.pokemons[2].species=8
        \\.zones[2].wild.grass.pokemons[3].species=8
        \\.zones[3].wild.grass.pokemons[0].species=0
        \\.zones[3].wild.grass.pokemons[1].species=0
        \\.zones[3].wild.grass.pokemons[2].species=4
        \\.zones[3].wild.grass.pokemons[3].species=7
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--simular-total-stats" }, test_string, result_prefix ++
        \\.zones[0].wild.grass.pokemons[0].species=0
        \\.zones[0].wild.grass.pokemons[1].species=0
        \\.zones[0].wild.grass.pokemons[2].species=0
        \\.zones[0].wild.grass.pokemons[3].species=0
        \\.zones[1].wild.grass.pokemons[0].species=0
        \\.zones[1].wild.grass.pokemons[1].species=1
        \\.zones[1].wild.grass.pokemons[2].species=0
        \\.zones[1].wild.grass.pokemons[3].species=0
        \\.zones[2].wild.grass.pokemons[0].species=0
        \\.zones[2].wild.grass.pokemons[1].species=0
        \\.zones[2].wild.grass.pokemons[2].species=1
        \\.zones[2].wild.grass.pokemons[3].species=1
        \\.zones[3].wild.grass.pokemons[0].species=0
        \\.zones[3].wild.grass.pokemons[1].species=0
        \\.zones[3].wild.grass.pokemons[2].species=0
        \\.zones[3].wild.grass.pokemons[3].species=1
        \\
    );
}
