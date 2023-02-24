const clap = @import("clap");
const core = @import("core");
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

const format = core.format;

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

pub const parsers = .{
    .INT = clap.parsers.int(u64, 0),
    .FLOAT = clap.parsers.float(f64),
    .@"unchanged|random|random_follow_evos" = clap.parsers.enumeration(Method),
};

pub const params = clap.parseParamsComptime(
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\-s, --seed <INT>
    \\        The seed to use for random numbers. A random seed will be picked if this is not
    \\        specified.
    \\
    \\-v, --version
    \\        Output version information and exit.
    \\
    \\-a, --abilities <unchanged|random|random_follow_evos>
    \\        The method for which pokemon abilities will be randomized. (default: unchanged)
    \\
    \\-i, --items <unchanged|random|random_follow_evos>
    \\        The method for which pokemon items will be randomized. (default: unchanged)
    \\
    \\-t, --types <unchanged|random|random_follow_evos>
    \\        The method for which pokemon types will be randomized. (default: unchanged)
    \\
    \\-S, --stats <unchanged|random|random_follow_evos>
    \\        The method for which pokemon stats will be randomized. (default: unchanged)
    \\
    \\    --same-total-stats
    \\        Pokémons will have the same total stats after randomization.
    \\
    \\-m, --machines <unchanged|random|random_follow_evos>
    \\        The method for which pokemon machines learned (tms,hms) will be randomized.
    \\        (default: unchanged)
    \\
    \\    --non-stab-machine-chance <FLOAT>
    \\        The chance a pokemon can learn a machine providing a non stab move when
    \\        randomizing machines. (default: 0.5)
    \\
    \\    --stab-machine-chance <FLOAT>
    \\        The chance a pokemon can learn a machine providing a stab move when randomizing
    \\        machines. (default: 0.5)
    \\
    \\    --status-moves-are-stab
    \\        Whether status moves, which are the same typing as the pokemon, should be
    \\        considered as stab moves when determining the chance that the move should be
    \\        learnable.
);

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const options = Options{
        .seed = args.args.seed orelse std.crypto.random.int(u64),
        .same_total_stats = args.args.@"same-total-stats",
        .status_moves_are_stab = args.args.@"status-moves-are-stab",
        .abilities = args.args.abilities orelse .unchanged,
        .types = args.args.types orelse .unchanged,
        .items = args.args.items orelse .unchanged,
        .stats = args.args.stats orelse .unchanged,
        .machines = args.args.machines orelse .unchanged,
        .chance_to_learn_non_stab_machine = args.args.@"non-stab-machine-chance" orelse 0.5,
        .chance_to_learn_stab_machine = args.args.@"stab-machine-chance" orelse 0.5,
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
        for (pokemon.evos.values()) |evo|
            _ = program.first_evos.swapRemove(evo.target);
    }

    try program.randomize();
    try program.output(stdio.out);
}

fn output(program: *Program, writer: anytype) !void {
    for (program.pokemons.values(), 0..) |*pokemon, i| {
        const species = program.pokemons.keys()[i];
        try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
            .types = pokemon.types,
            .abilities = pokemon.abilities,
            .items = pokemon.items,
            .stats = pokemon.stats,
            .evos = pokemon.evos,
        }) });

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
                .evos => |evos| {
                    switch (evos.value) {
                        .target => |target| try pokemon.evos.put(
                            allocator,
                            evos.index,
                            .{ .target = target },
                        ),
                        .param, .method => return error.DidNotConsumeData,
                    }
                },
                .catch_rate,
                .base_exp_yield,
                .gender_ratio,
                .egg_cycles,
                .base_friendship,
                .growth_rate,
                .egg_groups,
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
    var default_random = rand.DefaultPrng.init(program.options.seed);
    const random = default_random.random();

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
    for (pokemon.evos.values()) |evo| {
        const evo_pokemon = program.pokemons.getPtr(evo.target).?;
        inline for (fields) |field|
            @field(evo_pokemon, field) = @field(pokemon, field);
        program.copyFieldsToEvolutions(evo_pokemon.*, fields);
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
        var res: usize = 0;
        for (stats.slice()) |item| res += item;
        break :blk res;
    } else blk: {
        var min_total: usize = 1;
        for (stats_to_start_from.slice()) |item| min_total += item;

        const max_total = stats_to_start_from.len * math.maxInt(u8);
        break :blk random.intRangeAtMost(usize, math.min(min_total, max_total), max_total);
    };

    var stats = stats_to_start_from;
    randomUntilSum(random, u8, stats.slice(), new_total);
    pokemon.statsFromSlice(stats.slice());

    if (program.options.stats == .random_follow_evos) {
        for (pokemon.evos.values()) |evo| {
            const evo_pokemon = program.pokemons.getPtr(evo.target).?;
            program.randomizeStatsEx(random, evo_pokemon, stats);
        }
    }
}

fn randomUntilSum(
    random: rand.Random,
    comptime T: type,
    buf: []T,
    sum: usize,
) void {
    var curr: usize = 0;
    for (buf) |item| curr += item;

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

const Evos = std.AutoArrayHashMapUnmanaged(u8, Evo);
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

const Evo = struct {
    target: u16,
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
    @setEvalBranchQuota(10000000);

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
        var pokemon_total: usize = 0;
        for (pokemon_stats.slice()) |item| pokemon_total += item;

        for (pokemon.evos.values()) |evo| {
            const evo_pokemon = program.pokemons.getPtr(evo.target).?;
            const evo_stats = evo_pokemon.statsToArray();

            var evo_total: usize = 0;
            for (evo_stats.slice()) |item| evo_total += item;

            try testing.expectEqual(pokemon_stats.len, evo_stats.len);
            for (pokemon_stats.constSlice(), 0..) |poke_stat, i| {
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
        for (pokemon.evos.values()) |evo| {
            const evo_pokemon = program.pokemons.getPtr(evo.target).?;
            try util.set.expectEqual(@field(pokemon, field), @field(evo_pokemon, field));
        }
    }
}

fn expectSameTotalStats(old_prog: Program, new_prog: Program) !void {
    const old_keys = old_prog.pokemons.keys();
    const old_pokemons = old_prog.pokemons.values();

    try testing.expectEqual(old_pokemons.len, new_prog.pokemons.values().len);
    for (old_pokemons, 0..) |*old, i| {
        const new = new_prog.pokemons.getPtr(old_keys[i]).?;
        const old_stats = old.statsToArray();
        const new_stats = new.statsToArray();

        try testing.expectEqual(old_stats.len, new_stats.len);

        var old_total: usize = 0;
        var new_total: usize = 0;
        for (old_stats.slice()) |item| old_total += item;
        for (new_stats.slice()) |item| new_total += item;
        try testing.expectEqual(
            old_total,
            new_total,
        );
    }
}

const number_of_seeds = 40;
const Pattern = util.testing.Pattern;

test "tm35-rand-pokemons - stats" {
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
            Pattern.string(710, 710, "].stats.hp="),
            Pattern.string(710, 710, "].stats.attack="),
            Pattern.string(710, 710, "].stats.defense="),
            Pattern.string(710, 710, "].stats.speed="),
            Pattern.string(710, 710, "].stats.sp_attack="),
            Pattern.string(710, 710, "].stats.sp_defense="),
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

test "tm35-rand-pokemons - machines" {
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

test "tm35-rand-pokemons - types" {
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

test "tm35-rand-pokemons - abilities" {
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

test "tm35-rand-pokemons - items" {
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
