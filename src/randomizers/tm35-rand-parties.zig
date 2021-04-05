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

const algo = util.algorithm;

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
        clap.parseParam("-a, --abilities <random|same|themed>                                      Which ability each party member should have. (default: random)") catch unreachable,
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

const ThemeOption = enum {
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
    const abilities_arg = args.option("--abilities") orelse "random";
    const items_arg = args.option("--items") orelse "none";
    const moves_arg = args.option("--moves") orelse "none";
    const party_size_max_arg = args.option("--party-size-max") orelse "6";
    const party_size_method_arg = args.option("--party-size-pick-method") orelse "unchanged";
    const party_size_min_arg = args.option("--party-size-min") orelse "1";
    const stats_arg = args.option("--stats") orelse "random";
    const types_arg = args.option("--types") orelse "random";

    const party_size_min = fmt.parseUnsigned(u8, party_size_min_arg, 10);
    const party_size_max = fmt.parseUnsigned(u8, party_size_max_arg, 10);
    const abilities = std.meta.stringToEnum(ThemeOption, abilities_arg) orelse {
        log.err("--abilities does not support '{}'\n", .{abilities_arg});
        return error.InvalidArgument;
    };
    const items = std.meta.stringToEnum(ItemOption, items_arg) orelse {
        log.err("--items does not support '{}'\n", .{items_arg});
        return error.InvalidArgument;
    };
    const party_size_method = std.meta.stringToEnum(PartySizeMethod, party_size_method_arg) orelse {
        log.err("--party-size-pick-method does not support '{}'\n", .{party_size_method_arg});
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
    const types = std.meta.stringToEnum(ThemeOption, types_arg) orelse {
        log.err("--types does not support '{}'\n", .{types_arg});
        return error.InvalidArgument;
    };
    for ([_]struct { arg: []const u8, value: []const u8, check: anyerror!u8 }{
        .{ .arg = "--party-size-min", .value = party_size_min_arg, .check = party_size_min },
        .{ .arg = "--party-size-max", .value = party_size_max_arg, .check = party_size_max },
    }) |arg| {
        if (arg.check) |_| {} else |err| {
            log.err("Invalid value for {}: {}\n", .{ arg.arg, arg.value });
            return error.InvalidArgument;
        }
    }

    const data = try handleInput(allocator, stdio.in, stdio.out);
    const species = try data.pokedexPokemons(allocator);
    var ctx = Context{
        .allocator = allocator,
        .random = &rand.DefaultPrng.init(seed).random,

        .data = data,
        .options = .{
            .abilities = abilities,
            .items = items,
            .moves = moves,
            .party_size_max = party_size_max catch unreachable,
            .party_size_min = party_size_min catch unreachable,
            .party_size_method = party_size_method,
            .stats = stats,
            .types = types,
        },

        .species = species,
        .species_by_type = try data.speciesByType(allocator, species),
        .stats = data.minMaxStats(species),
    };
    try randomize(&ctx);
    try outputData(stdio.out, data);
}

fn handleInput(allocator: *mem.Allocator, reader: anytype, writer: anytype) !Data {
    var fifo = util.io.Fifo(.Dynamic).init(allocator);
    var data = Data{};
    while (try util.io.readLine(reader, &fifo)) |line| {
        parseLine(allocator, &data, line) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParserFailed => try writer.print("{}\n", .{line}),
        };
    }
    return data;
}

