const clap = @import("clap");
const format = @import("format");
const it = @import("ziter");
const std = @import("std");
const ston = @import("ston");
const util = @import("util");

const ascii = std.ascii;
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

const escape = util.escape;

const Program = @This();

allocator: mem.Allocator,
random: rand.Random,

options: struct {
    seed: u64,
    abilities: ThemeOption,
    items: ItemOption,
    moves: MoveOption,
    party_size_max: u8,
    party_size_min: u8,
    party_size_method: PartySizeMethod,
    stats: StatsOption,
    types: ThemeOption,
    excluded_pokemons: []const []const u8,
},

pokedex: Set = Set{},
pokemons: Pokemons = Pokemons{},
trainers: Trainers = Trainers{},
moves: Moves = Moves{},
held_items: Set = Set{},

// Precomputed data for later use. Initialized in `run`
species: Set = undefined,
species_by_ability: SpeciesBy = undefined,
species_by_type: SpeciesBy = undefined,
stats: MinMax(u16) = undefined,

// Containers we reuse often enough that keeping them around with
// their preallocated capacity is worth the hassel.
simular: std.ArrayListUnmanaged(u16) = std.ArrayListUnmanaged(u16){},
intersection: Set = Set{},

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

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Randomizes trainer parties.
    \\
;

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam(
        "-h, --help " ++
            "Display this help text and exit.",
    ) catch unreachable,
    clap.parseParam(
        "-i, --items <none|unchanged|random> " ++
            "The method used to picking held items. (default: none)",
    ) catch unreachable,
    clap.parseParam(
        "-o, --moves <none|unchanged|best|best_for_level|random_learnable|random> " ++
            "  The method used to picking moves. (default: none)",
    ) catch unreachable,
    clap.parseParam(
        "-m, --party-size-min <INT> " ++
            "The minimum size each trainers party is allowed to be. (default: 1)",
    ) catch unreachable,
    clap.parseParam(
        "-M, --party-size-max <INT> " ++
            "The maximum size each trainers party is allowed to be. (default: 6)",
    ) catch unreachable,
    clap.parseParam(
        "-p, --party-size <unchanged|minimum|random> " ++
            "The method used to pick the trainer party size. (default: unchanged)",
    ) catch unreachable,
    clap.parseParam(
        "-s, --seed <INT> " ++
            "The seed to use for random numbers. A random seed will be picked if this is not " ++
            "specified.",
    ) catch unreachable,
    clap.parseParam(
        "-S, --stats <random|simular|follow_level> " ++
            "The total stats the picked pokemon should have. (default: random)",
    ) catch unreachable,
    clap.parseParam(
        "-t, --types <random|same|themed> " ++
            "Which types each trainer should use. (default: random)",
    ) catch unreachable,
    clap.parseParam(
        "-a, --abilities <random|same|themed> " ++
            "Which ability each party member should have. (default: random)",
    ) catch unreachable,
    clap.parseParam(
        "-e, --exclude <STRING>... " ++
            "List of pokemons to never pick. Case insensitive. Supports wildcards like 'nido*'.",
    ) catch unreachable,
    clap.parseParam(
        "-v, --version " ++
            "Output version information and exit.",
    ) catch unreachable,
};

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const seed = try util.getSeed(args);
    const abilities_arg = args.option("--abilities") orelse "random";
    const items_arg = args.option("--items") orelse "none";
    const moves_arg = args.option("--moves") orelse "none";
    const party_size_max_arg = args.option("--party-size-max") orelse "6";
    const party_size_method_arg = args.option("--party-size") orelse "unchanged";
    const party_size_min_arg = args.option("--party-size-min") orelse "1";
    const stats_arg = args.option("--stats") orelse "random";
    const types_arg = args.option("--types") orelse "random";
    const excluded_pokemons_arg = args.options("--exclude");

    const party_size_min = fmt.parseUnsigned(u8, party_size_min_arg, 10);
    const party_size_max = fmt.parseUnsigned(u8, party_size_max_arg, 10);
    const abilities = std.meta.stringToEnum(ThemeOption, abilities_arg) orelse {
        log.err("--abilities does not support '{s}'", .{abilities_arg});
        return error.InvalidArgument;
    };
    const items = std.meta.stringToEnum(ItemOption, items_arg) orelse {
        log.err("--items does not support '{s}'", .{items_arg});
        return error.InvalidArgument;
    };
    const party_size_method = std.meta.stringToEnum(
        PartySizeMethod,
        party_size_method_arg,
    ) orelse {
        log.err("--party-size-pick-method does not support '{s}'", .{party_size_method_arg});
        return error.InvalidArgument;
    };
    const moves = std.meta.stringToEnum(MoveOption, moves_arg) orelse {
        log.err("--moves does not support '{s}'", .{moves_arg});
        return error.InvalidArgument;
    };
    const stats = std.meta.stringToEnum(StatsOption, stats_arg) orelse {
        log.err("--stats does not support '{s}'", .{stats_arg});
        return error.InvalidArgument;
    };
    const types = std.meta.stringToEnum(ThemeOption, types_arg) orelse {
        log.err("--types does not support '{s}'", .{types_arg});
        return error.InvalidArgument;
    };
    for ([_]struct { arg: []const u8, value: []const u8, check: anyerror!u8 }{
        .{ .arg = "--party-size-min", .value = party_size_min_arg, .check = party_size_min },
        .{ .arg = "--party-size-max", .value = party_size_max_arg, .check = party_size_max },
    }) |arg| {
        if (arg.check) |_| {} else |_| {
            log.err("Invalid value for {s}: {s}", .{ arg.arg, arg.value });
            return error.InvalidArgument;
        }
    }

    var excluded_pokemons = try std.ArrayList([]const u8)
        .initCapacity(allocator, excluded_pokemons_arg.len);
    for (excluded_pokemons_arg) |exclude|
        excluded_pokemons.appendAssumeCapacity(try ascii.allocLowerString(allocator, exclude));

    return Program{
        .allocator = allocator,
        .random = undefined, // Initialized in `run`

        .options = .{
            .seed = seed,
            .abilities = abilities,
            .items = items,
            .moves = moves,
            .party_size_max = party_size_max catch unreachable,
            .party_size_min = party_size_min catch unreachable,
            .party_size_method = party_size_method,
            .stats = stats,
            .types = types,
            .excluded_pokemons = excluded_pokemons.toOwnedSlice(),
        },
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    const allocator = program.allocator;
    try format.io(allocator, stdio.in, stdio.out, program, useGame);

    const species = try pokedexPokemons(
        allocator,
        program.pokedex,
        program.pokemons,
        program.options.excluded_pokemons,
    );
    program.random = rand.DefaultPrng.init(program.options.seed).random();
    program.species = species;
    program.species_by_ability = try speciesByAbility(allocator, program.pokemons, species);
    program.species_by_type = try speciesByType(allocator, program.pokemons, species);
    program.stats = minMaxStats(program.pokemons, species);

    try program.randomize();
    try program.output(stdio.out);
}

