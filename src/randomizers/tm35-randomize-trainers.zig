const clap = @import("clap");
const core = @import("core");
const std = @import("std");
const ston = @import("ston");
const util = @import("util");

const ascii = std.ascii;
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

const format = core.format;

const escape = util.escape.default;

const Program = @This();

allocator: mem.Allocator,
random: rand.Random,

options: Options,

pokedex: Set = Set{},
pokemons: Pokemons = Pokemons{},
trainers: Trainers = Trainers{},
trainer_names: TrainerNames = TrainerNames{},
moves: Moves = Moves{},
held_items: Set = Set{},

// Precomputed data for later use. Initialized in `run`
species: Set = undefined,
species_by_ability: SpeciesBy = undefined,
species_by_type: SpeciesBy = undefined,
species_by_dual_type: SpeciesByDualType = undefined,
stats: MinMax(u16) = undefined,

// Containers we reuse often enough that keeping them around with
// their preallocated capacity is worth the hassel.
simular: std.ArrayListUnmanaged(u16) = std.ArrayListUnmanaged(u16){},
intersection: Set = Set{},
pick_from_excluded: Set = Set{},

const Options = struct {
    seed: u64,
    abilities: AbilityThemeOption,
    avoid_same: bool,
    held_items: HeldItemOption,
    moves: MoveOption,
    party_size_max: u8,
    party_size_min: u8,
    party_size: PartySizeOption,
    party_pokemons: PartyPokemonsOption,
    stats: StatsOption,
    types: TypeThemeOption,
    excluded_pokemons: []const []const u8,
    excluded_trainers: []const []const u8,
    included_pokemons: []const []const u8,
    included_trainers: []const []const u8,
};

