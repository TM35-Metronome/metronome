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
        clap.parseParam("-h, --help                        Display this help text and exit.                                                               ") catch unreachable,
        clap.parseParam("-f, --fix-moves                   Fix party member moves (will pick the best level up moves the pokemon can learn for its level).") catch unreachable,
        clap.parseParam("-s, --seed <NUM>                  The seed to use for random numbers. A random seed will be picked if this is not specified.     ") catch unreachable,
        clap.parseParam("-i, --simular-total-stats         Replaced party members should have simular total stats.                                        ") catch unreachable,
        clap.parseParam("-t, --types <random|same|themed>  Which types each trainer should use. (default: random)                                         ") catch unreachable,
        clap.parseParam("-v, --version                     Output version information and exit.                                                           ") catch unreachable,
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
    var stdio_unbuf = util.getStdIo() catch |err| return 1;
    var stdio = stdio_unbuf.getBuffered();
    defer stdio.err.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(&arena.allocator) catch
        return errors.allocErr(&stdio.err.stream);
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

    const types_arg = args.option("--types") orelse "random";
    const types = std.meta.stringToEnum(TypesOption, types_arg) orelse {
        stdio.err.print("--types does not support '{}'\n", types_arg) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const fix_moves = args.flag("--fix-moves");
    const simular_total_stats = args.flag("--simular-total-stats");

    var line_buf = std.Buffer.initSize(allocator, 0) catch |err| return errors.allocErr(stdio.err);
    var data = Data{
        .types = std.ArrayList([]const u8).init(allocator),
        .pokemons_by_types = PokemonByType.init(allocator),
        .pokemons = Pokemons.init(allocator),
        .trainers = Trainers.init(allocator),
        .moves = Moves.init(allocator),
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

    randomize(data, seed, fix_moves, simular_total_stats, types) catch |err| return errors.randErr(stdio.err, err);

    var trainer_iter = data.trainers.iterator();
    while (trainer_iter.next()) |trainer_kv| {
        const trainer_i = trainer_kv.key;
        const trainer = trainer_kv.value;

        var party_iter = trainer.party.iterator();
        while (party_iter.next()) |party_kv| {
            const member_i = party_kv.key;
            const member = party_kv.value;

            if (member.species) |s|
                stdio.out.print(".trainers[{}].party[{}].species={}\n", trainer_i, member_i, s) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            if (member.level) |l|
                stdio.out.print(".trainers[{}].party[{}].level={}\n", trainer_i, member_i, l) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

            var move_iter = member.moves.iterator();
            while (move_iter.next()) |move_kv| {
                stdio.out.print(".trainers[{}].party[{}].moves[{}]={}\n", trainer_i, member_i, move_kv.key, move_kv.value) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
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
    var simular = std.ArrayList(usize).init(allocator);

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

                var min = @intCast(i64, sum(u8, pokemon.stats));
                var max = min;

                simular.resize(0) catch unreachable;
                while (simular.len < 25) : ({
                    min -= 5;
                    max += 5;
                }) {
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

test "tm35-rand-parties" {
    const H = struct {
        fn pokemon(comptime id: []const u8, comptime stat: []const u8, comptime types: []const u8, comptime move_: []const u8) []const u8 {
            return ".pokemons[" ++ id ++ "].hp=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].attack=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].defense=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].speed=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].sp_attack=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].sp_defense=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].types[0]=" ++ types ++ "\n" ++
                ".pokemons[" ++ id ++ "].types[1]=" ++ types ++ "\n" ++
                ".pokemons[" ++ id ++ "].moves[0].id=" ++ move_ ++ "\n" ++
                ".pokemons[" ++ id ++ "].moves[0].level=0\n";
        }
        fn trainer(comptime id: []const u8, comptime species: []const u8, comptime move_: []const u8) []const u8 {
            return ".trainers[" ++ id ++ "].party[0].species=" ++ species ++ "\n" ++
                ".trainers[" ++ id ++ "].party[0].level=5\n" ++
                ".trainers[" ++ id ++ "].party[0].moves[0]=" ++ move_ ++ "\n" ++
                ".trainers[" ++ id ++ "].party[1].species=" ++ species ++ "\n" ++
                ".trainers[" ++ id ++ "].party[1].level=5\n" ++
                ".trainers[" ++ id ++ "].party[1].moves[0]=" ++ move_ ++ "\n";
        }
        fn move(comptime id: []const u8, comptime power: []const u8, comptime type_: []const u8, comptime pp: []const u8, comptime accuracy: []const u8) []const u8 {
            return ".moves[" ++ id ++ "].power=" ++ power ++ "\n" ++
                ".moves[" ++ id ++ "].type=" ++ type_ ++ "\n" ++
                ".moves[" ++ id ++ "].pp=" ++ pp ++ "\n" ++
                ".moves[" ++ id ++ "].accuracy=" ++ accuracy ++ "\n";
        }
    };

    const result_prefix = comptime H.pokemon("0", "10", "normal", "1") ++
        H.pokemon("1", "15", "dragon", "2") ++
        H.pokemon("2", "20", "flying", "3") ++
        H.pokemon("3", "25", "grass", "4") ++
        H.pokemon("4", "30", "fire", "5") ++
        H.pokemon("5", "35", "water", "6") ++
        H.pokemon("6", "40", "rock", "7") ++
        H.pokemon("7", "45", "ground", "8") ++
        H.move("0", "0", "normal", "0", "0") ++
        H.move("1", "10", "normal", "10", "255") ++
        H.move("2", "10", "dragon", "10", "255") ++
        H.move("3", "10", "flying", "10", "255") ++
        H.move("4", "10", "grass", "10", "255") ++
        H.move("5", "10", "fire", "10", "255") ++
        H.move("6", "10", "water", "10", "255") ++
        H.move("7", "10", "rock", "10", "255") ++
        H.move("8", "10", "ground", "10", "255");

    const test_string = comptime result_prefix ++
        H.trainer("0", "0", "1") ++
        H.trainer("1", "1", "2") ++
        H.trainer("2", "2", "3") ++
        H.trainer("3", "3", "4");

    testProgram([_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.trainers[3].party[1].species=2
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[1].party[1].species=3
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[0].species=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[2].party[1].species=6
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[2].party[0].species=7
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[0].party[0].species=3
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\
    );
    testProgram([_][]const u8{ "--seed=0", "--fix-moves" }, test_string, result_prefix ++
        \\.trainers[3].party[1].species=2
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=3
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=1
        \\.trainers[1].party[1].species=3
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=4
        \\.trainers[1].party[0].species=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[2].party[1].species=6
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=7
        \\.trainers[2].party[0].species=7
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=8
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[0].party[0].species=3
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=4
        \\
    );

    const same_types_result =
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\.trainers[3].party[0].species=3
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[0].species=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[0].party[0].species=0
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\
    ;
    testProgram([_][]const u8{ "--seed=0", "--types=same" }, test_string, result_prefix ++ same_types_result);
    testProgram([_][]const u8{ "--seed=0", "--fix-moves", "--types=same" }, test_string, result_prefix ++ same_types_result);
    testProgram([_][]const u8{ "--seed=0", "--types=themed" }, test_string, result_prefix ++
        \\.trainers[3].party[1].species=2
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\.trainers[3].party[0].species=2
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[0].species=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[2].party[1].species=1
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[2].party[0].species=1
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[0].party[1].species=6
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[0].party[0].species=6
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\
    );
    testProgram([_][]const u8{ "--seed=0", "--fix-moves", "--types=themed" }, test_string, result_prefix ++
        \\.trainers[3].party[1].species=2
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=3
        \\.trainers[3].party[0].species=2
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=3
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[0].species=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[2].party[1].species=1
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=2
        \\.trainers[2].party[0].species=1
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=2
        \\.trainers[0].party[1].species=6
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=7
        \\.trainers[0].party[0].species=6
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=7
        \\
    );
}

fn testProgram(
    args: []const []const u8,
    in: []const u8,
    out: []const u8,
) void {
    var alloc_buf: [1024 * 50]u8 = undefined;
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
