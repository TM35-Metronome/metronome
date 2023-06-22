const std = @import("std");
const util = @import("util");

const math = std.math;
const mem = std.mem;

pub const AbilitySet = std.AutoArrayHashMapUnmanaged(u16, void);
pub const ItemSet = std.AutoArrayHashMapUnmanaged(u16, void);
pub const PokedexSet = std.AutoArrayHashMapUnmanaged(u16, void);
pub const SpeciesSet = std.AutoArrayHashMapUnmanaged(u16, void);
pub const TypeSet = std.AutoArrayHashMapUnmanaged(u16, void);

pub fn pokedexPokemons(
    allocator: mem.Allocator,
    pokemons: anytype,
    pokedex: PokedexSet,
) !SpeciesSet {
    var res = SpeciesSet{};
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

pub fn includeExcludePokemons(
    allocator: mem.Allocator,
    pokemons: anytype,
    species: SpeciesSet,
    excluded_pokemons: []const []const u8,
    included_pokemons: []const []const u8,
) !SpeciesSet {
    var res = SpeciesSet{};
    errdefer res.deinit(allocator);

    for (species.keys()) |s| {
        const pokemon = pokemons.getPtr(s) orelse continue;
        if (util.glob.matchesOneOf(pokemon.name, included_pokemons) == null and
            util.glob.matchesOneOf(pokemon.name, excluded_pokemons) != null)
            continue;

        _ = try res.put(allocator, s, {});
    }

    return res;
}

pub fn MinMax(comptime T: type) type {
    return struct { min: T, max: T };
}

pub fn minMaxStats(pokemons: anytype, species: SpeciesSet) MinMax(u16) {
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
