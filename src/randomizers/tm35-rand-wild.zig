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
        clap.parseParam("-h, --help                 Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-s, --seed <INT>           The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-t, --simular-total-stats  Replaced wild Pokémons should have simular total stats.                                   ") catch unreachable,
        clap.parseParam("-v, --version              Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-rand-wild ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nRandomizes wild Pokémon encounters.\n" ++
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
    const simular_total_stats = args.flag("--simular-total-stats");

    var fifo = util.read.Fifo(.Dynamic).init(allocator);
    var data = Data{};
    while (util.read.line(stdio.in, &fifo) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        parseLine(&data, strings, allocator, line) catch |err| switch (err) {
            error.OutOfMemory => return exit.allocErr(stdio.err),
            error.ParseError => stdio.out.print("{}\n", .{line}) catch |err2| {
                return exit.stdoutErr(stdio.err, err2);
            },
        };
    }

    randomize(data, allocator, seed, simular_total_stats) catch |err| return exit.randErr(stdio.err, err);

    for (data.wild_pokemons.values()) |zone, i| {
        const zone_i = data.wild_pokemons.at(i).key;

        for (zone.wild_areas.values()) |area, j| {
            const area_id = zone.wild_areas.at(j).key;
            const area_name = strings.get(area_id);

            for (area.pokemons.values()) |*pokemon, k| {
                const poke_i = area.pokemons.at(k).key;
                if (pokemon.min_level) |l|
                    stdio.out.print(".wild_pokemons[{}].{}.pokemons[{}].min_level={}\n", .{ zone_i, area_name, poke_i, l }) catch |err| return exit.stdoutErr(stdio.err, err);
                if (pokemon.max_level) |l|
                    stdio.out.print(".wild_pokemons[{}].{}.pokemons[{}].max_level={}\n", .{ zone_i, area_name, poke_i, l }) catch |err| return exit.stdoutErr(stdio.err, err);
                if (pokemon.species) |s|
                    stdio.out.print(".wild_pokemons[{}].{}.pokemons[{}].species={}\n", .{ zone_i, area_name, poke_i, s }) catch |err| return exit.stdoutErr(stdio.err, err);
            }
        }
    }

    return 0;
}

fn parseLine(
    data: *Data,
    strings: *util.StringCache,
    allocator: *mem.Allocator,
    str: []const u8,
) !void {
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
        c("pokemons") => {
            const index = try p.parse(parse.index);
            const pokemon = try data.pokemons.getOrPutValue(allocator, index, Pokemon{});

            switch (m(try p.parse(parse.anyField))) {
                c("catch_rate") => pokemon.catch_rate = try p.parse(parse.usizev),
                c("pokedex_entry") => pokemon.pokedex_entry = try p.parse(parse.usizev),
                c("stats") => switch (m(try p.parse(parse.anyField))) {
                    c("hp") => pokemon.stats[0] = try p.parse(parse.u8v),
                    c("attack") => pokemon.stats[1] = try p.parse(parse.u8v),
                    c("defense") => pokemon.stats[2] = try p.parse(parse.u8v),
                    c("speed") => pokemon.stats[3] = try p.parse(parse.u8v),
                    c("sp_attack") => pokemon.stats[4] = try p.parse(parse.u8v),
                    c("sp_defense") => pokemon.stats[5] = try p.parse(parse.u8v),
                    else => return error.ParseError,
                },
                // TODO: We're not using type information for anything yet
                c("types") => {
                    _ = try p.parse(parse.index);
                    _ = try pokemon.types.put(allocator, try p.parse(parse.usizev));
                },
                else => return error.ParseError,
            }
            return error.ParseError;
        },
        c("wild_pokemons") => {
            const zone_index = try p.parse(parse.index);
            const zone = try data.wild_pokemons.getOrPutValue(allocator, zone_index, Zone{});
            const area_name = try p.parse(parse.anyField);

            const area_id = try strings.put(area_name);
            const area = try zone.wild_areas.getOrPutValue(allocator, area_id, WildArea{});

            try p.parse(comptime parse.field("pokemons"));
            const poke_index = try p.parse(parse.index);
            const pokemon = try area.pokemons.getOrPutValue(allocator, poke_index, WildPokemon{});

            // TODO: We're not using min/max level for anything yet
            switch (m(try p.parse(parse.anyField))) {
                c("min_level") => pokemon.min_level = try p.parse(parse.u8v),
                c("max_level") => pokemon.max_level = try p.parse(parse.u8v),
                c("species") => pokemon.species = try p.parse(parse.usizev),
                else => return error.ParseError,
            }

            return;
        },
        else => return error.ParseError,
    }
    unreachable;
}

