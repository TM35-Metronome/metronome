const common = @import("common.zig");
const std = @import("std");
const util = @import("util");

const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const testing = std.testing;

pub usingnamespace @import("mecha");

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

fn toUnionField(
    comptime T: type,
    comptime field_type: type,
    comptime field_name: []const u8,
) fn (field_type) T {
    return struct {
        fn conv(c: field_type) T {
            return @unionInit(T, field_name, c);
        }
    }.conv;
}

pub fn parse(arena: *mem.Allocator, str: []const u8) !Game {
    const res = (comptime parser(Game))(arena, str) catch |err| switch (err) {
        error.OtherError => unreachable,
        error.OutOfMemory => return error.OutOfMemory,
        error.ParserFailed => return error.ParserFailed,
    };
    return res.value;
}

pub fn parser(comptime T: type) Parser(T) {
    @setEvalBranchQuota(100000000);
    const Res = Result(T);
    if (isArray(T)) {
        return map(T, toStruct(T), combine(.{
            ascii.char('['),
            int(T.Index, 10),
            ascii.char(']'),
            parser(T.Value),
        }));
    } else switch (T) {
        []const u8 => {
            // With no '\\' we can assume that string does not need to be unescaped, so we
            // can avoid doing an allocation.
            const text = combine(.{ many(ascii.not(ascii.char('\\')), .{ .collect = false }), eos });
            const escaped_text = convert([]const u8, struct {
                fn conv(allocator: *mem.Allocator, str: []const u8) Error![]const u8 {
                    return try util.escape.default.unescapeAlloc(allocator, str);
                }
            }.conv, rest);

            return combine(.{
                ascii.char('='),
                oneOf(.{ text, escaped_text }),
            });
        },
        else => switch (@typeInfo(T)) {
            .Int => return combine(.{ ascii.char('='), int(T, 10), eos }),
            .Enum => return combine(.{ ascii.char('='), enumeration(T), eos }),
            .Bool => return convert(bool, toBool, combine(.{ ascii.char('='), rest })),
            .Union => |info| return struct {
                fn p(allocator: *mem.Allocator, str: []const u8) Error!Result(T) {
                    // Ensure that fields are sorted, so that the largest field name
                    // is matched on first.
                    const fields = comptime blk: {
                        const Field = struct {
                            name: []const u8,
                            index: usize,
                        };

                        var res: [info.fields.len]Field = undefined;
                        for (info.fields) |f, i|
                            res[i] = .{ .name = f.name, .index = i };

                        std.sort.sort(Field, &res, {}, struct {
                            fn len(_: void, a: Field, b: Field) bool {
                                return a.name.len > b.name.len;
                            }
                        }.len);
                        break :blk res;
                    };

                    inline for (fields) |f, i| {
                        if (mem.startsWith(u8, str, "." ++ f.name)) {
                            const after_field = str[f.name.len + 1 ..];
                            const FieldT = info.fields[f.index].field_type;
                            const to_union = comptime toUnionField(T, FieldT, f.name);
                            const field_parser = comptime map(T, to_union, parser(FieldT));
                            return field_parser(allocator, after_field);
                        }
                    }

                    return error.ParserFailed;
                }
            }.p,
            else => @compileError("'" ++ @typeName(T) ++ "' is not supported"),
        },
    }
}

pub fn write(writer: anytype, value: anytype) !void {
    const T = @TypeOf(value);
    if (comptime isArray(T)) {
        try writer.print("[{}]", .{value.index});
        try write(writer, value.value);
    } else switch (T) {
        []const u8 => {
            try writer.writeAll("=");
            try util.escape.default.escapeWrite(writer, value);
            try writer.writeAll("\n");
        },
        else => switch (@typeInfo(T)) {
            .Bool, .Int => try writer.print("={}\n", .{value}),
            .Enum => try write(writer, @tagName(value)),
            .Union => |info| {
                const Tag = @TagType(T);
                inline for (info.fields) |field| {
                    if (@field(Tag, field.name) == value) {
                        try writer.print(".{s}", .{field.name});
                        try write(writer, @field(value, field.name));
                    }
                }
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
    const p1 = comptime parser(u8);
    expectResult(u8, .{ .value = 0, .rest = "" }, p1(allocator, "=0"));
    expectResult(u8, .{ .value = 1, .rest = "" }, p1(allocator, "=1"));
    expectResult(u8, .{ .value = 111, .rest = "" }, p1(allocator, "=111"));

    const p2 = comptime parser(u32);
    expectResult(u32, .{ .value = 0, .rest = "" }, p2(allocator, "=0"));
    expectResult(u32, .{ .value = 1, .rest = "" }, p2(allocator, "=1"));
    expectResult(u32, .{ .value = 101010, .rest = "" }, p2(allocator, "=101010"));

    const U1 = union(enum) {
        a: u8,
        b: u16,
        c: u32,
    };
    const p3 = comptime parser(U1);
    expectResult(U1, .{ .value = .{ .a = 0 }, .rest = "" }, p3(allocator, ".a=0"));
    expectResult(U1, .{ .value = .{ .b = 1 }, .rest = "" }, p3(allocator, ".b=1"));
    expectResult(U1, .{ .value = .{ .c = 101010 }, .rest = "" }, p3(allocator, ".c=101010"));

    const A1 = Array(u8, u8);
    const p4 = comptime parser(A1);
    expectResult(A1, .{ .value = .{ .index = 0, .value = 0 }, .rest = "" }, p4(allocator, "[0]=0"));
    expectResult(A1, .{ .value = .{ .index = 1, .value = 2 }, .rest = "" }, p4(allocator, "[1]=2"));
    expectResult(A1, .{ .value = .{ .index = 22, .value = 33 }, .rest = "" }, p4(allocator, "[22]=33"));

    const U2 = union(enum) {
        a: Array(u32, union(enum) {
            a: u8,
            b: u32,
        }),
        b: u16,
    };
    const p5 = comptime parser(U2);
    expectResult(U2, .{ .value = .{ .a = .{ .index = 0, .value = .{ .a = 0 } } }, .rest = "" }, p5(allocator, ".a[0].a=0"));
    expectResult(U2, .{ .value = .{ .a = .{ .index = 3, .value = .{ .b = 44 } } }, .rest = "" }, p5(allocator, ".a[3].b=44"));
    expectResult(U2, .{ .value = .{ .b = 1 }, .rest = "" }, p5(allocator, ".b=1"));
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
    };
}

pub const Pokemon = union(enum) {
    stats: Stats(u8),
    types: Array(u8, u8),
    catch_rate: u8,
    base_exp_yield: u8,
    ev_yield: Stats(u2),
    items: Array(u8, u16),
    gender_ratio: u8,
    egg_cycles: u8,
    base_friendship: u8,
    growth_rate: GrowthRate,
    egg_groups: Array(u8, EggGroup),
    abilities: Array(u8, u8),
    color: Color,
    evos: Array(u8, Evolution),
    moves: Array(u8, LevelUpMove),
    tms: Array(u8, bool),
    hms: Array(u8, bool),
    name: []const u8,
    pokedex_entry: u16,
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
};
