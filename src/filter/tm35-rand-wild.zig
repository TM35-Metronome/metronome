const clap = @import("clap");
const common = @import("tm35-common");
const fun = @import("fun");
const gba = @import("gba.zig");
const gen5 = @import("gen5-types.zig");
const nds = @import("nds.zig");
const std = @import("std");
const builtin = @import("builtin");
const format = @import("format");

const bits = fun.bits;
const debug = std.debug;
const heap = std.heap;
const io = std.io;
const fs = std.fs;
const math = std.math;
const mem = std.mem;
const fmt = std.fmt;
const os = std.os;
const rand = std.rand;
const slice = fun.generic.slice;

const BufInStream = io.BufferedInStream(fs.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);
const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = [_]Param{
    Param{
        .id = "display this help text and exit",
        .names = Names{ .short = 'h', .long = "help" },
    },
    Param{
        .id = "replaced party members should have simular total stats",
        .names = Names{ .short = 't', .long = "simular-total-stats" },
    },
    Param{
        .id = "the seed used to randomize stats",
        .names = Names{ .short = 's', .long = "seed" },
        .takes_value = true,
    },
    Param{
        .id = "",
        .takes_value = true,
    },
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-wild [OPTION]...
        \\Reads the tm35 format from stdin and randomizes wild pokemon encounters.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() !void {
    const unbuf_stdout = &(try io.getStdOut()).outStream().stream;
    var buf_stdout = BufOutStream.init(unbuf_stdout);
    defer buf_stdout.flush() catch {};

    const stderr = &(try io.getStdErr()).outStream().stream;
    const stdin = &BufInStream.init(&(try std.io.getStdIn()).inStream().stream).stream;
    const stdout = &buf_stdout.stream;

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
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

    const simular_total_stats = args.flag("--simular-total-stats");
    const seed = blk: {
        const seed_str = args.option("--seed") orelse {
            var buf: [8]u8 = undefined;
            try std.os.getrandom(buf[0..]);
            break :blk mem.readInt(u64, &buf, builtin.Endian.Little);
        };

        break :blk try fmt.parseUnsigned(u64, seed_str, 10);
    };

    const data = try readData(allocator, stdin, stdout);
    try randomize(data, seed, simular_total_stats);

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
                    try stdout.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", zone_i, area_name, poke_i, l);
                if (pokemon.max_level) |l|
                    try stdout.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", zone_i, area_name, poke_i, l);
                if (pokemon.species) |s|
                    try stdout.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", zone_i, area_name, poke_i, s);
            }
        }
    }
}

fn readData(allocator: *mem.Allocator, in_stream: var, out_stream: var) !Data {
    var res = Data{
        .pokemon_list = std.ArrayList(usize).init(allocator),
        .pokemons = Pokemons.init(allocator),
        .zones = Zones.init(allocator),
    };

    var line_buf = try std.Buffer.initSize(allocator, 0);
    defer line_buf.deinit();

    var line: usize = 1;
    while (in_stream.readUntilDelimiterBuffer(&line_buf, '\n', 10000)) : (line += 1) {
        const str = mem.trimRight(u8, line_buf.toSlice(), "\r\n");
        const print_line = parseLine(&res, str) catch true;
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

    if (parser.eatField("pokemons")) |_| {
        const poke_index = try parser.eatIndex();
        const poke_entry = try data.pokemons.getOrPut(poke_index);
        if (!poke_entry.found_existing) {
            poke_entry.kv.value = Pokemon.init(allocator);
            try data.pokemon_list.append(poke_index);
        }
        const pokemon = &poke_entry.kv.value;

        if (parser.eatField("starts")) {
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
        const area_name = try parser.eatAnyField();

        // To keep it simple, we just leak a shit ton of type names here.
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

                    // TODO: We could probably reuse this ArrayList
                    var simular = std.ArrayList(usize).init(allocator);
                    var stats: [Pokemon.stats.len]u8 = undefined;
                    var min = @intCast(i64, sum(u8, pokemon.toBuf(&stats)));
                    var max = min;

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
        builtin.TypeId.Int => u64,
        builtin.TypeId.Float => f64,
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
const WildAreas = std.AutoHashMap([]const u8, WildArea);
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
