const builtin = @import("builtin");
const clap = @import("zig-clap");
const format = @import("tm35-format");
const fun = @import("fun-with-zig");
const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;

const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = []Param{
    Param.flag(
        "display this help text and exit",
        Names.both("help"),
    ),
    Param.flag(
        "fix party member moves (will pick the best level up moves the pokemon can learn for its level)",
        Names.long("fix-moves"),
    ),
    Param.option(
        "the seed used to randomize parties",
        Names.both("seed"),
    ),
    Param.flag(
        "replaced party members should have simular total stats",
        Names.long("simular-total-stats"),
    ),
    Param.option(
        "which types each trainer should use [same, random, themed]",
        Names.both("types"),
    ),
    Param.positional(""),
};

const TypesOption = enum {
    same,
    random,
    themed,
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-parties [OPTION]...
        \\Reads the tm35 format from stdin and randomizes the parties of trainers.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    const stdin_file = std.io.getStdIn() catch return 1;
    const stderr_file = std.io.getStdErr() catch return 1;
    const stdout_file = std.io.getStdOut() catch return 1;
    var stdin_stream = stdin_file.inStream();
    var stderr_stream = stderr_file.outStream();
    var stdout_stream = stdout_file.outStream();
    var buf_stdin = io.BufferedInStream(os.File.InStream.Error).init(&stdin_stream.stream);
    var buf_stdout = io.BufferedOutStream(os.File.OutStream.Error).init(&stdout_stream.stream);

    const stdin = &buf_stdin.stream;
    const stdout = &buf_stdout.stream;
    const stderr = &stderr_stream.stream;

    var direct_allocator_state = std.heap.DirectAllocator.init();
    const direct_allocator = &direct_allocator_state.allocator;
    defer direct_allocator_state.deinit();

    // TODO: Other allocator?
    const allocator = direct_allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    const iter = &arg_iter.iter;
    defer arg_iter.deinit();
    _ = iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator.Error, iter) catch |err| {
        debug.warn("error: {}\n", err);
        usage(stderr) catch {};
        return 1;
    };
    defer args.deinit();

    main2(allocator, args, stdin, stdout, stderr) catch |err| {
        debug.warn("error: {}\n", err);
        return 1;
    };

    buf_stdout.flush() catch |err| {
        debug.warn("error: {}\n", err);
        return 1;
    };

    return 0;
}

pub fn main2(allocator: *mem.Allocator, args: Clap, stdin: var, stdout: var, stderr: var) !void {
    if (args.flag("--help"))
        return try usage(stdout);

    const fix_moves = args.flag("--fix-moves");
    const simular_total_stats = args.flag("--simular-total-stats");
    const types = blk: {
        const types = args.option("--types") orelse "random";
        break :blk std.meta.stringToEnum(TypesOption, types) orelse {
            debug.warn("error: Unknown --types value '{}'\n", types);
            return try usage(stderr);
        };
    };
    const seed = blk: {
        const seed_str = args.option("--seed") orelse {
            var buf: [8]u8 = undefined;
            try std.os.getRandomBytes(buf[0..]);
            break :blk mem.readInt(buf[0..8], u64, builtin.Endian.Little);
        };

        break :blk try fmt.parseUnsigned(u64, seed_str, 10);
    };

    var arena = heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const data = try readData(&arena.allocator, stdin, stdout);
    try randomize(data, seed, fix_moves, simular_total_stats, types);

    var trainer_iter = data.trainers.iterator();
    while (trainer_iter.next()) |trainer_kv| {
        const trainer_i = trainer_kv.key;
        const trainer = trainer_kv.value;

        var party_iter = trainer.party.iterator();
        while (party_iter.next()) |party_kv| {
            const member_i = party_kv.key;
            const member = party_kv.value;

            if (member.species) |s|
                try stdout.print(".trainers[{}].party[{}].species={}\n", trainer_i, member_i, s);

            var move_iter = member.moves.iterator();
            while (move_iter.next()) |move_kv| {
                try stdout.print(".trainers[{}].party[{}].moves[{}]={}\n", trainer_i, member_i, move_kv.key, move_kv.value);
            }
        }
    }
}