fn output(program: *Program, writer: anytype) !void {
    try ston.serialize(writer, .{ .trainers = program.trainers });
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try program.pokedex.put(allocator, pokedex.index, {});
            return error.ParserFailed;
        },
        .pokemons => |pokemons| {
            const pokemon = (try program.pokemons.getOrPutValue(allocator, pokemons.index, .{}))
                .value_ptr;
            switch (pokemons.value) {
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .pokedex_entry => |pokedex_entry| pokemon.pokedex_entry = pokedex_entry,
                .name => |name| {
                    pokemon.name = try escape.default.unescapeAlloc(allocator, name);
                    for (pokemon.name) |*c|
                        c.* = ascii.toLower(c.*);
                },
                .stats => |stats| {
                    const stat = @enumToInt(stats);
                    if (pokemon.stats[stat] > stats.value()) {
                        pokemon.total_stats -= pokemon.stats[stat] - stats.value();
                    } else {
                        pokemon.total_stats += stats.value() - pokemon.stats[stat];
                    }
                    pokemon.stats[stat] = stats.value();
                },
                .types => |types| _ = try pokemon.types.put(allocator, types.value, {}),
                .abilities => |ability| _ = try pokemon.abilities.put(
                    allocator,
                    ability.index,
                    ability.value,
                ),
                .moves => |moves| {
                    const move = (try pokemon.lvl_up_moves.getOrPutValue(
                        allocator,
                        moves.index,
                        .{},
                    )).value_ptr;
                    format.setField(move, moves.value);
                },
                .base_exp_yield,
                .ev_yield,
                .items,
                .gender_ratio,
                .egg_cycles,
                .base_friendship,
                .growth_rate,
                .egg_groups,
                .color,
                .evos,
                .tms,
                .hms,
                => return error.ParserFailed,
            }
            return error.ParserFailed;
        },
        .trainers => |trainers| {
            const trainer = (try program.trainers.getOrPutValue(allocator, trainers.index, .{}))
                .value_ptr;
            switch (trainers.value) {
                .party_size => |party_size| trainer.party_size = party_size,
                .party_type => |party_type| trainer.party_type = party_type,
                .party => |party| {
                    const member = (try trainer.party.getOrPutValue(allocator, party.index, .{}))
                        .value_ptr;
                    switch (party.value) {
                        .species => |species| member.species = species,
                        .level => |level| member.level = level,
                        .item => |item| member.item = item,
                        .ability => |ability| member.ability = ability,
                        .moves => |moves| _ = try member.moves.put(
                            allocator,
                            moves.index,
                            moves.value,
                        ),
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
                    _ = try program.held_items.put(allocator, items.index, {});
                return error.ParserFailed;
            },
            .name,
            .description,
            .price,
            .pocket,
            => return error.ParserFailed,
        },
        .moves => |moves| {
            const move = (try program.moves.getOrPutValue(allocator, moves.index, .{}))
                .value_ptr;
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

fn randomize(program: *Program) !void {
    if (program.species_by_type.count() == 0) {
        std.log.err("No types where found. Cannot randomize.", .{});
        return;
    }

    for (program.trainers.values()) |*trainer| {
        // Trainers with 0 party members are considered "invalid" trainers
        // and will not be randomized.
        if (trainer.party_size == 0)
            continue;
        try program.randomizeTrainer(trainer);
    }
}

fn randomizeTrainer(program: *Program, trainer: *Trainer) !void {
    const allocator = program.allocator;
    const themes = Themes{
        .type = switch (program.options.types) {
            .themed => util.random.item(program.random, program.species_by_type.keys()).?.*,
            else => undefined,
        },
        .ability = switch (program.options.abilities) {
            .themed => util.random.item(program.random, program.species_by_ability.keys()).?.*,
            else => undefined,
        },
    };

    const wants_moves = switch (program.options.moves) {
        .unchanged => trainer.party_type.haveMoves(),
        .none => false,
        .best,
        .best_for_level,
        .random_learnable,
        .random,
        => true,
    };
    const wants_items = switch (program.options.items) {
        .unchanged => trainer.party_type.haveItem(),
        .none => false,
        .random => true,
    };

    trainer.party_size = switch (program.options.party_size_method) {
        .unchanged => math.clamp(
            trainer.party_size,
            program.options.party_size_min,
            program.options.party_size_max,
        ),
        .random => program.random.intRangeAtMost(
            u8,
            program.options.party_size_min,
            program.options.party_size_max,
        ),
        .minimum => program.options.party_size_min,
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
        const result = try trainer.party.getOrPut(allocator, i);
        if (!result.found_existing) {
            const member = trainer.party.values()[party_member];
            result.value_ptr.* = .{
                .species = member.species,
                .item = member.item,
                .level = member.level,
                .moves = try member.moves.clone(allocator),
            };
            party_member += 1;
            party_member %= @intCast(u8, party_member_max);
        }
    }

    for (trainer.party.values()[0..trainer.party_size]) |*member| {
        try randomizePartyMember(program, themes, trainer.*, member);
        switch (program.options.items) {
            .unchanged => {},
            .none => member.item = null,
            .random => member.item = util.random.item(
                program.random,
                program.held_items.keys(),
            ).?.*,
        }

        switch (program.options.moves) {
            .none, .unchanged => {},
            .best, .best_for_level => if (member.species) |species| {
                const pokemon = program.pokemons.get(species).?;
                const level = switch (program.options.moves) {
                    .best => math.maxInt(u8),
                    .best_for_level => member.level orelse math.maxInt(u8),
                    else => unreachable,
                };
                fillWithBestMovesForLevel(
                    program.moves,
                    pokemon,
                    level,
                    &member.moves,
                );
            },
            .random_learnable => if (member.species) |species| {
                const pokemon = program.pokemons.get(species).?;
                fillWithRandomLevelUpMoves(program.random, pokemon.lvl_up_moves, &member.moves);
            },
            .random => fillWithRandomMoves(program.random, program.moves, &member.moves),
        }
    }
}

fn fillWithBestMovesForLevel(
    all_moves: Moves,
    pokemon: Pokemon,
    level: u8,
    moves: *MemberMoves,
) void {
    // Before pick best moves, we make sure the Pokémon has no moves.
    mem.set(u16, moves.values(), 0);

    // Go over all level up moves, and replace the current moves with better moves
    // as we find them
    for (pokemon.lvl_up_moves.values()) |lvl_up_move| {
        if (lvl_up_move.id == 0)
            continue;
        if (level < lvl_up_move.level)
            continue;
        // Pokémon already have this move. We don't wonna have the same move twice
        if (hasMove(moves.values(), lvl_up_move.id))
            continue;

        const this_move = all_moves.get(lvl_up_move.id) orelse continue;
        const this_move_r = RelativeMove.from(pokemon, this_move);

        for (moves.values()) |*move| {
            const prev_move = all_moves.get(move.*) orelse {
                // Could not find info about this move. Assume it's and invalid or bad
                // move and replace it.
                move.* = lvl_up_move.id;
                break;
            };

            const prev_move_r = RelativeMove.from(pokemon, prev_move);
            if (!this_move_r.lessThan(prev_move_r)) {
                // We found a move that is better what the Pokémon already have!
                move.* = lvl_up_move.id;
                break;
            }
        }
    }
}

fn fillWithRandomMoves(random: rand.Random, all_moves: Moves, moves: *MemberMoves) void {
    const has_null_move = all_moves.get(0) != null;
    for (moves.values()) |*move, i| {
        // We need to have more moves in the game than the party member can have,
        // otherwise, we cannot pick only unique moves. Also, move `0` is the
        // `null` move, so we don't count that as a move we can pick from.
        if (all_moves.count() - @boolToInt(has_null_move) <= i) {
            move.* = 0;
            continue;
        }

        // Loop until we have picked a move that the party member does not already
        // have.
        move.* = while (true) {
            const pick = util.random.item(random, all_moves.keys()).?.*;
            if (pick != 0 and !hasMove(moves.values()[0..i], pick))
                break pick;
        } else unreachable;
    }
}

fn fillWithRandomLevelUpMoves(
    random: rand.Random,
    lvl_up_moves: LvlUpMoves,
    moves: *MemberMoves,
) void {
    for (moves.values()) |*move, i| {
        // We need to have more moves in the learnset than the party member can have,
        // otherwise, we cannot pick only unique moves.
        // TODO: This code does no take into account that `lvl_up_moves` can contain
        //       duplicates or moves with `id == null`. We need to do a count of
        //       "valid moves" from the learnset and do this check against that
        //       instead.
        if (lvl_up_moves.count() <= i) {
            move.* = 0;
            continue;
        }

        // Loop until we have picked a move that the party member does not already
        // have.
        move.* = while (true) {
            const pick = util.random.item(random, lvl_up_moves.values()).?.id;
            if (pick != 0 and !hasMove(moves.values()[0..i], pick))
                break pick;
        } else unreachable;
    }
}

const Themes = struct {
    type: u16,
    ability: u16,
};

fn randomizePartyMember(
    program: *Program,
    themes: Themes,
    trainer: Trainer,
    member: *PartyMember,
) !void {
    const allocator = program.allocator;
    const species = member.species orelse return;
    const level = member.level orelse trainer.partyAverageLevel();
    const ability_index = member.ability orelse 0;
    const type_set = switch (program.options.types) {
        .same => blk: {
            const pokemon = program.pokemons.get(species) orelse
                break :blk program.species;
            if (pokemon.types.count() == 0)
                break :blk program.species;

            const t = util.random.item(program.random, pokemon.types.keys()).?.*;
            break :blk program.species_by_type.get(t).?;
        },
        .themed => program.species_by_type.get(themes.type).?,
        .random => program.species,
    };

    var new_ability: ?u16 = null;
    const ability_set = switch (program.options.abilities) {
        .same => blk: {
            const pokemon = program.pokemons.get(species) orelse
                break :blk program.species;
            const ability = pokemon.abilities.get(ability_index) orelse
                break :blk program.species;
            if (ability == 0)
                break :blk program.species;
            new_ability = ability;
            break :blk program.species_by_ability.get(ability).?;
        },
        .themed => blk: {
            new_ability = themes.ability;
            break :blk program.species_by_ability.get(themes.ability).?;
        },
        .random => program.species,
    };

    if (program.options.abilities != .random and program.options.types != .random) {
        // The intersection between the type_set and ability_set will give
        // us all pokémons that have a certain type+ability pair. This is
        // the set we will pick from.
        var intersection = program.intersection.promote(allocator);
        intersection.clearRetainingCapacity();
        try util.set.intersectInline(&intersection, ability_set, type_set);
        program.intersection = intersection.unmanaged;
    }

    // Pick the first set that has items in it.
    const pick_from = if (program.intersection.count() != 0)
        program.intersection
    else if (program.options.abilities != .random and ability_set.count() != 0)
        ability_set
    else if (program.options.types != .random and type_set.count() != 0)
        type_set
    else
        program.species;

    // When we have picked a new species for our Pokémon we also need
    // to fix the ability the Pokémon have, if we're picking Pokémons
    // based on ability.
    defer if (member.species) |new_species| done: {
        const ability_to_find = new_ability orelse break :done;
        const pokemon = program.pokemons.get(new_species) orelse break :done;

        // Find the index of the ability we want the party member to
        // have. If we don't find the ability. The best we can do is
        // just let the Pokémon keep the ability it already has.
        if (findAbility(pokemon.abilities.iterator(), ability_to_find)) |entry|
            member.ability = entry.key_ptr.*;
    };

    switch (program.options.stats) {
        .follow_level => {
            member.species = try randomSpeciesWithSimularTotalStats(
                program,
                pick_from,
                levelScaling(program.stats.min, program.stats.max, level),
            );
            return;
        },
        .simular => if (program.pokemons.get(species)) |pokemon| {
            member.species = try randomSpeciesWithSimularTotalStats(
                program,
                pick_from,
                pokemon.total_stats,
            );
            return;
        } else {},
        .random => {},
    }

    // If the above switch didn't return, the best we can do is just pick a
    // random Pokémon from the pick_from set
    member.species = util.random.item(program.random, pick_from.keys()).?.*;
}

fn randomSpeciesWithSimularTotalStats(program: *Program, pick_from: Set, total_stats: u16) !u16 {
    const allocator = program.allocator;
    var min = @intCast(isize, total_stats);
    var max = min;

    program.simular.shrinkRetainingCapacity(0);
    while (program.simular.items.len < 25) : ({
        min -= 5;
        max += 5;
    }) {
        for (pick_from.keys()) |s| {
            const p = program.pokemons.get(s).?;
            const total = @intCast(isize, p.total_stats);
            if (min <= total and total <= max)
                try program.simular.append(allocator, s);
        }
    }

    return util.random.item(program.random, program.simular.items).?.*;
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

fn hasMove(moves: []const u16, id: u16) bool {
    return it.anyEx(moves, id, struct {
        fn f(m: u16, e: u16) bool {
            return m == e;
        }
    }.f);
}

fn findAbility(abilities: Abilities.Iterator, ability: u16) ?Abilities.Entry {
    return it.findEx(abilities, ability, struct {
        fn f(m: u16, e: Abilities.Entry) bool {
            return m == e.value_ptr.*;
        }
    }.f);
}

fn MinMax(comptime T: type) type {
    return struct { min: T, max: T };
}

const Abilities = std.AutoArrayHashMapUnmanaged(u8, u16);
const LvlUpMoves = std.AutoArrayHashMapUnmanaged(u16, LvlUpMove);
const MemberMoves = std.AutoArrayHashMapUnmanaged(u8, u16);
const Moves = std.AutoArrayHashMapUnmanaged(u16, Move);
const Party = std.AutoArrayHashMapUnmanaged(u8, PartyMember);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);
const SpeciesBy = std.AutoArrayHashMapUnmanaged(u16, Set);
const Trainers = std.AutoArrayHashMapUnmanaged(u16, Trainer);

fn pokedexPokemons(
    allocator: mem.Allocator,
    pokedex: Set,
    pokemons: Pokemons,
    excluded_pokemons: []const []const u8,
) !Set {
    var res = Set{};
    errdefer res.deinit(allocator);

    outer: for (pokemons.values()) |pokemon, i| {
        const species = pokemons.keys()[i];
        if (pokemon.catch_rate == 0)
            continue;
        if (pokedex.get(pokemon.pokedex_entry) == null)
            continue;

        for (excluded_pokemons) |glob| {
            if (util.glob.match(glob, pokemon.name))
                continue :outer;
        }

        _ = try res.put(allocator, species, {});
    }

    return res;
}

fn minMaxStats(pokemons: Pokemons, species: Set) MinMax(u16) {
    var res = MinMax(u16){
        .min = math.maxInt(u16),
        .max = 0,
    };
    for (species.keys()) |s| {
        const pokemon = pokemons.get(s).?;
        res.min = math.min(res.min, pokemon.total_stats);
        res.max = math.max(res.max, pokemon.total_stats);
    }
    return res;
}

fn speciesByType(allocator: mem.Allocator, pokemons: Pokemons, species: Set) !SpeciesBy {
    var res = SpeciesBy{};
    errdefer {
        for (res.values()) |*set|
            set.deinit(allocator);
        res.deinit(allocator);
    }

    for (species.keys()) |s| {
        const pokemon = pokemons.get(s).?;
        for (pokemon.types.keys()) |t| {
            const set = (try res.getOrPutValue(allocator, t, .{})).value_ptr;
            _ = try set.put(allocator, s, {});
        }
    }

    return res;
}

fn speciesByAbility(allocator: mem.Allocator, pokemons: Pokemons, species: Set) !SpeciesBy {
    var res = SpeciesBy{};
    errdefer {
        for (res.values()) |*set|
            set.deinit(allocator);
        res.deinit(allocator);
    }

    for (species.keys()) |s| {
        const pokemon = pokemons.get(s).?;
        for (pokemon.abilities.values()) |ability| {
            if (ability == 0)
                continue;
            const set = (try res.getOrPutValue(allocator, ability, .{})).value_ptr;
            _ = try set.put(allocator, s, {});
        }
    }

    return res;
}

const Trainer = struct {
    party_size: u8 = 0,
    party_type: format.PartyType = .none,
    party: Party = Party{},

    fn partyAverageLevel(trainer: Trainer) u8 {
        var count: u16 = 0;
        var sum: u16 = 0;
        for (trainer.party.values()) |member| {
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
    ability: ?u8 = null,
    moves: MemberMoves = MemberMoves{},
};

const LvlUpMove = struct {
    level: u16 = 0,
    id: u16 = 0,
};

const Move = struct {
    power: u8 = 0,
    accuracy: u8 = 0,
    pp: u8 = 0,
    type: u16 = math.maxInt(u16),
};

// Represents a moves power in relation to the pokemon who uses it
const RelativeMove = struct {
    power: u16,
    accuracy: u8,
    pp: u8,

    fn from(p: Pokemon, m: Move) RelativeMove {
        const is_stab = p.types.get(m.type) != null;
        return RelativeMove{
            .power = @as(u16, m.power) + (m.power / 2) * @boolToInt(is_stab),
            .accuracy = m.accuracy,
            .pp = m.pp,
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
    total_stats: u16 = 0,
    types: Set = Set{},
    abilities: Abilities = Abilities{},
    lvl_up_moves: LvlUpMoves = LvlUpMoves{},
    catch_rate: usize = 1,
    pokedex_entry: u16 = math.maxInt(u16),
    name: []u8 = "",
};

test "tm35-rand-parties" {
    const H = struct {
        fn pokemon(
            comptime id: []const u8,
            comptime stat: []const u8,
            comptime types: []const u8,
            comptime ability: []const u8,
            comptime move_: []const u8,
            comptime catch_rate: []const u8,
            comptime name: []const u8,
        ) []const u8 {
            return ".pokedex[" ++ id ++ "].height=0\n" ++
                ".pokemons[" ++ id ++ "].pokedex_entry=" ++ id ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.hp=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.attack=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.defense=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.speed=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.sp_attack=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].stats.sp_defense=" ++ stat ++ "\n" ++
                ".pokemons[" ++ id ++ "].types[0]=" ++ types ++ "\n" ++
                ".pokemons[" ++ id ++ "].types[1]=" ++ types ++ "\n" ++
                ".pokemons[" ++ id ++ "].abilities[0]=" ++ ability ++ "\n" ++
                ".pokemons[" ++ id ++ "].moves[0].id=" ++ move_ ++ "\n" ++
                ".pokemons[" ++ id ++ "].moves[0].level=0\n" ++
                ".pokemons[" ++ id ++ "].catch_rate=" ++ catch_rate ++ "\n" ++
                ".pokemons[" ++ id ++ "].name=" ++ name ++ "\n";
        }
        fn trainer(
            comptime id: []const u8,
            comptime species: []const u8,
            comptime item_: ?[]const u8,
            comptime move_: ?[]const u8,
        ) []const u8 {
            const prefix = ".trainers[" ++ id ++ "]";
            const _type: []const u8 = if (move_ != null and item_ != null) "both" //
            else if (move_) |_| "moves" //
            else if (item_) |_| "item" //
            else "none";

            return prefix ++ ".party_size=2\n" ++
                prefix ++ ".party_type=" ++ _type ++ "\n" ++
                prefix ++ ".party[0].species=" ++ species ++ "\n" ++
                prefix ++ ".party[0].level=5\n" ++
                prefix ++ ".party[0].ability=0\n" ++
                (if (item_) |i| prefix ++ ".party[0].item=" ++ i ++ "\n" else "") ++
                (if (move_) |m| prefix ++ ".party[0].moves[0]=" ++ m ++ "\n" else "") ++
                prefix ++ ".party[1].species=" ++ species ++ "\n" ++
                prefix ++ ".party[1].level=5\n" ++
                prefix ++ ".party[1].ability=0\n" ++
                (if (item_) |i| prefix ++ ".party[1].item=" ++ i ++ "\n" else "") ++
                (if (move_) |m| prefix ++ ".party[1].moves[0]=" ++ m ++ "\n" else "");
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

    const result_prefix = comptime H.pokemon("0", "10", "0", "0", "1", "1", "pokemon 0") ++
        H.pokemon("1", "15", "16", "1", "2", "1", "pokemon 1") ++
        H.pokemon("2", "20", "2", "2", "3", "1", "pokemon 2") ++
        H.pokemon("3", "25", "12", "3", "4", "1", "pokemon 3") ++
        H.pokemon("4", "30", "10", "1", "5", "1", "pokemon 4") ++
        H.pokemon("5", "35", "11", "2", "6", "1", "pokemon 5") ++
        H.pokemon("6", "40", "5", "3", "7", "1", "pokemon 6") ++
        H.pokemon("7", "45", "4", "1", "8", "1", "pokemon 7") ++
        H.pokemon("8", "45", "4", "2", "8", "0", "pokemon 8") ++
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

    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=3
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=2
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=0
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=0
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=6
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--party-size-min=3",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=3
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=3
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[0].party[2].species=2
        \\.trainers[0].party[2].level=5
        \\.trainers[0].party[2].moves[0]=1
        \\.trainers[1].party_size=3
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=0
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=3
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[1].party[2].species=0
        \\.trainers[1].party[2].level=5
        \\.trainers[1].party[2].moves[0]=2
        \\.trainers[2].party_size=3
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=6
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=6
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[2].party[2].species=2
        \\.trainers[2].party[2].level=5
        \\.trainers[2].party[2].moves[0]=3
        \\.trainers[3].party_size=3
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=2
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\.trainers[3].party[2].species=0
        \\.trainers[3].party[2].level=5
        \\.trainers[3].party[2].moves[0]=4
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--party-size-max=1",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=1
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=1
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=3
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].item=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=1
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=1
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--party-size=minimum",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=1
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=1
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=3
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].item=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=1
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=1
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--party-size=random",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=3
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=2
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=3
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=0
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=3
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=6
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[2].party[2].species=0
        \\.trainers[2].party[2].level=5
        \\.trainers[2].party[2].moves[0]=3
        \\.trainers[3].party_size=1
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--items=unchanged",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=3
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=item
        \\.trainers[1].party[0].species=2
        \\.trainers[1].party[0].item=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=0
        \\.trainers[1].party[1].item=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=0
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=6
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--items=random",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=item
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].item=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=2
        \\.trainers[0].party[1].item=1
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=item
        \\.trainers[1].party[0].species=3
        \\.trainers[1].party[0].item=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=6
        \\.trainers[1].party[1].item=4
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=item
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].item=1
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].item=1
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=item
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].item=1
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=0
        \\.trainers[3].party[1].item=2
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--moves=unchanged",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=moves
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=3
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=moves
        \\.trainers[1].party[0].species=2
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=0
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=moves
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=0
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=moves
        \\.trainers[3].party[0].species=6
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    const moves_result =
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=moves
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=3
        \\.trainers[0].party[1].species=3
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=4
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=moves
        \\.trainers[1].party[0].species=2
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=3
        \\.trainers[1].party[1].species=0
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=1
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=moves
        \\.trainers[2].party[0].species=3
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=4
        \\.trainers[2].party[1].species=0
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=1
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=moves
        \\.trainers[3].party[0].species=6
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=7
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=7
        \\
    ;
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--moves=best",
    }, test_string, result_prefix ++ moves_result);
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--moves=best_for_level",
    }, test_string, result_prefix ++ moves_result);
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--moves=random_learnable",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=moves
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=3
        \\.trainers[0].party[1].species=2
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=3
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=moves
        \\.trainers[1].party[0].species=3
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=4
        \\.trainers[1].party[1].species=6
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=7
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=moves
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=moves
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=1
        \\.trainers[3].party[1].species=0
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=1
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--moves=random",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=moves
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=3
        \\.trainers[0].party[1].species=2
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=4
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=moves
        \\.trainers[1].party[0].species=0
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=7
        \\.trainers[1].party[1].species=6
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=moves
        \\.trainers[2].party[0].species=0
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=2
        \\.trainers[2].party[1].species=0
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=moves
        \\.trainers[3].party[0].species=5
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=1
        \\.trainers[3].party[1].species=2
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=3
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--types=same",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=0
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=0
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=1
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=3
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=3
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--types=themed",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=2
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=0
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=0
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=6
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=6
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=0
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=0
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--abilities=same",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=2
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=3
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=4
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=2
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=2
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=6
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=6
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=0",
        "--abilities=themed",
    }, test_string, result_prefix ++
        \\.trainers[0].party_size=2
        \\.trainers[0].party_type=none
        \\.trainers[0].party[0].species=4
        \\.trainers[0].party[0].level=5
        \\.trainers[0].party[0].ability=0
        \\.trainers[0].party[0].moves[0]=1
        \\.trainers[0].party[1].species=4
        \\.trainers[0].party[1].level=5
        \\.trainers[0].party[1].ability=0
        \\.trainers[0].party[1].moves[0]=1
        \\.trainers[1].party_size=2
        \\.trainers[1].party_type=none
        \\.trainers[1].party[0].species=4
        \\.trainers[1].party[0].level=5
        \\.trainers[1].party[0].ability=0
        \\.trainers[1].party[0].moves[0]=2
        \\.trainers[1].party[1].species=1
        \\.trainers[1].party[1].level=5
        \\.trainers[1].party[1].ability=0
        \\.trainers[1].party[1].moves[0]=2
        \\.trainers[2].party_size=2
        \\.trainers[2].party_type=none
        \\.trainers[2].party[0].species=6
        \\.trainers[2].party[0].level=5
        \\.trainers[2].party[0].ability=0
        \\.trainers[2].party[0].moves[0]=3
        \\.trainers[2].party[1].species=3
        \\.trainers[2].party[1].level=5
        \\.trainers[2].party[1].ability=0
        \\.trainers[2].party[1].moves[0]=3
        \\.trainers[3].party_size=2
        \\.trainers[3].party_type=none
        \\.trainers[3].party[0].species=1
        \\.trainers[3].party[0].level=5
        \\.trainers[3].party[0].ability=0
        \\.trainers[3].party[0].moves[0]=4
        \\.trainers[3].party[1].species=1
        \\.trainers[3].party[1].level=5
        \\.trainers[3].party[1].ability=0
        \\.trainers[3].party[1].moves[0]=4
        \\
    );

    // Test excluding system by running 100 seeds and checking that none of them pick the
    // excluded pokemons
    var seed: u8 = 0;
    while (seed < 100) : (seed += 1) {
        var buf: [100]u8 = undefined;
        const seed_arg = try fmt.bufPrint(&buf, "--seed={}", .{seed});
        const out = try util.testing.runProgram(Program, .{ .args = &[_][]const u8{
            "--exclude=pokemon 2",
            "--exclude=pokemon 4",
            seed_arg,
        }, .in = test_string });
        defer testing.allocator.free(out);

        try testing.expect(mem.indexOf(u8, out, ".species=2") == null);
        try testing.expect(mem.indexOf(u8, out, ".species=4") == null);
    }
}
