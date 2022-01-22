const clap = @import("clap");
const format = @import("format");
const it = @import("ziter");
const std = @import("std");
const ston = @import("ston");
const util = @import("util");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const log = std.log;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const Program = @This();

allocator: mem.Allocator,
options: Options,
first_evos: Set = Set{},
types: Set = Set{},
abilities: Set = Set{},
items: Set = Set{},
moves: Moves = Moves{},
pokemons: Pokemons = Pokemons{},
tms: Machines = Machines{},
hms: Machines = Machines{},

const Options = struct {
    seed: u64,

    abilities: Method,
    types: Method,
    items: Method,

    stats: Method,
    same_total_stats: bool,

    machines: Method,
    chance_to_learn_non_stab_machine: f64,
    chance_to_learn_stab_machine: f64,

    status_moves_are_stab: bool,
};

const Method = enum {
    unchanged,
    random,
    random_follow_evos,
};

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Randomizes Pokémons.
    \\
;

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam(
        "-h, --help " ++
            "Display this help text and exit.",
    ) catch unreachable,
    clap.parseParam(
        "-s, --seed <INT> " ++
            "The seed to use for random numbers. A random seed will be picked if this is not " ++
            "specified.",
    ) catch unreachable,
    clap.parseParam(
        "-v, --version " ++
            "Output version information and exit.",
    ) catch unreachable,
    clap.parseParam(
        "-a, --abilities <unchanged|random|random_follow_evos> " ++
            "The method for which pokemon abilities will be randomized. (default: unchanged)",
    ) catch unreachable,
    clap.parseParam(
        "-i, --items <unchanged|random|random_follow_evos> " ++
            "The method for which pokemon items will be randomized. (default: unchanged)",
    ) catch unreachable,
    clap.parseParam(
        "-t, --types <unchanged|random|random_follow_evos> " ++
            "The method for which pokemon types will be randomized. (default: unchanged)",
    ) catch unreachable,
    clap.parseParam(
        "-S, --stats <unchanged|random|random_follow_evos> " ++
            "The method for which pokemon stats will be randomized. (default: unchanged)",
    ) catch unreachable,
    clap.parseParam(
        "    --same-total-stats " ++
            "Pokémons will have the same total stats after randomization.",
    ) catch unreachable,
    clap.parseParam(
        "-m, --machines <unchanged|random|random_follow_evos> " ++
            "The method for which pokemon machines learned (tms,hms) will be randomized. " ++
            "(default: unchanged)",
    ) catch unreachable,
    clap.parseParam(
        "    --non-stab-machine-chance <FLOAT> " ++
            "The chance a pokemon can learn a machine providing a non stab move when " ++
            "randomizing machines. (default: 0.5)",
    ) catch unreachable,
    clap.parseParam(
        "    --stab-machine-chance <FLOAT> " ++
            "The chance a pokemon can learn a machine providing a stab move when randomizing " ++
            "machines. (default: 0.5)",
    ) catch unreachable,
    clap.parseParam(
        "    --status-moves-are-stab " ++
            "Whether status moves, which are the same typing as the pokemon, should be " ++
            "considered as stab moves when determining the chance that the move should be " ++
            "learnable.",
    ) catch unreachable,
};

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const options = Options{
        .seed = try util.args.seed(args),
        .same_total_stats = args.flag("--same-total-stats"),
        .status_moves_are_stab = args.flag("--status-moves-are-stab"),
        .abilities = (try util.args.enumeration(args, "--abilities", Method)) orelse .unchanged,
        .types = (try util.args.enumeration(args, "--types", Method)) orelse .unchanged,
        .items = (try util.args.enumeration(args, "--items", Method)) orelse .unchanged,
        .stats = (try util.args.enumeration(args, "--stats", Method)) orelse .unchanged,
        .machines = (try util.args.enumeration(args, "--machines", Method)) orelse .unchanged,
        .chance_to_learn_non_stab_machine = (try util.args.float(args, "--non-stab-machine-chance", f64)) orelse 0.5,
        .chance_to_learn_stab_machine = (try util.args.float(args, "--stab-machine-chance", f64)) orelse 0.5,
    };
    return Program{
        .allocator = allocator,
        .options = options,
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    try format.io(program.allocator, stdio.in, stdio.out, program, useGame);

    try program.first_evos.ensureTotalCapacity(program.allocator, program.pokemons.count());
    for (program.pokemons.keys()) |species|
        program.first_evos.putAssumeCapacity(species, {});
    for (program.pokemons.values()) |pokemon| {
        for (pokemon.evos.values()) |species|
            _ = program.first_evos.swapRemove(species);
    }

    try program.randomize();
    try program.output(stdio.out);
}

