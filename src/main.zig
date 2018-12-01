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
    const unbuf_stdin = &(std.io.getStdIn() catch return 1).inStream().stream;
    const unbuf_stdout = &(std.io.getStdOut() catch return 1).outStream().stream;

    var buf_stdin = BufInStream.init(unbuf_stdin);
    var buf_stdout = BufOutStream.init(unbuf_stdout);

    const stderr = &(std.io.getStdErr() catch return 1).outStream().stream;
    const stdin = &buf_stdin.stream;
    const stdout = &buf_stdout.stream;

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
            if (member.level) |l|
                try stdout.print(".trainers[{}].party[{}].level={}\n", trainer_i, member_i, l);

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
        ".trainers[*].party[*].level",
        ".trainers[*].party[*].moves[*]",

        ".moves[*].power",
        ".moves[*].accuracy",
        ".moves[*].pp",
        ".moves[*].type",
    });

    const match = try m.match(str);
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
                m.case(".pokemons[*].stats.hp") => pokemon.hp = try fmt.parseUnsigned(u8, match.value.str, 10),
                m.case(".pokemons[*].stats.attack") => pokemon.attack = try fmt.parseUnsigned(u8, match.value.str, 10),
                m.case(".pokemons[*].stats.defense") => pokemon.defense = try fmt.parseUnsigned(u8, match.value.str, 10),
                m.case(".pokemons[*].stats.speed") => pokemon.speed = try fmt.parseUnsigned(u8, match.value.str, 10),
                m.case(".pokemons[*].stats.sp_attack") => pokemon.sp_attack = try fmt.parseUnsigned(u8, match.value.str, 10),
                m.case(".pokemons[*].stats.sp_defense") => pokemon.sp_defense = try fmt.parseUnsigned(u8, match.value.str, 10),
                m.case(".pokemons[*].types[*]") => {
                    // To keep it simple, we just leak a shit ton of type names here.
                    const type_name = try mem.dupe(allocator, u8, match.value.str);
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
                        m.case(".pokemons[*].moves[*].id") => move.id = try fmt.parseUnsigned(usize, match.value.str, 10),
                        m.case(".pokemons[*].moves[*].level") => move.level = try fmt.parseUnsigned(u8, match.value.str, 10),
                        else => unreachable,
                    }
                },
                else => unreachable,
            }

            break :blk true;
        },

        m.case(".trainers[*].party[*].species"),
        m.case(".trainers[*].party[*].level"),
        m.case(".trainers[*].party[*].moves[*]"),
        => blk: {
            const trainer_index = try fmt.parseUnsigned(usize, match.anys[0].str, 10);
            const party_index = try fmt.parseUnsigned(usize, match.anys[1].str, 10);

            const trainer_entry = try data.trainers.getOrPutValue(trainer_index, Trainer.init(allocator));
            const trainer = &trainer_entry.value;

            const member_entry = try trainer.party.getOrPutValue(party_index, PartyMember.init(allocator));
            const member = &member_entry.value;

            switch (match.case) {
                m.case(".trainers[*].party[*].species") => member.species = try fmt.parseUnsigned(usize, match.value.str, 10),
                m.case(".trainers[*].party[*].level") => member.level = try fmt.parseUnsigned(u8, match.value.str, 10),
                m.case(".trainers[*].party[*].moves[*]") => {
                    const move_index = try fmt.parseUnsigned(usize, match.anys[2].str, 10);
                    const member_move = try fmt.parseUnsigned(usize, match.value.str, 10);
                    _ = try member.moves.put(move_index, member_move);
                },
                else => unreachable,
            }

            break :blk false;
        },

        m.case(".moves[*].power"),
        m.case(".moves[*].type"),
        m.case(".moves[*].pp"),
        m.case(".moves[*].accuracy"),
        => blk: {
            const index = try fmt.parseUnsigned(usize, match.anys[0].str, 10);
            const entry = try data.moves.getOrPutValue(index, Move{
                .power = null,
                .accuracy = null,
                .pp = null,
                .@"type" = null,
            });
            const move = &entry.value;

            switch (match.case) {
                m.case(".moves[*].power") => move.power = try fmt.parseUnsigned(u8, match.value.str, 10),
                m.case(".moves[*].accuracy") => move.accuracy = try fmt.parseUnsigned(u8, match.value.str, 10),
                m.case(".moves[*].pp") => move.pp = try fmt.parseUnsigned(u8, match.value.str, 10),
                m.case(".moves[*].type") => move.@"type" = try mem.dupe(allocator, u8, match.value.str),
                else => unreachable,
            }

            break :blk true;
        },
        else => true,
    };
}