fn outputData(writer: anytype, data: Data) !void {
    for (data.trainers.items()) |trainer_kv| {
        const tid = trainer_kv.key;
        const trainer = trainer_kv.value;
        try format.write(writer, format.Game.trainer(tid, .{ .party_size = trainer.party_size }));
        try format.write(writer, format.Game.trainer(tid, .{ .party_type = trainer.party_type }));
        for (trainer.party.items()[0..trainer.party_size]) |member_kv| {
            const pi = member_kv.key;
            const member = member_kv.value;
            if (member.species) |s|
                try format.write(writer, format.Game.trainer(tid, format.Trainer.partyMember(pi, .{ .species = s })));
            if (member.level) |l|
                try format.write(writer, format.Game.trainer(tid, format.Trainer.partyMember(pi, .{ .level = l })));
            if (member.item) |item|
                try format.write(writer, format.Game.trainer(tid, format.Trainer.partyMember(pi, .{ .item = item })));
            for (member.moves.items()) |move_kv| {
                const mi = move_kv.key;
                const move = move_kv.value;
                try format.write(writer, format.Game.trainer(
                    tid,
                    format.Trainer.partyMember(pi, .{
                        .moves = .{ .index = mi, .value = move },
                    }),
                ));
            }
        }
    }
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !void {
    const parsed = try format.parseNoEscape(str);
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try data.pokedex.put(allocator, pokedex.index, {});
            return error.ParserFailed;
        },
        .pokemons => |pokemons| {
            const pokemon = &(try data.pokemons.getOrPutValue(allocator, pokemons.index, Pokemon{})).value;
            switch (pokemons.value) {
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .pokedex_entry => |pokedex_entry| pokemon.pokedex_entry = pokedex_entry,
                .types => |types| _ = try pokemon.types.put(allocator, types.value, {}),
                .stats => |stats| pokemon.stats[@enumToInt(stats)] = stats.value(),
                .moves => |moves| {
                    const move = try pokemon.lvl_up_moves.getOrPutValue(allocator, moves.index, LvlUpMove{});
                    format.setField(&move.value, moves.value);
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
            const trainer = &(try data.trainers.getOrPutValue(allocator, trainers.index, Trainer{})).value;
            switch (trainers.value) {
                .party_size => |party_size| trainer.party_size = party_size,
                .party_type => |party_type| trainer.party_type = party_type,
                .party => |party| {
                    const member = &(try trainer.party.getOrPutValue(allocator, party.index, PartyMember{})).value;
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
                    _ = try data.held_items.put(allocator, items.index, {});
                return error.ParserFailed;
            },
            .name,
            .description,
            .price,
            .pocket,
            => return error.ParserFailed,
        },
        .moves => |moves| {
            const move = &(try data.moves.getOrPutValue(allocator, moves.index, Move{})).value;
            switch (moves.value) {
                .power => |power| move.power = power,
                .type => |_type| move.type = _type,
                .pp => |pp| move.pp = pp,
                .accuracy => |accuracy| move.accuracy = accuracy,
                .name,
                .description,
                .effect,
                .target,
                .priority,
                .category,
                => {},
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
    abilities: ThemeOption,
    items: ItemOption,
    moves: MoveOption,
    party_size_max: u8,
    party_size_min: u8,
    party_size_method: PartySizeMethod,
    stats: StatsOption,
    types: ThemeOption,
};

const Context = struct {
    allocator: *mem.Allocator,
    random: *rand.Random,

    data: Data,
    options: Options,

    // Precomputed data for later use
    species: Set,
    species_by_type: SpeciesBy,
    stats: MinMax(u16),

    // Containers we reuse often enough that keeping them around with
    // their preallocated capacity is worth the hassel.
    simular: std.ArrayListUnmanaged(u16) = std.ArrayListUnmanaged(u16){},
};

fn randomize(ctx: *Context) !void {
    if (ctx.species_by_type.count() == 0) {
        std.log.err("No types where found. Cannot randomize.", .{});
        return;
    }

    for (ctx.data.trainers.items()) |*trainer_kv| {
        // Trainers with 0 party members are considered "invalid" trainers
        // and will not be randomized.
        if (trainer_kv.value.party_size == 0)
            continue;
        try randomizeTrainer(
            ctx,
            &trainer_kv.value,
        );
    }
}

fn randomizeTrainer(ctx: *Context, trainer: *Trainer) !void {
    const theme = switch (ctx.options.types) {
        .themed => util.random.item(ctx.random, ctx.species_by_type.items()).?.key,
        else => undefined,
    };

    const wants_moves = switch (ctx.options.moves) {
        .unchanged => trainer.party_type.haveMoves(),
        .none => false,
        .best,
        .best_for_level,
        .random_learnable,
        .random,
        => true,
    };
    const wants_items = switch (ctx.options.items) {
        .unchanged => trainer.party_type.haveItem(),
        .none => false,
        .random => true,
    };

    trainer.party_size = switch (ctx.options.party_size_method) {
        .unchanged => math.clamp(
            trainer.party_size,
            ctx.options.party_size_min,
            ctx.options.party_size_max,
        ),
        .random => ctx.random.intRangeAtMost(
            u8,
            ctx.options.party_size_min,
            ctx.options.party_size_max,
        ),
        .minimum => ctx.options.party_size_min,
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

    // Fill trainer party with more Pokémons until `party_size` have been
    // reached. The Pokémons we fill the party with are Pokémons that are
    // already in the party. This code assumes that at least 1 Pokémon
    // is in the party, which is always true as we don't randomize trainers
    // with a party size of 0.
    const party_member_max = trainer.party.count();
    var party_member: u8 = 0;
    var i: u8 = 0;
    while (i < trainer.party_size) : (i += 1) {
        const result = try trainer.party.getOrPut(ctx.allocator, i);
        if (!result.found_existing) {
            const member = trainer.party.items()[party_member].value;
            result.entry.value = .{
                .species = member.species,
                .item = member.item,
                .level = member.level,
                .moves = try member.moves.clone(ctx.allocator),
            };
            party_member += 1;
            party_member %= @intCast(u8, party_member_max);
        }
    }

    for (trainer.party.items()[0..trainer.party_size]) |*member_kv| {
        const member = &member_kv.value;
        if (member.species) |old_species| {
            member.species = try randomSpecies(
                ctx,
                theme,
                old_species,
                member.level orelse trainer.partyAverageLevel(),
            );
        }

        member.item = switch (ctx.options.items) {
            .none => null,
            .unchanged => member.item,
            .random => util.random.item(
                ctx.random,
                ctx.data.held_items.items(),
            ).?.key,
        };

        var k: u8 = 0;
        while (wants_moves and ctx.options.moves != .unchanged and
            (k < 4 or k < member.moves.count())) : (k += 1)
        {
            const move = try member.moves.getOrPutValue(ctx.allocator, k, 0);
            const curr_moves = member.moves.items()[0..k];
            move.value = switch (ctx.options.moves) {
                .none, .unchanged => unreachable,
                .best, .best_for_level => blk: {
                    // These null unwraps are ok, as we have already picked a
                    // random pokemon, so none of these check should fail.
                    const pokemon = ctx.data.pokemons.get(member.species.?).?;
                    const member_lvl = member.level orelse math.maxInt(u8);
                    const lvl_up_moves = pokemon.lvl_up_moves.items();

                    var m_best: ?u16 = null;
                    for (lvl_up_moves) |lvl_up_move_kv| {
                        const lvl_up_move = lvl_up_move_kv.value;
                        const lvl_move_id = lvl_up_move.id orelse continue;
                        const lvl_move = ctx.data.moves.get(lvl_move_id) orelse continue;
                        const lvl_move_lvl = lvl_up_move.level orelse 0;
                        const lvl_move_r = RelativeMove.from(pokemon, lvl_move);

                        if (ctx.options.moves == .best_for_level and member_lvl < lvl_move_lvl)
                            continue;

                        const this_move = ctx.data.moves.get(lvl_move_id) orelse continue;
                        const this_move_r = RelativeMove.from(pokemon, this_move);

                        const best = m_best orelse lvl_move_id;
                        const prev_move = ctx.data.moves.get(best).?;
                        const prev_move_r = RelativeMove.from(pokemon, prev_move);

                        if (!this_move_r.lessThan(prev_move_r)) {
                            if (!hasMove(curr_moves, lvl_move_id))
                                m_best = lvl_move_id;
                        }
                    }

                    break :blk m_best orelse 0;
                },
                .random => while (ctx.data.moves.count() - 1 > k) {
                    const pick = util.random.item(ctx.random, ctx.data.moves.items()[1..]).?.key;
                    if (!hasMove(curr_moves, pick))
                        break pick;
                } else 0,
                .random_learnable => blk: {
                    // These null unwraps are ok, as we have already picked a
                    // random pokemon, so none of these check should fail.
                    const pokemon = ctx.data.pokemons.get(member.species.?).?;
                    const member_lvl = member.level orelse math.maxInt(u8);
                    const lvl_up_moves = pokemon.lvl_up_moves.items();

                    while (lvl_up_moves.len > k) {
                        const pick = util.random.item(
                            ctx.random,
                            lvl_up_moves,
                        ).?.value.id orelse continue;
                        if (!hasMove(curr_moves, pick))
                            break :blk pick;
                    }

                    break :blk 0;
                },
            };
        }
    }
}

fn randomSpecies(ctx: *Context, theme: u16, old_species: u16, level: u8) !u16 {
    const pokemon = ctx.data.pokemons.get(old_species) orelse {
        return util.random.item(ctx.random, ctx.species.items()).?.key;
    };
    const pick_from = switch (ctx.options.types) {
        .same => blk: {
            const types = pokemon.types;
            if (types.count() == 0)
                return util.random.item(ctx.random, ctx.species.items()).?.key;

            const t = util.random.item(ctx.random, types.items()).?.key;
            break :blk ctx.species_by_type.get(t).?;
        },
        .random => util.random.item(
            ctx.random,
            ctx.species_by_type.items(),
        ).?.value,
        .themed => ctx.species_by_type.get(theme).?,
    };

    return switch (ctx.options.stats) {
        .follow_level => try randomSpeciesWithSimularTotalStats(
            ctx,
            pick_from,
            levelScaling(ctx.stats.min, ctx.stats.max, level),
        ),
        .simular => try randomSpeciesWithSimularTotalStats(
            ctx,
            pick_from,
            algo.fold(pokemon.stats, @as(u16, 0), algo.add),
        ),
        .random => util.random.item(ctx.random, pick_from.items()).?.key,
    };
}

fn randomSpeciesWithSimularTotalStats(
    ctx: *Context,
    pick_from: Set,
    total_stats: u16,
) !u16 {
    var min = @intCast(isize, total_stats);
    var max = min;

    ctx.simular.shrinkRetainingCapacity(0);
    while (ctx.simular.items.len < 25) : ({
        min -= 5;
        max += 5;
    }) {
        for (pick_from.items()) |s| {
            const p = ctx.data.pokemons.get(s.key).?;
            const total = @intCast(isize, algo.fold(&p.stats, @as(u16, 0), algo.add));
            if (min <= total and total <= max)
                try ctx.simular.append(ctx.allocator, s.key);
        }
    }

    return util.random.item(ctx.random, ctx.simular.items).?.*;
}

fn levelScaling(min: u16, max: u16, level: u16) u16 {
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
    return @floatToInt(u16, res);
}

fn hasMove(moves: []const MemberMoves.Entry, id: u16) bool {
    for (moves) |move| {
        if (move.value == id)
            return true;
    }

    return false;
}

fn MinMax(comptime T: type) type {
    return struct { min: T, max: T };
}

const LvlUpMoves = std.AutoArrayHashMapUnmanaged(u16, LvlUpMove);
const MemberMoves = std.AutoArrayHashMapUnmanaged(u8, u16);
const Moves = std.AutoArrayHashMapUnmanaged(u16, Move);
const Party = std.AutoArrayHashMapUnmanaged(u8, PartyMember);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);
const SpeciesBy = std.AutoArrayHashMapUnmanaged(u16, Set);
const Trainers = std.AutoArrayHashMapUnmanaged(u16, Trainer);

const Data = struct {
    pokedex: Set = Set{},
    pokemons: Pokemons = Pokemons{},
    trainers: Trainers = Trainers{},
    moves: Moves = Moves{},
    held_items: Set = Set{},

    fn pokedexPokemons(d: Data, allocator: *mem.Allocator) !Set {
        var res = Set{};
        errdefer res.deinit(allocator);

        for (d.pokemons.items()) |pokemon| {
            if (pokemon.value.catch_rate == 0)
                continue;
            if (d.pokedex.get(pokemon.value.pokedex_entry) == null)
                continue;

            _ = try res.put(allocator, pokemon.key, {});
        }

        return res;
    }

    fn minMaxStats(d: Data, species: Set) MinMax(u16) {
        var res = MinMax(u16){
            .min = math.maxInt(u16),
            .max = 0,
        };
        for (species.items()) |s| {
            const pokemon = d.pokemons.get(s.key).?;
            const total_stats = algo.fold(pokemon.stats, @as(u16, 0), algo.add);
            res.min = math.min(res.max, total_stats);
            res.max = math.max(res.max, total_stats);
        }
        return res;
    }

    fn speciesByType(d: Data, allocator: *mem.Allocator, species: Set) !SpeciesBy {
        var res = SpeciesBy{};
        errdefer {
            for (res.items()) |*set|
                set.value.deinit(allocator);
            res.deinit(allocator);
        }

        for (species.items()) |s| {
            const pokemon = d.pokemons.get(s.key).?;
            for (pokemon.types.items()) |t| {
                const set = try res.getOrPutValue(allocator, t.key, Set{});
                _ = try set.value.put(allocator, s.key, {});
            }
        }

        return res;
    }

    fn speciesByAbility(d: Data, allocator: *mem.Allocator, species: Set) !SpeciesBy {
        var res = SpeciesBy{};
        errdefer {
            for (res.values()) |set|
                set.deinit(allocator);
            res.deinit(allocator);
        }

        var sit = species.iterator();
        while (sit.next()) |s| {
            const pokemon = d.pokemons.get(s).?;
            var pit = pokemon.abilities.iterator();
            while (pit.next()) |a| {
                const set = try res.getOrPutValue(allocator, a, Set{});
                _ = try set.put(allocator, s);
            }
        }

        return res;
    }
};

const Trainer = struct {
    party_size: u8 = 0,
    party_type: format.PartyType = .none,
    party: Party = Party{},

    fn partyAverageLevel(trainer: Trainer) u8 {
        var count: u16 = 0;
        var sum: u16 = 0;
        for (trainer.party.items()) |member_kv| {
            const member = member_kv.value;
            sum += member.level orelse 0;
            count += @boolToInt(member.level != null);
        }
        if (count == 0)
            return 2;
        return @intCast(u8, sum / count);
    }
};

const PartyMember = struct {
    species: ?u16 = null,
    item: ?u16 = null,
    level: ?u8 = null,
    moves: MemberMoves = MemberMoves{},
};

const LvlUpMove = struct {
    level: ?u16 = null,
    id: ?u16 = null,
};

const Move = struct {
    power: ?u8 = null,
    accuracy: ?u8 = null,
    pp: ?u8 = null,
    type: ?u16 = null,
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
                const is_stab = p.types.get(m.type orelse math.maxInt(u16)) != null;
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
    pokedex_entry: u16 = math.maxInt(u16),
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
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=3
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=6
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=7
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--party-size-min=3" }, test_string, result_prefix ++
        \\.trainers[0].party_size=3
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[0].party[2].species=3
        \\.trainers[0].party[2].level=5
        \\.trainers[0].party[2].moves[0]=1
        \\.trainers[1].party_size=3
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=6
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[2].species=7
        \\.trainers[1].party[2].level=5
        \\.trainers[1].party[2].moves[0]=2
        \\.trainers[2].party_size=3
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=0
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=3
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[2].party[2].species=6
        \\.trainers[2].party[2].level=5
        \\.trainers[2].party[2].moves[0]=3
        \\.trainers[3].party_size=3
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=2
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\.trainers[3].party[2].species=0
        \\.trainers[3].party[2].level=5
        \\.trainers[3].party[2].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--party-size-max=1" }, test_string, result_prefix ++
        \\.trainers[0].party_size=1
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[1].party_size=1
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=0
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[2].party_size=1
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[3].party_size=1
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=1
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--party-size-pick-method=minimum" }, test_string, result_prefix ++
        \\.trainers[0].party_size=1
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[1].party_size=1
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=0
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[2].party_size=1
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[3].party_size=1
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=1
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--party-size-pick-method=random" }, test_string, result_prefix ++
        \\.trainers[0].party_size=1
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=0
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[1].party_size=4
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=3
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[2].species=6
        \\.trainers[1].party[2].level=5
        \\.trainers[1].party[2].moves[0]=2
        \\.trainers[1].party[3].species=7
        \\.trainers[1].party[3].level=5
        \\.trainers[1].party[3].moves[0]=2
        \\.trainers[2].party_size=4
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=0
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=6
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[2].party[2].species=7
        \\.trainers[2].party[2].level=5
        \\.trainers[2].party[2].moves[0]=3
        \\.trainers[2].party[3].species=1
        \\.trainers[2].party[3].level=5
        \\.trainers[2].party[3].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=1
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--items=unchanged" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=item
        \\.trainers[1].party[0].species=3
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].item=1
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].item=1
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=6
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=7
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--items=random" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=item
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].item=1
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=1
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].item=4
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=item
        \\.trainers[1].party[0].species=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].item=4
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=6
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].item=4
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=item
        \\.trainers[2].party[0].species=0
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].item=2
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=6
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].item=4
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=item
        \\.trainers[3].party[0].species=2
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].item=2
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=7
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].item=3
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--moves=unchanged" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=moves
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=moves
        \\.trainers[1].party[0].species=3
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=moves
        \\.trainers[2].party[0].species=6
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=7
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=moves
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    const moves_result =
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=moves
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=3
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
        \\.trainers[1].party[0].species=3
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=4
        \\.trainers[1].party[0].moves[1]=0
        \\.trainers[1].party[0].moves[2]=0
        \\.trainers[1].party[0].moves[3]=0
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[1].moves[1]=0
        \\.trainers[1].party[1].moves[2]=0
        \\.trainers[1].party[1].moves[3]=0
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=moves
        \\.trainers[2].party[0].species=6
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=7
        \\.trainers[2].party[0].moves[1]=0
        \\.trainers[2].party[0].moves[2]=0
        \\.trainers[2].party[0].moves[3]=0
        \\.trainers[2].party[1].species=7
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=8
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
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
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
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=3
        \\.trainers[0].party[0].moves[1]=0
        \\.trainers[0].party[0].moves[2]=0
        \\.trainers[0].party[0].moves[3]=0
        \\.trainers[0].party[1].species=1
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=2
        \\.trainers[0].party[1].moves[1]=0
        \\.trainers[0].party[1].moves[2]=0
        \\.trainers[0].party[1].moves[3]=0
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=moves
        \\.trainers[1].party[0].species=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[0].moves[1]=0
        \\.trainers[1].party[0].moves[2]=0
        \\.trainers[1].party[0].moves[3]=0
        \\.trainers[1].party[1].species=6
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=7
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
        \\.trainers[2].party[1].species=6
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=7
        \\.trainers[2].party[1].moves[1]=0
        \\.trainers[2].party[1].moves[2]=0
        \\.trainers[2].party[1].moves[3]=0
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=moves
        \\.trainers[3].party[0].species=2
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=3
        \\.trainers[3].party[0].moves[1]=0
        \\.trainers[3].party[0].moves[2]=0
        \\.trainers[3].party[0].moves[3]=0
        \\.trainers[3].party[1].species=7
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=8
        \\.trainers[3].party[1].moves[1]=0
        \\.trainers[3].party[1].moves[2]=0
        \\.trainers[3].party[1].moves[3]=0
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=0", "--moves=random" }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=moves
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[0].moves[1]=2
        \\.trainers[0].party[0].moves[2]=4
        \\.trainers[0].party[0].moves[3]=7
        \\.trainers[0].party[1].species=1
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].moves[0]=7
        \\.trainers[0].party[1].moves[1]=8
        \\.trainers[0].party[1].moves[2]=1
        \\.trainers[0].party[1].moves[3]=4
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=moves
        \\.trainers[1].party[0].species=6
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].moves[0]=8
        \\.trainers[1].party[0].moves[1]=3
        \\.trainers[1].party[0].moves[2]=2
        \\.trainers[1].party[0].moves[3]=4
        \\.trainers[1].party[1].species=7
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].moves[0]=5
        \\.trainers[1].party[1].moves[1]=2
        \\.trainers[1].party[1].moves[2]=7
        \\.trainers[1].party[1].moves[3]=8
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=moves
        \\.trainers[2].party[0].species=6
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
        \\.trainers[3].party[0].species=7
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=7
        \\.trainers[3].party[0].moves[1]=3
        \\.trainers[3].party[0].moves[2]=5
        \\.trainers[3].party[0].moves[3]=1
        \\.trainers[3].party[1].species=2
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
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=2
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
        \\.trainers[2].party[0].species=1
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=1
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=6
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
}
