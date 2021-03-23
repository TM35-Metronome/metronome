const clap = @import("clap");
const format = @import("format");
const std = @import("std");
const util = @import("util");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const log = std.log;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help                                                                Display this help text and exit.") catch unreachable,
        clap.parseParam("-i, --items <none|unchanged|random>                                       The method used to picking held items. (default: none)") catch unreachable,
        clap.parseParam("-o, --moves <none|unchanged|best|best_for_level|random_learnable|random>  The method used to picking moves. (default: none)") catch unreachable,
        clap.parseParam("-m, --party-size-min <INT>                                                The minimum size each trainers party is allowed to be. (default: 1)") catch unreachable,
        clap.parseParam("-M, --party-size-max <INT>                                                The maximum size each trainers party is allowed to be. (default: 6)") catch unreachable,
        clap.parseParam("-p, --party-size-pick-method <unchanged|minimum|random>                   The method used to pick the trainer party size. (default: unchanged)") catch unreachable,
        clap.parseParam("-s, --seed <INT>                                                          The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-S, --stats <random|simular|follow_level>                                 The total stats the picked pokemon should have. (default: random)") catch unreachable,
        clap.parseParam("-t, --types <random|same|themed>                                          Which types each trainer should use. (default: random)") catch unreachable,
        clap.parseParam("-v, --version                                                             Output version information and exit.") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-rand-parties ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nRandomizes trainer parties.\n" ++
        "\n" ++
        "Options:\n");
    try clap.help(writer, &params);
}

const ItemOption = enum {
    none,
    unchanged,
    random,
};

const MoveOption = enum {
    none,
    unchanged,
    best,
    best_for_level,
    random_learnable,
    random,
};

const TypesOption = enum {
    same,
    random,
    themed,
};

const StatsOption = enum {
    random,
    simular,
    follow_level,
};