fn output(program: *Program, writer: anytype) !void {
    for (program.pokemons.values()) |*pokemon, i| {
        const species = program.pokemons.keys()[i];
        try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
            .types = pokemon.types,
            .abilities = pokemon.abilities,
            .items = pokemon.items,
        }) });

        var stat_it = pokemon.stats.iterator();
        while (stat_it.next()) |entry| {
            try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
                .stats = ston.field(@tagName(entry.key), entry.value.*),
            }) });
        }

        for (pokemon.evos.keys()) |evo_id, j| {
            const evo = pokemon.evos.values()[j];
            try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
                .evos = ston.index(evo_id, .{ .target = evo }),
            }) });
        }
        for (pokemon.evo_params.keys()) |evo_id, j| {
            const param = pokemon.evo_params.values()[j];
            try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
                .evos = ston.index(evo_id, .{ .param = param }),
            }) });
        }
        for (pokemon.evo_methods.keys()) |evo_id, j| {
            const method = pokemon.evo_methods.values()[j];
            try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
                .evos = ston.index(evo_id, .{ .method = method }),
            }) });
        }
        var j: usize = 0;
        while (j < pokemon.tms_learned.len) : (j += 1) {
            if (!pokemon.tms_occupied.get(j))
                continue;
            try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
                .tms = ston.index(j, pokemon.tms_learned.get(j)),
            }) });
        }
        j = 0;
        while (j < pokemon.hms_learned.len) : (j += 1) {
            if (!pokemon.hms_occupied.get(j))
                continue;
            try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
                .hms = ston.index(j, pokemon.hms_learned.get(j)),
            }) });
        }
    }
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .pokemons => |pokemons| {
            const pokemon = (try program.pokemons.getOrPutValue(
                allocator,
                pokemons.index,
                .{},
            )).value_ptr;

            switch (pokemons.value) {
                .tms => |tms| {
                    pokemon.tms_occupied.set(tms.index, true);
                    pokemon.tms_learned.set(tms.index, tms.value);
                },
                .hms => |hms| {
                    pokemon.hms_occupied.set(hms.index, true);
                    pokemon.hms_learned.set(hms.index, hms.value);
                },
                .stats => |stats| pokemon.stats.put(stats, stats.value()),
                .types => |types| _ = try pokemon.types.put(allocator, types.index, types.value),
                .items => |items| _ = try pokemon.items.put(allocator, items.index, items.value),
                .abilities => |abilities| _ = try pokemon.abilities.put(
                    allocator,
                    abilities.index,
                    abilities.value,
                ),
                .evos => |evos| switch (evos.value) {
                    .target => |target| _ = try pokemon.evos.put(allocator, evos.index, target),
                    .param => |param| _ = try pokemon.evo_params.put(
                        allocator,
                        evos.index,
                        param,
                    ),
                    .method => |method| _ = try pokemon.evo_methods.put(
                        allocator,
                        evos.index,
                        method,
                    ),
                },
                .catch_rate,
                .base_exp_yield,
                .ev_yield,
                .gender_ratio,
                .egg_cycles,
                .base_friendship,
                .growth_rate,
                .egg_groups,
                .color,
                .moves,
                .name,
                .pokedex_entry,
                => return error.DidNotConsumeData,
            }
            return;
        },
        .moves => |moves| {
            const move = (try program.moves.getOrPutValue(allocator, moves.index, .{})).value_ptr;
            switch (moves.value) {
                .type => |_type| move.type = _type,
                .category => |category| move.category = category,
                .name,
                .description,
                .effect,
                .accuracy,
                .pp,
                .target,
                .priority,
                .power,
                => {},
            }
            return error.DidNotConsumeData;
        },
        .tms => |tms| {
            _ = try program.tms.put(allocator, tms.index, tms.value);
            return error.DidNotConsumeData;
        },
        .hms => |hms| {
            _ = try program.hms.put(allocator, hms.index, hms.value);
            return error.DidNotConsumeData;
        },
        .types => |types| {
            _ = try program.types.put(allocator, types.index, {});
            return error.DidNotConsumeData;
        },
        .abilities => |abilities| {
            // TODO: Ability 0 is invalid in games. Figure out a generic way of figuring this
            //       out.
            if (abilities.index != 0)
                _ = try program.abilities.put(allocator, abilities.index, {});

            return error.DidNotConsumeData;
        },
        .items => |items| {
            // TODO: Item 0 is invalid in games. Figure out a generic way of figuring this
            //       out.
            if (items.index != 0)
                _ = try program.items.put(allocator, items.index, {});

            return error.DidNotConsumeData;
        },
        else => return error.DidNotConsumeData,
    }
    unreachable;
}

