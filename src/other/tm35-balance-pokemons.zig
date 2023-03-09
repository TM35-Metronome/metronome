const clap = @import("clap");
const core = @import("core");
const std = @import("std");
const ston = @import("ston");
const util = @import("util");
const ziter = @import("ziter");

const math = std.math;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;

const format = core.format;

const Program = @This();

allocator: mem.Allocator,
options: Options,

pokedex: Set = Set{},
pokemons: Pokemons = .{},

first_evos: Set = Set{},
species_by_category: SpeciesByCategory = .{},

const Options = struct {
    stats: Method,
};

const Method = enum {
    unchanged,
    buff_weak,
};

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Tries to buff weak Pokémons to be more usable compared to strong ones.
    \\
;

pub const parsers = .{
    .@"unchanged|buff_weak" = clap.parsers.enumeration(Method),
};

pub const params = clap.parseParamsComptime(
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\-v, --version
    \\        Output version information and exit.
    \\
    \\-s, --stats <unchanged|buff_weak>
    \\        Buff stats of weak Pokémons.
    \\
);

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const options = Options{
        .stats = args.args.stats orelse .unchanged,
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

    const pokedex_mons = try getPokedexPokemons(
        program.allocator,
        program.pokemons,
        program.pokedex,
    );
    try program.first_evos.ensureTotalCapacity(program.allocator, pokedex_mons.count());

    for (pokedex_mons.keys()) |species|
        program.first_evos.putAssumeCapacity(species, {});
    for (program.pokemons.values()) |pokemon| {
        for (pokemon.evos.values()) |evo|
            _ = program.first_evos.swapRemove(evo.target);
    }
    for (program.first_evos.keys()) |species| {
        const total_evolution_chain = program.countEvolutions(species);
        try program.categoriesPokemonAndEvos(species, .{
            .total_evolution_chain = total_evolution_chain,
            .current_evolution = 0,
        });
    }

    try program.balance();
    try program.output(stdio.out);
}

fn output(program: *Program, writer: anytype) !void {
    for (program.pokemons.keys(), program.pokemons.values()) |species, *pokemon| {
        try ston.serialize(writer, .{ .pokemons = ston.index(species, .{
            .stats = pokemon.stats,
        }) });
    }
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .pokedex => |pokedex| {
            _ = try program.pokedex.put(allocator, pokedex.index, {});
            return error.DidNotConsumeData;
        },
        .pokemons => |pokemons| {
            const pokemon = (try program.pokemons.getOrPutValue(
                allocator,
                pokemons.index,
                .{},
            )).value_ptr;

            switch (pokemons.value) {
                .stats => |stats| pokemon.stats.put(stats, stats.value()),
                .evos => |evos| switch (evos.value) {
                    .target => |target| {
                        try pokemon.evos.put(allocator, evos.index, .{ .target = target });
                        return error.DidNotConsumeData;
                    },
                    .param, .method => return error.DidNotConsumeData,
                },
                .pokedex_entry => |pokedex_entry| {
                    pokemon.pokedex_entry = pokedex_entry;
                    return error.DidNotConsumeData;
                },
                .catch_rate => |catch_rate| {
                    pokemon.catch_rate = catch_rate;
                    return error.DidNotConsumeData;
                },
                .items,
                .base_exp_yield,
                .gender_ratio,
                .egg_cycles,
                .base_friendship,
                .growth_rate,
                .egg_groups,
                .moves,
                .name,
                .types,
                .abilities,
                .hms,
                .tms,
                => return error.DidNotConsumeData,
            }
            return;
        },
        else => return error.DidNotConsumeData,
    }
    unreachable;
}

fn balance(program: *Program) !void {
    // const categories = program.species_by_category.keys();
    const category_sets = program.species_by_category.values();

    switch (program.options.stats) {
        .buff_weak => for (category_sets) |species_set| {
            // Let's figure out the best total stats for the category. Use this to buff weaker
            // pokemons stats.
            var max_total_stats: u16 = 0;
            var min_total_stats: u16 = math.maxInt(u16);
            for (species_set.keys()) |species| {
                const pokemon = program.pokemons.getPtr(species).?;
                const stats = pokemon.statsToArray();
                const total_stats = ziter.deref(stats.slice()).sum(u16);
                max_total_stats = math.max(max_total_stats, total_stats);
                min_total_stats = math.min(min_total_stats, total_stats);
            }

            for (species_set.keys()) |species| {
                const pokemon = program.pokemons.getPtr(species).?;
                var stats = pokemon.statsToArray();
                const total_stats = ziter.deref(stats.slice()).sum(u16);

                const buff = statBuff(min_total_stats, max_total_stats, total_stats);
                const buff_to_each_stat = @intCast(u8, buff / stats.len);
                var buff_remains = buff % stats.len;
                for (stats.slice()) |*stat| {
                    // Only one pokemon has a stat of 1. That is Shedinja with HP 1. We don't wonna
                    // buff that, as that would break how that pokemon works.
                    if (stat.* == 1) {
                        buff_remains += buff_to_each_stat;
                        continue;
                    }

                    const old_stat = stat.*;
                    stat.* +|= buff_to_each_stat;

                    // We might hit the max stat of 255. In that case, we save the amount we didn't
                    // get to add in buff_remains for later.
                    buff_remains += buff_to_each_stat - (stat.* - old_stat);
                }

                while (buff_remains != 0) for (stats.slice()) |*stat| {
                    if (stat.* != 1 and stat.* != math.maxInt(u8) and buff_remains != 0) {
                        stat.* += 1;
                        buff_remains -= 1;
                    }
                };

                pokemon.statsFromSlice(stats.slice());
            }
        },
        .unchanged => {},
    }
}