const PartySizeMethod = enum {
    unchanged,
    minimum,
    random,
};

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) anyerror!void {
    const seed = try util.getSeed(args);
    const items_arg = args.option("--items") orelse "none";
    const moves_arg = args.option("--moves") orelse "none";
    const party_size_max_arg = args.option("--party-size-max") orelse "6";
    const party_size_method_arg = args.option("--party-size-pick-method") orelse "unchanged";
    const party_size_min_arg = args.option("--party-size-min") orelse "1";
    const stats_arg = args.option("--stats") orelse "random";
    const types_arg = args.option("--types") orelse "random";

    const party_size_min = fmt.parseUnsigned(usize, party_size_min_arg, 10);
    const party_size_max = fmt.parseUnsigned(usize, party_size_max_arg, 10);
    const types = std.meta.stringToEnum(TypesOption, types_arg) orelse {
        log.err("--types does not support '{}'\n", .{types_arg});
        return error.InvalidArgument;
    };
    const items = std.meta.stringToEnum(ItemOption, items_arg) orelse {
        log.err("--items does not support '{}'\n", .{items_arg});
        return error.InvalidArgument;
    };
    const moves = std.meta.stringToEnum(MoveOption, moves_arg) orelse {
        log.err("--moves does not support '{}'\n", .{moves_arg});
        return error.InvalidArgument;
    };
    const stats = std.meta.stringToEnum(StatsOption, stats_arg) orelse {
        log.err("--stats does not support '{}'\n", .{stats_arg});
        return error.InvalidArgument;
    };
    const party_size_method = std.meta.stringToEnum(PartySizeMethod, party_size_method_arg) orelse {
        log.err("--party-size-pick-method does not support '{}'\n", .{party_size_method_arg});
        return error.InvalidArgument;
    };
    for ([_]struct { arg: []const u8, value: []const u8, check: anyerror!usize }{
        .{ .arg = "--party-size-min", .value = party_size_min_arg, .check = party_size_min },
        .{ .arg = "--party-size-max", .value = party_size_max_arg, .check = party_size_max },
    }) |arg| {
        if (arg.check) |_| {} else |err| {
            log.err("Invalid value for {}: {}\n", .{ arg.arg, arg.value });
            return error.InvalidArgument;
        }
    }

    var fifo = util.io.Fifo(.Dynamic).init(allocator);
    var data = Data{};
    while (try util.io.readLine(stdio.in, &fifo)) |line| {
        parseLine(allocator, &data, line) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParserFailed => try stdio.out.print("{}\n", .{line}),
        };
    }

    try randomize(allocator, &data, .{
        .seed = seed,
        .types = types,
        .items = items,
        .moves = moves,
        .stats = stats,
        .party_size_method = party_size_method,
        .party_size_min = party_size_min catch unreachable,
        .party_size_max = party_size_max catch unreachable,
    });

    for (data.trainers.values()) |trainer, i| {
        const trainer_i = data.trainers.at(i).key;
        const party_type = @tagName(trainer.party_type);

        try stdio.out.print(".trainers[{}].party_size={}\n", .{ trainer_i, trainer.party_size });
        try stdio.out.print(".trainers[{}].party_type={}\n", .{ trainer_i, party_type });
        for (trainer.party.values()[0..trainer.party_size]) |member, j| {
            if (member.species) |s|
                try stdio.out.print(".trainers[{}].party[{}].species={}\n", .{ trainer_i, j, s });
            if (member.level) |l|
                try stdio.out.print(".trainers[{}].party[{}].level={}\n", .{ trainer_i, j, l });
            if (member.item) |item|
                try stdio.out.print(".trainers[{}].party[{}].item={}\n", .{ trainer_i, j, item });
            for (member.moves.values()) |move, k| {
                const move_i = member.moves.at(k).key;
                try stdio.out.print(".trainers[{}].party[{}].moves[{}]={}\n", .{ trainer_i, j, move_i, move });
            }
        }
    }
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !void {
    const parsed = try format.parseNoEscape(str);
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try data.pokedex.put(allocator, pokedex.index);
            return error.ParserFailed;
        },
        .pokemons => |pokemons| {
            const pokemon = try data.pokemons.getOrPutValue(allocator, pokemons.index, Pokemon{});
            switch (pokemons.value) {
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .pokedex_entry => |pokedex_entry| pokemon.pokedex_entry = pokedex_entry,
                .types => |types| _ = try pokemon.types.put(allocator, types.value),
                .stats => |stats| switch (stats) {
                    .hp => |hp| pokemon.stats[0] = hp,
                    .attack => |attack| pokemon.stats[1] = attack,
                    .defense => |defense| pokemon.stats[2] = defense,
                    .speed => |speed| pokemon.stats[3] = speed,
                    .sp_attack => |sp_attack| pokemon.stats[4] = sp_attack,
                    .sp_defense => |sp_defense| pokemon.stats[5] = sp_defense,
                },
                .moves => |moves| {
                    const move = try pokemon.lvl_up_moves.getOrPutValue(allocator, moves.index, LvlUpMove{});
                    switch (moves.value) {
                        .id => |id| move.id = id,
                        .level => |level| move.level = level,
                    }
                },
                .base_exp_yield,
                .ev_yield,
                .items,
                .gender_ratio,
                .egg_cycles,
                .base_friendship,
                .growth_rate,
                .egg_groups,
                .abilities,
                .color,
                .evos,
                .tms,
                .hms,
                .name,
                => return error.ParserFailed,
            }
            return error.ParserFailed;
        },
        .trainers => |trainers| {
            const trainer = try data.trainers.getOrPutValue(allocator, trainers.index, Trainer{});
            switch (trainers.value) {
                .party_size => |party_size| trainer.party_size = party_size,
                .party_type => |party_type| trainer.party_type = party_type,
                .party => |party| {
                    const member = try trainer.party.getOrPutValue(allocator, party.index, PartyMember{});
                    switch (party.value) {
                        .species => |species| member.species = species,
                        .level => |level| member.level = level,
                        .item => |item| member.item = item,
                        .moves => |moves| _ = try member.moves.put(allocator, moves.index, moves.value),
                        .ability => return error.ParserFailed,
                    }
                    return;
                },
                .class,
                .encounter_music,
                .trainer_picture,
                .name,
                .items,
                => return error.ParserFailed,
            }
            return;
        },
        .items => |items| switch (items.value) {
            .battle_effect => |effect| {
                if (effect != 0)
                    _ = try data.held_items.put(allocator, items.index);
                return error.ParserFailed;
            },
            .name,
            .description,
            .price,
            .pocket,
            => return error.ParserFailed,
        },
        .moves => |moves| {
            const move = try data.moves.getOrPutValue(allocator, moves.index, Move{});
            switch (moves.value) {
                .power => |power| move.power = power,
                .type => |_type| move.type = _type,
                .pp => |pp| move.pp = pp,
                .accuracy => |accuracy| move.accuracy = accuracy,
                else => {},
            }
            return error.ParserFailed;
        },
        .version,
        .game_title,
        .gamecode,
        .instant_text,
        .starters,
        .text_delays,
        .abilities,
        .types,
        .tms,
        .hms,
        .maps,
        .wild_pokemons,
        .static_pokemons,
        .given_pokemons,
        .pokeball_items,
        .hidden_hollows,
        .text,
        => return error.ParserFailed,
    }
    unreachable;
}