fn randomize(program: *Program) !void {
    const random = rand.DefaultPrng.init(program.options.seed).random();

    if (program.types.keys().len != 0) switch (program.options.types) {
        .unchanged => {},
        .random => for (program.pokemons.values()) |*pokemon| {
            util.random.items(random, pokemon.types.values(), program.types.keys());
        },
        .random_follow_evos => for (program.first_evos.keys()) |species| {
            const pokemon = program.pokemons.getPtr(species).?;
            util.random.items(random, pokemon.types.values(), program.types.keys());
            program.copyFieldsToEvolutions(pokemon.*, &.{"types"});
        },
    };

    if (program.abilities.keys().len != 0) switch (program.options.abilities) {
        .unchanged => {},
        .random => for (program.pokemons.values()) |*pokemon| {
            util.random.items(random, pokemon.abilities.values(), program.abilities.keys());
        },
        .random_follow_evos => for (program.first_evos.keys()) |species| {
            const pokemon = program.pokemons.getPtr(species).?;
            util.random.items(random, pokemon.abilities.values(), program.abilities.keys());
            program.copyFieldsToEvolutions(pokemon.*, &.{"abilities"});
        },
    };

    if (program.items.keys().len != 0) switch (program.options.items) {
        .unchanged => {},
        .random => for (program.pokemons.values()) |*pokemon| {
            util.random.items(random, pokemon.items.values(), program.items.keys());
        },
        .random_follow_evos => for (program.first_evos.keys()) |species| {
            const pokemon = program.pokemons.getPtr(species).?;
            util.random.items(random, pokemon.items.values(), program.items.keys());
            program.copyFieldsToEvolutions(pokemon.*, &.{"items"});
        },
    };

    switch (program.options.stats) {
        .unchanged => {},
        .random => for (program.pokemons.values()) |*pokemon| {
            program.randomizeStats(random, pokemon);
        },
        .random_follow_evos => for (program.first_evos.keys()) |species| {
            const pokemon = program.pokemons.getPtr(species).?;
            program.randomizeStats(random, pokemon);
        },
    }

    switch (program.options.machines) {
        .unchanged => {},
        .random => for (program.pokemons.values()) |*pokemon| {
            program.randomizeMachinesLearned(
                random,
                &pokemon.tms_learned,
                pokemon.types.values(),
                program.tms,
            );
            program.randomizeMachinesLearned(
                random,
                &pokemon.hms_learned,
                pokemon.types.values(),
                program.hms,
            );
        },
        .random_follow_evos => for (program.first_evos.keys()) |species| {
            const pokemon = program.pokemons.getPtr(species).?;
            program.randomizeMachinesLearned(
                random,
                &pokemon.tms_learned,
                pokemon.types.values(),
                program.tms,
            );
            program.randomizeMachinesLearned(
                random,
                &pokemon.hms_learned,
                pokemon.types.values(),
                program.hms,
            );
            program.copyFieldsToEvolutions(pokemon.*, &.{ "hms_learned", "tms_learned" });
        },
    }
}