const HeldItemOption = enum {
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

const AbilityThemeOption = enum {
    same,
    random,
    themed,
};

const TypeThemeOption = enum {
    same,
    random,
    themed,
    dual_themed,
};

const StatsOption = enum {
    random,
    simular,
    follow_level,
};

const PartySizeOption = enum {
    unchanged,
    minimum,
    random,
};

const PartyPokemonsOption = enum {
    unchanged,
    randomize,
};

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Randomizes trainer parties.
    \\
;

pub const parsers = .{
    .INT = clap.parsers.int(u64, 0),
    .STRING = clap.parsers.string,
    .@"none|unchanged|best|best_for_level|random_learnable|random" = clap.parsers.enumeration(MoveOption),
    .@"none|unchanged|random" = clap.parsers.enumeration(HeldItemOption),
    .@"unchanged|randomize" = clap.parsers.enumeration(PartyPokemonsOption),
    .@"unchanged|minimum|random" = clap.parsers.enumeration(PartySizeOption),
    .@"random|simular|follow_level" = clap.parsers.enumeration(StatsOption),
    .@"random|same|themed" = clap.parsers.enumeration(AbilityThemeOption),
    .@"random|same|themed|dual_themed" = clap.parsers.enumeration(TypeThemeOption),
};

pub const params = clap.parseParamsComptime(
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\--avoid-same
    \\        If possible, avoid having multiple party members of the same species in a party.
    \\
    \\--held-items <none|unchanged|random>
    \\        The method used to picking held items. (default: unchanged)
    \\
    \\--moves <none|unchanged|best|best_for_level|random_learnable|random>
    \\        The method used to picking moves. (default: none)
    \\
    \\-p, --party-pokemons <unchanged|randomize>
    \\        Whether the trainers pokemons should be randomized. (default: unchanged)
    \\
    \\-m, --party-size-min <INT>
    \\        The minimum size each trainers party is allowed to be. (default: 1)
    \\
    \\-M, --party-size-max <INT>
    \\        The maximum size each trainers party is allowed to be. (default: 6)
    \\
    \\--party-size <unchanged|minimum|random>
    \\        The method used to pick the trainer party size. (default: unchanged)
    \\
    \\-s, --seed <INT>
    \\        The seed to use for random numbers. A random seed will be picked if this is not
    \\        specified.
    \\
    \\-S, --stats <random|simular|follow_level>
    \\        The total stats the picked pokemon should have if pokemons are randomized.
    \\        (default: random)
    \\
    \\-t, --types <random|same|themed|dual_themed>
    \\        Which types each trainer should use if pokemons are randomized. (default: random)
    \\
    \\-a, --abilities <random|same|themed>
    \\        Which ability each party member should have. (default: random)
    \\
    \\--exclude-trainer <STRING>...
    \\        List of trainers to not change. Case insensitive. Supports wildcards like 'grunt*'.
    \\
    \\--include-trainer <STRING>...
    \\        List of trainers to change, ignoring --exlude-trainer. Case insensitive. Supports
    \\        wildcards like 'grunt*'.
    \\
    \\--exclude-pokemon <STRING>...
    \\        List of pokemons to never pick. Case insensitive. Supports wildcards like 'nido*'.
    \\
    \\--include-pokemon <STRING>...
    \\        List of pokemons to pick from, ignoring --exlude-trainer. Case insensitive.
    \\        Supports wildcards like 'nido*'.
    \\
    \\-v, --version
    \\        Output version information and exit.
    \\
);

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const excluded_pokemons_arg = args.args.@"exclude-pokemon";
    const excluded_pokemons = try allocator.alloc([]const u8, excluded_pokemons_arg.len);
    for (excluded_pokemons, excluded_pokemons_arg) |*excluded, arg|
        excluded.* = try ascii.allocLowerString(allocator, arg);

    const excluded_trainers_arg = args.args.@"exclude-trainer";
    const excluded_trainers = try allocator.alloc([]const u8, excluded_trainers_arg.len);
    for (excluded_trainers, excluded_trainers_arg) |*excluded, arg|
        excluded.* = try ascii.allocLowerString(allocator, arg);

    const included_pokemons_arg = args.args.@"include-pokemon";
    const included_pokemons = try allocator.alloc([]const u8, included_pokemons_arg.len);
    for (included_pokemons, included_pokemons_arg) |*included, arg|
        included.* = try ascii.allocLowerString(allocator, arg);

    const included_trainers_arg = args.args.@"include-trainer";
    const included_trainers = try allocator.alloc([]const u8, included_trainers_arg.len);
    for (included_trainers, included_trainers_arg) |*included, arg|
        included.* = try ascii.allocLowerString(allocator, arg);

    const options = Options{
        .seed = args.args.seed orelse std.crypto.random.int(u64),
        .avoid_same = args.args.@"avoid-same" != 0,
        .party_size_min = math.cast(u8, args.args.@"party-size-min" orelse 1) orelse return error.ArgumentToBig,
        .party_size_max = math.cast(u8, args.args.@"party-size-max" orelse 6) orelse return error.ArgumentToBig,
        .party_size = args.args.@"party-size" orelse .unchanged,
        .party_pokemons = args.args.@"party-pokemons" orelse .unchanged,
        .abilities = args.args.abilities orelse .random,
        .moves = args.args.moves orelse .unchanged,
        .held_items = args.args.@"held-items" orelse .unchanged,
        .stats = args.args.stats orelse .random,
        .types = args.args.types orelse .random,
        .excluded_pokemons = excluded_pokemons,
        .excluded_trainers = excluded_trainers,
        .included_pokemons = included_pokemons,
        .included_trainers = included_trainers,
    };

    return Program{
        .allocator = allocator,
        .random = undefined, // Initialized in `run`
        .options = options,
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    var default_random = rand.DefaultPrng.init(program.options.seed);
    const allocator = program.allocator;
    try format.io(allocator, stdio.in, stdio.out, program, useGame);

    const species = try pokedexPokemons(
        allocator,
        program.pokedex,
        program.pokemons,
        program.options.excluded_pokemons,
        program.options.included_pokemons,
    );
    program.random = default_random.random();
    program.species = species;
    program.species_by_ability = try speciesByAbility(allocator, program.pokemons, species);
    program.species_by_type = try speciesByType(allocator, program.pokemons, species);
    program.species_by_dual_type = try speciesByDualType(allocator, program.pokemons, species);
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
            return error.DidNotConsumeData;
        },
        .pokemons => |pokemons| {
            const pokemon = (try program.pokemons.getOrPutValue(allocator, pokemons.index, .{}))
                .value_ptr;
            switch (pokemons.value) {
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .pokedex_entry => |pokedex_entry| pokemon.pokedex_entry = pokedex_entry,
                .name => |name| {
                    pokemon.name = try escape.unescapeAlloc(allocator, name);
                    for (pokemon.name) |*c|
                        c.* = ascii.toLower(c.*);
                },
                .stats => |stats| {
                    const stat = @intFromEnum(stats);
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
                else => return error.DidNotConsumeData,
            }
            return error.DidNotConsumeData;
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
                },
                .name => |_name| {
                    const name = try escape.unescapeAlloc(allocator, _name);
                    for (name) |*c|
                        c.* = ascii.toLower(c.*);

                    _ = try program.trainer_names.getOrPutValue(allocator, trainers.index, name);
                    return error.DidNotConsumeData;
                },
                else => return error.DidNotConsumeData,
            }
            return;
        },
        .items => |items| switch (items.value) {
            .battle_effect => |effect| {
                if (effect != 0)
                    _ = try program.held_items.put(allocator, items.index, {});
                return error.DidNotConsumeData;
            },
            else => return error.DidNotConsumeData,
        },
        .moves => |moves| {
            const move = (try program.moves.getOrPutValue(allocator, moves.index, .{}))
                .value_ptr;
            switch (moves.value) {
                .power => |power| move.power = power,
                .type => |_type| move.type = _type,
                .pp => |pp| move.pp = pp,
                .accuracy => |accuracy| move.accuracy = accuracy,
                else => {},
            }
            return error.DidNotConsumeData;
        },
        else => return error.DidNotConsumeData,
    }
    unreachable;
}