const Options = struct {
    seed: u64,
    types: TypesOption,
    items: ItemOption,
    moves: MoveOption,
    stats: StatsOption,
    party_size_method: PartySizeMethod,
    party_size_min: usize,
    party_size_max: usize,
};

fn randomize(allocator: *mem.Allocator, data: *Data, opt: Options) !void {
    var random_adapt = rand.DefaultPrng.init(opt.seed);
    const random = &random_adapt.random;
    var simular = std.ArrayList(usize).init(allocator);

    const species = try data.pokedexPokemons(allocator);
    const species_by_type = try data.speciesByType(allocator, species);
    const all_types_count = species_by_type.count();
    if (all_types_count == 0) {
        std.log.err("No types where found. Cannot randomize.", .{});
        return;
    }

    var min_stats: usize = math.maxInt(usize);
    var max_stats: usize = 0;
    for (species.span()) |range| {
        var s = range.start;
        while (s <= range.end) : (s += 1) {
            const pokemon = data.pokemons.get(s) orelse continue;
            const stats = sum(u8, &pokemon.stats);
            min_stats = math.min(min_stats, stats);
            max_stats = math.max(max_stats, stats);
        }
    }

    for (data.trainers.values()) |*trainer, i| {
        const trainer_i = data.trainers.at(i).key;

        const theme = switch (opt.types) {
            .themed => species_by_type.at(random.intRangeLessThan(usize, 0, all_types_count)).key,
            else => undefined,
        };

        var stat_count: usize = 0;
        var stat_total: usize = 0;
        var level_count: u16 = 0;
        var level_total: u16 = 0;
        for (trainer.party.values()) |member| {
            if (member.species) |_species| {
                const pokemon = data.pokemons.get(_species) orelse continue;
                stat_total += sum(u8, &pokemon.stats);
                stat_count += 1;
            }
            if (member.level) |level| {
                level_total += level;
                level_count += 1;
            }
        }
        const average_stats: ?usize = if (stat_count != 0) stat_total / stat_count else null;
        const average_level = if (level_count != 0) level_total / level_count else 0;

        trainer.party_size = switch (opt.party_size_method) {
            .unchanged => math.clamp(trainer.party_size, opt.party_size_min, opt.party_size_max),
            .minimum => opt.party_size_min,
            .random => random.intRangeAtMost(usize, opt.party_size_min, opt.party_size_max),
        };

        const wants_moves = switch (opt.moves) {
            .unchanged => switch (trainer.party_type) {
                .moves, .both => true,
                .none, .item => false,
            },
            .none => false,
            .best,
            .best_for_level,
            .random_learnable,
            .random,
            => true,
        };
        const wants_items = switch (opt.items) {
            .unchanged => switch (trainer.party_type) {
                .item, .both => true,
                .none, .moves => false,
            },
            .none => false,
            .random => true,
        };

        trainer.party_type = switch (wants_moves) {
            true => switch (wants_items) {
                true => format.PartyType.both,
                false => format.PartyType.moves,
            },
            false => switch (wants_items) {
                true => format.PartyType.item,
                false => format.PartyType.none,
            },
        };

        var j: usize = 0;
        while (j < trainer.party_size) : (j += 1) {
            const member = try trainer.party.getOrPutValue(allocator, j, PartyMember{
                .level = average_level,
            });
            const old_species = member.species;

            const new_type = switch (opt.types) {
                .same => blk: {
                    const m_pokemon = if (old_species) |s| data.pokemons.get(s) else null;
                    const pokemon = m_pokemon orelse {
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
            member.species = switch (opt.stats) {
                .simular, .follow_level => blk: {
                    const total_stats = switch (opt.stats) {
                        .simular => blk2: {
                            // If we don't know what the old Pokemon was, then we can't do similar_total_stats.
                            // We therefor just pick a random pokemon and continue.
                            const m_pokemon = if (old_species) |s| data.pokemons.get(s) else null;
                            break :blk2 if (m_pokemon) |p| sum(u8, &p.stats) else average_stats orelse {
                                break :blk pick_from.at(random.intRangeLessThan(usize, 0, pick_max));
                            };
                        },
                        .follow_level => blk2: {
                            const level = member.level orelse average_level;
                            break :blk2 levelScaling(min_stats, max_stats, level);
                        },
                        .random => unreachable,
                    };

                    var min = @intCast(i64, total_stats);
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

                    break :blk simular.items[random.intRangeLessThan(usize, 0, simular.items.len)];
                },
                .random => pick_from.at(random.intRangeLessThan(usize, 0, pick_max)),
            };

            member.item = switch (opt.items) {
                .none => null,
                .unchanged => member.item,
                .random => data.held_items.at(random.intRangeLessThan(usize, 0, data.held_items.count())),
            };

            var k: usize = 0;
            while (wants_moves and opt.moves != .unchanged and (k < 4 or k < member.moves.count())) : (k += 1) {
                const move = try member.moves.getOrPutValue(allocator, k, 0);
                const curr_moves = member.moves.values()[0..k];
                move.* = switch (opt.moves) {
                    .none, .unchanged => unreachable,
                    .best, .best_for_level => blk: {
                        // These null unwraps are ok, as we have already picked a
                        // random pokemon, so none of these check should fail.
                        const pokemon = data.pokemons.get(member.species.?).?;
                        const member_lvl = member.level orelse math.maxInt(u8);
                        const lvl_up_moves = pokemon.lvl_up_moves.values();

                        var m_best: ?usize = null;
                        for (lvl_up_moves) |lvl_up_move| {
                            const lvl_move_id = lvl_up_move.id orelse continue;
                            const lvl_move = data.moves.get(lvl_move_id) orelse continue;
                            const lvl_move_lvl = lvl_up_move.level orelse 0;
                            const lvl_move_r = RelativeMove.from(pokemon.*, lvl_move.*);

                            if (opt.moves == .best_for_level and member_lvl < lvl_move_lvl)
                                continue;

                            const this_move = data.moves.get(lvl_move_id) orelse continue;
                            const this_move_r = RelativeMove.from(pokemon.*, this_move.*);

                            const best = m_best orelse lvl_move_id;
                            const prev_move = data.moves.get(best).?;
                            const prev_move_r = RelativeMove.from(pokemon.*, prev_move.*);

                            if (!this_move_r.lessThan(prev_move_r)) {
                                if (mem.indexOfScalar(usize, curr_moves, lvl_move_id) == null)
                                    m_best = lvl_move_id;
                            }
                        }

                        break :blk m_best orelse 0;
                    },
                    .random => while (data.moves.count() - 1 > k) {
                        const pick = random.intRangeLessThan(usize, 1, data.moves.count());
                        const picked_move = data.moves.at(pick).key;
                        if (mem.indexOfScalar(usize, curr_moves, picked_move) == null)
                            break picked_move;
                    } else 0,
                    .random_learnable => blk: {
                        // These null unwraps are ok, as we have already picked a
                        // random pokemon, so none of these check should fail.
                        const pokemon = data.pokemons.get(member.species.?).?;
                        const member_lvl = member.level orelse math.maxInt(u8);
                        const lvl_up_moves = pokemon.lvl_up_moves.values();

                        while (lvl_up_moves.len > k) {
                            const pick = random.intRangeLessThan(usize, 0, lvl_up_moves.len);
                            const picked_move = lvl_up_moves[pick].id orelse continue;

                            if (mem.indexOfScalar(usize, curr_moves, picked_move) == null)
                                break :blk picked_move;
                        }

                        break :blk 0;
                    },
                };
                var z = move;
            }
        }
    }
}

fn levelScaling(min: usize, max: usize, level: usize) usize {
    const fmin = @intToFloat(f64, min);
    const fmax = @intToFloat(f64, max);
    const diff = fmax - fmin;
    const x = @intToFloat(f64, level);

    // Function adapted from -0.0001 * x^2 + 0.02 * x
    // This functions grows fast at the start, getting 75%
    // to max stats at level 50.
    const a = -0.0001 * diff;
    const b = 0.02 * diff;
    const xp2 = math.pow(f64, x, 2);
    const res = a * xp2 + b * x + fmin;
    return @floatToInt(usize, res);
}

fn SumReturn(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Int => usize,
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

const LvlUpMoves = util.container.IntMap.Unmanaged(usize, LvlUpMove);
const MemberMoves = util.container.IntMap.Unmanaged(usize, usize);
const Moves = util.container.IntMap.Unmanaged(usize, Move);
const Party = util.container.IntMap.Unmanaged(usize, PartyMember);
const Pokemons = util.container.IntMap.Unmanaged(usize, Pokemon);
const Set = util.container.IntSet.Unmanaged(usize);
const SpeciesByType = util.container.IntMap.Unmanaged(usize, Set);
const Trainers = util.container.IntMap.Unmanaged(usize, Trainer);

const Data = struct {
    pokedex: Set = Set{},
    pokemons: Pokemons = Pokemons{},
    trainers: Trainers = Trainers{},
    moves: Moves = Moves{},
    held_items: Set = Set{},

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

    fn speciesByType(d: Data, allocator: *mem.Allocator, species: Set) !SpeciesByType {
        var res = SpeciesByType{};
        errdefer {
            for (res.values()) |set|
                set.deinit(allocator);
            res.deinit(allocator);
        }

        for (species.span()) |s_range| {
            var s = s_range.start;
            while (s <= s_range.end) : (s += 1) {
                const pokemon = d.pokemons.get(s).?;

                for (pokemon.types.span()) |t_range| {
                    var t = t_range.start;
                    while (t <= t_range.end) : (t += 1) {
                        const set = try res.getOrPutValue(allocator, t, Set{});
                        _ = try set.put(allocator, s);
                    }
                }
            }
        }

        return res;
    }
};

const Trainer = struct {
    party_size: usize = 0,
    party_type: format.PartyType = .none,
    party: Party = Party{},
};

const PartyMember = struct {
    species: ?usize = null,
    item: ?usize = null,
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
    pokedex_entry: usize = math.maxInt(usize),
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
            return ".pokedex[" ++ id ++ "].height=0\n" ++
                ".pokemons[" ++ id ++ "].pokedex_entry=" ++ id ++ "\n" ++
                ".pokemons[" ++ id ++ "].hp=" ++ stat ++ "\n" ++
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
        fn trainer(comptime id: []const u8, comptime species: []const u8, comptime item_: ?[]const u8, comptime move_: ?[]const u8) []const u8 {
            const _type: []const u8 = if (move_ != null and item_ != null) "both" //
            else if (move_) |_| "moves" //
            else if (item_) |_| "item" //
            else "none";
            return ".trainers[" ++ id ++ "].party_size=2\n" ++
                ".trainers[" ++ id ++ "].party_type=" ++ _type ++ "\n" ++
                ".trainers[" ++ id ++ "].party[0].species=" ++ species ++ "\n" ++
                ".trainers[" ++ id ++ "].party[0].level=5\n" ++
                (if (item_) |i| ".trainers[" ++ id ++ "].party[0].item=" ++ i ++ "\n" else "") ++
                (if (move_) |m| ".trainers[" ++ id ++ "].party[0].moves[0]=" ++ m ++ "\n" else "") ++
                ".trainers[" ++ id ++ "].party[1].species=" ++ species ++ "\n" ++
                ".trainers[" ++ id ++ "].party[1].level=5\n" ++
                (if (item_) |i| ".trainers[" ++ id ++ "].party[1].item=" ++ i ++ "\n" else "") ++
                (if (move_) |m| ".trainers[" ++ id ++ "].party[1].moves[0]=" ++ m ++ "\n" else "");
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
        fn item(
            comptime id: []const u8,
            comptime effect: []const u8,
        ) []const u8 {
            return ".items[" ++ id ++ "].battle_effect=" ++ effect ++ "\n";
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
        H.move("8", "10", "4", "10", "255") ++
        H.item("0", "0") ++
        H.item("1", "1") ++
        H.item("2", "2") ++
        H.item("3", "3") ++
        H.item("4", "4");

    const test_string = comptime result_prefix ++
        H.trainer("0", "0", null, "1") ++
        H.trainer("1", "1", "1", "2") ++
        H.trainer("2", "2", null, "3") ++
        H.trainer("3", "3", null, "4");

    util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=6
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=2
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=1
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--party-size-min=3" }, test_string, result_prefix ++
        \\.trainers[0].party_size=3
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[0].party[2].species=6
        \\.trainers[0].party[2].level=5
        \\.trainers[1].party_size=3
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=2
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=3
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[2].species=1
        \\.trainers[1].party[2].level=5
        \\.trainers[2].party_size=3
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=0
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=6
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[2].party[2].species=3
        \\.trainers[2].party[2].level=5
        \\.trainers[3].party_size=3
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=7
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\.trainers[3].party[2].species=0
        \\.trainers[3].party[2].level=5
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--party-size-max=1" }, test_string, result_prefix ++
        \\.trainers[0].party_size=1
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[1].party_size=1
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=0
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[2].party_size=1
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=6
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[3].party_size=1
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=2
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--party-size-pick-method=minimum" }, test_string, result_prefix ++
        \\.trainers[0].party_size=1
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[1].party_size=1
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=0
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[2].party_size=1
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=6
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[3].party_size=1
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=2
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--party-size-pick-method=random" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=0
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=2
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=6
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=2
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=3
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[2].species=1
        \\.trainers[1].party[2].level=5
        \\.trainers[1].party[3].species=0
        \\.trainers[1].party[3].level=5
        \\.trainers[1].party[4].species=6
        \\.trainers[1].party[4].level=5
        \\.trainers[1].party[5].species=3
        \\.trainers[1].party[5].level=5
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=1
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=4
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=2
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=1
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\.trainers[3].party[2].species=1
        \\.trainers[3].party[2].level=5
        \\.trainers[3].party[3].species=1
        \\.trainers[3].party[3].level=5
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--items=unchanged" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=item
        \\.trainers[1].party[0].species=6
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].item=1
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=2
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].item=1
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=1
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--items=random" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=item
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].item=1
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=2
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].item=4
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=item
        \\.trainers[1].party[0].species=2
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].item=4
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=3
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].item=4
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=item
        \\.trainers[2].party[0].species=0
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].item=2
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=3
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].item=4
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=item
        \\.trainers[3].party[0].species=7
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].item=2
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=1
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].item=3
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--moves=unchanged" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=moves
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=moves
        \\.trainers[1].party[0].species=6
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=2
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=moves
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=1
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=moves
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    const moves_result =
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=moves
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=8
        \\.trainers[0].party[0].moves[1]=0
        \\.trainers[0].party[0].moves[2]=0
        \\.trainers[0].party[0].moves[3]=0
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[0].party[1].moves[1]=0
        \\.trainers[0].party[1].moves[2]=0
        \\.trainers[0].party[1].moves[3]=0
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=moves
        \\.trainers[1].party[0].species=6
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=7
        \\.trainers[1].party[0].moves[1]=0
        \\.trainers[1].party[0].moves[2]=0
        \\.trainers[1].party[0].moves[3]=0
        \\.trainers[1].party[1].species=2
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=3
        \\.trainers[1].party[1].moves[1]=0
        \\.trainers[1].party[1].moves[2]=0
        \\.trainers[1].party[1].moves[3]=0
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=moves
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=4
        \\.trainers[2].party[0].moves[1]=0
        \\.trainers[2].party[0].moves[2]=0
        \\.trainers[2].party[0].moves[3]=0
        \\.trainers[2].party[1].species=1
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=2
        \\.trainers[2].party[1].moves[1]=0
        \\.trainers[2].party[1].moves[2]=0
        \\.trainers[2].party[1].moves[3]=0
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=moves
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=1
        \\.trainers[3].party[0].moves[1]=0
        \\.trainers[3].party[0].moves[2]=0
        \\.trainers[3].party[0].moves[3]=0
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=7
        \\.trainers[3].party[1].moves[1]=0
        \\.trainers[3].party[1].moves[2]=0
        \\.trainers[3].party[1].moves[3]=0
        \\
    ;
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--moves=best" }, test_string, result_prefix ++ moves_result);
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--moves=best_for_level" }, test_string, result_prefix ++ moves_result);
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--moves=random_learnable" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=moves
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=8
        \\.trainers[0].party[0].moves[1]=0
        \\.trainers[0].party[0].moves[2]=0
        \\.trainers[0].party[0].moves[3]=0
        \\.trainers[0].party[1].species=2
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=3
        \\.trainers[0].party[1].moves[1]=0
        \\.trainers[0].party[1].moves[2]=0
        \\.trainers[0].party[1].moves[3]=0
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=moves
        \\.trainers[1].party[0].species=2
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=3
        \\.trainers[1].party[0].moves[1]=0
        \\.trainers[1].party[0].moves[2]=0
        \\.trainers[1].party[0].moves[3]=0
        \\.trainers[1].party[1].species=3
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=4
        \\.trainers[1].party[1].moves[1]=0
        \\.trainers[1].party[1].moves[2]=0
        \\.trainers[1].party[1].moves[3]=0
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=moves
        \\.trainers[2].party[0].species=0
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=1
        \\.trainers[2].party[0].moves[1]=0
        \\.trainers[2].party[0].moves[2]=0
        \\.trainers[2].party[0].moves[3]=0
        \\.trainers[2].party[1].species=3
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=4
        \\.trainers[2].party[1].moves[1]=0
        \\.trainers[2].party[1].moves[2]=0
        \\.trainers[2].party[1].moves[3]=0
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=moves
        \\.trainers[3].party[0].species=7
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=8
        \\.trainers[3].party[0].moves[1]=0
        \\.trainers[3].party[0].moves[2]=0
        \\.trainers[3].party[0].moves[3]=0
        \\.trainers[3].party[1].species=1
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=2
        \\.trainers[3].party[1].moves[1]=0
        \\.trainers[3].party[1].moves[2]=0
        \\.trainers[3].party[1].moves[3]=0
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--moves=random" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=moves
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[0].moves[1]=2
        \\.trainers[0].party[0].moves[2]=4
        \\.trainers[0].party[0].moves[3]=7
        \\.trainers[0].party[1].species=2
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=7
        \\.trainers[0].party[1].moves[1]=8
        \\.trainers[0].party[1].moves[2]=1
        \\.trainers[0].party[1].moves[3]=4
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=moves
        \\.trainers[1].party[0].species=3
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=8
        \\.trainers[1].party[0].moves[1]=3
        \\.trainers[1].party[0].moves[2]=2
        \\.trainers[1].party[0].moves[3]=4
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=5
        \\.trainers[1].party[1].moves[1]=2
        \\.trainers[1].party[1].moves[2]=7
        \\.trainers[1].party[1].moves[3]=8
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=moves
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[0].moves[1]=8
        \\.trainers[2].party[0].moves[2]=7
        \\.trainers[2].party[0].moves[3]=5
        \\.trainers[2].party[1].species=5
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[2].party[1].moves[1]=2
        \\.trainers[2].party[1].moves[2]=8
        \\.trainers[2].party[1].moves[3]=7
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=moves
        \\.trainers[3].party[0].species=1
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=7
        \\.trainers[3].party[0].moves[1]=3
        \\.trainers[3].party[0].moves[2]=5
        \\.trainers[3].party[0].moves[3]=1
        \\.trainers[3].party[1].species=7
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=2
        \\.trainers[3].party[1].moves[1]=7
        \\.trainers[3].party[1].moves[2]=8
        \\.trainers[3].party[1].moves[3]=6
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--types=same" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=0
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=3
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--types=themed" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=7
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=7
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=2
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=2
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=3
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
}
