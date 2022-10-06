const common = @import("common.zig");
const mecha = @import("mecha");
const std = @import("std");
const ston = @import("ston");
const util = @import("util");

const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;

const escape = util.escape;

// The tm35 format in 8 lines of cfg:
// Line <- Suffix* '=' .*
//
// Suffix
//    <- '.' IDENTIFIER
//     / '[' INTEGER ']'
//
// INTEGER <- [0-9]+
// IDENTIFIER <- [A-Za-z0-9_]+
//

/// A function for efficiently reading the tm35 format from `reader` and write unwanted lines
/// back into `writer`. `consume` will be called once a line has been parsed successfully, which
/// allows the caller to handle the parsed result however they like. If `consume` returns
/// `error.DidNotConsumeData`, then that will indicate to `io`, that the callback could not handle
/// the result and that `io` should handle it instead. Any other error from `consume` will
/// be returned from `io` as well.
pub fn io(
    allocator: mem.Allocator,
    reader: anytype,
    writer: anytype,
    ctx: anytype,
    consume: anytype,
) !void {
    @setEvalBranchQuota(100000);

    // WARNING: All the optimizations below have been done with the aid of profilers. Do not
    // simplify the code unless you have checked that the simplified code is just as fast.
    // Here is a simple oneliner you can use on linux to check:
    // ```
    // zig build tm35-noop -Drelease && \
    //   perf stat -r 250 dash -c 'zig-out/bin/tm35-noop < src/common/test_file.tm35 > /dev/null'
    // ```

    // Use an arraylist for buffering input. This allows us to ensure that there is always at
    // least one entire line in the input. ston.Deserializer can then work straight on the input
    // data without having to read the lines into a buffer first.
    var in = std.ArrayList(u8).init(allocator);
    defer in.deinit();

    try in.ensureUnusedCapacity(util.io.bufsize);

    {
        const in_slice = in.unusedCapacitySlice();
        in.items.len = try reader.read(in_slice[0 .. in_slice.len - 1]);
        in_slice[in.items.len] = 0;
    }

    const max_usize = math.maxInt(usize);
    var first_none_consumed_line: usize = max_usize;
    var start_of_line: usize = 0;
    var parser = ston.Parser{ .str = in.items.ptr[0..in.items.len :0] };
    var des = ston.Deserializer(Game){ .parser = &parser };
    while (parser.str.len != 0) : (start_of_line = parser.i) {
        while (des.next()) |res| : (start_of_line = parser.i) {
            if (consume(ctx, res)) |_| {
                if (first_none_consumed_line != max_usize) {
                    // Ok, `consume` just consumed a line after we have had at least one line
                    // that was not consumed. we can now slice from
                    // `first_none_consumed_line..start_of_line` to get all the lines we need to
                    // handle and append them all in one go to `out`. This is faster than
                    // appending none consumed lines one at the time because this feeds more data
                    // to mem.copy which then causes us to hit a codepath that is really fast
                    // on a lot of data.
                    const start = first_none_consumed_line;
                    const lines = parser.str[start..start_of_line];
                    try writer.writeAll(lines);
                    first_none_consumed_line = max_usize;
                }
            } else |err| switch (err) {
                // When `consume` returns `DidNotConsumeData` it communicates to us that they
                // could not handle the result in any meaningful way, so we are responsible
                // for writing the parsed string back out.
                error.DidNotConsumeData => if (first_none_consumed_line == max_usize) {
                    first_none_consumed_line = start_of_line;
                },
                else => return err,
            }
        } else |err|
        // If we couldn't parse a portion of the buffer, then we skip to the next line
        // and try again. The current line will just be written out again.
        if (mem.indexOfScalarPos(u8, parser.str, parser.i, '\n')) |index| {
            if (first_none_consumed_line == max_usize)
                first_none_consumed_line = start_of_line;

            const line = parser.str[start_of_line .. index + 1];
            parser.i = index + 1;
            std.log.debug("{s}: '{s}'", .{ @errorName(err), line[0 .. line.len - 1] });
            continue;
        }

        // Ok, we are done deserializing this batch of input. We need to output all the
        // lines that wasn't consumed and write them to `writer`.
        if (first_none_consumed_line != max_usize) {
            const start = first_none_consumed_line;
            const lines = parser.str[start..start_of_line];
            try writer.writeAll(lines);
            first_none_consumed_line = max_usize;
        }

        // There is probably some leftover which wasn't part of a full line. Copy that to the
        // start and make room for more data. Here we need to ensure that `out` has at least as
        // much capacity as `in`.
        mem.copy(u8, in.items, in.items[start_of_line..]);
        in.shrinkRetainingCapacity(in.items.len - start_of_line);
        try in.ensureUnusedCapacity(util.io.bufsize);

        const in_slice = in.unusedCapacitySlice();
        const num = try reader.read(in_slice[0 .. in_slice.len - 1]);
        in.items.len += num;

        if (num == 0 and in.items.len != 0) {
            // If we get here, then the input did not have a terminating newline. In that case
            // the above parsing logic will never succeed. Let's append a newline here so that
            // we can handle that egde case.
            in.appendAssumeCapacity('\n');
        }

        in.allocatedSlice()[in.items.len] = 0;
        parser = ston.Parser{ .str = in.items.ptr[0..in.items.len :0] };
    }
}

