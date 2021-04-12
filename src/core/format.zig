const common = @import("common.zig");
const mecha = @import("mecha");
const std = @import("std");
const util = @import("util");

const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const testing = std.testing;

//! The tm35 format in 8 lines of cfg:
//! Line <- Suffix* '=' .*
//!
//! Suffix
//!    <- '.' IDENTIFIER
//!     / '[' INTEGER ']'
//!
//! INTEGER <- [0-9]+
//! IDENTIFIER <- [A-Za-z0-9_]+
//!

pub fn parseEscape(arena: *mem.Allocator, str: []const u8) !Game {
    const res = (comptime parser(Game, "", true))(arena, str) catch |err| switch (err) {
        error.OtherError => unreachable,
        error.OutOfMemory => return error.OutOfMemory,
        error.ParserFailed => return error.ParserFailed,
    };
    return res.value;
}

pub fn parseNoEscape(str: []const u8) !Game {
    var fba = std.heap.FixedBufferAllocator.init("");
    const res = (comptime parser(Game, "", false))(&fba.allocator, str) catch |err| switch (err) {
        error.OtherError => unreachable,
        error.OutOfMemory => unreachable,
        error.ParserFailed => return error.ParserFailed,
    };
    return res.value;
}

fn parser(comptime T: type, comptime prefix: []const u8, comptime do_escape: bool) mecha.Parser(T) {
    if (isArray(T))
        return arrayParser(T, prefix, do_escape);
    switch (T) {
        []const u8 => if (do_escape) {
            // With no '\\' we can assume that string does not need to be unescaped, so we
            // can avoid doing an allocation.
            const text = mecha.combine(.{
                mecha.many(mecha.ascii.not(mecha.ascii.char('\\')), .{ .collect = false }),
                mecha.eos,
            });
            const escaped_text = mecha.convert([]const u8, struct {
                fn conv(allocator: *mem.Allocator, str: []const u8) mecha.Error![]const u8 {
                    return try util.escape.default.unescapeAlloc(allocator, str);
                }
            }.conv, mecha.rest);

            return mecha.combine(.{
                mecha.string(prefix ++ "="),
                mecha.oneOf(.{ text, escaped_text }),
            });
        } else {
            return mecha.combine(.{
                mecha.string(prefix ++ "="),
                mecha.rest,
            });
        },
        else => {},
    }
    switch (@typeInfo(T)) {
        .Int => return intValueParser(T, prefix),
        .Enum => return mecha.combine(
            .{ mecha.string(prefix ++ "="), mecha.enumeration(T), mecha.eos },
        ),
        .Bool => return mecha.convert(bool, mecha.toBool, mecha.combine(
            .{ mecha.string(prefix ++ "="), mecha.rest },
        )),
        .Union => return unionParser(T, prefix, do_escape),
        else => @compileError("'" ++ @typeName(T) ++ "' is not supported"),
    }
}

const inl = std.builtin.CallOptions{ .modifier = .always_inline };

fn arrayParser(comptime T: type, comptime prefix: []const u8, comptime do_escape: bool) mecha.Parser(T) {
    const Res = mecha.Result(T);
    return struct {
        fn p(allocator: *mem.Allocator, str: []const u8) mecha.Error!Res {
            if (!mem.startsWith(u8, str, prefix ++ "["))
                return error.ParserFailed;
            const index = try @call(
                inl,
                comptime mecha.int(T.Index, .{ .parse_sign = false }),
                .{ allocator, str[prefix.len + 1 ..] },
            );
            const value = try @call(
                inl,
                comptime parser(T.Value, "]", do_escape),
                .{ allocator, index.rest },
            );
            return Res{
                .rest = value.rest,
                .value = .{
                    .index = index.value,
                    .value = value.value,
                },
            };
        }
    }.p;
}

