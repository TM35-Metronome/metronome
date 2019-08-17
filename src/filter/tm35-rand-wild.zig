const build_options = @import("build_options");
const clap = @import("clap");
const format = @import("format");
const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const os = std.os;
const rand = std.rand;

const BufInStream = io.BufferedInStream(fs.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);

const Clap = clap.ComptimeClap(clap.Help, params);
const Param = clap.Param(clap.Help);

const readLine = @import("readline").readLine;

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
        stdout.stream.print("{}\n", build_options.version) catch |err| return failedWriteError("<stdout>", err);
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

    const simular_total_stats = args.flag("--simular-total-stats");

    var line_buf = std.Buffer.initSize(allocator, 0) catch |err| return errPrint("Allocation failed: {}", err);
    var data = Data{
        .pokemon_list = std.ArrayList(usize).init(allocator),
        .pokemons = Pokemons.init(allocator),
        .zones = Zones.init(allocator),
    };

    while (readLine(stdin, &line_buf) catch |err| return failedReadError("<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&data, str) catch true;
        if (print_line)
            stdout.stream.print("{}\n", str) catch |err| return failedWriteError("<stdout>", err);

        line_buf.shrink(0);
    }
    stdout.flush() catch |err| return failedWriteError("<stdout>", err);

    randomize(data, seed, simular_total_stats) catch |err| return errPrint("Failed to randomize data: {}", err);

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
                    stdout.stream.print(".zones[{}].wild.{}.pokemons[{}].min_level={}\n", zone_i, area_name, poke_i, l) catch |err| return failedWriteError("<stdout>", err);
                if (pokemon.max_level) |l|
                    stdout.stream.print(".zones[{}].wild.{}.pokemons[{}].max_level={}\n", zone_i, area_name, poke_i, l) catch |err| return failedWriteError("<stdout>", err);
                if (pokemon.species) |s|
                    stdout.stream.print(".zones[{}].wild.{}.pokemons[{}].species={}\n", zone_i, area_name, poke_i, s) catch |err| return failedWriteError("<stdout>", err);
            }
        }
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
