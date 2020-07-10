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
const parse = util.parse;

const Clap = clap.ComptimeClap(clap.Help, &params);
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
    try stream.writeAll("Usage: tm35-rand-parties ");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Randomizes trainer parties.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

const TypesOption = enum {
    same,
    random,
    themed,
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

    const types_arg = args.option("--types") orelse "random";
    const types = std.meta.stringToEnum(TypesOption, types_arg) orelse {
        stdio.err.print("--types does not support '{}'\n", .{types_arg}) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const fix_moves = args.flag("--fix-moves");
    const simular_total_stats = args.flag("--simular-total-stats");

    var data = Data{};
    var line_buf = std.ArrayList(u8).init(allocator);
    while (util.readLine(&stdin, &line_buf) catch |err| return errors.readErr(stdio.err, "<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(allocator, &data, str) catch |err| switch (err) {
            error.OutOfMemory => return errors.allocErr(stdio.err),
            error.ParseError => true,
        };
        if (print_line)
            stdio.out.print("{}\n", .{str}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

        line_buf.resize(0) catch unreachable;
    }

    randomize(
        allocator,
        data,
        seed,
        fix_moves,
        simular_total_stats,
        types,
    ) catch |err| return errors.randErr(stdio.err, err);

    for (data.trainers.values()) |trainer, i| {
        const trainer_i = data.trainers.at(i).key;
        for (trainer.party.values()) |member, j| {
            const member_i = trainer.party.at(j).key;

            if (member.species) |s|
                stdio.out.print(".trainers[{}].party[{}].species={}\n", .{ trainer_i, member_i, s }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            if (member.level) |l|
                stdio.out.print(".trainers[{}].party[{}].level={}\n", .{ trainer_i, member_i, l }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

            for (member.moves.values()) |move, k| {
                const move_i = member.moves.at(k).key;
                stdio.out.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ trainer_i, member_i, move_i, move }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            }
        }
    }
    return 0;
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !bool {
    const sw = parse.Swhash(16);
    const m = sw.match;
    const c = sw.case;
    var p = parse.MutParser{ .str = str };

    switch (m(try p.parse(parse.anyField))) {
        c("pokemons") => {
            const poke_index = try p.parse(parse.index);
            const pokemon = try data.pokemons.getOrPutValue(allocator, poke_index, Pokemon{});

            switch (m(try p.parse(parse.anyField))) {
                c("catch_rate") => pokemon.catch_rate = try p.parse(parse.usizev),
                c("stats") => switch (m(try p.parse(parse.anyField))) {
                    c("hp") => pokemon.stats[0] = try p.parse(parse.u8v),
                    c("attack") => pokemon.stats[1] = try p.parse(parse.u8v),
                    c("defense") => pokemon.stats[2] = try p.parse(parse.u8v),
                    c("speed") => pokemon.stats[3] = try p.parse(parse.u8v),
                    c("sp_attack") => pokemon.stats[4] = try p.parse(parse.u8v),
                    c("sp_defense") => pokemon.stats[5] = try p.parse(parse.u8v),
                    else => return true,
                },
                c("types") => {
                    _ = try p.parse(parse.index);
                    _ = try pokemon.types.put(allocator, try p.parse(parse.usizev));
                },
                c("moves") => {
                    const move_index = try p.parse(parse.index);
                    const move = try pokemon.lvl_up_moves.getOrPutValue(allocator, move_index, LvlUpMove{});

                    switch (m(try p.parse(parse.anyField))) {
                        c("id") => move.id = try p.parse(parse.usizev),
                        c("level") => move.level = try p.parse(parse.u16v),
                        else => return true,
                    }
                },
                else => return true,
            }
        },
        c("trainers") => {
            const trainer_index = try p.parse(parse.index);
            try p.parse(comptime parse.field("party"));
            const party_index = try p.parse(parse.index);

            const trainer = try data.trainers.getOrPutValue(allocator, trainer_index, Trainer{});
            const member = try trainer.party.getOrPutValue(allocator, party_index, PartyMember{});
            switch (m(try p.parse(parse.anyField))) {
                c("species") => member.species = try p.parse(parse.usizev),
                c("level") => member.level = try p.parse(parse.u16v),
                c("moves") => {
                    const move_index = try p.parse(parse.index);
                    const move = try p.parse(parse.usizev);
                    _ = try member.moves.put(allocator, move_index, move);
                },
                else => return true,
            }

            return false;
        },
        c("moves") => {
            const index = try p.parse(parse.index);
            const move = try data.moves.getOrPutValue(allocator, index, Move{});

            switch (m(try p.parse(parse.anyField))) {
                c("power") => move.power = try p.parse(parse.u8v),
                c("type") => move.type = try p.parse(parse.usizev),
                c("pp") => move.pp = try p.parse(parse.u8v),
                c("accuracy") => move.accuracy = try p.parse(parse.u8v),
                else => return true,
            }
        },
        else => return true,
    }

    return true;
}

fn randomize(
    allocator: *mem.Allocator,
    data: Data,
    seed: u64,
    fix_moves: bool,
    simular_total_stats: bool,
    types_op: TypesOption,
) !void {
    var random_adapt = rand.DefaultPrng.init(seed);
    const random = &random_adapt.random;
    var simular = std.ArrayList(usize).init(allocator);

    const dummy_move: ?usize = blk: {
        if (!fix_moves)
            break :blk null;

        var res = data.moves.values()[0];
        for (data.moves.values()) |move, i| {
            const pp = move.pp orelse continue;
            if (pp == 0)
                break :blk data.moves.at(i).key;
        }

        break :blk null;
    };

    const species_by_type = try data.speciesByType(allocator);
    const all_types_count = species_by_type.count();

    for (data.trainers.values()) |trainer, i| {
        const trainer_i = data.trainers.at(i).key;

        const theme = switch (types_op) {
            .themed => species_by_type.at(random.intRangeLessThan(usize, 0, all_types_count)).key,
            else => undefined,
        };

        for (trainer.party.values()) |*member, j| {
            const old_species = member.species orelse continue;

            const new_type = switch (types_op) {
                .same => blk: {
                    const pokemon = data.pokemons.get(old_species) orelse {
                        // If we can't find the prev Pokemons type, then the only thing we can
                        // do is chose a random one.
                        break :blk species_by_type.at(random.intRangeLessThan(usize, 0, all_types_count)).key;
                    };
                    const types = pokemon.types;
                    const types_count = types.count();
                    if (types_count == 0)
                        continue;

                    break :blk types.at(random.intRangeLessThan(usize, 0, types_count));
                },
                .random => species_by_type.at(random.intRangeLessThan(usize, 0, all_types_count)).key,
                .themed => theme,
            };

            const pick_from = species_by_type.get(new_type).?;
            const pick_max = pick_from.count();
            if (simular_total_stats) blk: {
                // If we don't know what the old Pokemon was, then we can't do similar_total_stats.
                // We therefor just pick a random pokemon and continue.
                const pokemon = data.pokemons.get(old_species) orelse {
                    member.species = pick_from.at(random.intRangeLessThan(usize, 0, pick_max));
                    break :blk;
                };

                var min = @intCast(i64, sum(u8, &pokemon.stats));
                var max = min;

                simular.resize(0) catch unreachable;
                while (simular.items.len < 25) : ({
                    min -= 5;
                    max += 5;
                }) {
                    for (pick_from.span()) |range| {
                        var s = range.start;
                        while (s <= range.end) : (s += 1) {
                            const p = data.pokemons.get(s).?;
                            const total = @intCast(i64, sum(u8, &p.stats));
                            if (min <= total and total <= max)
                                try simular.append(s);
                        }
                    }
                }

                member.species = simular.items[random.intRangeLessThan(usize, 0, simular.items.len)];
            } else {
                member.species = pick_from.at(random.intRangeLessThan(usize, 0, pick_max));
            }

            if (fix_moves and member.moves.count() != 0) blk: {
                const pokemon = data.pokemons.get(member.species.?).?;
                const no_move = dummy_move orelse break :blk;
                const member_lvl = member.level orelse math.maxInt(u8);

                // Reset moves
                for (member.moves.values()) |*move|
                    move.* = no_move;

                for (pokemon.lvl_up_moves.values()) |lvl_up_move| {
                    const lvl_move_id = lvl_up_move.id orelse continue;
                    const lvl_move_lvl = lvl_up_move.level orelse 0;
                    const lvl_move = data.moves.get(lvl_move_id) orelse continue;
                    const lvl_move_r = RelativeMove.from(pokemon.*, lvl_move.*);

                    if (member_lvl < lvl_move_lvl)
                        continue;

                    var weakest = &member.moves.values()[0];
                    for (member.moves.values()) |*move| {
                        const weakest_move = data.moves.get(weakest.*) orelse continue;
                        const weakest_move_r = RelativeMove.from(pokemon.*, weakest_move.*);
                        const member_move = data.moves.get(move.*) orelse continue;
                        const member_move_r = RelativeMove.from(pokemon.*, member_move.*);

                        if (member_move_r.lessThan(weakest_move_r))
                            weakest = move;
                    }

                    const weakest_move = data.moves.get(weakest.*) orelse continue;
                    const weakest_move_r = RelativeMove.from(pokemon.*, weakest_move.*);
                    if (weakest_move_r.lessThan(lvl_move_r))
                        weakest.* = lvl_move_id;
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
const SpeciesByType = util.container.IntMap.Unmanaged(usize, Set);
const Pokemons = util.container.IntMap.Unmanaged(usize, Pokemon);
const LvlUpMoves = util.container.IntMap.Unmanaged(usize, LvlUpMove);
const Trainers = util.container.IntMap.Unmanaged(usize, Trainer);
const Party = util.container.IntMap.Unmanaged(usize, PartyMember);
const MemberMoves = util.container.IntMap.Unmanaged(usize, usize);
const Moves = util.container.IntMap.Unmanaged(usize, Move);

const Data = struct {
    pokemons: Pokemons = Pokemons{},
    trainers: Trainers = Trainers{},
    moves: Moves = Moves{},

    fn speciesByType(d: Data, allocator: *mem.Allocator) !SpeciesByType {
        var res = SpeciesByType{};
        errdefer {
            for (res.values()) |set|
                set.deinit(allocator);
            res.deinit(allocator);
        }

        for (d.pokemons.values()) |pokemon, i| {
            const s = d.pokemons.at(i).key;
            // We shouldn't pick Pokemon with 0 catch rate as they tend to be
            // Pokemon not meant to be used in the standard game.
            // Pokemons from the film studio in bw2 have 0 catch rate.
            if (pokemon.catch_rate == 0)
                continue;

            for (pokemon.types.span()) |range| {
                var t = range.start;
                while (t <= range.end) : (t += 1) {
                    const set = try res.getOrPutValue(allocator, t, Set{});
                    _ = try set.put(allocator, s);
                }
            }
        }

        return res;
    }
};

const Trainer = struct {
    party: Party = Party{},
};

const PartyMember = struct {
    species: ?usize = null,
    level: ?u16 = null,
    moves: MemberMoves = MemberMoves{},
};

const LvlUpMove = struct {
    level: ?u16 = null,
    id: ?usize = null,
};

const Move = struct {
    power: ?u8 = null,
    accuracy: ?u8 = null,
    pp: ?u8 = null,
    type: ?usize = null,
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
                const is_stab = p.types.exists(m.type orelse math.maxInt(usize));
                const stab = 1.0 + 0.5 * @intToFloat(f32, @boolToInt(is_stab));
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
    stats: [6]u8 = [_]u8{0} ** 6,
    types: Set = Set{},
    lvl_up_moves: LvlUpMoves = LvlUpMoves{},
    catch_rate: usize = 1,
};

test "tm35-rand-parties" {
    const H = struct {
        fn pokemon(
            comptime id: []const u8,
            comptime stat: []const u8,
            comptime types: []const u8,
            comptime move_: []const u8,
            comptime catch_rate: []const u8,
        ) []const u8 {
            return ".pokemons[" ++ id ++ "].hp=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].attack=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].defense=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].speed=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].sp_attack=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].sp_defense=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].types[0]=" ++ types ++ "\n" ++
                ".pokemons[" ++ id ++ "].types[1]=" ++ types ++ "\n" ++
                ".pokemons[" ++ id ++ "].moves[0].id=" ++ move_ ++ "\n" ++
                ".pokemons[" ++ id ++ "].moves[0].level=0\n" ++
                ".pokemons[" ++ id ++ "].catch_rate=" ++ catch_rate ++ "\n";
        }
        fn trainer(comptime id: []const u8, comptime species: []const u8, comptime move_: []const u8) []const u8 {
            return ".trainers[" ++ id ++ "].party[0].species=" ++ species ++ "\n" ++
                ".trainers[" ++ id ++ "].party[0].level=5\n" ++
                ".trainers[" ++ id ++ "].party[0].moves[0]=" ++ move_ ++ "\n" ++
                ".trainers[" ++ id ++ "].party[1].species=" ++ species ++ "\n" ++
                ".trainers[" ++ id ++ "].party[1].level=5\n" ++
                ".trainers[" ++ id ++ "].party[1].moves[0]=" ++ move_ ++ "\n";
        }
        fn move(
            comptime id: []const u8,
            comptime power: []const u8,
            comptime type_: []const u8,
            comptime pp: []const u8,
            comptime accuracy: []const u8,
        ) []const u8 {
            return ".moves[" ++ id ++ "].power=" ++ power ++ "\n" ++
                ".moves[" ++ id ++ "].type=" ++ type_ ++ "\n" ++
                ".moves[" ++ id ++ "].pp=" ++ pp ++ "\n" ++
                ".moves[" ++ id ++ "].accuracy=" ++ accuracy ++ "\n";
        }
    };

    const result_prefix = comptime H.pokemon("0", "10", "0", "1", "1") ++
        H.pokemon("1", "15", "16", "2", "1") ++
        H.pokemon("2", "20", "2", "3", "1") ++
        H.pokemon("3", "25", "12", "4", "1") ++
        H.pokemon("4", "30", "10", "5", "1") ++
        H.pokemon("5", "35", "11", "6", "1") ++
        H.pokemon("6", "40", "5", "7", "1") ++
        H.pokemon("7", "45", "4", "8", "1") ++
        H.pokemon("8", "45", "4", "8", "0") ++
        H.move("0", "0", "0", "0", "0") ++
        H.move("1", "10", "0", "10", "255") ++
        H.move("2", "10", "16", "10", "255") ++
        H.move("3", "10", "2", "10", "255") ++
        H.move("4", "10", "12", "10", "255") ++
        H.move("5", "10", "10", "10", "255") ++
        H.move("6", "10", "11", "10", "255") ++
        H.move("7", "10", "5", "10", "255") ++
        H.move("8", "10", "4", "10", "255");

    const test_string = comptime result_prefix ++
        H.trainer("0", "0", "1") ++
        H.trainer("1", "1", "2") ++
        H.trainer("2", "2", "3") ++
        H.trainer("3", "3", "4");

    util.testing.testProgram(main2, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party[0].species=6
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=2
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=1
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--fix-moves" }, test_string, result_prefix ++
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=8
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party[0].species=6
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=7
        \\.trainers[1].party[1].species=2
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=3
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=4
        \\.trainers[2].party[1].species=1
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=2
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=1
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=7
        \\
    );

    const same_types_result =
        \\.trainers[0].party[0].species=0
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party[0].species=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party[0].species=3
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    ;
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--types=same" }, test_string, result_prefix ++ same_types_result);
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--fix-moves", "--types=same" }, test_string, result_prefix ++ same_types_result);
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--types=themed" }, test_string, result_prefix ++
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=7
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party[0].species=2
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=2
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party[0].species=3
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--fix-moves", "--types=themed" }, test_string, result_prefix ++
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=8
        \\.trainers[0].party[1].species=7
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=8
        \\.trainers[1].party[0].species=2
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=3
        \\.trainers[1].party[1].species=2
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=3
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party[0].species=3
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
}