fn randomizeMachinesLearned(
    program: *Program,
    random: rand.Random,
    learned: *MachinesLearned,
    pokemon_types: []const u16,
    machines: Machines,
) void {
    var i: usize = 0;
    while (i < learned.len) : (i += 1) {
        const chance: f64 = blk: {
            const no_stab_chance = program.options.chance_to_learn_non_stab_machine;
            const move_id = machines.get(@intCast(u8, i)) orelse break :blk no_stab_chance;
            const move = program.moves.get(move_id) orelse break :blk no_stab_chance;
            if (move.category == .status and !program.options.status_moves_are_stab)
                break :blk no_stab_chance;
            if (mem.indexOfScalar(u16, pokemon_types, move.type) == null)
                break :blk no_stab_chance;

            break :blk program.options.chance_to_learn_stab_machine;
        };

        learned.set(i, random.float(f64) < chance);
    }
}

fn copyFieldsToEvolutions(
    program: *Program,
    pokemon: Pokemon,
    comptime fields: []const []const u8,
) void {
    for (pokemon.evos.values()) |evo_species| {
        const evo = program.pokemons.getPtr(evo_species).?;
        inline for (fields) |field|
            @field(evo, field) = @field(pokemon, field);
        program.copyFieldsToEvolutions(evo.*, fields);
    }
}

fn randomizeStats(program: *Program, random: rand.Random, pokemon: *Pokemon) void {
    var stats = pokemon.statsToArray();
    mem.set(u8, stats.slice(), 0);
    program.randomizeStatsEx(random, pokemon, stats);
}

fn randomizeStatsEx(
    program: *Program,
    random: rand.Random,
    pokemon: *Pokemon,
    stats_to_start_from: std.BoundedArray(u8, Stats.len),
) void {
    const new_total = if (program.options.same_total_stats) blk: {
        const stats = pokemon.statsToArray();
        break :blk it.fold(stats.constSlice(), @as(usize, 0), foldu8);
    } else blk: {
        const min_total = it.fold(stats_to_start_from.constSlice(), @as(usize, 0), foldu8) + 1;
        const max_total = stats_to_start_from.len * math.maxInt(u8);
        break :blk random.intRangeAtMost(usize, math.min(min_total, max_total), max_total);
    };

    var stats = stats_to_start_from;
    randomUntilSum(random, u8, stats.slice(), new_total);
    pokemon.statsFromSlice(stats.slice());

    if (program.options.stats == .random_follow_evos) {
        for (pokemon.evos.values()) |species| {
            const evo = program.pokemons.getPtr(species).?;
            program.randomizeStatsEx(random, evo, stats);
        }
    }
}

fn randomUntilSum(
    random: rand.Random,
    comptime T: type,
    buf: []T,
    sum: usize,
) void {
    var curr = it.fold(buf, @as(usize, 0), foldu8);
    const max = math.min(sum, buf.len * math.maxInt(T));
    while (curr < max) {
        const item = util.random.item(random, buf).?;
        const old = item.*;
        item.* +|= 1;
        curr += item.* - old;
    }
    while (curr > max) {
        const item = util.random.item(random, buf).?;
        const old = item.*;
        item.* -|= 1;
        curr -= old - item.*;
    }
}

fn foldu8(a: usize, b: u8) usize {
    return a + b;
}

fn foldf32(a: f64, b: f32) f64 {
    return a + b;
}

const EvoMethods = std.AutoArrayHashMapUnmanaged(u8, format.Evolution.Method);
const EvoParams = std.AutoArrayHashMapUnmanaged(u8, u16);
const Evos = std.AutoArrayHashMapUnmanaged(u8, u16);
const Machines = std.AutoArrayHashMapUnmanaged(u8, u16);
const Map = std.AutoArrayHashMapUnmanaged(u8, u16);
const Moves = std.AutoArrayHashMapUnmanaged(u16, Move);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);

const MachinesLearned = std.PackedIntArray(bool, math.maxInt(u7) + 1);
const Stats = std.EnumMap(meta.Tag(format.Stats(u8)), u8);