fn unionParser(comptime T: type, comptime prefix: []const u8, comptime do_escape: bool) mecha.Parser(T) {
    const Res = mecha.Result(T);
    const info = @typeInfo(T).Union;
    return struct {
        fn p(allocator: *mem.Allocator, str: []const u8) mecha.Error!Res {
            inline for (info.fields) |f| {
                const new_prefix = prefix ++ "." ++ f.name;
                const field_parser = comptime parser(f.field_type, new_prefix, do_escape);
                if (@call(inl, field_parser, .{ allocator, str })) |res| {
                    return Res{
                        .rest = res.rest,
                        .value = @unionInit(T, f.name, res.value),
                    };
                } else |err| switch (err) {
                    error.ParserFailed => {},
                    else => return err,
                }
            }

            return error.ParserFailed;
        }
    }.p;
}

fn intValueParser(comptime T: type, comptime prefix: []const u8) mecha.Parser(T) {
    const Res = mecha.Result(T);
    return struct {
        fn p(allocator: *mem.Allocator, str: []const u8) mecha.Error!Res {
            if (!mem.startsWith(u8, str, prefix ++ "="))
                return error.ParserFailed;
            const res = try @call(
                inl,
                comptime mecha.int(T, .{ .parse_sign = false }),
                .{ allocator, str[prefix.len + 1 ..] },
            );
            if (res.rest.len != 0)
                return error.ParserFailed;
            return res;
        }
    }.p;
}

pub fn write(writer: anytype, value: anytype) !void {
    const T = @TypeOf(value);
    if (comptime isArray(T)) {
        try writer.writeByte('[');
        try fmt.formatInt(value.index, 10, false, .{}, writer);
        try writer.writeByte(']');
        try write(writer, value.value);
    } else switch (T) {
        []const u8 => {
            try writer.writeByte('=');
            try util.escape.default.escapeWrite(writer, value);
            try writer.writeByte('\n');
        },
        else => switch (@typeInfo(T)) {
            .Bool => try writer.writeAll(if (value) "=true\n" else "=false\n"),
            .Int => {
                try writer.writeByte('=');
                try fmt.formatInt(value, 10, false, .{}, writer);
                try writer.writeByte('\n');
            },
            .Enum => try write(writer, @tagName(value)),
            .Union => |info| {
                const Tag = @TagType(T);
                inline for (info.fields) |field| {
                    if (@field(Tag, field.name) == value) {
                        try writer.writeAll("." ++ field.name);
                        try write(writer, @field(value, field.name));
                        return;
                    }
                }
                unreachable;
            },
            else => @compileError("'" ++ @typeName(T) ++ "' is not supported"),
        },
    }
}

pub fn Array(comptime _Index: type, comptime _Value: type) type {
    return struct {
        pub const Index = _Index;
        pub const Value = _Value;

        index: Index,
        value: Value,
    };
}

pub fn isArray(comptime T: type) bool {
    if (@typeInfo(T) != .Struct)
        return false;
    if (!@hasDecl(T, "Index") or !@hasDecl(T, "Value"))
        return false;
    if (@TypeOf(T.Index) != type or @TypeOf(T.Value) != type)
        return false;
    return T == Array(T.Index, T.Value);
}

