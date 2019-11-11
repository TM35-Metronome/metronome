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
        clap.parseParam("-h, --help                        Display this help text and exit.                                                               ") catch unreachable,
        clap.parseParam("-f, --fix-moves                   Fix party member moves (will pick the best level up moves the pokemon can learn for its level).") catch unreachable,
        clap.parseParam("-s, --seed <NUM>                  The seed to use for random numbers. A random seed will be picked if this is not specified.     ") catch unreachable,
        clap.parseParam("-i, --simular-total-stats         Replaced party members should have simular total stats.                                        ") catch unreachable,
        clap.parseParam("-t, --types <random|same|themed>  Which types each trainer should use. (default: random)                                         ") catch unreachable,
        clap.parseParam("-v, --version                     Output version information and exit.                                                           ") catch unreachable,
        Param{ .takes_value = true },
    };
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-parties [-hfiv] [-s <NUM>] [-t <random|same|themed>]
        \\Randomizes trainer parties.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

const TypesOption = enum {
    same,
    random,
    themed,
};

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
        stdout.stream.print("{}\n", program_version) catch |err| return failedWriteError("<stdout>", err);
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

    const types = if (args.option("--types")) |types|
        std.meta.stringToEnum(TypesOption, types) orelse {
            debug.warn("--types does not support '{}'\n", types);
            usage(stderr) catch |err| return failedWriteError("<stderr>", err);
            return 1;
        }
    else
        TypesOption.random;

    const fix_moves = args.flag("--fix-moves");
    const simular_total_stats = args.flag("--simular-total-stats");

    var line_buf = std.Buffer.initSize(allocator, 0) catch |err| return errPrint("Allocation failed: {}", err);
    var data = Data{
        .types = std.ArrayList([]const u8).init(allocator),
        .pokemons_by_types = PokemonByType.init(allocator),
        .pokemons = Pokemons.init(allocator),
        .trainers = Trainers.init(allocator),
        .moves = Moves.init(allocator),
    };

    while (util.readLine(stdin, &line_buf) catch |err| return failedReadError("<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&data, str) catch true;
        if (print_line)
            stdout.stream.print("{}\n", str) catch |err| return failedWriteError("<stdout>", err);

        line_buf.shrink(0);
    }
    stdout.flush() catch |err| return failedWriteError("<stdout>", err);

    randomize(data, seed, fix_moves, simular_total_stats, types) catch |err| return errPrint("Failed to randomize data: {}", err);

    var trainer_iter = data.trainers.iterator();
    while (trainer_iter.next()) |trainer_kv| {
        const trainer_i = trainer_kv.key;
        const trainer = trainer_kv.value;

        var party_iter = trainer.party.iterator();
        while (party_iter.next()) |party_kv| {
            const member_i = party_kv.key;
            const member = party_kv.value;

            if (member.species) |s|
                stdout.stream.print(".trainers[{}].party[{}].species={}\n", trainer_i, member_i, s) catch |err| return failedWriteError("<stdout>", err);
            if (member.level) |l|
                stdout.stream.print(".trainers[{}].party[{}].level={}\n", trainer_i, member_i, l) catch |err| return failedWriteError("<stdout>", err);

            var move_iter = member.moves.iterator();
            while (move_iter.next()) |move_kv| {
                stdout.stream.print(".trainers[{}].party[{}].moves[{}]={}\n", trainer_i, member_i, move_kv.key, move_kv.value) catch |err| return failedWriteError("<stdout>", err);
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
    var parser = format.Parser{ .str = str };

    if (parser.eatField("pokemons")) |_| {
        const poke_index = try parser.eatIndex();
        const poke_entry = try data.pokemons.getOrPutValue(poke_index, Pokemon.init(allocator));
        const pokemon = &poke_entry.value;

        if (parser.eatField("stats")) |_| {
            if (parser.eatField("hp")) |_| {
                pokemon.stats[0] = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("attack")) |_| {
                pokemon.stats[1] = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("defense")) |_| {
                pokemon.stats[2] = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("speed")) |_| {
                pokemon.stats[3] = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_attack")) |_| {
                pokemon.stats[4] = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_defense")) |_| {
                pokemon.stats[5] = try parser.eatUnsignedValue(u8, 10);
            } else |_| {}
        } else |_| if (parser.eatField("types")) |_| {
            _ = try parser.eatIndex();

            // To keep it simple, we just leak a shit ton of type names here.
            const type_name = try mem.dupe(allocator, u8, try parser.eatValue());
            const by_type_entry = try data.pokemons_by_types.getOrPut(type_name);
            if (!by_type_entry.found_existing) {
                by_type_entry.kv.value = std.ArrayList(usize).init(allocator);
                try data.types.append(type_name);
            }

            try pokemon.types.append(type_name);
            try by_type_entry.kv.value.append(poke_index);
        } else |_| if (parser.eatField("moves")) |_| {
            const move_index = try parser.eatIndex();
            const move_entry = try pokemon.lvl_up_moves.getOrPutValue(move_index, LvlUpMove{
                .level = null,
                .id = null,
            });
            const move = &move_entry.value;

            if (parser.eatField("id")) |_| {
                move.id = try parser.eatUnsignedValue(usize, 10);
            } else |_| if (parser.eatField("level")) |_| {
                move.level = try parser.eatUnsignedValue(u16, 10);
            } else |_| {}
        } else |_| {}
    } else |_| if (parser.eatField("trainers")) |_| {
        const trainer_index = try parser.eatIndex();
        try parser.eatField("party");
        const party_index = try parser.eatIndex();

        const trainer_entry = try data.trainers.getOrPutValue(trainer_index, Trainer.init(allocator));
        const trainer = &trainer_entry.value;

        const member_entry = try trainer.party.getOrPutValue(party_index, PartyMember.init(allocator));
        const member = &member_entry.value;

        if (parser.eatField("species")) |_| {
            member.species = try parser.eatUnsignedValue(usize, 10);
        } else |_| if (parser.eatField("level")) |_| {
            member.level = try parser.eatUnsignedValue(u16, 10);
        } else |_| if (parser.eatField("moves")) |_| {
            const move_index = try parser.eatIndex();
            _ = try member.moves.put(move_index, try parser.eatUnsignedValue(usize, 10));
        } else |_| {
            return true;
        }

        return false;
    } else |_| if (parser.eatField("moves")) |_| {
        const index = try parser.eatIndex();
        const entry = try data.moves.getOrPutValue(index, Move{
            .power = null,
            .accuracy = null,
            .pp = null,
            .type = null,
        });
        const move = &entry.value;

        if (parser.eatField("power")) |_| {
            move.power = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("type")) |_| {
            move.type = try mem.dupe(allocator, u8, try parser.eatValue());
        } else |_| if (parser.eatField("pp")) |_| {
            move.pp = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("accuracy")) |_| {
            move.accuracy = try parser.eatUnsignedValue(u8, 10);
        } else |_| {}
    } else |_| {}

    return true;
}

fn randomize(data: Data, seed: u64, fix_moves: bool, simular_total_stats: bool, types_op: TypesOption) !void {
    const allocator = data.pokemons.allocator;
    var random_adapt = rand.DefaultPrng.init(seed);
    const random = &random_adapt.random;

    //if (data.types.len == 0)
    //    return;

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
                var min = @intCast(i64, sum(u8, pokemon.stats));
                var max = min;

                while (simular.len < 5) {
                    min -= 5;
                    max += 5;

                    for (pick_from) |s| {
                        const p = data.pokemons.get(s).?.value;
                        const total = @intCast(i64, sum(u8, p.stats));
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

const PokemonByType = std.StringHashMap(std.ArrayList(usize));
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
    level: ?u16,
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
    level: ?u16,
    id: ?usize,
};

const Move = struct {
    power: ?u8,
    accuracy: ?u8,
    pp: ?u8,
    type: ?[]const u8,
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
                    const t2 = m.type orelse continue;
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
    stats: [6]u8,
    types: std.ArrayList([]const u8),
    lvl_up_moves: LvlUpMoves,

    fn init(allocator: *mem.Allocator) Pokemon {
        return Pokemon{
            .stats = [_]u8{0} ** 6,
            .types = std.ArrayList([]const u8).init(allocator),
            .lvl_up_moves = LvlUpMoves.init(allocator),
        };
    }
};