const Pokemon = struct {
    stats: Stats = Stats{},
    types: Map = Map{},
    abilities: Map = Map{},
    items: Map = Map{},
    tms_learned: MachinesLearned = mem.zeroes(MachinesLearned),
    tms_occupied: MachinesLearned = mem.zeroes(MachinesLearned),
    hms_learned: MachinesLearned = mem.zeroes(MachinesLearned),
    hms_occupied: MachinesLearned = mem.zeroes(MachinesLearned),
    evos: Evos = Evos{},
    evo_params: EvoParams = EvoParams{},
    evo_methods: EvoMethods = EvoMethods{},

    fn statsToArray(pokemon: *Pokemon) std.BoundedArray(u8, Stats.len) {
        var res = std.BoundedArray(u8, Stats.len){ .buffer = undefined };
        var stats_it = pokemon.stats.iterator();
        while (stats_it.next()) |stat|
            res.appendAssumeCapacity(stat.value.*);

        return res;
    }

    fn statsFromSlice(pokemon: *Pokemon, stats: []const u8) void {
        var i: usize = 0;
        var stats_it = pokemon.stats.iterator();
        while (stats_it.next()) |stat| : (i += 1)
            stat.value.* = stats[i];
    }
};

const Move = struct {
    type: u16 = math.maxInt(u16),
    category: format.Move.Category = .physical,
};

//
// Testing
//

fn runProgram(arena: mem.Allocator, opt: util.testing.RunProgramOptions) !Program {
    const res = try util.testing.runProgram(Program, opt);
    defer testing.allocator.free(res);

    return collectData(arena, res);
}

fn collectData(arena: mem.Allocator, data: [:0]const u8) !Program {
    var program = Program{ .allocator = arena, .options = undefined };
    var parser = ston.Parser{ .str = data };
    var des = ston.Deserializer(format.Game){ .parser = &parser };
    while (des.next()) |game| {
        program.useGame(game) catch |err| switch (err) {
            error.DidNotConsumeData => continue,
            else => {
                try testing.expect(false);
                unreachable;
            },
        };
    } else |_| {
        try testing.expectEqual(parser.str.len, parser.i);
    }

    return program;
}

fn expectStatsFollowEvos(program: Program, allow_evo_with_lower_stats: bool) !void {
    const pokemons = program.pokemons.values();
    for (pokemons) |*pokemon| {
        const pokemon_stats = pokemon.statsToArray();
        const pokemon_total = it.fold(pokemon_stats.constSlice(), @as(usize, 0), foldu8);
        for (pokemon.evos.values()) |species| {
            const evo = program.pokemons.getPtr(species).?;
            const evo_stats = evo.statsToArray();
            const evo_total = it.fold(evo_stats.constSlice(), @as(usize, 0), foldu8);

            try testing.expectEqual(pokemon_stats.len, evo_stats.len);
            for (pokemon_stats.constSlice()) |poke_stat, i| {
                const evo_stat = evo_stats.constSlice()[i];

                const evo_has_more_stats = pokemon_total <= evo_total;
                if (!allow_evo_with_lower_stats)
                    try testing.expect(evo_has_more_stats);
                try testing.expect((evo_has_more_stats and poke_stat <= evo_stat) or
                    (!evo_has_more_stats and poke_stat >= evo_stat));
            }
        }
    }
}

fn expectPokemonMapFieldFollowEvo(program: Program, comptime field: []const u8) !void {
    const pokemons = program.pokemons.values();
    for (pokemons) |*pokemon| {
        for (pokemon.evos.values()) |species| {
            const evo = program.pokemons.getPtr(species).?;
            try util.set.expectEqual(@field(pokemon, field), @field(evo, field));
        }
    }
}

fn expectSameTotalStats(old_prog: Program, new_prog: Program) !void {
    const old_keys = old_prog.pokemons.keys();
    const new_keys = new_prog.pokemons.keys();
    const old_pokemons = old_prog.pokemons.values();
    const new_pokemons = new_prog.pokemons.values();

    try testing.expectEqual(old_pokemons.len, new_pokemons.len);
    for (old_pokemons) |*old, i| {
        const new = &new_pokemons[i];
        const old_stats = old.statsToArray();
        const new_stats = new.statsToArray();

        try testing.expectEqual(old_keys[i], new_keys[i]);
        try testing.expectEqual(old_stats.len, new_stats.len);
        try testing.expectEqual(
            it.fold(old_stats.constSlice(), @as(usize, 0), foldu8),
            it.fold(new_stats.constSlice(), @as(usize, 0), foldu8),
        );
    }
}