fn readData(allocator: *mem.Allocator, in_stream: var, out_stream: var) !Data {
    var res = Data{
        .types = std.ArrayList([]const u8).init(allocator),
        .pokemons_by_types = PokemonByType.init(allocator),
        .pokemons = Pokemons.init(allocator),
        .trainers = Trainers.init(allocator),
        .moves = Moves.init(allocator),
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
    @setEvalBranchQuota(100000);

    const allocator = data.pokemons.allocator;
    const m = format.Matcher([][]const u8{
        ".pokemons[*].stats.hp",
        ".pokemons[*].stats.attack",
        ".pokemons[*].stats.defense",
        ".pokemons[*].stats.speed",
        ".pokemons[*].stats.sp_attack",
        ".pokemons[*].stats.sp_defense",
        ".pokemons[*].types[*]",
        ".pokemons[*].moves[*].id",
        ".pokemons[*].moves[*].level",

        ".trainers[*].party[*].species",
        ".trainers[*].party[*].moves[*]",

        ".moves[*].power",
    });

    const match = try m.match(str);
    const value_str = mem.trim(u8, match.value.str, "\t ");
    return switch (match.case) {
        m.case(".pokemons[*].stats.hp"),
        m.case(".pokemons[*].stats.attack"),
        m.case(".pokemons[*].stats.defense"),
        m.case(".pokemons[*].stats.speed"),
        m.case(".pokemons[*].stats.sp_attack"),
        m.case(".pokemons[*].stats.sp_defense"),
        m.case(".pokemons[*].types[*]"),
        m.case(".pokemons[*].moves[*].id"),
        m.case(".pokemons[*].moves[*].level"),
        => blk: {
            const poke_index = try fmt.parseUnsigned(usize, match.anys[0].str, 10);
            const poke_entry = try data.pokemons.getOrPutValue(poke_index, Pokemon.init(allocator));
            const pokemon = &poke_entry.value;

            switch (match.case) {
                m.case(".pokemons[*].stats.hp") => pokemon.hp = try fmt.parseUnsigned(u8, value_str, 10),
                m.case(".pokemons[*].stats.attack") => pokemon.attack = try fmt.parseUnsigned(u8, value_str, 10),
                m.case(".pokemons[*].stats.defense") => pokemon.defense = try fmt.parseUnsigned(u8, value_str, 10),
                m.case(".pokemons[*].stats.speed") => pokemon.speed = try fmt.parseUnsigned(u8, value_str, 10),
                m.case(".pokemons[*].stats.sp_attack") => pokemon.sp_attack = try fmt.parseUnsigned(u8, value_str, 10),
                m.case(".pokemons[*].stats.sp_defense") => pokemon.sp_defense = try fmt.parseUnsigned(u8, value_str, 10),
                m.case(".pokemons[*].types[*]") => {
                    // To keep it simple, we just leak a shit ton of type names here.
                    const type_name = try mem.dupe(allocator, u8, value_str);
                    const by_type_entry = try data.pokemons_by_types.getOrPut(type_name);
                    if (!by_type_entry.found_existing) {
                        by_type_entry.kv.value = std.ArrayList(usize).init(allocator);
                        try data.types.append(type_name);
                    }

                    try pokemon.types.append(type_name);
                    try by_type_entry.kv.value.append(poke_index);
                },
                m.case(".pokemons[*].moves[*].id"), m.case(".pokemons[*].moves[*].level") => {
                    const move_index = try fmt.parseUnsigned(usize, match.anys[1].str, 10);
                    const move_entry = try pokemon.lvl_up_moves.getOrPutValue(move_index, LvlUpMove{
                        .level = null,
                        .id = null,
                    });
                    const move = &move_entry.value;
                    switch (match.case) {
                        m.case(".pokemons[*].moves[*].id") => move.id = try fmt.parseUnsigned(usize, value_str, 10),
                        m.case(".pokemons[*].moves[*].level") => move.level = try fmt.parseUnsigned(u8, value_str, 10),
                        else => unreachable,
                    }
                },
                else => unreachable,
            }

            break :blk true;
        },

        m.case(".trainers[*].party[*].species"), m.case(".trainers[*].party[*].moves[*]") => blk: {
            const trainer_index = try fmt.parseUnsigned(usize, match.anys[0].str, 10);
            const party_index = try fmt.parseUnsigned(usize, match.anys[1].str, 10);

            const trainer_entry = try data.trainers.getOrPutValue(trainer_index, Trainer.init(allocator));
            const trainer = &trainer_entry.value;

            const member_entry = try trainer.party.getOrPutValue(party_index, PartyMember.init(allocator));
            const member = &member_entry.value;

            switch (match.case) {
                m.case(".trainers[*].party[*].species") => member.species = try fmt.parseUnsigned(usize, value_str, 10),
                m.case(".trainers[*].party[*].moves[*]") => {
                    const move_index = try fmt.parseUnsigned(usize, match.anys[2].str, 10);
                    const member_move = try fmt.parseUnsigned(usize, value_str, 10);
                    _ = try member.moves.put(move_index, member_move);
                },
                else => unreachable,
            }

            break :blk false;
        },

        m.case(".moves[*].power") => blk: {
            const index = try fmt.parseUnsigned(usize, match.anys[0].str, 10);
            const entry = try data.moves.getOrPutValue(index, Move{ .power = null });
            entry.value.power = try fmt.parseUnsigned(u8, value_str, 10);

            break :blk true;
        },
        else => true,
    };
}

fn randomize(data: Data, seed: u64, fix_moves: bool, simular_total_stats: bool, types_op: TypesOption) !void {
    const allocator = data.pokemons.allocator;
    var random_adapt = rand.DefaultPrng.init(seed);
    const random = &random_adapt.random;

    var trainer_iter = data.trainers.iterator();
    while (trainer_iter.next()) |trainer_kv| {
        const trainer_i = trainer_kv.key;
        const trainer = trainer_kv.value;

        const theme = switch (types_op) {
            TypesOption.themed => data.types.toSlice()[random.range(usize, 0, data.types.len)],
            else => undefined,
        };

        var party_iter = trainer.party.iterator();
        skip: while (party_iter.next()) |party_kv| {
            const member_i = party_kv.key;
            const member = &party_kv.value;
            const species = member.species orelse continue :skip;
            const poke_kv = data.pokemons.get(species) orelse continue :skip;
            const pokemon = poke_kv.value;

            const new_type = switch (types_op) {
                TypesOption.same => blk: {
                    if (pokemon.types.len == 0)
                        continue :skip;

                    break :blk pokemon.types.toSlice()[random.range(usize, 0, pokemon.types.len)];
                },
                TypesOption.random => data.types.toSlice()[random.range(usize, 0, data.types.len)],
                TypesOption.themed => theme,
            };

            const pick_from = data.pokemons_by_types.get(new_type).?.value.toSliceConst();
            if (simular_total_stats) {
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

                member.species = simular.toSlice()[random.range(usize, 0, simular.len)];
            } else {
                member.species = pick_from[random.range(usize, 0, pick_from.len)];
            }

            // TODO: fix_moves
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

const PokemonByType = std.AutoHashMap([]const u8, std.ArrayList(usize));
const Pokemons = std.AutoHashMap(usize, Pokemon);
const LvlUpMoves = std.AutoHashMap(usize, LvlUpMove);
const Trainers = std.AutoHashMap(usize, Trainer);
const Party = std.AutoHashMap(usize, PartyMember);
const MemberMoves = std.AutoHashMap(usize, usize);
const Moves = std.AutoHashMap(usize, Move);

const Data = struct {
    types: std.ArrayList([]const u8),
    pokemons_by_types: PokemonByType,
    pokemons: Pokemons,
    trainers: Trainers,
    moves: Moves,
};

const Trainer = struct {
    party: Party,

    fn init(allocator: *mem.Allocator) Trainer {
        return Trainer{ .party = Party.init(allocator) };
    }
};

const PartyMember = struct {
    species: ?usize,
    moves: MemberMoves,

    fn init(allocator: *mem.Allocator) PartyMember {
        return PartyMember{
            .species = null,
            .moves = MemberMoves.init(allocator),
        };
    }
};

const LvlUpMove = struct {
    level: ?u8,
    id: ?usize,
};

const Move = struct {
    power: ?u8,
};

const Pokemon = struct {
    hp: ?u8,
    attack: ?u8,
    defense: ?u8,
    speed: ?u8,
    sp_attack: ?u8,
    sp_defense: ?u8,
    types: std.ArrayList([]const u8),
    lvl_up_moves: LvlUpMoves,

    fn init(allocator: *mem.Allocator) Pokemon {
        return Pokemon{
            .hp = null,
            .attack = null,
            .defense = null,
            .speed = null,
            .sp_attack = null,
            .sp_defense = null,
            .types = std.ArrayList([]const u8).init(allocator),
            .lvl_up_moves = LvlUpMoves.init(allocator),
        };
    }

    const stats = [][]const u8{
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