fn randomize(data: Data, allocator: *mem.Allocator, seed: u64, simular_total_stats: bool) !void {
    const random = &rand.DefaultPrng.init(seed).random;
    var simular = std.ArrayList(usize).init(allocator);

    const species = try data.pokedexPokemons(allocator);
    const species_max = species.count();

    for (data.wild_pokemons.values()) |zone| {
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

                    var min = @intCast(i64, sum(u8, &pokemon.stats));
                    var max = min;

                    simular.resize(0) catch unreachable;
                    while (simular.items.len < 5) {
                        min -= 5;
                        max += 5;

                        for (species.span()) |range| {
                            var s = range.start;
                            while (s <= range.end) : (s += 1) {
                                const p = data.pokemons.get(s).?;
                                const total = @intCast(i64, sum(u8, &p.stats));
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

const Data = struct {
    pokedex: Set = Set{},
    pokemons: Pokemons = Pokemons{},
    wild_pokemons: Zones = Zones{},

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
    stats: [6]u8 = [_]u8{0} ** 6,
    catch_rate: usize = 1,
    types: Set = Set{},
    pokedex_entry: usize = math.maxInt(usize),
};

test "tm35-rand-wild" {
    const result_prefix =
        \\.pokemons[0].pokedex_entry=0
        \\.pokemons[0].stats.hp=10
        \\.pokemons[0].stats.attack=10
        \\.pokemons[0].stats.defense=10
        \\.pokemons[0].stats.speed=10
        \\.pokemons[0].stats.sp_attack=10
        \\.pokemons[0].stats.sp_defense=10
        \\.pokemons[0].catch_rate=10
        \\.pokemons[1].pokedex_entry=1
        \\.pokemons[1].stats.hp=12
        \\.pokemons[1].stats.attack=12
        \\.pokemons[1].stats.defense=12
        \\.pokemons[1].stats.speed=12
        \\.pokemons[1].stats.sp_attack=12
        \\.pokemons[1].stats.sp_defense=12
        \\.pokemons[1].catch_rate=10
        \\.pokemons[2].pokedex_entry=2
        \\.pokemons[2].stats.hp=14
        \\.pokemons[2].stats.attack=14
        \\.pokemons[2].stats.defense=14
        \\.pokemons[2].stats.speed=14
        \\.pokemons[2].stats.sp_attack=14
        \\.pokemons[2].stats.sp_defense=14
        \\.pokemons[2].catch_rate=10
        \\.pokemons[3].pokedex_entry=3
        \\.pokemons[3].stats.hp=16
        \\.pokemons[3].stats.attack=16
        \\.pokemons[3].stats.defense=16
        \\.pokemons[3].stats.speed=16
        \\.pokemons[3].stats.sp_attack=16
        \\.pokemons[3].stats.sp_defense=16
        \\.pokemons[3].catch_rate=10
        \\.pokemons[4].pokedex_entry=4
        \\.pokemons[4].stats.hp=18
        \\.pokemons[4].stats.attack=18
        \\.pokemons[4].stats.defense=18
        \\.pokemons[4].stats.speed=18
        \\.pokemons[4].stats.sp_attack=18
        \\.pokemons[4].stats.sp_defense=18
        \\.pokemons[4].catch_rate=10
        \\.pokemons[5].pokedex_entry=5
        \\.pokemons[5].stats.hp=20
        \\.pokemons[5].stats.attack=20
        \\.pokemons[5].stats.defense=20
        \\.pokemons[5].stats.speed=20
        \\.pokemons[5].stats.sp_attack=20
        \\.pokemons[5].stats.sp_defense=20
        \\.pokemons[5].catch_rate=10
        \\.pokemons[6].pokedex_entry=6
        \\.pokemons[6].stats.hp=22
        \\.pokemons[6].stats.attack=22
        \\.pokemons[6].stats.defense=22
        \\.pokemons[6].stats.speed=22
        \\.pokemons[6].stats.sp_attack=22
        \\.pokemons[6].stats.sp_defense=22
        \\.pokemons[6].catch_rate=10
        \\.pokemons[7].pokedex_entry=7
        \\.pokemons[7].stats.hp=24
        \\.pokemons[7].stats.attack=24
        \\.pokemons[7].stats.defense=24
        \\.pokemons[7].stats.speed=24
        \\.pokemons[7].stats.sp_attack=24
        \\.pokemons[7].stats.sp_defense=24
        \\.pokemons[7].catch_rate=10
        \\.pokemons[8].pokedex_entry=8
        \\.pokemons[8].stats.hp=28
        \\.pokemons[8].stats.attack=28
        \\.pokemons[8].stats.defense=28
        \\.pokemons[8].stats.speed=28
        \\.pokemons[8].stats.sp_attack=28
        \\.pokemons[8].stats.sp_defense=28
        \\.pokemons[8].catch_rate=10
        \\.pokemons[9].pokedex_entry=9
        \\.pokemons[9].stats.hp=28
        \\.pokemons[9].stats.attack=28
        \\.pokemons[9].stats.defense=28
        \\.pokemons[9].stats.speed=28
        \\.pokemons[9].stats.sp_attack=28
        \\.pokemons[9].stats.sp_defense=28
        \\.pokemons[9].catch_rate=0
        \\.pokedex[0].field
        \\.pokedex[1].field
        \\.pokedex[2].field
        \\.pokedex[3].field
        \\.pokedex[4].field
        \\.pokedex[5].field
        \\.pokedex[6].field
        \\.pokedex[7].field
        \\.pokedex[8].field
        \\.pokedex[9].field
        \\
    ;

    const test_string = result_prefix ++
        \\.wild_pokemons[0].grass.pokemons[0].species=0
        \\.wild_pokemons[0].grass.pokemons[1].species=0
        \\.wild_pokemons[0].grass.pokemons[2].species=0
        \\.wild_pokemons[0].grass.pokemons[3].species=0
        \\.wild_pokemons[1].grass.pokemons[0].species=0
        \\.wild_pokemons[1].grass.pokemons[1].species=0
        \\.wild_pokemons[1].grass.pokemons[2].species=0
        \\.wild_pokemons[1].grass.pokemons[3].species=0
        \\.wild_pokemons[2].grass.pokemons[0].species=0
        \\.wild_pokemons[2].grass.pokemons[1].species=0
        \\.wild_pokemons[2].grass.pokemons[2].species=0
        \\.wild_pokemons[2].grass.pokemons[3].species=0
        \\.wild_pokemons[3].grass.pokemons[0].species=0
        \\.wild_pokemons[3].grass.pokemons[1].species=0
        \\.wild_pokemons[3].grass.pokemons[2].species=0
        \\.wild_pokemons[3].grass.pokemons[3].species=0
        \\
    ;
    util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.wild_pokemons[0].grass.pokemons[0].species=2
        \\.wild_pokemons[0].grass.pokemons[1].species=0
        \\.wild_pokemons[0].grass.pokemons[2].species=0
        \\.wild_pokemons[0].grass.pokemons[3].species=2
        \\.wild_pokemons[1].grass.pokemons[0].species=3
        \\.wild_pokemons[1].grass.pokemons[1].species=7
        \\.wild_pokemons[1].grass.pokemons[2].species=1
        \\.wild_pokemons[1].grass.pokemons[3].species=6
        \\.wild_pokemons[2].grass.pokemons[0].species=6
        \\.wild_pokemons[2].grass.pokemons[1].species=6
        \\.wild_pokemons[2].grass.pokemons[2].species=8
        \\.wild_pokemons[2].grass.pokemons[3].species=8
        \\.wild_pokemons[3].grass.pokemons[0].species=0
        \\.wild_pokemons[3].grass.pokemons[1].species=0
        \\.wild_pokemons[3].grass.pokemons[2].species=4
        \\.wild_pokemons[3].grass.pokemons[3].species=7
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--simular-total-stats" }, test_string, result_prefix ++
        \\.wild_pokemons[0].grass.pokemons[0].species=0
        \\.wild_pokemons[0].grass.pokemons[1].species=0
        \\.wild_pokemons[0].grass.pokemons[2].species=0
        \\.wild_pokemons[0].grass.pokemons[3].species=0
        \\.wild_pokemons[1].grass.pokemons[0].species=0
        \\.wild_pokemons[1].grass.pokemons[1].species=1
        \\.wild_pokemons[1].grass.pokemons[2].species=0
        \\.wild_pokemons[1].grass.pokemons[3].species=0
        \\.wild_pokemons[2].grass.pokemons[0].species=0
        \\.wild_pokemons[2].grass.pokemons[1].species=0
        \\.wild_pokemons[2].grass.pokemons[2].species=1
        \\.wild_pokemons[2].grass.pokemons[3].species=1
        \\.wild_pokemons[3].grass.pokemons[0].species=0
        \\.wild_pokemons[3].grass.pokemons[1].species=0
        \\.wild_pokemons[3].grass.pokemons[2].species=0
        \\.wild_pokemons[3].grass.pokemons[3].species=1
        \\
    );
}