fn countEvolutions(program: Program, species: u16) u8 {
    const pokemon = program.pokemons.get(species).?;

    var res: u8 = 0;
    for (pokemon.evos.values()) |evo| {
        const evos = program.countEvolutions(evo.target);
        res = math.max(res, evos + 1);
    }

    return res;
}

fn categoriesPokemonAndEvos(program: *Program, species: u16, category: Pokemon.Category) !void {
    const category_set = try program.species_by_category.getOrPutValue(
        program.allocator,
        category,
        .{},
    );
    try category_set.value_ptr.put(program.allocator, species, {});

    const pokemon = program.pokemons.get(species).?;
    for (pokemon.evos.values()) |evo| {
        try program.categoriesPokemonAndEvos(evo.target, .{
            .total_evolution_chain = category.total_evolution_chain,
            .current_evolution = category.current_evolution + 1,
        });
    }
}

// Function to calculate the buff to stats based on the maximum total stats and our total stats.
// This function will give larger buffs, the bigger the differnce. See tests for examples for how
// this function grows.
fn statBuff(min_total_stats: u16, max_total_stats: u16, total_stats: u16) u16 {
    if (min_total_stats == max_total_stats)
        return 0;

    const total_min_diff = total_stats - min_total_stats;
    const min_max_diff = max_total_stats - min_total_stats;
    const fmin_max_diff = @intToFloat(f64, min_max_diff);
    const x = @intToFloat(f64, min_max_diff - total_min_diff);
    const @"x^2" = math.pow(f64, x, 2);
    return @floatToInt(u16, math.max(0, @"x^2" / (fmin_max_diff * 1.4) - (3 * x) / 14));
}

fn statBuffNewTotal(min_total_stats: u16, max_total_stats: u16, total_stats: u16) u16 {
    return statBuff(min_total_stats, max_total_stats, total_stats) + total_stats;
}