const number_of_seeds = 40;
const Pattern = util.testing.Pattern;

test "stats" {
    const test_case = try util.testing.filter(util.testing.test_case, &.{
        ".pokemons[*].stats.*",
        ".pokemons[*].evos[*].*",
    });
    defer testing.allocator.free(test_case);

    var original_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer original_arena.deinit();
    const original = try collectData(original_arena.allocator(), test_case);

    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{"--stats=random"},
        .patterns = &[_]Pattern{
            Pattern.glob(710, 710, ".pokemons[*].stats.hp=*"),
            Pattern.glob(710, 710, ".pokemons[*].stats.attack=*"),
            Pattern.glob(710, 710, ".pokemons[*].stats.defense=*"),
            Pattern.glob(710, 710, ".pokemons[*].stats.speed=*"),
            Pattern.glob(710, 710, ".pokemons[*].stats.sp_attack=*"),
            Pattern.glob(710, 710, ".pokemons[*].stats.sp_defense=*"),
        },
    });

    var seed: usize = 0;
    while (seed < number_of_seeds) : (seed += 1) {
        var buf: [20]u8 = undefined;
        const seed_arg = std.fmt.bufPrint(&buf, "--seed={}", .{seed}) catch unreachable;

        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const data = try runProgram(arena.allocator(), .{
            .in = test_case,
            .args = &[_][]const u8{ "--stats=random_follow_evos", seed_arg },
        });
        try expectStatsFollowEvos(data, false);
    }

    seed = 0;
    while (seed < number_of_seeds) : (seed += 1) {
        var buf: [20]u8 = undefined;
        const seed_arg = std.fmt.bufPrint(&buf, "--seed={}", .{seed}) catch unreachable;

        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const data = try runProgram(arena.allocator(), .{
            .in = test_case,
            .args = &[_][]const u8{
                "--stats=random_follow_evos", "--same-total-stats",
                seed_arg,
            },
        });
        try expectSameTotalStats(original, data);
        try expectStatsFollowEvos(data, true);
    }
}

