const std = @import("std");

const common = @import("common.zig");
const rom = @import("rom.zig");

pub const offsets = @import("gen5/offsets.zig");
pub const script = @import("gen5/script.zig");

const mem = std.mem;

const nds = rom.nds;

const Narc = nds.fs.Narc;
const Nitro = nds.fs.Nitro;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu128 = rom.int.lu128;

pub const BasePokemon = extern struct {
    stats: common.Stats,
    types: [2]Type,

    catch_rate: u8,

    evs: [3]u8, // TODO: Figure out if common.EvYield fits in these 3 bytes
    items: [3]lu16,

    gender_ratio: u8,
    egg_cycles: u8,
    base_friendship: u8,

    growth_rate: common.GrowthRate,

    egg_group1: common.EggGroup,
    egg_group2: common.EggGroup,

    abilities: [3]u8,

    // TODO: The three fields below are kinda unknown
    flee_rate: u8,
    form_stats_start: [2]u8,
    form_sprites_start: [2]u8,

    form_count: u8,

    color: common.Color,

    base_exp_yield: u8,

    height: lu16,
    weight: lu16,

    // Memory layout
    // TMS 01-92, HMS 01-06, TMS 93-95
    machine_learnset: lu128,

    // TODO: Tutor data only exists in BW2
    //special_tutors: lu32,
    //driftveil_tutor: lu32,
    //lentimas_tutor: lu32,
    //humilau_tutor: lu32,
    //nacrene_tutor: lu32,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 55);
    }
};

pub const PartyType = packed enum(u8) {
    none = 0b00,
    item = 0b10,
    moves = 0b01,
    both = 0b11,
};

pub const PartyMemberBase = extern struct {
    iv: u8,
    gender_ability: GenderAbilityPair,
    level: u8,
    padding: u8,
    species: lu16,
    form: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }

    const GenderAbilityPair = packed struct {
        gender: u4,
        ability: u4,
    };

    pub fn toParent(base: *PartyMemberBase, comptime Parent: type) *Parent {
        return @fieldParentPtr(Parent, "base", base);
    }
};

pub const PartyMemberNone = extern struct {
    base: PartyMemberBase,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const PartyMemberItem = extern struct {
    base: PartyMemberBase,
    item: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 10);
    }
};

pub const PartyMemberMoves = extern struct {
    base: PartyMemberBase,
    moves: [4]lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const PartyMemberBoth = extern struct {
    base: PartyMemberBase,
    item: lu16,
    moves: [4]lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 18);
    }
};

pub const Trainer = extern struct {
    party_type: PartyType,
    class: u8,
    battle_type: u8, // TODO: This should probably be an enum
    party_size: u8,
    items: [4]lu16,
    ai: lu32,
    healer: bool,
    cash: u8,
    post_battle_item: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 20);
    }

    pub fn partyMember(trainer: Trainer, party: []u8, i: usize) ?*PartyMemberBase {
        return switch (trainer.party_type) {
            .none => trainer.partyMemberHelper(party, @sizeOf(PartyMemberNone), i),
            .item => trainer.partyMemberHelper(party, @sizeOf(PartyMemberItem), i),
            .moves => trainer.partyMemberHelper(party, @sizeOf(PartyMemberMoves), i),
            .both => trainer.partyMemberHelper(party, @sizeOf(PartyMemberBoth), i),
        };
    }

    fn partyMemberHelper(trainer: Trainer, party: []u8, member_size: usize, i: usize) ?*PartyMemberBase {
        const start = i * member_size;
        const end = start + member_size;
        if (party.len < end)
            return null;

        return &mem.bytesAsSlice(PartyMemberBase, party[start..][0..@sizeOf(PartyMemberBase)])[0];
    }
};

pub const Move = extern struct {
    type: Type,
    effect_category: u8,
    category: common.MoveCategory,
    power: u8,
    accuracy: u8,
    pp: u8,
    priority: u8,
    min_max_hits: MinMaxPair,
    result_effect: lu16,
    effect_chance: u8,
    status: u8,
    min_turns: u8,
    max_turns: u8,
    crit: u8,
    flinch: u8,
    effect: lu16,
    target_hp: u8,
    user_hp: u8,
    target: u8,
    stats_affected: [3]u8,
    stats_affected_magnetude: [3]u8,
    stats_affected_chance: [3]u8,

    // TODO: Figure out if this is actually how the last fields are layed out.
    padding: [2]u8,
    flags: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 34);
    }

    const MinMaxPair = packed struct {
        min: u4,
        max: u4,
    };
};

