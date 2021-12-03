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
/// back into `writer`. `parse` will be called once a line has been parsed successfully, which
/// allows the caller to handle the parsed result however they like. If `parse` returns
/// `error.ParserFailed`, then that will indicate to `io`, that the callback could not handle
/// the result and that `io` should handle it instead. Any other error from `parse` will
/// be returned from `io` as well.
pub fn io(
    allocator: *mem.Allocator,
    reader: anytype,
    writer: anytype,
    ctx: anytype,
    parse: anytype,
) !void {
    var tok: ston.Tokenizer = undefined;
    var des = ston.Deserializer(Game){ .tok = &tok };
    var fifo = util.io.Fifo(.Dynamic).init(allocator);
    defer fifo.deinit();

    while (true) {
        const buf = fifo.readableSlice(0);
        tok = ston.tokenize(buf);

        var start: usize = 0;
        while (true) {
            while (des.next()) |res| {
                parse(ctx, res) catch |err| switch (err) {
                    // When `parse` returns `ParserFailed` it communicates to us that they
                    // could not handle the result in any meaningful way, so we are responsible
                    // for writing the parsed string back out.
                    error.ParserFailed => try writer.writeAll(buf[start..tok.i]),
                    else => return err,
                };

                start = tok.i;
            } else |_| {}

            // If we couldn't parse a portion of the buffer, then we skip to the next line
            // and try again. The current line will just be written out again.
            if (mem.indexOfScalarPos(u8, buf, start, '\n')) |index| {
                const line = buf[start .. index + 1];
                try writer.writeAll(line);

                start = index + 1;
                continue;
            }

            break;
        }

        const new_buf = blk: {
            fifo.discard(start);
            fifo.realign();
            const slice = fifo.writableSlice(0);
            if (slice.len != 0)
                break :blk slice;
            break :blk try fifo.writableWithSize(math.max(util.io.bufsize, fifo.buf.len));
        };

        const num = try reader.read(new_buf);
        fifo.update(num);

        if (num == 0) {
            if (fifo.count == 0)
                return;

            // If get here, then both parsing and the "index of newline" branches above
            // failed. Let's terminate the buffer, so that at least the "index of newline"
            // branch will succeed. Once that succeed, this branch will never be hit again.
            try fifo.writeItem('\n');
        }
    }
}

/// Takes a struct pointer and a union and sets the structs field with
/// the same name as the unions active tag to that tags value.
/// All union field names must exist in the struct, and these union
/// field types must be able to coirse to the struct fields type.
pub fn setField(struct_ptr: anytype, union_val: anytype) void {
    const Union = @TypeOf(union_val);

    inline for (@typeInfo(Union).Union.fields) |field| {
        if (union_val == @field(meta.TagType(Union), field.name)) {
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
        if (val == @field(meta.TagType(T), field.name)) {
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
    abilities: ston.Index(u8, u8),
    egg_groups: ston.Index(u8, EggGroup),
    evos: ston.Index(u8, Evolution),
    hms: ston.Index(u8, bool),
    items: ston.Index(u8, u16),
    moves: ston.Index(u8, LevelUpMove),
    tms: ston.Index(u8, bool),
    types: ston.Index(u8, u8),
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
    grass: WildArea,
    grass_morning: WildArea,
    grass_day: WildArea,
    grass_night: WildArea,
    dark_grass: WildArea,
    rustling_grass: WildArea,
    land: WildArea,
    surf: WildArea,
    ripple_surf: WildArea,
    rock_smash: WildArea,
    fishing: WildArea,
    ripple_fishing: WildArea,
    swarm_replace: WildArea,
    day_replace: WildArea,
    night_replace: WildArea,
    radar_replace: WildArea,
    unknown_replace: WildArea,
    gba_replace: WildArea,
    sea_unknown: WildArea,
    old_rod: WildArea,
    good_rod: WildArea,
    super_rod: WildArea,

    pub fn init(tag: meta.TagType(WildPokemons), area: WildArea) WildPokemons {
        const Tag = meta.TagType(WildPokemons);
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