fn randomize(data: Data, seed: u64, fix_moves: bool, simular_total_stats: bool, types_op: TypesOption) !void {
    const allocator = data.pokemons.allocator;
    var random_adapt = rand.DefaultPrng.init(seed);
    const random = &random_adapt.random;

    const dummy_move: ?usize = blk: {
        if (!fix_moves)
            break :blk null;

        var move_iter = data.moves.iterator();
        var res = move_iter.next() orelse break :blk null;
        while (move_iter.next()) |move_kv| {
            if (move_kv.value.pp) |pp| {
                // If a move has no PP, the it is almost certain that this move is the dummy move
                // used when party members has less than 4 moves learned.
                if (pp == 0)
                    break :blk move_kv.key;
            }
        }

        break :blk null;
    };

    var trainer_iter = data.trainers.iterator();
    while (trainer_iter.next()) |trainer_kv| {
        const trainer_i = trainer_kv.key;
        const trainer = trainer_kv.value;

        const theme = switch (types_op) {
            TypesOption.themed => data.types.toSlice()[random.range(usize, 0, data.types.len)],
            else => undefined,
        };

        var party_iter = trainer.party.iterator();
        while (party_iter.next()) |party_kv| {
            const member = &party_kv.value;
            const old_species = member.species orelse continue;

            const new_type = switch (types_op) {
                TypesOption.same => blk: {
                    const pokemon = data.pokemons.get(old_species) orelse {
                        // If we can't find the prev Pokemons type, then the only thing we can
                        // do is chose a random one.
                        break :blk data.types.toSlice()[random.range(usize, 0, data.types.len)];
                    };
                    const types = pokemon.value.types;
                    if (types.len == 0)
                        continue;

                    break :blk types.toSlice()[random.range(usize, 0, types.len)];
                },
                TypesOption.random => data.types.toSlice()[random.range(usize, 0, data.types.len)],
                TypesOption.themed => theme,
            };

            const pick_from = data.pokemons_by_types.get(new_type).?.value.toSliceConst();
            if (simular_total_stats) blk: {
                // If we don't know what the old Pokemon was, then we can't do simular_total_stats.
                // We therefor just pick a random pokemon and continue.
                const poke_kv = data.pokemons.get(old_species) orelse {
                    member.species = pick_from[random.range(usize, 0, pick_from.len)];
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

                member.species = simular.toSlice()[random.range(usize, 0, simular.len)];
            } else {
                member.species = pick_from[random.range(usize, 0, pick_from.len)];
            }

            if (fix_moves and member.moves.count() != 0) blk: {
                const pokemon = data.pokemons.get(member.species.?).?.value;
                const no_move = dummy_move orelse break :blk;
                const member_lvl = member.level orelse math.maxInt(u8);

                {
                    // Reset moves
                    var move_iter = member.moves.iterator();
                    while (move_iter.next()) |member_move_kv| {
                        member_move_kv.value = no_move;
                    }
                }

                var lvl_move_iter = pokemon.lvl_up_moves.iterator();
                while (lvl_move_iter.next()) |lvl_up_move| {
                    const lvl_move_id = lvl_up_move.value.id orelse continue;
                    const lvl_move_lvl = lvl_up_move.value.level orelse 0;
                    const lvl_move = data.moves.get(lvl_move_id) orelse continue;
                    const lvl_move_r = RelativeMove.from(pokemon, lvl_move.value);

                    if (member_lvl < lvl_move_lvl)
                        continue;

                    var move_iter = member.moves.iterator();
                    var weakest = move_iter.next().?;
                    while (move_iter.next()) |member_move_kv| {
                        const weakest_move = data.moves.get(weakest.value) orelse continue;
                        const weakest_move_r = RelativeMove.from(pokemon, weakest_move.value);
                        const member_move = data.moves.get(member_move_kv.value) orelse continue;
                        const member_move_r = RelativeMove.from(pokemon, member_move.value);

                        if (member_move_r.lessThan(weakest_move_r))
                            weakest = member_move_kv;
                    }

                    const weakest_move = data.moves.get(weakest.value) orelse continue;
                    const weakest_move_r = RelativeMove.from(pokemon, weakest_move.value);
                    if (weakest_move_r.lessThan(lvl_move_r))
                        weakest.value = lvl_move_id;
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
    level: ?u8,
    moves: MemberMoves,

    fn init(allocator: *mem.Allocator) PartyMember {
        return PartyMember{
            .species = null,
            .level = null,
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
    accuracy: ?u8,
    pp: ?u8,
    @"type": ?[]const u8,
};

// Represents a moves power in relation to the pokemon who uses it
const RelativeMove = struct {
    power: u8,
    accuracy: u8,
    pp: u8,

    fn from(p: Pokemon, m: Move) RelativeMove {
        return RelativeMove{
            .power = blk: {
                const power = @intToFloat(f32, m.power orelse 0);
                const stab = for (p.types.toSlice()) |t1| {
                    const t2 = m.@"type" orelse continue;
                    if (mem.eql(u8, t1, t2))
                        break f32(1.5);
                } else f32(1.0);

                break :blk math.cast(u8, @floatToInt(u64, power * stab)) catch math.maxInt(u8);
            },
            .accuracy = m.accuracy orelse 0,
            .pp = m.pp orelse 0,
        };
    }

    fn lessThan(a: RelativeMove, b: RelativeMove) bool {
        if (a.power < b.power)
            return true;
        if (a.power > b.power)
            return false;
        if (a.accuracy < b.accuracy)
            return true;
        if (a.accuracy > b.accuracy)
            return false;
        return a.pp < b.pp;
    }
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