pub const LevelUpMove = extern struct {
    id: lu16,
    level: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 4);
    }
};

pub const Type = packed enum(u8) {
    normal = 0x00,
    fighting = 0x01,
    flying = 0x02,
    poison = 0x03,
    ground = 0x04,
    rock = 0x05,
    bug = 0x06,
    ghost = 0x07,
    steel = 0x08,
    fire = 0x09,
    water = 0x0A,
    grass = 0x0B,
    electric = 0x0C,
    psychic = 0x0D,
    ice = 0x0E,
    dragon = 0x0F,
    dark = 0x10,

    // HACK: This is a workaround for invalid types in games.
    unknown_0x11 = 0x11,
    unknown_0x12 = 0x12,
    unknown_0x13 = 0x13,
    unknown_0x14 = 0x14,
    unknown_0x15 = 0x15,
    unknown_0x16 = 0x16,
    unknown_0x17 = 0x17,
    unknown_0x18 = 0x18,
    unknown_0x19 = 0x19,
    unknown_0x1a = 0x1a,
    unknown_0x1b = 0x1b,
    unknown_0x1c = 0x1c,
    unknown_0x1d = 0x1d,
    unknown_0x1e = 0x1e,
    unknown_0x1f = 0x1f,
    unknown_0x20 = 0x20,
    unknown_0x21 = 0x21,
    unknown_0x22 = 0x22,
    unknown_0x23 = 0x23,
    unknown_0x24 = 0x24,
    unknown_0x25 = 0x25,
    unknown_0x26 = 0x26,
    unknown_0x27 = 0x27,
    unknown_0x28 = 0x28,
    unknown_0x29 = 0x29,
    unknown_0x2a = 0x2a,
    unknown_0x2b = 0x2b,
    unknown_0x2c = 0x2c,
    unknown_0x2d = 0x2d,
    unknown_0x2e = 0x2e,
    unknown_0x2f = 0x2f,
    unknown_0x30 = 0x30,
    unknown_0x31 = 0x31,
    unknown_0x32 = 0x32,
    unknown_0x33 = 0x33,
    unknown_0x34 = 0x34,
    unknown_0x35 = 0x35,
    unknown_0x36 = 0x36,
    unknown_0x37 = 0x37,
    unknown_0x38 = 0x38,
    unknown_0x39 = 0x39,
    unknown_0x3a = 0x3a,
    unknown_0x3b = 0x3b,
    unknown_0x3c = 0x3c,
    unknown_0x3d = 0x3d,
    unknown_0x3e = 0x3e,
    unknown_0x3f = 0x3f,
    unknown_0x40 = 0x40,
    unknown_0x41 = 0x41,
    unknown_0x42 = 0x42,
    unknown_0x43 = 0x43,
    unknown_0x44 = 0x44,
    unknown_0x45 = 0x45,
    unknown_0x46 = 0x46,
    unknown_0x47 = 0x47,
    unknown_0x48 = 0x48,
    unknown_0x49 = 0x49,
    unknown_0x4a = 0x4a,
    unknown_0x4b = 0x4b,
    unknown_0x4c = 0x4c,
    unknown_0x4d = 0x4d,
    unknown_0x4e = 0x4e,
    unknown_0x4f = 0x4f,
    unknown_0x50 = 0x50,
    unknown_0x51 = 0x51,
    unknown_0x52 = 0x52,
    unknown_0x53 = 0x53,
    unknown_0x54 = 0x54,
    unknown_0x55 = 0x55,
    unknown_0x56 = 0x56,
    unknown_0x57 = 0x57,
    unknown_0x58 = 0x58,
    unknown_0x59 = 0x59,
    unknown_0x5a = 0x5a,
    unknown_0x5b = 0x5b,
    unknown_0x5c = 0x5c,
    unknown_0x5d = 0x5d,
    unknown_0x5e = 0x5e,
    unknown_0x5f = 0x5f,
    unknown_0x60 = 0x60,
    unknown_0x61 = 0x61,
    unknown_0x62 = 0x62,
    unknown_0x63 = 0x63,
    unknown_0x64 = 0x64,
    unknown_0x65 = 0x65,
    unknown_0x66 = 0x66,
    unknown_0x67 = 0x67,
    unknown_0x68 = 0x68,
    unknown_0x69 = 0x69,
    unknown_0x6a = 0x6a,
    unknown_0x6b = 0x6b,
    unknown_0x6c = 0x6c,
    unknown_0x6d = 0x6d,
    unknown_0x6e = 0x6e,
    unknown_0x6f = 0x6f,
    unknown_0x70 = 0x70,
    unknown_0x71 = 0x71,
    unknown_0x72 = 0x72,
    unknown_0x73 = 0x73,
    unknown_0x74 = 0x74,
    unknown_0x75 = 0x75,
    unknown_0x76 = 0x76,
    unknown_0x77 = 0x77,
    unknown_0x78 = 0x78,
    unknown_0x79 = 0x79,
    unknown_0x7a = 0x7a,
    unknown_0x7b = 0x7b,
    unknown_0x7c = 0x7c,
    unknown_0x7d = 0x7d,
    unknown_0x7e = 0x7e,
    unknown_0x7f = 0x7f,
    unknown_0x80 = 0x80,
    unknown_0x81 = 0x81,
    unknown_0x82 = 0x82,
    unknown_0x83 = 0x83,
    unknown_0x84 = 0x84,
    unknown_0x85 = 0x85,
    unknown_0x86 = 0x86,
    unknown_0x87 = 0x87,
    unknown_0x88 = 0x88,
    unknown_0x89 = 0x89,
    unknown_0x8a = 0x8a,
    unknown_0x8b = 0x8b,
    unknown_0x8c = 0x8c,
    unknown_0x8d = 0x8d,
    unknown_0x8e = 0x8e,
    unknown_0x8f = 0x8f,
    unknown_0x90 = 0x90,
    unknown_0x91 = 0x91,
    unknown_0x92 = 0x92,
    unknown_0x93 = 0x93,
    unknown_0x94 = 0x94,
    unknown_0x95 = 0x95,
    unknown_0x96 = 0x96,
    unknown_0x97 = 0x97,
    unknown_0x98 = 0x98,
    unknown_0x99 = 0x99,
    unknown_0x9a = 0x9a,
    unknown_0x9b = 0x9b,
    unknown_0x9c = 0x9c,
    unknown_0x9d = 0x9d,
    unknown_0x9e = 0x9e,
    unknown_0x9f = 0x9f,
    unknown_0xa0 = 0xa0,
    unknown_0xa1 = 0xa1,
    unknown_0xa2 = 0xa2,
    unknown_0xa3 = 0xa3,
    unknown_0xa4 = 0xa4,
    unknown_0xa5 = 0xa5,
    unknown_0xa6 = 0xa6,
    unknown_0xa7 = 0xa7,
    unknown_0xa8 = 0xa8,
    unknown_0xa9 = 0xa9,
    unknown_0xaa = 0xaa,
    unknown_0xab = 0xab,
    unknown_0xac = 0xac,
    unknown_0xad = 0xad,
    unknown_0xae = 0xae,
    unknown_0xaf = 0xaf,
    unknown_0xb0 = 0xb0,
    unknown_0xb1 = 0xb1,
    unknown_0xb2 = 0xb2,
    unknown_0xb3 = 0xb3,
    unknown_0xb4 = 0xb4,
    unknown_0xb5 = 0xb5,
    unknown_0xb6 = 0xb6,
    unknown_0xb7 = 0xb7,
    unknown_0xb8 = 0xb8,
    unknown_0xb9 = 0xb9,
    unknown_0xba = 0xba,
    unknown_0xbb = 0xbb,
    unknown_0xbc = 0xbc,
    unknown_0xbd = 0xbd,
    unknown_0xbe = 0xbe,
    unknown_0xbf = 0xbf,
    unknown_0xc0 = 0xc0,
    unknown_0xc1 = 0xc1,
    unknown_0xc2 = 0xc2,
    unknown_0xc3 = 0xc3,
    unknown_0xc4 = 0xc4,
    unknown_0xc5 = 0xc5,
    unknown_0xc6 = 0xc6,
    unknown_0xc7 = 0xc7,
    unknown_0xc8 = 0xc8,
    unknown_0xc9 = 0xc9,
    unknown_0xca = 0xca,
    unknown_0xcb = 0xcb,
    unknown_0xcc = 0xcc,
    unknown_0xcd = 0xcd,
    unknown_0xce = 0xce,
    unknown_0xcf = 0xcf,
    unknown_0xd0 = 0xd0,
    unknown_0xd1 = 0xd1,
    unknown_0xd2 = 0xd2,
    unknown_0xd3 = 0xd3,
    unknown_0xd4 = 0xd4,
    unknown_0xd5 = 0xd5,
    unknown_0xd6 = 0xd6,
    unknown_0xd7 = 0xd7,
    unknown_0xd8 = 0xd8,
    unknown_0xd9 = 0xd9,
    unknown_0xda = 0xda,
    unknown_0xdb = 0xdb,
    unknown_0xdc = 0xdc,
    unknown_0xdd = 0xdd,
    unknown_0xde = 0xde,
    unknown_0xdf = 0xdf,
    unknown_0xe0 = 0xe0,
    unknown_0xe1 = 0xe1,
    unknown_0xe2 = 0xe2,
    unknown_0xe3 = 0xe3,
    unknown_0xe4 = 0xe4,
    unknown_0xe5 = 0xe5,
    unknown_0xe6 = 0xe6,
    unknown_0xe7 = 0xe7,
    unknown_0xe8 = 0xe8,
    unknown_0xe9 = 0xe9,
    unknown_0xea = 0xea,
    unknown_0xeb = 0xeb,
    unknown_0xec = 0xec,
    unknown_0xed = 0xed,
    unknown_0xee = 0xee,
    unknown_0xef = 0xef,
    unknown_0xf0 = 0xf0,
    unknown_0xf1 = 0xf1,
    unknown_0xf2 = 0xf2,
    unknown_0xf3 = 0xf3,
    unknown_0xf4 = 0xf4,
    unknown_0xf5 = 0xf5,
    unknown_0xf6 = 0xf6,
    unknown_0xf7 = 0xf7,
    unknown_0xf8 = 0xf8,
    unknown_0xf9 = 0xf9,
    unknown_0xfa = 0xfa,
    unknown_0xfb = 0xfb,
    unknown_0xfc = 0xfc,
    unknown_0xfd = 0xfd,
    unknown_0xfe = 0xfe,
    unknown_0xff = 0xff,
};