test "parse" {
    const allocator = testing.failing_allocator;
    const p1 = comptime parser(u8, "", false);
    mecha.expectResult(u8, .{ .value = 0, .rest = "" }, p1(allocator, "=0"));
    mecha.expectResult(u8, .{ .value = 1, .rest = "" }, p1(allocator, "=1"));
    mecha.expectResult(u8, .{ .value = 111, .rest = "" }, p1(allocator, "=111"));

    const p2 = comptime parser(u32, "", false);
    mecha.expectResult(u32, .{ .value = 0, .rest = "" }, p2(allocator, "=0"));
    mecha.expectResult(u32, .{ .value = 1, .rest = "" }, p2(allocator, "=1"));
    mecha.expectResult(u32, .{ .value = 101010, .rest = "" }, p2(allocator, "=101010"));

    const U1 = union(enum) {
        a: u8,
        b: u16,
        c: u32,
    };
    const p3 = comptime parser(U1, "", false);
    mecha.expectResult(U1, .{ .value = .{ .a = 0 }, .rest = "" }, p3(allocator, ".a=0"));
    mecha.expectResult(U1, .{ .value = .{ .b = 1 }, .rest = "" }, p3(allocator, ".b=1"));
    mecha.expectResult(U1, .{ .value = .{ .c = 101010 }, .rest = "" }, p3(allocator, ".c=101010"));

    const A1 = Array(u8, u8);
    const p4 = comptime parser(A1, "", false);
    mecha.expectResult(A1, .{ .value = .{ .index = 0, .value = 0 }, .rest = "" }, p4(allocator, "[0]=0"));
    mecha.expectResult(A1, .{ .value = .{ .index = 1, .value = 2 }, .rest = "" }, p4(allocator, "[1]=2"));
    mecha.expectResult(A1, .{ .value = .{ .index = 22, .value = 33 }, .rest = "" }, p4(allocator, "[22]=33"));

    const U2 = union(enum) {
        a: Array(u32, union(enum) {
            a: u8,
            b: u32,
        }),
        b: u16,
    };
    const p5 = comptime parser(U2, "", false);
    mecha.expectResult(U2, .{ .value = .{ .a = .{ .index = 0, .value = .{ .a = 0 } } }, .rest = "" }, p5(allocator, ".a[0].a=0"));
    mecha.expectResult(U2, .{ .value = .{ .a = .{ .index = 3, .value = .{ .b = 44 } } }, .rest = "" }, p5(allocator, ".a[3].b=44"));
    mecha.expectResult(U2, .{ .value = .{ .b = 1 }, .rest = "" }, p5(allocator, ".b=1"));
}

/// Takes a struct pointer and a union and sets the structs field with
/// the same name as the unions active tag to that tags value.
/// All union field names must exist in the struct, and these union
/// field types must be able to coirse to the struct fields type.
pub fn setField(struct_ptr: anytype, union_val: anytype) void {
    const Struct = @TypeOf(struct_ptr.*);
    const Union = @TypeOf(union_val);

    inline for (@typeInfo(Union).Union.fields) |field| {
        if (union_val == @field(@TagType(Union), field.name)) {
            @field(struct_ptr, field.name) = @field(union_val, field.name);
            return;
        }
    }
}