/// Takes a struct pointer and a union and sets the structs field with
/// the same name as the unions active tag to that tags value.
/// All union field names must exist in the struct, and these union
/// field types must be able to coirse to the struct fields type.
pub fn setField(struct_ptr: anytype, union_val: anytype) void {
    const Union = @TypeOf(union_val);

    inline for (@typeInfo(Union).Union.fields) |field| {
        if (union_val == @field(meta.Tag(Union), field.name)) {
            @field(struct_ptr, field.name) = @field(union_val, field.name);
            return;
        }
    }
    unreachable;
}

fn getUnionValue(
    val: anytype,
) @TypeOf(&@field(val, @typeInfo(@TypeOf(val)).Union.fields[0].name)) {
    const T = @TypeOf(val);
    inline for (@typeInfo(T).Union.fields) |field| {
        if (val == @field(meta.Tag(T), field.name)) {
            return &@field(val, field.name);
        }
    }
    unreachable;
}

pub const Color = common.ColorKind;
pub const EggGroup = common.EggGroup;
pub const GrowthRate = common.GrowthRate;
pub const PartyType = common.PartyType;
pub const Version = common.Version;

pub const Game = union(enum) {
    version: Version,
    game_title: []const u8,
    gamecode: []const u8,
    instant_text: bool,
    starters: ston.Index(u8, u16),
    text_delays: ston.Index(u8, u8),
    trainers: ston.Index(u16, Trainer),
    moves: ston.Index(u16, Move),
    pokemons: ston.Index(u16, Pokemon),
    abilities: ston.Index(u16, Ability),
    types: ston.Index(u8, Type),
    tms: ston.Index(u8, u16),
    hms: ston.Index(u8, u16),
    items: ston.Index(u16, Item),
    pokedex: ston.Index(u16, Pokedex),
    maps: ston.Index(u16, Map),
    wild_pokemons: ston.Index(u16, WildPokemons),
    static_pokemons: ston.Index(u16, StaticPokemon),
    given_pokemons: ston.Index(u16, GivenPokemon),
    pokeball_items: ston.Index(u16, PokeballItem),
    hidden_hollows: ston.Index(u16, HiddenHollow),
    text: ston.Index(u16, []const u8),
};

pub const Trainer = union(enum) {
    class: u8,
    encounter_music: u8,
    trainer_picture: u8,
    name: []const u8,
    items: ston.Index(u8, u16),
    party_type: PartyType,
    party_size: u8,
    party: ston.Index(u8, PartyMember),
};

pub const PartyMember = union(enum) {
    ability: u4,
    level: u8,
    species: u16,
    item: u16,
    moves: ston.Index(u8, u16),
};

pub const Move = union(enum) {
    name: []const u8,
    description: []const u8,
    effect: u8,
    power: u8,
    type: u8,
    accuracy: u8,
    pp: u8,
    target: u8,
    priority: u8,
    category: Category,

    pub const Category = common.MoveCategory;
};

pub fn Stats(comptime T: type) type {
    return union(enum) {
        hp: T,
        attack: T,
        defense: T,
        speed: T,
        sp_attack: T,
        sp_defense: T,

        pub fn value(stats: @This()) T {
            return getUnionValue(stats).*;
        }
    };
}

pub const Pokemon = union(enum) {
    name: []const u8,
    stats: Stats(u8),
    ev_yield: Stats(u2),
    base_exp_yield: u16,
    base_friendship: u8,
    catch_rate: u8,
    egg_cycles: u8,
    gender_ratio: u8,
    pokedex_entry: u16,
    growth_rate: GrowthRate,
    color: Color,
    egg_groups: ston.Index(u1, EggGroup),
    types: ston.Index(u1, u8),
    abilities: ston.Index(u2, u8),
    hms: ston.Index(u7, bool),
    tms: ston.Index(u7, bool),
    items: ston.Index(u8, u16),
    evos: ston.Index(u8, Evolution),
    moves: ston.Index(u8, LevelUpMove),
};