fn randomize(program: *Program) !void {
    if (program.species_by_type.count() == 0) {
        std.log.err("No types where found. Cannot randomize.", .{});
        return;
    }

    for (program.trainers.keys(), program.trainers.values()) |trainer_id, *trainer| {
        // Trainers with 0 party members are considered "invalid" trainers
        // and will not be randomized.
        if (trainer.party_size == 0)
            continue;

        if (program.trainer_names.get(trainer_id)) |name| {
            if (util.glob.matchesOneOf(name, program.options.included_trainers) == null and
                util.glob.matchesOneOf(name, program.options.excluded_trainers) != null)
                continue;
        }

        try program.randomizeTrainer(trainer);
    }
}

fn randomizeTrainer(program: *Program, trainer: *Trainer) !void {
    const allocator = program.allocator;
    const types = switch (program.options.types) {
        .themed => blk: {
            const t = util.random.item(program.random, program.species_by_type.keys()).?.*;
            break :blk [_]u16{ t, t };
        },
        .dual_themed => util.random.item(program.random, program.species_by_dual_type.keys()).?.*,
        else => undefined,
    };
    const ability = switch (program.options.abilities) {
        .themed => util.random.item(program.random, program.species_by_ability.keys()).?.*,
        else => undefined,
    };
    const themes = Themes{
        .types = types,
        .ability = ability,
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
    const wants_items = switch (program.options.held_items) {
        .unchanged => trainer.party_type.haveItem(),
        .none => false,
        .random => true,
    };

    trainer.party_size = switch (program.options.party_size) {
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
    for (0..trainer.party_size) |i| {
        const result = try trainer.party.getOrPut(allocator, @intCast(i));
        if (!result.found_existing) {
            const member = trainer.party.values()[party_member];
            result.value_ptr.* = .{
                .species = member.species,
                .item = member.item,
                .level = member.level,
                .moves = try member.moves.clone(allocator),
            };
            party_member += 1;
            party_member %= @intCast(party_member_max);
        }
    }

    const average_level = trainer.partyAverageLevel();
    const trainer_party = trainer.party.values()[0..trainer.party_size];
    for (trainer_party, 0..) |*member, member_i| {
        switch (program.options.party_pokemons) {
            .randomize => try randomizePartyMember(
                program,
                themes,
                trainer_party[0..member_i],
                average_level,
                member,
            ),
            .unchanged => {},
        }

        switch (program.options.held_items) {
            .unchanged => {},
            .none => member.item = null,
            .random => member.item = util.random.item(
                program.random,
                program.held_items.keys(),
            ).?.*,
        }

        switch (program.options.moves) {
            .none, .unchanged => {},
            .best, .best_for_level, .random_learnable, .random => {
                // Ensure that the pokemon has 4 moves
                _ = try member.moves.getOrPutValue(program.allocator, 0, 0);
                _ = try member.moves.getOrPutValue(program.allocator, 1, 0);
                _ = try member.moves.getOrPutValue(program.allocator, 2, 0);
                _ = try member.moves.getOrPutValue(program.allocator, 3, 0);
            },
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
                    member.moves.values(),
                );
            },
            .random_learnable => if (member.species) |species| {
                const pokemon = program.pokemons.get(species).?;
                fillWithRandomLevelUpMoves(
                    program.random,
                    pokemon.lvl_up_moves.values(),
                    member.moves.values(),
                );
            },
            .random => fillWithRandomMoves(
                program.random,
                program.moves.keys(),
                member.moves.values(),
            ),
        }
    }
}