// TODO: Verify layout
pub const Evolution = extern struct {
    method: Method,
    padding: u8,
    param: lu16,
    target: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
    }

    pub const Method = packed enum(u8) {
        unused = 0x00,
        friend_ship = 0x01,
        unknown_0x02 = 0x02,
        unknown_0x03 = 0x03,
        level_up = 0x04,
        trade = 0x05,
        trade_holding_item = 0x06,
        trade_with_pokemon = 0x07,
        use_item = 0x08,
        attack_gth_defense = 0x09,
        attack_eql_defense = 0x0A,
        attack_lth_defense = 0x0B,
        personality_value1 = 0x0C,
        personality_value2 = 0x0D,
        level_up_may_spawn_pokemon = 0x0E,
        level_up_spawn_if_cond = 0x0F,
        beauty = 0x10,
        use_item_on_male = 0x11,
        use_item_on_female = 0x12,
        level_up_holding_item_during_daytime = 0x13,
        level_up_holding_item_during_the_night = 0x14,
        level_up_knowning_move = 0x15,
        level_up_with_other_pokemon_in_party = 0x16,
        level_up_male = 0x17,
        level_up_female = 0x18,
        level_up_in_special_magnetic_field = 0x19,
        level_up_near_moss_rock = 0x1A,
        level_up_near_ice_rock = 0x1B,
        unknown_0x1c = 0x1c,
        unknown_0x1d = 0x1d,
        unknown_0x1e = 0x1e,
        unknown_0x1f = 0x1f,
        unknown_0x20 = 0x20,
        unknown_0x21 = 0x21,
        unknown_0x22 = 0x22,
        unknown_0x23 = 0x23,
        unknown_0x24 = 0x24,
        unknown_0x25 = 0x25,
        unknown_0x26 = 0x26,
        unknown_0x27 = 0x27,
        unknown_0x28 = 0x28,
        unknown_0x29 = 0x29,
        unknown_0x2a = 0x2a,
        unknown_0x2b = 0x2b,
        unknown_0x2c = 0x2c,
        unknown_0x2d = 0x2d,
        unknown_0x2e = 0x2e,
        unknown_0x2f = 0x2f,
        unknown_0x30 = 0x30,
        unknown_0x31 = 0x31,
        unknown_0x32 = 0x32,
        unknown_0x33 = 0x33,
        unknown_0x34 = 0x34,
        unknown_0x35 = 0x35,
        unknown_0x36 = 0x36,
        unknown_0x37 = 0x37,
        unknown_0x38 = 0x38,
        unknown_0x39 = 0x39,
        unknown_0x3a = 0x3a,
        unknown_0x3b = 0x3b,
        unknown_0x3c = 0x3c,
        unknown_0x3d = 0x3d,
        unknown_0x3e = 0x3e,
        unknown_0x3f = 0x3f,
        unknown_0x40 = 0x40,
        unknown_0x41 = 0x41,
        unknown_0x42 = 0x42,
        unknown_0x43 = 0x43,
        unknown_0x44 = 0x44,
        unknown_0x45 = 0x45,
        unknown_0x46 = 0x46,
        unknown_0x47 = 0x47,
        unknown_0x48 = 0x48,
        unknown_0x49 = 0x49,
        unknown_0x4a = 0x4a,
        unknown_0x4b = 0x4b,
        unknown_0x4c = 0x4c,
        unknown_0x4d = 0x4d,
        unknown_0x4e = 0x4e,
        unknown_0x4f = 0x4f,
        unknown_0x50 = 0x50,
        unknown_0x51 = 0x51,
        unknown_0x52 = 0x52,
        unknown_0x53 = 0x53,
        unknown_0x54 = 0x54,
        unknown_0x55 = 0x55,
        unknown_0x56 = 0x56,
        unknown_0x57 = 0x57,
        unknown_0x58 = 0x58,
        unknown_0x59 = 0x59,
        unknown_0x5a = 0x5a,
        unknown_0x5b = 0x5b,
        unknown_0x5c = 0x5c,
        unknown_0x5d = 0x5d,
        unknown_0x5e = 0x5e,
        unknown_0x5f = 0x5f,
        unknown_0x60 = 0x60,
        unknown_0x61 = 0x61,
        unknown_0x62 = 0x62,
        unknown_0x63 = 0x63,
        unknown_0x64 = 0x64,
        unknown_0x65 = 0x65,
        unknown_0x66 = 0x66,
        unknown_0x67 = 0x67,
        unknown_0x68 = 0x68,
        unknown_0x69 = 0x69,
        unknown_0x6a = 0x6a,
        unknown_0x6b = 0x6b,
        unknown_0x6c = 0x6c,
        unknown_0x6d = 0x6d,
        unknown_0x6e = 0x6e,
        unknown_0x6f = 0x6f,
        unknown_0x70 = 0x70,
        unknown_0x71 = 0x71,
        unknown_0x72 = 0x72,
        unknown_0x73 = 0x73,
        unknown_0x74 = 0x74,
        unknown_0x75 = 0x75,
        unknown_0x76 = 0x76,
        unknown_0x77 = 0x77,
        unknown_0x78 = 0x78,
        unknown_0x79 = 0x79,
        unknown_0x7a = 0x7a,
        unknown_0x7b = 0x7b,
        unknown_0x7c = 0x7c,
        unknown_0x7d = 0x7d,
        unknown_0x7e = 0x7e,
        unknown_0x7f = 0x7f,
        unknown_0x80 = 0x80,
        unknown_0x81 = 0x81,
        unknown_0x82 = 0x82,
        unknown_0x83 = 0x83,
        unknown_0x84 = 0x84,
        unknown_0x85 = 0x85,
        unknown_0x86 = 0x86,
        unknown_0x87 = 0x87,
        unknown_0x88 = 0x88,
        unknown_0x89 = 0x89,
        unknown_0x8a = 0x8a,
        unknown_0x8b = 0x8b,
        unknown_0x8c = 0x8c,
        unknown_0x8d = 0x8d,
        unknown_0x8e = 0x8e,
        unknown_0x8f = 0x8f,
        unknown_0x90 = 0x90,
        unknown_0x91 = 0x91,
        unknown_0x92 = 0x92,
        unknown_0x93 = 0x93,
        unknown_0x94 = 0x94,
        unknown_0x95 = 0x95,
        unknown_0x96 = 0x96,
        unknown_0x97 = 0x97,
        unknown_0x98 = 0x98,
        unknown_0x99 = 0x99,
        unknown_0x9a = 0x9a,
        unknown_0x9b = 0x9b,
        unknown_0x9c = 0x9c,
        unknown_0x9d = 0x9d,
        unknown_0x9e = 0x9e,
        unknown_0x9f = 0x9f,
        unknown_0xa0 = 0xa0,
        unknown_0xa1 = 0xa1,
        unknown_0xa2 = 0xa2,
        unknown_0xa3 = 0xa3,
        unknown_0xa4 = 0xa4,
        unknown_0xa5 = 0xa5,
        unknown_0xa6 = 0xa6,
        unknown_0xa7 = 0xa7,
        unknown_0xa8 = 0xa8,
        unknown_0xa9 = 0xa9,
        unknown_0xaa = 0xaa,
        unknown_0xab = 0xab,
        unknown_0xac = 0xac,
        unknown_0xad = 0xad,
        unknown_0xae = 0xae,
        unknown_0xaf = 0xaf,
        unknown_0xb0 = 0xb0,
        unknown_0xb1 = 0xb1,
        unknown_0xb2 = 0xb2,
        unknown_0xb3 = 0xb3,
        unknown_0xb4 = 0xb4,
        unknown_0xb5 = 0xb5,
        unknown_0xb6 = 0xb6,
        unknown_0xb7 = 0xb7,
        unknown_0xb8 = 0xb8,
        unknown_0xb9 = 0xb9,
        unknown_0xba = 0xba,
        unknown_0xbb = 0xbb,
        unknown_0xbc = 0xbc,
        unknown_0xbd = 0xbd,
        unknown_0xbe = 0xbe,
        unknown_0xbf = 0xbf,
        unknown_0xc0 = 0xc0,
        unknown_0xc1 = 0xc1,
        unknown_0xc2 = 0xc2,
        unknown_0xc3 = 0xc3,
        unknown_0xc4 = 0xc4,
        unknown_0xc5 = 0xc5,
        unknown_0xc6 = 0xc6,
        unknown_0xc7 = 0xc7,
        unknown_0xc8 = 0xc8,
        unknown_0xc9 = 0xc9,
        unknown_0xca = 0xca,
        unknown_0xcb = 0xcb,
        unknown_0xcc = 0xcc,
        unknown_0xcd = 0xcd,
        unknown_0xce = 0xce,
        unknown_0xcf = 0xcf,
        unknown_0xd0 = 0xd0,
        unknown_0xd1 = 0xd1,
        unknown_0xd2 = 0xd2,
        unknown_0xd3 = 0xd3,
        unknown_0xd4 = 0xd4,
        unknown_0xd5 = 0xd5,
        unknown_0xd6 = 0xd6,
        unknown_0xd7 = 0xd7,
        unknown_0xd8 = 0xd8,
        unknown_0xd9 = 0xd9,
        unknown_0xda = 0xda,
        unknown_0xdb = 0xdb,
        unknown_0xdc = 0xdc,
        unknown_0xdd = 0xdd,
        unknown_0xde = 0xde,
        unknown_0xdf = 0xdf,
        unknown_0xe0 = 0xe0,
        unknown_0xe1 = 0xe1,
        unknown_0xe2 = 0xe2,
        unknown_0xe3 = 0xe3,
        unknown_0xe4 = 0xe4,
        unknown_0xe5 = 0xe5,
        unknown_0xe6 = 0xe6,
        unknown_0xe7 = 0xe7,
        unknown_0xe8 = 0xe8,
        unknown_0xe9 = 0xe9,
        unknown_0xea = 0xea,
        unknown_0xeb = 0xeb,
        unknown_0xec = 0xec,
        unknown_0xed = 0xed,
        unknown_0xee = 0xee,
        unknown_0xef = 0xef,
        unknown_0xf0 = 0xf0,
        unknown_0xf1 = 0xf1,
        unknown_0xf2 = 0xf2,
        unknown_0xf3 = 0xf3,
        unknown_0xf4 = 0xf4,
        unknown_0xf5 = 0xf5,
        unknown_0xf6 = 0xf6,
        unknown_0xf7 = 0xf7,
        unknown_0xf8 = 0xf8,
        unknown_0xf9 = 0xf9,
        unknown_0xfa = 0xfa,
        unknown_0xfb = 0xfb,
        unknown_0xfc = 0xfc,
        unknown_0xfd = 0xfd,
        unknown_0xfe = 0xfe,
        unknown_0xff = 0xff,
    };
};