pub const Evolution = union(enum) {
    method: Method,
    param: u16,
    target: u16,

    pub const Method = enum {
        attack_eql_defense,
        attack_gth_defense,
        attack_lth_defense,
        beauty,
        friend_ship,
        friend_ship_during_day,
        friend_ship_during_night,
        level_up,
        level_up_female,
        level_up_holding_item_during_daytime,
        level_up_holding_item_during_the_night,
        level_up_in_special_magnetic_field,
        level_up_knowning_move,
        level_up_male,
        level_up_may_spawn_pokemon,
        level_up_near_ice_rock,
        level_up_near_moss_rock,
        level_up_spawn_if_cond,
        level_up_with_other_pokemon_in_party,
        personality_value1,
        personality_value2,
        trade,
        trade_holding_item,
        trade_with_pokemon,
        unknown_0x02,
        unknown_0x03,
        unused,
        use_item,
        use_item_on_female,
        use_item_on_male,
    };
};

pub const LevelUpMove = union(enum) {
    id: u16,
    level: u16,
};

pub const Ability = union(enum) {
    name: []const u8,
};

pub const Type = union(enum) {
    name: []const u8,
};

pub const Pocket = enum {
    none,
    items,
    key_items,
    poke_balls,
    tms_hms,
    berries,
};

pub const Item = union(enum) {
    name: []const u8,
    description: []const u8,
    price: u32,
    battle_effect: u8,
    pocket: Pocket,
};

pub const Pokedex = union(enum) {
    height: u32,
    weight: u32,
    category: []const u8,
};

pub const Map = union(enum) {
    music: u16,
    cave: u8,
    weather: u8,
    type: u8,
    escape_rope: u8,
    battle_scene: u8,
    allow_cycling: bool,
    allow_escaping: bool,
    allow_running: bool,
    show_map_name: bool,
};

pub const WildPokemons = union(enum) {
    grass_0: WildArea,
    grass_1: WildArea,
    grass_2: WildArea,
    grass_3: WildArea,
    grass_4: WildArea,
    grass_5: WildArea,
    grass_6: WildArea,
    dark_grass_0: WildArea,
    dark_grass_1: WildArea,
    dark_grass_2: WildArea,
    dark_grass_3: WildArea,
    rustling_grass_0: WildArea,
    rustling_grass_1: WildArea,
    rustling_grass_2: WildArea,
    rustling_grass_3: WildArea,
    surf_0: WildArea,
    surf_1: WildArea,
    surf_2: WildArea,
    surf_3: WildArea,
    ripple_surf_0: WildArea,
    ripple_surf_1: WildArea,
    ripple_surf_2: WildArea,
    ripple_surf_3: WildArea,
    rock_smash: WildArea,
    fishing_0: WildArea,
    fishing_1: WildArea,
    fishing_2: WildArea,
    fishing_3: WildArea,
    ripple_fishing_0: WildArea,
    ripple_fishing_1: WildArea,
    ripple_fishing_2: WildArea,
    ripple_fishing_3: WildArea,

    pub fn init(tag: meta.Tag(WildPokemons), area: WildArea) WildPokemons {
        const Tag = meta.Tag(WildPokemons);
        inline for (@typeInfo(Tag).Enum.fields) |field| {
            if (@field(Tag, field.name) == tag)
                return @unionInit(WildPokemons, field.name, area);
        }
        unreachable;
    }

    pub fn value(pokemons: @This()) WildArea {
        return getUnionValue(pokemons).*;
    }
};

pub const WildArea = union(enum) {
    encounter_rate: u32,
    pokemons: ston.Index(u8, WildPokemon),
};

pub const WildPokemon = union(enum) {
    min_level: u8,
    max_level: u8,
    species: u16,
};

pub const StaticPokemon = union(enum) {
    species: u16,
    level: u16,
};

pub const GivenPokemon = union(enum) {
    species: u16,
    level: u16,
};

pub const PokeballItem = union(enum) {
    item: u16,
    amount: u16,
};

pub const HiddenHollow = union(enum) {
    groups: ston.Index(u8, union(enum) {
        pokemons: ston.Index(u8, union(enum) {
            species: u16,
        }),
    }),
    items: ston.Index(u8, u16),
};