test "machines" {
    const test_case = try util.testing.filter(util.testing.test_case, &.{
        ".pokemons[*].types[*]=*",
        ".pokemons[*].tms[*]=*",
        ".pokemons[*].hms[*]=*",
        ".pokemons[*].evos[*].*",
        ".moves[*].type=*",
        ".moves[*].category=*",
        ".tms[*]=*",
        ".hms[*]=*",
    });
    defer testing.allocator.free(test_case);

    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{},
        .patterns = &[_]Pattern{
            Pattern.glob(67450, 67450, ".pokemons[*].tms[*]=*"),
            Pattern.glob(4260, 4260, ".pokemons[*].hms[*]=*"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--machines=random",             "--stab-machine-chance=1.0",
            "--non-stab-machine-chance=1.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(67450, 67450, ".pokemons[*].tms[*]=true"),
            Pattern.glob(0, 0, ".pokemons[*].tms[*]=false"),
            Pattern.glob(4260, 4260, ".pokemons[*].hms[*]=true"),
            Pattern.glob(0, 0, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--status-moves-are-stab",   "--machines=random",
            "--stab-machine-chance=1.0", "--non-stab-machine-chance=1.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(67450, 67450, ".pokemons[*].tms[*]=true"),
            Pattern.glob(0, 0, ".pokemons[*].tms[*]=false"),
            Pattern.glob(4260, 4260, ".pokemons[*].hms[*]=true"),
            Pattern.glob(0, 0, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--machines=random",             "--stab-machine-chance=1.0",
            "--non-stab-machine-chance=0.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(4146, 4146, ".pokemons[*].tms[*]=true"),
            Pattern.glob(63304, 63304, ".pokemons[*].tms[*]=false"),
            Pattern.glob(650, 650, ".pokemons[*].hms[*]=true"),
            Pattern.glob(3610, 3610, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--status-moves-are-stab",   "--machines=random",
            "--stab-machine-chance=1.0", "--non-stab-machine-chance=0.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(6612, 6612, ".pokemons[*].tms[*]=true"),
            Pattern.glob(60838, 60838, ".pokemons[*].tms[*]=false"),
            Pattern.glob(650, 650, ".pokemons[*].hms[*]=true"),
            Pattern.glob(3610, 3610, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--machines=random",             "--stab-machine-chance=0.0",
            "--non-stab-machine-chance=1.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(63304, 63304, ".pokemons[*].tms[*]=true"),
            Pattern.glob(4146, 4146, ".pokemons[*].tms[*]=false"),
            Pattern.glob(3610, 3610, ".pokemons[*].hms[*]=true"),
            Pattern.glob(650, 650, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--status-moves-are-stab",   "--machines=random",
            "--stab-machine-chance=0.0", "--non-stab-machine-chance=1.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(60838, 60838, ".pokemons[*].tms[*]=true"),
            Pattern.glob(6612, 6612, ".pokemons[*].tms[*]=false"),
            Pattern.glob(3610, 3610, ".pokemons[*].hms[*]=true"),
            Pattern.glob(650, 650, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--machines=random",             "--stab-machine-chance=0.0",
            "--non-stab-machine-chance=0.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(0, 0, ".pokemons[*].tms[*]=true"),
            Pattern.glob(67450, 67450, ".pokemons[*].tms[*]=false"),
            Pattern.glob(0, 0, ".pokemons[*].hms[*]=true"),
            Pattern.glob(4260, 4260, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--status-moves-are-stab",   "--machines=random",
            "--stab-machine-chance=0.0", "--non-stab-machine-chance=0.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(0, 0, ".pokemons[*].tms[*]=true"),
            Pattern.glob(67450, 67450, ".pokemons[*].tms[*]=false"),
            Pattern.glob(0, 0, ".pokemons[*].hms[*]=true"),
            Pattern.glob(4260, 4260, ".pokemons[*].hms[*]=false"),
        },
    });

    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--machines=random_follow_evos", "--stab-machine-chance=1.0",
            "--non-stab-machine-chance=1.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(67450, 67450, ".pokemons[*].tms[*]=true"),
            Pattern.glob(0, 0, ".pokemons[*].tms[*]=false"),
            Pattern.glob(4260, 4260, ".pokemons[*].hms[*]=true"),
            Pattern.glob(0, 0, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--status-moves-are-stab",   "--machines=random_follow_evos",
            "--stab-machine-chance=1.0", "--non-stab-machine-chance=1.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(67450, 67450, ".pokemons[*].tms[*]=true"),
            Pattern.glob(0, 0, ".pokemons[*].tms[*]=false"),
            Pattern.glob(4260, 4260, ".pokemons[*].hms[*]=true"),
            Pattern.glob(0, 0, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--machines=random_follow_evos", "--stab-machine-chance=1.0",
            "--non-stab-machine-chance=0.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(4078, 4078, ".pokemons[*].tms[*]=true"),
            Pattern.glob(63372, 63372, ".pokemons[*].tms[*]=false"),
            Pattern.glob(651, 651, ".pokemons[*].hms[*]=true"),
            Pattern.glob(3609, 3609, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--status-moves-are-stab",   "--machines=random_follow_evos",
            "--stab-machine-chance=1.0", "--non-stab-machine-chance=0.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(6587, 6587, ".pokemons[*].tms[*]=true"),
            Pattern.glob(60863, 60863, ".pokemons[*].tms[*]=false"),
            Pattern.glob(651, 651, ".pokemons[*].hms[*]=true"),
            Pattern.glob(3609, 3609, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--machines=random_follow_evos", "--stab-machine-chance=0.0",
            "--non-stab-machine-chance=1.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(63372, 63372, ".pokemons[*].tms[*]=true"),
            Pattern.glob(4078, 4078, ".pokemons[*].tms[*]=false"),
            Pattern.glob(3609, 3609, ".pokemons[*].hms[*]=true"),
            Pattern.glob(651, 651, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--status-moves-are-stab",   "--machines=random_follow_evos",
            "--stab-machine-chance=0.0", "--non-stab-machine-chance=1.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(60863, 60863, ".pokemons[*].tms[*]=true"),
            Pattern.glob(6587, 6587, ".pokemons[*].tms[*]=false"),
            Pattern.glob(3609, 3609, ".pokemons[*].hms[*]=true"),
            Pattern.glob(651, 651, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--machines=random_follow_evos", "--stab-machine-chance=0.0",
            "--non-stab-machine-chance=0.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(0, 0, ".pokemons[*].tms[*]=true"),
            Pattern.glob(67450, 67450, ".pokemons[*].tms[*]=false"),
            Pattern.glob(0, 0, ".pokemons[*].hms[*]=true"),
            Pattern.glob(4260, 4260, ".pokemons[*].hms[*]=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{
            "--status-moves-are-stab",   "--machines=random_follow_evos",
            "--stab-machine-chance=0.0", "--non-stab-machine-chance=0.0",
        },
        .patterns = &[_]Pattern{
            Pattern.glob(0, 0, ".pokemons[*].tms[*]=true"),
            Pattern.glob(67450, 67450, ".pokemons[*].tms[*]=false"),
            Pattern.glob(0, 0, ".pokemons[*].hms[*]=true"),
            Pattern.glob(4260, 4260, ".pokemons[*].hms[*]=false"),
        },
    });
}

test "types" {
    const test_case = try util.testing.filter(util.testing.test_case, &.{
        ".pokemons[*].types[*]=*",
        ".pokemons[*].evos[*].*",
        ".types[*].name=*",
    });
    defer testing.allocator.free(test_case);

    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{"--types=unchanged"},
        .patterns = &[_]Pattern{Pattern.glob(1420, 1420, ".pokemons[*].types[*]=*")},
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{"--types=random"},
        .patterns = &[_]Pattern{Pattern.glob(1420, 1420, ".pokemons[*].types[*]=*")},
    });

    var seed: usize = 0;
    while (seed < number_of_seeds) : (seed += 1) {
        var buf: [20]u8 = undefined;
        const seed_arg = std.fmt.bufPrint(&buf, "--seed={}", .{seed}) catch unreachable;

        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const data = try runProgram(arena.allocator(), .{
            .in = test_case,
            .args = &[_][]const u8{ "--types=random_follow_evos", seed_arg },
        });
        try expectPokemonMapFieldFollowEvo(data, "types");
    }
}

test "abilities" {
    const test_case = try util.testing.filter(util.testing.test_case, &.{
        ".pokemons[*].abilities[*]=*",
        ".pokemons[*].evos[*].*",
        ".abilities[*].name=*",
    });
    defer testing.allocator.free(test_case);

    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{"--abilities=unchanged"},
        .patterns = &[_]Pattern{Pattern.glob(2130, 2130, ".pokemons[*].abilities[*]=*")},
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{"--abilities=random"},
        .patterns = &[_]Pattern{Pattern.glob(2130, 2130, ".pokemons[*].abilities[*]=*")},
    });

    var seed: usize = 0;
    while (seed < number_of_seeds) : (seed += 1) {
        var buf: [20]u8 = undefined;
        const seed_arg = std.fmt.bufPrint(&buf, "--seed={}", .{seed}) catch unreachable;

        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const data = try runProgram(arena.allocator(), .{
            .in = test_case,
            .args = &[_][]const u8{ "--abilities=random_follow_evos", seed_arg },
        });
        try expectPokemonMapFieldFollowEvo(data, "abilities");
    }
}

test "items" {
    const test_case = try util.testing.filter(util.testing.test_case, &.{
        ".pokemons[*].items[*]=*",
        ".pokemons[*].evos[*].*",
        ".items[*].name=*",
    });
    defer testing.allocator.free(test_case);

    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{"--items=unchanged"},
        .patterns = &[_]Pattern{Pattern.glob(2130, 2130, ".pokemons[*].items[*]=*")},
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_case,
        .args = &[_][]const u8{"--items=random"},
        .patterns = &[_]Pattern{Pattern.glob(2130, 2130, ".pokemons[*].items[*]=*")},
    });

    var seed: usize = 0;
    while (seed < number_of_seeds) : (seed += 1) {
        var buf: [20]u8 = undefined;
        const seed_arg = std.fmt.bufPrint(&buf, "--seed={}", .{seed}) catch unreachable;

        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const data = try runProgram(arena.allocator(), .{
            .in = test_case,
            .args = &[_][]const u8{ "--items=random_follow_evos", seed_arg },
        });
        try expectPokemonMapFieldFollowEvo(data, "items");
    }
}