pub const Species = extern struct {
    value: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 2);
    }

    pub fn species(s: Species) u10 {
        return @truncate(u10, s.value.value());
    }

    pub fn setSpecies(s: *Species, spe: u10) void {
        s.value = lu16.init((@as(u16, s.form()) << @as(u4, 10)) | spe);
    }

    pub fn form(s: Species) u6 {
        return @truncate(u6, s.value.value() >> 10);
    }

    pub fn setForm(s: *Species, f: u10) void {
        s.value = lu16.init((@as(u16, f) << @as(u4, 10)) | s.species());
    }
};

pub const WildPokemon = extern struct {
    species: Species,
    min_level: u8,
    max_level: u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 4);
    }
};

pub const WildPokemons = extern struct {
    rates: [7]u8,
    pad: u8,
    grass: [12]WildPokemon,
    dark_grass: [12]WildPokemon,
    rustling_grass: [12]WildPokemon,
    surf: [5]WildPokemon,
    ripple_surf: [5]WildPokemon,
    fishing: [5]WildPokemon,
    ripple_fishing: [5]WildPokemon,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 232);
    }
};

pub const Pocket = packed struct {
    pocket: PocketKind,
    unknown: u4,
};

pub const PocketKind = packed enum(u4) {
    items = 0x00,
    tms_hms = 0x01,
    key_items = 0x02,
    unknown_0x03 = 0x03,
    unknown_0x04 = 0x04,
    unknown_0x05 = 0x05,
    unknown_0x06 = 0x06,
    unknown_0x07 = 0x07,
    balls = 0x08,
    unknown_0x9 = 0x9,
    unknown_0xa = 0xA,
    unknown_0xb = 0xB,
    unknown_0xc = 0xC,
    unknown_0xd = 0xD,
    unknown_0xe = 0xE,
    unknown_0xf = 0xF,
};