fn fillWithBestMovesForLevel(
    all_moves: Moves,
    pokemon: Pokemon,
    level: u8,
    moves: []u16,
) void {
    // Before pick best moves, we make sure the Pokémon has no moves.
    @memset(moves, 0);

    // Go over all level up moves, and replace the current moves with better moves
    // as we find them
    for (pokemon.lvl_up_moves.values()) |lvl_up_move| {
        if (lvl_up_move.id == 0)
            continue;
        if (level < lvl_up_move.level)
            continue;
        // Pokémon already have this move. We don't wonna have the same move twice
        if (mem.indexOfScalar(u16, moves, lvl_up_move.id)) |_|
            continue;

        const this_move = all_moves.get(lvl_up_move.id) orelse continue;
        const this_move_r = RelativeMove.from(pokemon, this_move);

        for (moves) |*move| {
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

fn fillWithRandomMoves(random: rand.Random, all_moves: []const u16, moves: []u16) void {
    const has_null_move = mem.indexOfScalar(u16, all_moves, 0) != null;
    for (moves, 0..) |*move, i| {
        // We need to have more moves in the game than the party member can have,
        // otherwise, we cannot pick only unique moves. Also, move `0` is the
        // `null` move, so we don't count that as a move we can pick from.
        if (all_moves.len - @intFromBool(has_null_move) <= i) {
            move.* = 0;
            continue;
        }

        // Loop until we have picked a move that the party member does not already
        // have.
        move.* = while (true) {
            const pick = util.random.item(random, all_moves).?.*;
            if (pick != 0 and mem.indexOfScalar(u16, moves[0..i], pick) == null)
                break pick;
        } else unreachable;
    }
}

fn fillWithRandomLevelUpMoves(
    random: rand.Random,
    lvl_up_moves: []const LvlUpMove,
    moves: []u16,
) void {
    for (moves, 0..) |*move, i| {
        // We need to have more moves in the learnset than the party member can have,
        // otherwise, we cannot pick only unique moves.
        // TODO: This code does no take into account that `lvl_up_moves` can contain
        //       duplicates or moves with `id == null`. We need to do a count of
        //       "valid moves" from the learnset and do this check against that
        //       instead.
        if (lvl_up_moves.len <= i) {
            move.* = 0;
            continue;
        }

        // Loop until we have picked a move that the party member does not already
        // have.
        move.* = while (true) {
            const pick = util.random.item(random, lvl_up_moves).?.id;
            if (pick != 0 and mem.indexOfScalar(u16, moves[0..i], pick) == null)
                break pick;
        } else unreachable;
    }
}

const Themes = struct {
    types: [2]u16,
    ability: u16,
};

fn randomizePartyMember(
    program: *Program,
    themes: Themes,
    other_party_members: []const PartyMember,
    average_level: u8,
    member: *PartyMember,
) !void {
    const allocator = program.allocator;
    const species = member.species orelse return;
    const level = member.level orelse average_level;
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
        .themed => program.species_by_type.get(themes.types[0]).?,
        .dual_themed => program.species_by_dual_type.get(themes.types).?,
        .random => Set{},
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
        .random => Set{},
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
    var pick_from = if (program.intersection.count() != 0)
        program.intersection
    else if (ability_set.count() != 0)
        ability_set
    else if (type_set.count() != 0)
        type_set
    else
        program.species;

    if (program.options.avoid_same) {
        // Now, we have to exclude party members already in the party. To do this we construct a
        // new set from `pick_from` with `other_party_members` excluded.
        program.pick_from_excluded.clearRetainingCapacity();
        try program.pick_from_excluded.ensureTotalCapacity(program.allocator, pick_from.count());

        for (pick_from.keys()) |picked|
            program.pick_from_excluded.putAssumeCapacity(picked, {});
        for (other_party_members) |other_member|
            _ = program.pick_from_excluded.swapRemove(other_member.species.?);

        // If we end up with 0 things to pick from, then we cannot avoid same. So only use our
        // newly created set, if it actually has things to pick from.
        if (program.pick_from_excluded.count() != 0)
            pick_from = program.pick_from_excluded;
    }

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

    member.species = switch (program.options.stats) {
        .follow_level => try randomSpeciesWithSimularTotalStats(
            program,
            pick_from,
            levelScaling(program.stats.min, program.stats.max, level),
        ),
        .simular => if (program.pokemons.get(species)) |pokemon|
            try randomSpeciesWithSimularTotalStats(
                program,
                pick_from,
                pokemon.total_stats,
            )
        else
            util.random.item(program.random, pick_from.keys()).?.*,
        .random => util.random.item(program.random, pick_from.keys()).?.*,
    };
}

fn randomSpeciesWithSimularTotalStats(program: *Program, pick_from: Set, total_stats: u16) !u16 {
    const allocator = program.allocator;
    var min: isize = @intCast(total_stats);
    var max = min;

    program.simular.shrinkRetainingCapacity(0);
    while (program.simular.items.len < 25) : ({
        min -= 5;
        max += 5;
    }) {
        for (pick_from.keys()) |s| {
            const p = program.pokemons.get(s).?;
            const total: isize = @intCast(p.total_stats);
            if (min <= total and total <= max)
                try program.simular.append(allocator, s);
        }
    }

    return util.random.item(program.random, program.simular.items).?.*;
}

fn levelScaling(min: u16, max: u16, level: u16) u16 {
    const fmin: f64 = @floatFromInt(min);
    const fmax: f64 = @floatFromInt(max);
    const diff = fmax - fmin;
    const x: f64 = @floatFromInt(level);

    // Function adapted from -0.0001 * x^2 + 0.02 * x
    // This functions grows fast at the start, getting 75%
    // to max stats at level 50.
    const a = -0.0001 * diff;
    const b = 0.02 * diff;
    const xp2 = math.pow(f64, x, 2);
    const res = a * xp2 + b * x + fmin;
    return @intFromFloat(res);
}

fn findAbility(_abilities: Abilities.Iterator, ability: u16) ?Abilities.Entry {
    var abilities = _abilities;
    while (abilities.next()) |entry| {
        if (entry.value_ptr.* == ability)
            return entry;
    }
    return null;
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
const SpeciesByDualType = std.AutoArrayHashMapUnmanaged([2]u16, Set);
const SpeciesBy = std.AutoArrayHashMapUnmanaged(u16, Set);
const TrainerNames = std.AutoArrayHashMapUnmanaged(u16, []const u8);
const Trainers = std.AutoArrayHashMapUnmanaged(u16, Trainer);

fn pokedexPokemons(
    allocator: mem.Allocator,
    pokedex: Set,
    pokemons: Pokemons,
    excluded_pokemons: []const []const u8,
    included_pokemons: []const []const u8,
) !Set {
    var res = Set{};
    errdefer res.deinit(allocator);

    for (pokemons.keys(), pokemons.values()) |species, pokemon| {
        if (pokemon.catch_rate == 0)
            continue;
        if (pokedex.get(pokemon.pokedex_entry) == null)
            continue;
        if (util.glob.matchesOneOf(pokemon.name, included_pokemons) == null and
            util.glob.matchesOneOf(pokemon.name, excluded_pokemons) != null)
            continue;

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
        res.min = @min(res.min, pokemon.total_stats);
        res.max = @max(res.max, pokemon.total_stats);
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

fn speciesByDualType(
    allocator: mem.Allocator,
    pokemons: Pokemons,
    species: Set,
) !SpeciesByDualType {
    var res = SpeciesByDualType{};
    errdefer {
        for (res.values()) |*set|
            set.deinit(allocator);
        res.deinit(allocator);
    }

    for (species.keys()) |s| {
        const pokemon = pokemons.get(s).?;
        const p_types = pokemon.types.keys();
        const types = switch (p_types.len) {
            0 => continue,
            1 => [2]u16{ p_types[0], p_types[0] },
            else => [2]u16{
                @min(p_types[0], p_types[1]),
                @max(p_types[0], p_types[1]),
            },
        };

        const set = (try res.getOrPutValue(allocator, types, .{})).value_ptr;
        _ = try set.put(allocator, s, {});
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
            count += @intFromBool(member.level != null);
        }
        if (count == 0)
            return 2;
        return @intCast(sum / count);
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
            .power = @as(u16, m.power) + (m.power / 2) * @intFromBool(is_stab),
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

const number_of_seeds = 40;
const Pattern = util.testing.Pattern;

test "tm35-rand-trainers" {
    const test_case = try util.testing.filter(util.testing.test_case, &.{
        ".items[*].battle_effect=*",
        ".moves[*].power=*",
        ".moves[*].type=*",
        ".moves[*].pp=*",
        ".moves[*].accuracy=*",
        ".pokemons[*].catch_rate=*",
        ".pokemons[*].pokedex_entry=*",
        ".pokemons[*].name=*",
        ".pokemons[*].stats.*",
        ".pokemons[*].types[*]=*",
        ".pokemons[*].abilities[*]=*",
        ".pokemons[*].moves[*].*",
        ".pokedex[*].*",
        ".trainers[*].party*",
        ".trainers[*].name=*",
    });
    defer testing.allocator.free(test_case);

    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{"--seed=0"},
        .patterns = &[_]Pattern{
            Pattern.endsWith(91, 91, "].party_type=both"),
            Pattern.endsWith(14, 14, "].party_type=item"),
            Pattern.endsWith(87, 87, "].party_type=moves"),
            Pattern.endsWith(621, 621, "].party_type=none"),
            Pattern.glob(408, 408, ".trainers[*].party[*].item=*"),
            Pattern.glob(2400, 2400, ".trainers[*].party[*].moves[*]=*"),
            Pattern.endsWith(252, 252, "].party_size=1"),
            Pattern.endsWith(296, 296, "].party_size=2"),
            Pattern.endsWith(187, 187, "].party_size=3"),
            Pattern.endsWith(26, 26, "].party_size=4"),
            Pattern.endsWith(13, 13, "].party_size=5"),
            Pattern.endsWith(39, 39, "].party_size=6"),
        },
    });

    // Held items
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{ "--held-items=none", "--seed=0" },
        .patterns = &[_]Pattern{
            Pattern.endsWith(0, 0, "].party_type=both"),
            Pattern.endsWith(0, 0, "].party_type=item"),
            Pattern.endsWith(178, 178, "].party_type=moves"),
            Pattern.endsWith(635, 635, "].party_type=none"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{ "--held-items=unchanged", "--seed=0" },
        .patterns = &[_]Pattern{
            Pattern.endsWith(91, 91, "].party_type=both"),
            Pattern.endsWith(14, 14, "].party_type=item"),
            Pattern.endsWith(87, 87, "].party_type=moves"),
            Pattern.endsWith(621, 621, "].party_type=none"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{ "--held-items=random", "--seed=0" },
        .patterns = &[_]Pattern{
            Pattern.endsWith(178, 178, "].party_type=both"),
            Pattern.endsWith(635, 635, "].party_type=item"),
            Pattern.endsWith(0, 0, "].party_type=moves"),
            Pattern.endsWith(0, 0, "].party_type=none"),
            Pattern.glob(1808, 1808, ".trainers[*].party[*].item=*"),
        },
    });

    // Moves
    // TODO: best|best_for_level|random_learnable
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{ "--moves=none", "--seed=0" },
        .patterns = &[_]Pattern{
            Pattern.endsWith(0, 0, "].party_type=both"),
            Pattern.endsWith(0, 0, "].party_type=moves"),
            Pattern.endsWith(105, 105, "].party_type=item"),
            Pattern.endsWith(708, 708, "].party_type=none"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{ "--moves=unchanged", "--seed=0" },
        .patterns = &[_]Pattern{
            Pattern.endsWith(91, 91, "].party_type=both"),
            Pattern.endsWith(14, 14, "].party_type=item"),
            Pattern.endsWith(87, 87, "].party_type=moves"),
            Pattern.endsWith(621, 621, "].party_type=none"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{ "--moves=random", "--seed=0" },
        .patterns = &[_]Pattern{
            Pattern.endsWith(105, 105, "].party_type=both"),
            Pattern.endsWith(0, 0, "].party_type=item"),
            Pattern.endsWith(708, 708, "].party_type=moves"),
            Pattern.endsWith(0, 0, "].party_type=none"),
            Pattern.glob(7232, 7232, ".trainers[*].party[*].moves[*]=*"),
        },
    });

    // Moves + Held items
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{ "--held-items=none", "--moves=none", "--seed=0" },
        .patterns = &[_]Pattern{
            Pattern.endsWith(0, 0, "].party_type=both"),
            Pattern.endsWith(0, 0, "].party_type=item"),
            Pattern.endsWith(0, 0, "].party_type=moves"),
            Pattern.endsWith(813, 813, "].party_type=none"),
        },
    });

    // Party size
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{ "--party-size-min=2", "--party-size-max=5", "--seed=0" },
        .patterns = &[_]Pattern{
            Pattern.endsWith(0, 0, "].party_size=1"),
            Pattern.endsWith(548, 548, "].party_size=2"),
            Pattern.endsWith(187, 187, "].party_size=3"),
            Pattern.endsWith(26, 26, "].party_size=4"),
            Pattern.endsWith(52, 52, "].party_size=5"),
            Pattern.endsWith(0, 0, "].party_size=6"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--party-size=minimum", "--party-size-min=2",
            "--party-size-max=5",   "--seed=0",
        },
        .patterns = &[_]Pattern{
            Pattern.endsWith(0, 0, "].party_size=1"),
            Pattern.endsWith(813, 813, "].party_size=2"),
            Pattern.endsWith(0, 0, "].party_size=3"),
            Pattern.endsWith(0, 0, "].party_size=4"),
            Pattern.endsWith(0, 0, "].party_size=5"),
            Pattern.endsWith(0, 0, "].party_size=6"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--party-size=random", "--party-size-min=2",
            "--party-size-max=5",  "--seed=0",
        },
        .patterns = &[_]Pattern{
            Pattern.endsWith(0, 0, "].party_size=1"),
            Pattern.endsWith(0, 813, "].party_size=2"),
            Pattern.endsWith(0, 813, "].party_size=3"),
            Pattern.endsWith(0, 813, "].party_size=4"),
            Pattern.endsWith(0, 813, "].party_size=5"),
            Pattern.endsWith(0, 0, "].party_size=6"),
        },
    });

    // Test excluding system by running 100 seeds and checking that none of them pick the
    // excluded pokemons
    for (0..number_of_seeds) |seed| {
        try util.testing.runProgramFindPatterns(Program, .{
            .in = test_case,
            .args = &[_][]const u8{
                "--exclude-pokemon=Gible",
                "--exclude-pokemon=Weedle",
                "--party-pokemons=randomize",
                (try util.testing.boundPrint(16, "--seed={}", .{seed})).slice(),
            },
            .patterns = &[_]Pattern{
                Pattern.glob(0, 0, ".trainers[*].party[*].species=13"),
                Pattern.glob(0, 0, ".trainers[*].party[*].species=443"),
            },
        });
    }

    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--exclude-pokemon=*",
            "--include-pokemon=Weedle",
            "--party-pokemons=randomize",
            "--seed=0",
        },
        .patterns = &[_]Pattern{
            // All are Weedle
            Pattern.glob(1808, 1808, ".trainers[*].party[*].species=*"),
            Pattern.glob(1808, 1808, ".trainers[*].party[*].species=13"),
        },
    });

    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--avoid-same",
            "--party-pokemons=randomize",

            // To test "avoid-same" we specify 2 Pokémons only and set the party size to 2.
            // Every trainer should therefor have exactly these two Pokémons and no duplicate.
            // We should therefor see exactly <number-of-trainers> Bulbasaurs and Ivysaurs
            // between party slot 0 and 1 and no more.
            // This test does not actually test for the exact behavior of `avoid-same` but
            // hopefully it is good enough to catch regressions.
            "--exclude-pokemon=*",
            "--include-pokemon=Bulbasaur",
            "--include-pokemon=Ivysaur",
            "--party-size=minimum",
            "--party-size-min=2",
            "--party-size-max=2",

            "--seed=0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(813, 813, ".trainers[*].party_size=2"),
            Pattern.glob(813, 813, ".trainers[*].party[0].species=*"),
            Pattern.glob(813, 813, ".trainers[*].party[1].species=*"),
            Pattern.glob(400, 400, ".trainers[*].party[0].species=1"),
            Pattern.glob(413, 413, ".trainers[*].party[1].species=1"),
            Pattern.glob(413, 413, ".trainers[*].party[0].species=2"),
            Pattern.glob(400, 400, ".trainers[*].party[1].species=2"),
        },
    });
}

// TODO: Test these parameters
//     "-S, --stats <random|simular|follow_level> " ++
//         "The total stats the picked pokemon should have if pokemons are randomized. " ++
//         "(default: random)",
//     "-t, --types <random|same|themed> " ++
//         "Which types each trainer should use if pokemons are randomized. " ++
//         "(default: random)",
//     "-a, --abilities <random|same|themed> " ++
//         "Which ability each party member should have. (default: random)",