fn getUnionValue(
    val: anytype,
) @TypeOf(&@field(val, @typeInfo(@TypeOf(val)).Union.fields[0].name)) {
    const T = @TypeOf(val);
    inline for (@typeInfo(T).Union.fields) |field| {
        if (val == @field(@TagType(T), field.name)) {
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
    starters: Array(u8, u16),
    text_delays: Array(u8, u8),
    trainers: Array(u16, Trainer),
    moves: Array(u16, Move),
    pokemons: Array(u16, Pokemon),
    abilities: Array(u16, Ability),
    types: Array(u8, Type),
    tms: Array(u8, u16),
    hms: Array(u8, u16),
    items: Array(u16, Item),
    pokedex: Array(u16, Pokedex),
    maps: Array(u16, Map),
    wild_pokemons: Array(u16, WildPokemons),
    static_pokemons: Array(u16, StaticPokemon),
    given_pokemons: Array(u16, GivenPokemon),
    pokeball_items: Array(u16, PokeballItem),
    hidden_hollows: Array(u16, HiddenHollow),
    text: Array(u16, []const u8),

    pub fn starter(index: u8, value: u16) Game {
        return .{ .starters = .{ .index = index, .value = value } };
    }

    pub fn text_delay(index: u8, value: u8) Game {
        return .{ .text_delays = .{ .index = index, .value = value } };
    }

    pub fn trainer(index: u16, value: Trainer) Game {
        return .{ .trainers = .{ .index = index, .value = value } };
    }

    pub fn move(index: u16, value: Move) Game {
        return .{ .moves = .{ .index = index, .value = value } };
    }

    pub fn pokemon(index: u16, value: Pokemon) Game {
        return .{ .pokemons = .{ .index = index, .value = value } };
    }

    pub fn ability(index: u16, value: Ability) Game {
        return .{ .abilities = .{ .index = index, .value = value } };
    }

    pub fn typ(index: u8, value: Type) Game {
        return .{ .types = .{ .index = index, .value = value } };
    }

    pub fn tm(index: u8, value: u16) Game {
        return .{ .tms = .{ .index = index, .value = value } };
    }

    pub fn hm(index: u8, value: u16) Game {
        return .{ .hms = .{ .index = index, .value = value } };
    }

    pub fn item(index: u16, value: Item) Game {
        return .{ .items = .{ .index = index, .value = value } };
    }

    pub fn pokede(index: u16, value: Pokedex) Game {
        return .{ .pokedes = .{ .index = index, .value = value } };
    }

    pub fn map(index: u16, value: Map) Game {
        return .{ .maps = .{ .index = index, .value = value } };
    }

    pub fn wild_pokemon(index: u16, value: WildPokemons) Game {
        return .{ .wild_pokemons = .{ .index = index, .value = value } };
    }

    pub fn static_pokemon(index: u16, value: StaticPokemon) Game {
        return .{ .static_pokemons = .{ .index = index, .value = value } };
    }

    pub fn given_pokemon(index: u16, value: GivenPokemon) Game {
        return .{ .given_pokemons = .{ .index = index, .value = value } };
    }

    pub fn pokeball_item(index: u16, value: PokeballItem) Game {
        return .{ .pokeball_items = .{ .index = index, .value = value } };
    }

    pub fn hidden_hollow(index: u16, value: HiddenHollow) Game {
        return .{ .hidden_hollows = .{ .index = index, .value = value } };
    }
};

pub const Trainer = union(enum) {
    class: u8,
    encounter_music: u8,
    trainer_picture: u8,
    name: []const u8,
    items: Array(u8, u16),
    party_type: PartyType,
    party_size: u8,
    party: Array(u8, PartyMember),

    pub fn partyMember(i: u8, member: PartyMember) Trainer {
        return .{ .party = .{ .index = i, .value = member } };
    }
};

pub const PartyMember = union(enum) {
    ability: u4,
    level: u8,
    species: u16,
    item: u16,
    moves: Array(u8, u16),
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
    base_exp_yield: u8,
    base_friendship: u8,
    catch_rate: u8,
    egg_cycles: u8,
    gender_ratio: u8,
    pokedex_entry: u16,
    growth_rate: GrowthRate,
    color: Color,
    abilities: Array(u8, u8),
    egg_groups: Array(u8, EggGroup),
    evos: Array(u8, Evolution),
    hms: Array(u8, bool),
    items: Array(u8, u16),
    moves: Array(u8, LevelUpMove),
    tms: Array(u8, bool),
    types: Array(u8, u8),

    pub fn evo(i: u8, evolution: Evolution) Pokemon {
        return .{ .evos = .{ .index = i, .value = evolution } };
    }
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

    pub fn init(tag: @TagType(WildPokemons), area: WildArea) WildPokemons {
        const Tag = @TagType(WildPokemons);
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
    pokemons: Array(u8, WildPokemon),
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
    versions: Array(u8, union(enum) {
        groups: Array(u8, union(enum) {
            pokemons: Array(u8, union(enum) {
                species: u16,
            })
        }),
    }),
    items: Array(u8, u16),

    pub fn pokemon(vi: u8, gi: u8, pi: u8, species: u16) HiddenHollow {
        return .{
            .versions = .{
                .index = vi,
                .value = .{
                    .groups = .{
                        .index = gi,
                        .value = .{
                            .pokemons = .{
                                .index = pi,
                                .value = .{ .species = species },
                            },
                        },
                    },
                },
            },
        };
    }
};