pub const Item = extern struct {
    price: lu16,
    battle_effect: u8,
    gain: u8,
    berry: u8,
    fling_effect: u8,
    fling_power: u8,
    natural_gift_power: u8,
    flag: u8,
    pocket: Pocket,
    type: u8,
    category: u8,
    category2: lu16,
    category3: u8,
    index: u8,
    anti_index: u8,
    statboosts: Boost,
    ev_yield: common.EvYield,
    hp_restore: u8,
    pp_restore: u8,
    happy: [3]u8,
    padding: [2]u8,

    pub const Boost = packed struct {
        hp: u2,
        level: u1,
        evolution: u1,
        attack: u4,
        defense: u4,
        sp_attack: u4,
        sp_defense: u4,
        speed: u4,
        accuracy: u4,
        crit: u2,
        pp: u2,
        target: u8,
        target2: u8,
    };
};

const PokeballItem = struct {
    item: *lu16,
    amount: *lu16,
};

pub const Game = struct {
    version: common.Version,
    allocator: *mem.Allocator,

    starters: [3][]*lu16,
    scripts: nds.fs.Fs,
    pokemons: nds.fs.Fs,
    evolutions: nds.fs.Fs,
    moves: nds.fs.Fs,
    level_up_moves: nds.fs.Fs,
    trainers: nds.fs.Fs,
    parties: nds.fs.Fs,
    wild_pokemons: nds.fs.Fs,
    itemdata: nds.fs.Fs,
    tms1: []lu16,
    hms: []lu16,
    tms2: []lu16,
    static_pokemons: []*script.Command,
    pokeball_items: []PokeballItem,

    pub fn fromRom(allocator: *mem.Allocator, nds_rom: nds.Rom) !Game {
        try nds_rom.decodeArm9();
        const header = nds_rom.header();
        const arm9 = nds_rom.arm9();
        const file_system = nds_rom.fileSystem();

        const info = try getOffsets(&header.gamecode);
        const hm_tm_prefix_index = mem.indexOf(u8, arm9, offsets.hm_tm_prefix) orelse return error.CouldNotFindTmsOrHms;
        const hm_tm_index = hm_tm_prefix_index + offsets.hm_tm_prefix.len;
        const hm_tm_len = (offsets.tm_count + offsets.hm_count) * @sizeOf(u16);
        const hm_tms = mem.bytesAsSlice(lu16, arm9[hm_tm_index..][0..hm_tm_len]);
        const scripts = try getNarc(file_system, info.scripts);

        const commands = try findScriptCommands(info.version, scripts, allocator);
        errdefer {
            allocator.free(commands.static_pokemons);
            allocator.free(commands.pokeball_items);
        }

        return Game{
            .version = info.version,
            .allocator = allocator,
            .starters = blk: {
                var res: [3][]*lu16 = undefined;
                var filled: usize = 0;
                errdefer for (res[0..filled]) |item|
                    allocator.free(item);

                for (info.starters) |offs, i| {
                    res[i] = try allocator.alloc(*lu16, offs.len);
                    filled += 1;

                    for (offs) |offset, j| {
                        const fat = scripts.fat[offset.file];
                        const file_data = scripts.data[fat.start.value()..fat.end.value()];
                        res[i][j] = mem.bytesAsValue(lu16, file_data[offset.offset..][0..2]);
                    }
                }

                break :blk res;
            },
            .scripts = scripts,
            .pokemons = try getNarc(file_system, info.pokemons),
            .evolutions = try getNarc(file_system, info.evolutions),
            .level_up_moves = try getNarc(file_system, info.level_up_moves),
            .moves = try getNarc(file_system, info.moves),
            .trainers = try getNarc(file_system, info.trainers),
            .parties = try getNarc(file_system, info.parties),
            .wild_pokemons = try getNarc(file_system, info.wild_pokemons),
            .itemdata = try getNarc(file_system, info.itemdata),
            .tms1 = hm_tms[0..92],
            .hms = hm_tms[92..98],
            .tms2 = hm_tms[98..],
            .static_pokemons = commands.static_pokemons,
            .pokeball_items = commands.pokeball_items,
        };
    }

    pub fn deinit(game: Game) void {
        for (game.starters) |starter_ptrs|
            game.allocator.free(starter_ptrs);
        game.allocator.free(game.static_pokemons);
        game.allocator.free(game.pokeball_items);
    }

    const ScriptCommands = struct {
        static_pokemons: []*script.Command,
        pokeball_items: []PokeballItem,
    };

    fn findScriptCommands(version: common.Version, scripts: nds.fs.Fs, allocator: *mem.Allocator) !ScriptCommands {
        if (version == .black or version == .white) {
            // We don't support decoding scripts for hg/ss yet.
            return ScriptCommands{
                .static_pokemons = &[_]*script.Command{},
                .pokeball_items = &[_]PokeballItem{},
            };
        }

        var static_pokemons = std.ArrayList(*script.Command).init(allocator);
        errdefer static_pokemons.deinit();
        var pokeball_items = std.ArrayList(PokeballItem).init(allocator);
        errdefer pokeball_items.deinit();

        var script_offsets = std.ArrayList(isize).init(allocator);
        defer script_offsets.deinit();

        for (scripts.fat) |fat, script_i| {
            const script_data = scripts.data[fat.start.value()..fat.end.value()];
            defer script_offsets.resize(0) catch unreachable;

            for (script.getScriptOffsets(script_data)) |relative_offset, i| {
                const offset = relative_offset.value() + @intCast(isize, i + 1) * @sizeOf(lu32);
                if (@intCast(isize, script_data.len) < offset)
                    continue;
                if (offset < 0)
                    continue;
                try script_offsets.append(offset);
            }

            // The variable 0x8008 is the variables that stores items given
            // from Pokéballs.
            var var_800C: ?*lu16 = null;

            var offset_i: usize = 0;
            while (offset_i < script_offsets.items.len) : (offset_i += 1) {
                const offset = script_offsets.items[offset_i];
                if (@intCast(isize, script_data.len) < offset)
                    return error.Error;
                if (offset < 0)
                    return error.Error;

                var decoder = script.CommandDecoder{
                    .bytes = script_data,
                    .i = @intCast(usize, offset),
                };
                while (decoder.next() catch continue) |command| {
                    // If we hit var 0x800C, the var_800C_tmp will be set and
                    // var_800C will become var_800C_tmp. Then the next iteration
                    // of this loop will set var_8008 to null again. This allows us
                    // to store this state for only the next iteration of the loop.
                    var var_800C_tmp: ?*lu16 = null;
                    defer var_800C = var_800C_tmp;

                    switch (command.tag) {
                        // TODO: We're not finding any given items yet
                        .wild_battle => try static_pokemons.append(command),

                        // In scripts, field items are two set_var_eq_val commands
                        // followed by a jump to the code that gives this item:
                        //   set_var_eq_val 0x800C // Item given
                        //   set_var_eq_val 0x800D // Amount of items
                        //   jump ???
                        .set_var_eq_val => switch (command.data().set_var_eq_val.container.value()) {
                            0x800C => var_800C_tmp = &command.data().set_var_eq_val.value,
                            0x800D => if (var_800C) |item| {
                                const amount = &command.data().set_var_eq_val.value;
                                try pokeball_items.append(PokeballItem{
                                    .item = item,
                                    .amount = amount,
                                });
                            },
                            else => {},
                        },
                        .jump => {
                            const off = command.data().jump.offset.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .@"if" => {
                            const off = command.data().@"if".offset.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        else => {},
                    }
                }
            }
        }

        return ScriptCommands{
            .static_pokemons = static_pokemons.toOwnedSlice(),
            .pokeball_items = pokeball_items.toOwnedSlice(),
        };
    }

    fn nodeAsFile(node: nds.fs.Narc.Node) !*nds.fs.Narc.File {
        switch (node.kind) {
            .file => |file| return file,
            .folder => return error.NotFile,
        }
    }

    fn getOffsets(gamecode: []const u8) !offsets.Info {
        for (offsets.infos) |info| {
            //if (!mem.eql(u8, info.game_title, game_title))
            //    continue;
            if (!mem.eql(u8, &info.gamecode, gamecode))
                continue;

            return info;
        }

        return error.NotGen5Game;
    }

    pub fn getNarc(file_system: nds.fs.Fs, path: []const []const u8) !nds.fs.Fs {
        const file = file_system.lookup(path) orelse return error.FileNotFound;
        return try nds.fs.Fs.fromNarc(file);
    }
};