test "statBuff" {
    // Buffs for no evolution pokemons
    try testing.expectEqual(@as(u16, 720), statBuffNewTotal(250, 720, 720)); // Arceus
    try testing.expectEqual(@as(u16, 680), statBuffNewTotal(250, 720, 680)); // Mewtwo
    try testing.expectEqual(@as(u16, 600), statBuffNewTotal(250, 720, 600)); // Celebi
    try testing.expectEqual(@as(u16, 580), statBuffNewTotal(250, 720, 580)); // Registeel
    try testing.expectEqual(@as(u16, 547), statBuffNewTotal(250, 720, 535)); // Lapras
    try testing.expectEqual(@as(u16, 526), statBuffNewTotal(250, 720, 500)); // Pinsir
    try testing.expectEqual(@as(u16, 511), statBuffNewTotal(250, 720, 470)); // Alomomola
    try testing.expectEqual(@as(u16, 499), statBuffNewTotal(250, 720, 440)); // Solrock
    try testing.expectEqual(@as(u16, 488), statBuffNewTotal(250, 720, 405)); // Plusle
    try testing.expectEqual(@as(u16, 482), statBuffNewTotal(250, 720, 380)); // Corsola
    try testing.expectEqual(@as(u16, 485), statBuffNewTotal(250, 720, 250)); // Smeargle

    // Buffs for a third evolution pokemon in a 3 evolution line
    try testing.expectEqual(@as(u16, 670), statBuffNewTotal(385, 670, 670)); // Slaking
    try testing.expectEqual(@as(u16, 600), statBuffNewTotal(385, 670, 600)); // Salamence
    try testing.expectEqual(@as(u16, 554), statBuffNewTotal(385, 670, 540)); // Gyarados
    try testing.expectEqual(@as(u16, 536), statBuffNewTotal(385, 670, 500)); // Gengar
    try testing.expectEqual(@as(u16, 524), statBuffNewTotal(385, 670, 450)); // Jumpluff
    try testing.expectEqual(@as(u16, 527), statBuffNewTotal(385, 670, 385)); // Butterfree

    // Buffs for a second evolution pokemon in a 3 evolution line
    try testing.expectEqual(@as(u16, 515), statBuffNewTotal(205, 515, 515)); // Porygon2
    try testing.expectEqual(@as(u16, 455), statBuffNewTotal(205, 515, 455)); // Golbat
    try testing.expectEqual(@as(u16, 420), statBuffNewTotal(205, 515, 420)); // Dragonnair
    try testing.expectEqual(@as(u16, 399), statBuffNewTotal(205, 515, 390)); // Boldore
    try testing.expectEqual(@as(u16, 373), statBuffNewTotal(205, 515, 340)); // Staravia
    try testing.expectEqual(@as(u16, 360), statBuffNewTotal(205, 515, 300)); // Pikachu
    try testing.expectEqual(@as(u16, 356), statBuffNewTotal(205, 515, 278)); // Kirlia
    try testing.expectEqual(@as(u16, 360), statBuffNewTotal(205, 515, 205)); // Metapod

    // Buffs for a first evolution pokemon in a 3 evolution line
    try testing.expectEqual(@as(u16, 395), statBuffNewTotal(190, 395, 395)); // Porygon
    try testing.expectEqual(@as(u16, 360), statBuffNewTotal(190, 395, 360)); // Elekid
    try testing.expectEqual(@as(u16, 323), statBuffNewTotal(190, 395, 320)); // Oddish
    try testing.expectEqual(@as(u16, 305), statBuffNewTotal(190, 395, 290)); // Solosis
    try testing.expectEqual(@as(u16, 294), statBuffNewTotal(190, 395, 260)); // Venipede
    try testing.expectEqual(@as(u16, 289), statBuffNewTotal(190, 395, 210)); // Igglybuff
    try testing.expectEqual(@as(u16, 292), statBuffNewTotal(190, 395, 190)); // Azurill

    // Buffs for a second evolution pokemon in a 2 evolution line
    try testing.expectEqual(@as(u16, 567), statBuffNewTotal(236, 567, 567)); // Archeops
    try testing.expectEqual(@as(u16, 535), statBuffNewTotal(236, 567, 535)); // Tangrowth
    try testing.expectEqual(@as(u16, 500), statBuffNewTotal(236, 567, 500)); // Muk
    try testing.expectEqual(@as(u16, 470), statBuffNewTotal(236, 567, 470)); // Cinccino
    try testing.expectEqual(@as(u16, 454), statBuffNewTotal(236, 567, 450)); // Venomoth
    try testing.expectEqual(@as(u16, 435), statBuffNewTotal(236, 567, 420)); // Wobbuffet
    try testing.expectEqual(@as(u16, 419), statBuffNewTotal(236, 567, 390)); // Ledian
    try testing.expectEqual(@as(u16, 415), statBuffNewTotal(236, 567, 380)); // Delcatty
    try testing.expectEqual(@as(u16, 401), statBuffNewTotal(236, 567, 236)); // Shedinja

    // Buffs for a first evolution pokemon in a 2 evolution line
    try testing.expectEqual(@as(u16, 500), statBuffNewTotal(180, 500, 500)); // Scyther
    try testing.expectEqual(@as(u16, 455), statBuffNewTotal(180, 500, 455)); // Dusclops
    try testing.expectEqual(@as(u16, 401), statBuffNewTotal(180, 500, 401)); // Archen
    try testing.expectEqual(@as(u16, 376), statBuffNewTotal(180, 500, 365)); // Aipom
    try testing.expectEqual(@as(u16, 358), statBuffNewTotal(180, 500, 330)); // Teddiursa
    try testing.expectEqual(@as(u16, 346), statBuffNewTotal(180, 500, 300)); // Sandshrew
    try testing.expectEqual(@as(u16, 338), statBuffNewTotal(180, 500, 270)); // Wingull
    try testing.expectEqual(@as(u16, 335), statBuffNewTotal(180, 500, 237)); // Makuhita
    try testing.expectEqual(@as(u16, 340), statBuffNewTotal(180, 500, 180)); // Sunkurn

    try testing.expectEqual(@as(u16, 360), statBuffNewTotal(360, 360, 360)); // Edgecase
}

const BestTotalStatsPerCategory = std.AutoArrayHashMapUnmanaged(Pokemon.Category, u16);
const Evos = std.AutoArrayHashMapUnmanaged(u8, Evo);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);
const SpeciesByCategory = std.AutoArrayHashMapUnmanaged(Pokemon.Category, Set);
const Stats = std.EnumMap(meta.Tag(format.Stats(u8)), u8);

fn getPokedexPokemons(allocator: mem.Allocator, pokemons: Pokemons, pokedex: Set) !Set {
    var res = Set{};
    errdefer res.deinit(allocator);

    for (pokemons.keys(), pokemons.values()) |species, pokemon| {
        if (pokemon.catch_rate == 0)
            continue;
        if (pokedex.get(pokemon.pokedex_entry) == null)
            continue;
        _ = try res.put(allocator, species, {});
    }

    return res;
}

const Pokemon = struct {
    stats: Stats = Stats{},
    pokedex_entry: u16 = math.maxInt(u16),
    catch_rate: usize = 1,
    evos: Evos = Evos{},

    fn statsToArray(pokemon: *Pokemon) std.BoundedArray(u8, Stats.len) {
        var res = std.BoundedArray(u8, Stats.len){};
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

    const Category = struct {
        total_evolution_chain: u8,
        current_evolution: u8,
    };
};

const Evo = struct {
    target: u16,
};
