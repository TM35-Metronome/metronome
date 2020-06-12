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

    var line_buf = std.ArrayList(u8).init(allocator);
    var data = Data{
        .type_set = std.BufSet.init(allocator),
        .pokemons = Pokemons.init(allocator),
        .trainers = Trainers.init(allocator),
        .moves = Moves.init(allocator),
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
                stdio.out.print(".trainers[{}].party[{}].species={}\n", .{ trainer_i, member_i, s }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            if (member.level) |l|
                stdio.out.print(".trainers[{}].party[{}].level={}\n", .{ trainer_i, member_i, l }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

            var move_iter = member.moves.iterator();
            while (move_iter.next()) |move_kv| {
                stdio.out.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ trainer_i, member_i, move_kv.key, move_kv.value }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            }
        }
    }
    return 0;
}

fn parseLine(data: *Data, str: []const u8) !bool {
    const sw = parse.Swhash(16);
    const m = sw.match;
    const c = sw.case;
    const allocator = data.pokemons.allocator;
    var p = parse.MutParser{ .str = str };

    switch (m(try p.parse(parse.anyField))) {
        c("pokemons") => {
            const poke_index = try p.parse(parse.index);
            const poke_entry = try data.pokemons.getOrPutValue(poke_index, Pokemon.init(allocator));
            const pokemon = &poke_entry.value;

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

                    // To keep it simple, we just leak a shit ton of type names here.
                    const type_name = try mem.dupe(allocator, u8, try p.parse(parse.strv));
                    try data.type_set.put(type_name);
                    try pokemon.types.append(type_name);
                },
                c("moves") => {
                    const move_index = try p.parse(parse.index);
                    const move_entry = try pokemon.lvl_up_moves.getOrPutValue(move_index, LvlUpMove{
                        .level = null,
                        .id = null,
                    });
                    const move = &move_entry.value;

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

            const trainer_entry = try data.trainers.getOrPutValue(trainer_index, Trainer.init(allocator));
            const trainer = &trainer_entry.value;

            const member_entry = try trainer.party.getOrPutValue(party_index, PartyMember.init(allocator));
            const member = &member_entry.value;

            switch (m(try p.parse(parse.anyField))) {
                c("species") => member.species = try p.parse(parse.usizev),
                c("level") => member.level = try p.parse(parse.u16v),
                c("moves") => {
                    const move_index = try p.parse(parse.index);
                    _ = try member.moves.put(move_index, try p.parse(parse.usizev));
                },
                else => return true,
            }

            return false;
        },
        c("moves") => {
            const index = try p.parse(parse.index);
            const entry = try data.moves.getOrPutValue(index, Move{
                .power = null,
                .accuracy = null,
                .pp = null,
                .type = null,
            });
            const move = &entry.value;

            switch (m(try p.parse(parse.anyField))) {
                c("power") => move.power = try p.parse(parse.u8v),
                c("type") => move.type = try mem.dupe(allocator, u8, try p.parse(parse.strv)),
                c("pp") => move.pp = try p.parse(parse.u8v),
                c("accuracy") => move.accuracy = try p.parse(parse.u8v),
                else => return true,
            }
        },
        else => return true,
    }

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

    const all_types = try data.types();
    const species_by_type = try data.speciesByType();

    var trainer_iter = data.trainers.iterator();
    while (trainer_iter.next()) |trainer_kv| {
        const trainer_i = trainer_kv.key;
        const trainer = trainer_kv.value;

        const theme = switch (types_op) {
            TypesOption.themed => all_types[random.intRangeLessThan(usize, 0, all_types.len)],
            else => undefined,
        };

        var party_iter = trainer.party.iterator();
        while (party_iter.next()) |party_kv| {
            const member = &party_kv.value;
            const old_species = member.species orelse continue;

            const new_type = switch (types_op) {
                .same => blk: {
                    const pokemon = data.pokemons.get(old_species) orelse {
                        // If we can't find the prev Pokemons type, then the only thing we can
                        // do is chose a random one.
                        break :blk all_types[random.intRangeLessThan(usize, 0, all_types.len)];
                    };
                    const types = pokemon.value.types;
                    if (types.items.len == 0)
                        continue;

                    break :blk types.items[random.intRangeLessThan(usize, 0, types.items.len)];
                },
                .random => all_types[random.intRangeLessThan(usize, 0, all_types.len)],
                .themed => theme,
            };

            const pick_from = species_by_type.get(new_type).?.value;
            const pick_max = pick_from.count();
            if (simular_total_stats) blk: {
                // If we don't know what the old Pokemon was, then we can't do simular_total_stats.
                // We therefor just pick a random pokemon and continue.
                const poke_kv = data.pokemons.get(old_species) orelse {
                    member.species = pick_from.at(random.intRangeLessThan(usize, 0, pick_max));
                    break :blk;
                };
                const pokemon = poke_kv.value;

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
                            const p = data.pokemons.get(s).?.value;
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
const SpeciesByType = std.StringHashMap(Set);
const Pokemons = std.AutoHashMap(usize, Pokemon);
const LvlUpMoves = std.AutoHashMap(usize, LvlUpMove);
const Trainers = std.AutoHashMap(usize, Trainer);
const Party = std.AutoHashMap(usize, PartyMember);
const MemberMoves = std.AutoHashMap(usize, usize);
const Moves = std.AutoHashMap(usize, Move);

const Data = struct {
    type_set: std.BufSet,
    pokemons: Pokemons,
    trainers: Trainers,
    moves: Moves,

    fn types(d: Data) ![]const []const u8 {
        var res = std.ArrayList([]const u8).init(d.allocator());
        errdefer res.deinit();

        var it = d.type_set.iterator();
        while (it.next()) |kv|
            try res.append(kv.key);

        return res.toOwnedSlice();
    }

    fn speciesByType(d: Data) !SpeciesByType {
        var res = SpeciesByType.init(d.allocator());
        errdefer {
            var it = res.iterator();
            while (it.next()) |kv|
                kv.value.deinit(d.allocator());
            res.deinit();
        }

        var it = d.pokemons.iterator();
        while (it.next()) |kv| {
            const s = kv.key;
            const pokemon = kv.value;
            // We should't pick Pokemon with 0 catch rate as they tend to be
            // Pokémon not meant to be used in the standard game.
            // Pokémons from the film studio in bw2 have 0 catch rate.
            if (pokemon.catch_rate == 0)
                continue;

            for (pokemon.types.items) |t| {
                const entry = try res.getOrPutValue(t, Set{});
                _ = try entry.value.put(d.allocator(), s);
            }
        }

        return res;
    }

    fn allocator(d: Data) *mem.Allocator {
        return d.pokemons.allocator;
    }
};

const Trainer = struct {
    party: Party,

    fn init(allocator: *mem.Allocator) Trainer {
        return Trainer{ .party = Party.init(allocator) };
    }
};

const PartyMember = struct {
    species: ?usize = null,
    level: ?u16 = null,
    moves: MemberMoves,

    fn init(allocator: *mem.Allocator) PartyMember {
        return PartyMember{
            .moves = MemberMoves.init(allocator),
        };
    }
};

const LvlUpMove = struct {
    level: ?u16 = null,
    id: ?usize = null,
};

const Move = struct {
    power: ?u8 = null,
    accuracy: ?u8 = null,
    pp: ?u8 = null,
    type: ?[]const u8 = null,
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
                const stab = for (p.types.items) |t1| {
                    const t2 = m.type orelse continue;
                    if (mem.eql(u8, t1, t2))
                        break @as(f32, 1.5);
                } else @as(f32, 1.0);

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
    types: std.ArrayList([]const u8),
    lvl_up_moves: LvlUpMoves,
    catch_rate: usize = 1,

    fn init(allocator: *mem.Allocator) Pokemon {
        return Pokemon{
            .types = std.ArrayList([]const u8).init(allocator),
            .lvl_up_moves = LvlUpMoves.init(allocator),
        };
    }
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

    const result_prefix = comptime H.pokemon("0", "10", "normal", "1", "1") ++
        H.pokemon("1", "15", "dragon", "2", "1") ++
        H.pokemon("2", "20", "flying", "3", "1") ++
        H.pokemon("3", "25", "grass", "4", "1") ++
        H.pokemon("4", "30", "fire", "5", "1") ++
        H.pokemon("5", "35", "water", "6", "1") ++
        H.pokemon("6", "40", "rock", "7", "1") ++
        H.pokemon("7", "45", "ground", "8", "1") ++
        H.pokemon("8", "45", "ground", "8", "0") ++
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

    util.testing.testProgram(main2, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.trainers[3].party[1].species=0
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\.trainers[3].party[0].species=6
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[0].species=7
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[2].party[1].species=4
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[2].party[0].species=5
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[0].party[1].species=6
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[0].party[0].species=1
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--fix-moves" }, test_string, result_prefix ++
        \\.trainers[3].party[1].species=0
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=1
        \\.trainers[3].party[0].species=6
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=7
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[0].species=7
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=8
        \\.trainers[2].party[1].species=4
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=5
        \\.trainers[2].party[0].species=5
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=6
        \\.trainers[0].party[1].species=6
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=7
        \\.trainers[0].party[0].species=1
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=2
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
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--types=same" }, test_string, result_prefix ++ same_types_result);
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--fix-moves", "--types=same" }, test_string, result_prefix ++ same_types_result);
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--types=themed" }, test_string, result_prefix ++
        \\.trainers[3].party[1].species=0
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[1].party[1].species=7
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[0].species=7
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[2].party[1].species=7
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[2].party[0].species=7
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[0].party[1].species=4
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[0].party[0].species=4
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\
    );
    util.testing.testProgram(main2, &[_][]const u8{ "--seed=0", "--fix-moves", "--types=themed" }, test_string, result_prefix ++
        \\.trainers[3].party[1].species=0
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=1
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=1
        \\.trainers[1].party[1].species=7
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=8
        \\.trainers[1].party[0].species=7
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=8
        \\.trainers[2].party[1].species=7
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=8
        \\.trainers[2].party[0].species=7
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=8
        \\.trainers[0].party[1].species=4
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=5
        \\.trainers[0].party[0].species=4
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=5
        \\
    );
}
