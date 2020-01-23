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
    None = 0b00,
    Item = 0b10,
    Moves = 0b01,
    Both = 0b11,
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
            .None => trainer.partyMemberHelper(party, @sizeOf(PartyMemberNone), i),
            .Item => trainer.partyMemberHelper(party, @sizeOf(PartyMemberItem), i),
            .Moves => trainer.partyMemberHelper(party, @sizeOf(PartyMemberMoves), i),
            .Both => trainer.partyMemberHelper(party, @sizeOf(PartyMemberBoth), i),
        };
    }

    fn partyMemberHelper(trainer: Trainer, party: []u8, member_size: usize, i: usize) ?*PartyMemberBase {
        const start = i * member_size;
        const end = start + member_size;
        if (party.len < end)
            return null;

        return &@bytesToSlice(PartyMemberBase, party[start..][0..@sizeOf(PartyMemberBase)])[0];
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
    move_id: lu16,
    level: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 4);
    }
};

pub const Type = packed enum(u8) {
    Normal = 0x00,
    Fighting = 0x01,
    Flying = 0x02,
    Poison = 0x03,
    Ground = 0x04,
    Rock = 0x05,
    Bug = 0x06,
    Ghost = 0x07,
    Steel = 0x08,
    Fire = 0x09,
    Water = 0x0A,
    Grass = 0x0B,
    Electric = 0x0C,
    Psychic = 0x0D,
    Ice = 0x0E,
    Dragon = 0x0F,
    Dark = 0x10,

    // HACK: This is a workaround for invalid types in games.
    Unknown_0x11 = 0x11,
    Unknown_0x12 = 0x12,
    Unknown_0x13 = 0x13,
    Unknown_0x14 = 0x14,
    Unknown_0x15 = 0x15,
    Unknown_0x16 = 0x16,
    Unknown_0x17 = 0x17,
    Unknown_0x18 = 0x18,
    Unknown_0x19 = 0x19,
    Unknown_0x1A = 0x1A,
    Unknown_0x1B = 0x1B,
    Unknown_0x1C = 0x1C,
    Unknown_0x1D = 0x1D,
    Unknown_0x1E = 0x1E,
    Unknown_0x1F = 0x1F,
    Unknown_0x20 = 0x20,
    Unknown_0x21 = 0x21,
    Unknown_0x22 = 0x22,
    Unknown_0x23 = 0x23,
    Unknown_0x24 = 0x24,
    Unknown_0x25 = 0x25,
    Unknown_0x26 = 0x26,
    Unknown_0x27 = 0x27,
    Unknown_0x28 = 0x28,
    Unknown_0x29 = 0x29,
    Unknown_0x2A = 0x2A,
    Unknown_0x2B = 0x2B,
    Unknown_0x2C = 0x2C,
    Unknown_0x2D = 0x2D,
    Unknown_0x2E = 0x2E,
    Unknown_0x2F = 0x2F,
    Unknown_0x30 = 0x30,
    Unknown_0x31 = 0x31,
    Unknown_0x32 = 0x32,
    Unknown_0x33 = 0x33,
    Unknown_0x34 = 0x34,
    Unknown_0x35 = 0x35,
    Unknown_0x36 = 0x36,
    Unknown_0x37 = 0x37,
    Unknown_0x38 = 0x38,
    Unknown_0x39 = 0x39,
    Unknown_0x3A = 0x3A,
    Unknown_0x3B = 0x3B,
    Unknown_0x3C = 0x3C,
    Unknown_0x3D = 0x3D,
    Unknown_0x3E = 0x3E,
    Unknown_0x3F = 0x3F,
    Unknown_0x40 = 0x40,
    Unknown_0x41 = 0x41,
    Unknown_0x42 = 0x42,
    Unknown_0x43 = 0x43,
    Unknown_0x44 = 0x44,
    Unknown_0x45 = 0x45,
    Unknown_0x46 = 0x46,
    Unknown_0x47 = 0x47,
    Unknown_0x48 = 0x48,
    Unknown_0x49 = 0x49,
    Unknown_0x4A = 0x4A,
    Unknown_0x4B = 0x4B,
    Unknown_0x4C = 0x4C,
    Unknown_0x4D = 0x4D,
    Unknown_0x4E = 0x4E,
    Unknown_0x4F = 0x4F,
    Unknown_0x50 = 0x50,
    Unknown_0x51 = 0x51,
    Unknown_0x52 = 0x52,
    Unknown_0x53 = 0x53,
    Unknown_0x54 = 0x54,
    Unknown_0x55 = 0x55,
    Unknown_0x56 = 0x56,
    Unknown_0x57 = 0x57,
    Unknown_0x58 = 0x58,
    Unknown_0x59 = 0x59,
    Unknown_0x5A = 0x5A,
    Unknown_0x5B = 0x5B,
    Unknown_0x5C = 0x5C,
    Unknown_0x5D = 0x5D,
    Unknown_0x5E = 0x5E,
    Unknown_0x5F = 0x5F,
    Unknown_0x60 = 0x60,
    Unknown_0x61 = 0x61,
    Unknown_0x62 = 0x62,
    Unknown_0x63 = 0x63,
    Unknown_0x64 = 0x64,
    Unknown_0x65 = 0x65,
    Unknown_0x66 = 0x66,
    Unknown_0x67 = 0x67,
    Unknown_0x68 = 0x68,
    Unknown_0x69 = 0x69,
    Unknown_0x6A = 0x6A,
    Unknown_0x6B = 0x6B,
    Unknown_0x6C = 0x6C,
    Unknown_0x6D = 0x6D,
    Unknown_0x6E = 0x6E,
    Unknown_0x6F = 0x6F,
    Unknown_0x70 = 0x70,
    Unknown_0x71 = 0x71,
    Unknown_0x72 = 0x72,
    Unknown_0x73 = 0x73,
    Unknown_0x74 = 0x74,
    Unknown_0x75 = 0x75,
    Unknown_0x76 = 0x76,
    Unknown_0x77 = 0x77,
    Unknown_0x78 = 0x78,
    Unknown_0x79 = 0x79,
    Unknown_0x7A = 0x7A,
    Unknown_0x7B = 0x7B,
    Unknown_0x7C = 0x7C,
    Unknown_0x7D = 0x7D,
    Unknown_0x7E = 0x7E,
    Unknown_0x7F = 0x7F,
    Unknown_0x80 = 0x80,
    Unknown_0x81 = 0x81,
    Unknown_0x82 = 0x82,
    Unknown_0x83 = 0x83,
    Unknown_0x84 = 0x84,
    Unknown_0x85 = 0x85,
    Unknown_0x86 = 0x86,
    Unknown_0x87 = 0x87,
    Unknown_0x88 = 0x88,
    Unknown_0x89 = 0x89,
    Unknown_0x8A = 0x8A,
    Unknown_0x8B = 0x8B,
    Unknown_0x8C = 0x8C,
    Unknown_0x8D = 0x8D,
    Unknown_0x8E = 0x8E,
    Unknown_0x8F = 0x8F,
    Unknown_0x90 = 0x90,
    Unknown_0x91 = 0x91,
    Unknown_0x92 = 0x92,
    Unknown_0x93 = 0x93,
    Unknown_0x94 = 0x94,
    Unknown_0x95 = 0x95,
    Unknown_0x96 = 0x96,
    Unknown_0x97 = 0x97,
    Unknown_0x98 = 0x98,
    Unknown_0x99 = 0x99,
    Unknown_0x9A = 0x9A,
    Unknown_0x9B = 0x9B,
    Unknown_0x9C = 0x9C,
    Unknown_0x9D = 0x9D,
    Unknown_0x9E = 0x9E,
    Unknown_0x9F = 0x9F,
    Unknown_0xA0 = 0xA0,
    Unknown_0xA1 = 0xA1,
    Unknown_0xA2 = 0xA2,
    Unknown_0xA3 = 0xA3,
    Unknown_0xA4 = 0xA4,
    Unknown_0xA5 = 0xA5,
    Unknown_0xA6 = 0xA6,
    Unknown_0xA7 = 0xA7,
    Unknown_0xA8 = 0xA8,
    Unknown_0xA9 = 0xA9,
    Unknown_0xAA = 0xAA,
    Unknown_0xAB = 0xAB,
    Unknown_0xAC = 0xAC,
    Unknown_0xAD = 0xAD,
    Unknown_0xAE = 0xAE,
    Unknown_0xAF = 0xAF,
    Unknown_0xB0 = 0xB0,
    Unknown_0xB1 = 0xB1,
    Unknown_0xB2 = 0xB2,
    Unknown_0xB3 = 0xB3,
    Unknown_0xB4 = 0xB4,
    Unknown_0xB5 = 0xB5,
    Unknown_0xB6 = 0xB6,
    Unknown_0xB7 = 0xB7,
    Unknown_0xB8 = 0xB8,
    Unknown_0xB9 = 0xB9,
    Unknown_0xBA = 0xBA,
    Unknown_0xBB = 0xBB,
    Unknown_0xBC = 0xBC,
    Unknown_0xBD = 0xBD,
    Unknown_0xBE = 0xBE,
    Unknown_0xBF = 0xBF,
    Unknown_0xC0 = 0xC0,
    Unknown_0xC1 = 0xC1,
    Unknown_0xC2 = 0xC2,
    Unknown_0xC3 = 0xC3,
    Unknown_0xC4 = 0xC4,
    Unknown_0xC5 = 0xC5,
    Unknown_0xC6 = 0xC6,
    Unknown_0xC7 = 0xC7,
    Unknown_0xC8 = 0xC8,
    Unknown_0xC9 = 0xC9,
    Unknown_0xCA = 0xCA,
    Unknown_0xCB = 0xCB,
    Unknown_0xCC = 0xCC,
    Unknown_0xCD = 0xCD,
    Unknown_0xCE = 0xCE,
    Unknown_0xCF = 0xCF,
    Unknown_0xD0 = 0xD0,
    Unknown_0xD1 = 0xD1,
    Unknown_0xD2 = 0xD2,
    Unknown_0xD3 = 0xD3,
    Unknown_0xD4 = 0xD4,
    Unknown_0xD5 = 0xD5,
    Unknown_0xD6 = 0xD6,
    Unknown_0xD7 = 0xD7,
    Unknown_0xD8 = 0xD8,
    Unknown_0xD9 = 0xD9,
    Unknown_0xDA = 0xDA,
    Unknown_0xDB = 0xDB,
    Unknown_0xDC = 0xDC,
    Unknown_0xDD = 0xDD,
    Unknown_0xDE = 0xDE,
    Unknown_0xDF = 0xDF,
    Unknown_0xE0 = 0xE0,
    Unknown_0xE1 = 0xE1,
    Unknown_0xE2 = 0xE2,
    Unknown_0xE3 = 0xE3,
    Unknown_0xE4 = 0xE4,
    Unknown_0xE5 = 0xE5,
    Unknown_0xE6 = 0xE6,
    Unknown_0xE7 = 0xE7,
    Unknown_0xE8 = 0xE8,
    Unknown_0xE9 = 0xE9,
    Unknown_0xEA = 0xEA,
    Unknown_0xEB = 0xEB,
    Unknown_0xEC = 0xEC,
    Unknown_0xED = 0xED,
    Unknown_0xEE = 0xEE,
    Unknown_0xEF = 0xEF,
    Unknown_0xF0 = 0xF0,
    Unknown_0xF1 = 0xF1,
    Unknown_0xF2 = 0xF2,
    Unknown_0xF3 = 0xF3,
    Unknown_0xF4 = 0xF4,
    Unknown_0xF5 = 0xF5,
    Unknown_0xF6 = 0xF6,
    Unknown_0xF7 = 0xF7,
    Unknown_0xF8 = 0xF8,
    Unknown_0xF9 = 0xF9,
    Unknown_0xFA = 0xFA,
    Unknown_0xFB = 0xFB,
    Unknown_0xFC = 0xFC,
    Unknown_0xFD = 0xFD,
    Unknown_0xFE = 0xFE,
    Unknown_0xFF = 0xFF,
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
        Unused = 0x00,
        FriendShip = 0x01,
        Unknown_0x02 = 0x02,
        Unknown_0x03 = 0x03,
        LevelUp = 0x04,
        Trade = 0x05,
        TradeHoldingItem = 0x06,
        TradeWithPokemon = 0x07,
        UseItem = 0x08,
        AttackGthDefense = 0x09,
        AttackEqlDefense = 0x0A,
        AttackLthDefense = 0x0B,
        PersonalityValue1 = 0x0C,
        PersonalityValue2 = 0x0D,
        LevelUpMaySpawnPokemon = 0x0E,
        LevelUpSpawnIfCond = 0x0F,
        Beauty = 0x10,
        UseItemOnMale = 0x11,
        UseItemOnFemale = 0x12,
        LevelUpHoldingItemDuringDaytime = 0x13,
        LevelUpHoldingItemDuringTheNight = 0x14,
        LevelUpKnowningMove = 0x15,
        LevelUpWithOtherPokemonInParty = 0x16,
        LevelUpMale = 0x17,
        LevelUpFemale = 0x18,
        LevelUpInSpecialMagneticField = 0x19,
        LevelUpNearMossRock = 0x1A,
        LevelUpNearIceRock = 0x1B,
        Unknown_0x1C = 0x1C,
        Unknown_0x1D = 0x1D,
        Unknown_0x1E = 0x1E,
        Unknown_0x1F = 0x1F,
        Unknown_0x20 = 0x20,
        Unknown_0x21 = 0x21,
        Unknown_0x22 = 0x22,
        Unknown_0x23 = 0x23,
        Unknown_0x24 = 0x24,
        Unknown_0x25 = 0x25,
        Unknown_0x26 = 0x26,
        Unknown_0x27 = 0x27,
        Unknown_0x28 = 0x28,
        Unknown_0x29 = 0x29,
        Unknown_0x2A = 0x2A,
        Unknown_0x2B = 0x2B,
        Unknown_0x2C = 0x2C,
        Unknown_0x2D = 0x2D,
        Unknown_0x2E = 0x2E,
        Unknown_0x2F = 0x2F,
        Unknown_0x30 = 0x30,
        Unknown_0x31 = 0x31,
        Unknown_0x32 = 0x32,
        Unknown_0x33 = 0x33,
        Unknown_0x34 = 0x34,
        Unknown_0x35 = 0x35,
        Unknown_0x36 = 0x36,
        Unknown_0x37 = 0x37,
        Unknown_0x38 = 0x38,
        Unknown_0x39 = 0x39,
        Unknown_0x3A = 0x3A,
        Unknown_0x3B = 0x3B,
        Unknown_0x3C = 0x3C,
        Unknown_0x3D = 0x3D,
        Unknown_0x3E = 0x3E,
        Unknown_0x3F = 0x3F,
        Unknown_0x40 = 0x40,
        Unknown_0x41 = 0x41,
        Unknown_0x42 = 0x42,
        Unknown_0x43 = 0x43,
        Unknown_0x44 = 0x44,
        Unknown_0x45 = 0x45,
        Unknown_0x46 = 0x46,
        Unknown_0x47 = 0x47,
        Unknown_0x48 = 0x48,
        Unknown_0x49 = 0x49,
        Unknown_0x4A = 0x4A,
        Unknown_0x4B = 0x4B,
        Unknown_0x4C = 0x4C,
        Unknown_0x4D = 0x4D,
        Unknown_0x4E = 0x4E,
        Unknown_0x4F = 0x4F,
        Unknown_0x50 = 0x50,
        Unknown_0x51 = 0x51,
        Unknown_0x52 = 0x52,
        Unknown_0x53 = 0x53,
        Unknown_0x54 = 0x54,
        Unknown_0x55 = 0x55,
        Unknown_0x56 = 0x56,
        Unknown_0x57 = 0x57,
        Unknown_0x58 = 0x58,
        Unknown_0x59 = 0x59,
        Unknown_0x5A = 0x5A,
        Unknown_0x5B = 0x5B,
        Unknown_0x5C = 0x5C,
        Unknown_0x5D = 0x5D,
        Unknown_0x5E = 0x5E,
        Unknown_0x5F = 0x5F,
        Unknown_0x60 = 0x60,
        Unknown_0x61 = 0x61,
        Unknown_0x62 = 0x62,
        Unknown_0x63 = 0x63,
        Unknown_0x64 = 0x64,
        Unknown_0x65 = 0x65,
        Unknown_0x66 = 0x66,
        Unknown_0x67 = 0x67,
        Unknown_0x68 = 0x68,
        Unknown_0x69 = 0x69,
        Unknown_0x6A = 0x6A,
        Unknown_0x6B = 0x6B,
        Unknown_0x6C = 0x6C,
        Unknown_0x6D = 0x6D,
        Unknown_0x6E = 0x6E,
        Unknown_0x6F = 0x6F,
        Unknown_0x70 = 0x70,
        Unknown_0x71 = 0x71,
        Unknown_0x72 = 0x72,
        Unknown_0x73 = 0x73,
        Unknown_0x74 = 0x74,
        Unknown_0x75 = 0x75,
        Unknown_0x76 = 0x76,
        Unknown_0x77 = 0x77,
        Unknown_0x78 = 0x78,
        Unknown_0x79 = 0x79,
        Unknown_0x7A = 0x7A,
        Unknown_0x7B = 0x7B,
        Unknown_0x7C = 0x7C,
        Unknown_0x7D = 0x7D,
        Unknown_0x7E = 0x7E,
        Unknown_0x7F = 0x7F,
        Unknown_0x80 = 0x80,
        Unknown_0x81 = 0x81,
        Unknown_0x82 = 0x82,
        Unknown_0x83 = 0x83,
        Unknown_0x84 = 0x84,
        Unknown_0x85 = 0x85,
        Unknown_0x86 = 0x86,
        Unknown_0x87 = 0x87,
        Unknown_0x88 = 0x88,
        Unknown_0x89 = 0x89,
        Unknown_0x8A = 0x8A,
        Unknown_0x8B = 0x8B,
        Unknown_0x8C = 0x8C,
        Unknown_0x8D = 0x8D,
        Unknown_0x8E = 0x8E,
        Unknown_0x8F = 0x8F,
        Unknown_0x90 = 0x90,
        Unknown_0x91 = 0x91,
        Unknown_0x92 = 0x92,
        Unknown_0x93 = 0x93,
        Unknown_0x94 = 0x94,
        Unknown_0x95 = 0x95,
        Unknown_0x96 = 0x96,
        Unknown_0x97 = 0x97,
        Unknown_0x98 = 0x98,
        Unknown_0x99 = 0x99,
        Unknown_0x9A = 0x9A,
        Unknown_0x9B = 0x9B,
        Unknown_0x9C = 0x9C,
        Unknown_0x9D = 0x9D,
        Unknown_0x9E = 0x9E,
        Unknown_0x9F = 0x9F,
        Unknown_0xA0 = 0xA0,
        Unknown_0xA1 = 0xA1,
        Unknown_0xA2 = 0xA2,
        Unknown_0xA3 = 0xA3,
        Unknown_0xA4 = 0xA4,
        Unknown_0xA5 = 0xA5,
        Unknown_0xA6 = 0xA6,
        Unknown_0xA7 = 0xA7,
        Unknown_0xA8 = 0xA8,
        Unknown_0xA9 = 0xA9,
        Unknown_0xAA = 0xAA,
        Unknown_0xAB = 0xAB,
        Unknown_0xAC = 0xAC,
        Unknown_0xAD = 0xAD,
        Unknown_0xAE = 0xAE,
        Unknown_0xAF = 0xAF,
        Unknown_0xB0 = 0xB0,
        Unknown_0xB1 = 0xB1,
        Unknown_0xB2 = 0xB2,
        Unknown_0xB3 = 0xB3,
        Unknown_0xB4 = 0xB4,
        Unknown_0xB5 = 0xB5,
        Unknown_0xB6 = 0xB6,
        Unknown_0xB7 = 0xB7,
        Unknown_0xB8 = 0xB8,
        Unknown_0xB9 = 0xB9,
        Unknown_0xBA = 0xBA,
        Unknown_0xBB = 0xBB,
        Unknown_0xBC = 0xBC,
        Unknown_0xBD = 0xBD,
        Unknown_0xBE = 0xBE,
        Unknown_0xBF = 0xBF,
        Unknown_0xC0 = 0xC0,
        Unknown_0xC1 = 0xC1,
        Unknown_0xC2 = 0xC2,
        Unknown_0xC3 = 0xC3,
        Unknown_0xC4 = 0xC4,
        Unknown_0xC5 = 0xC5,
        Unknown_0xC6 = 0xC6,
        Unknown_0xC7 = 0xC7,
        Unknown_0xC8 = 0xC8,
        Unknown_0xC9 = 0xC9,
        Unknown_0xCA = 0xCA,
        Unknown_0xCB = 0xCB,
        Unknown_0xCC = 0xCC,
        Unknown_0xCD = 0xCD,
        Unknown_0xCE = 0xCE,
        Unknown_0xCF = 0xCF,
        Unknown_0xD0 = 0xD0,
        Unknown_0xD1 = 0xD1,
        Unknown_0xD2 = 0xD2,
        Unknown_0xD3 = 0xD3,
        Unknown_0xD4 = 0xD4,
        Unknown_0xD5 = 0xD5,
        Unknown_0xD6 = 0xD6,
        Unknown_0xD7 = 0xD7,
        Unknown_0xD8 = 0xD8,
        Unknown_0xD9 = 0xD9,
        Unknown_0xDA = 0xDA,
        Unknown_0xDB = 0xDB,
        Unknown_0xDC = 0xDC,
        Unknown_0xDD = 0xDD,
        Unknown_0xDE = 0xDE,
        Unknown_0xDF = 0xDF,
        Unknown_0xE0 = 0xE0,
        Unknown_0xE1 = 0xE1,
        Unknown_0xE2 = 0xE2,
        Unknown_0xE3 = 0xE3,
        Unknown_0xE4 = 0xE4,
        Unknown_0xE5 = 0xE5,
        Unknown_0xE6 = 0xE6,
        Unknown_0xE7 = 0xE7,
        Unknown_0xE8 = 0xE8,
        Unknown_0xE9 = 0xE9,
        Unknown_0xEA = 0xEA,
        Unknown_0xEB = 0xEB,
        Unknown_0xEC = 0xEC,
        Unknown_0xED = 0xED,
        Unknown_0xEE = 0xEE,
        Unknown_0xEF = 0xEF,
        Unknown_0xF0 = 0xF0,
        Unknown_0xF1 = 0xF1,
        Unknown_0xF2 = 0xF2,
        Unknown_0xF3 = 0xF3,
        Unknown_0xF4 = 0xF4,
        Unknown_0xF5 = 0xF5,
        Unknown_0xF6 = 0xF6,
        Unknown_0xF7 = 0xF7,
        Unknown_0xF8 = 0xF8,
        Unknown_0xF9 = 0xF9,
        Unknown_0xFA = 0xFA,
        Unknown_0xFB = 0xFB,
        Unknown_0xFC = 0xFC,
        Unknown_0xFD = 0xFD,
        Unknown_0xFE = 0xFE,
        Unknown_0xFF = 0xFF,
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
        s.value = lu16.init((u16(s.form()) << u4(10)) | spe);
    }

    pub fn form(s: Species) u6 {
        return @truncate(u6, s.value.value() >> 10);
    }

    pub fn setForm(s: *Species, f: u10) void {
        s.value = lu16.init((u16(f) << u4(10)) | s.species());
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

pub const Game = struct {
    version: common.Version,
    allocator: *mem.Allocator,

    starters: [3][]*lu16,
    scripts: *const nds.fs.Narc,
    pokemons: *const nds.fs.Narc,
    evolutions: *const nds.fs.Narc,
    moves: *const nds.fs.Narc,
    level_up_moves: *const nds.fs.Narc,
    trainers: *const nds.fs.Narc,
    parties: *const nds.fs.Narc,
    wild_pokemons: *const nds.fs.Narc,
    tms1: []lu16,
    hms: []lu16,
    tms2: []lu16,
    static_pokemons: []*script.Command,
    given_items: []*script.Command,

    pub fn fromRom(allocator: *mem.Allocator, nds_rom: nds.Rom) !Game {
        const info = try getInfo(nds_rom.header.gamecode);
        const hm_tm_prefix_index = mem.indexOf(u8, nds_rom.arm9, offsets.hm_tm_prefix) orelse return error.CouldNotFindTmsOrHms;
        const hm_tm_index = hm_tm_prefix_index + offsets.hm_tm_prefix.len;
        const hm_tm_len = (offsets.tm_count + offsets.hm_count) * @sizeOf(u16);
        const hm_tms = @bytesToSlice(lu16, nds_rom.arm9[hm_tm_index..][0..hm_tm_len]);
        const scripts = try getNarc(nds_rom.root, info.scripts);
        const script_files = scripts.nodes.toSlice();

        const commands = try findScriptCommands(info.version, scripts, allocator);
        errdefer {
            allocator.free(commands.static_pokemons);
            allocator.free(commands.given_items);
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
                        if (script_files.len <= offset.file)
                            return error.CouldNotFindStarter;

                        const node = script_files[offset.file];
                        const file = try nodeAsFile(node);
                        if (file.data.len < offset.offset + 2)
                            return error.CouldNotFindStarter;

                        res[i][j] = &@bytesToSlice(lu16, file.data[offset.offset..][0..2])[0];
                    }
                }

                break :blk res;
            },
            .scripts = scripts,
            .pokemons = try getNarc(nds_rom.root, info.pokemons),
            .evolutions = try getNarc(nds_rom.root, info.evolutions),
            .level_up_moves = try getNarc(nds_rom.root, info.level_up_moves),
            .moves = try getNarc(nds_rom.root, info.moves),
            .trainers = try getNarc(nds_rom.root, info.trainers),
            .parties = try getNarc(nds_rom.root, info.parties),
            .wild_pokemons = try getNarc(nds_rom.root, info.wild_pokemons),
            .tms1 = hm_tms[0..92],
            .hms = hm_tms[92..98],
            .tms2 = hm_tms[98..],
            .static_pokemons = commands.static_pokemons,
            .given_items = commands.given_items,
        };
    }

    pub fn deinit(game: Game) void {
        for (game.starters) |starter_ptrs|
            game.allocator.free(starter_ptrs);
        game.allocator.free(game.static_pokemons);
        game.allocator.free(game.given_items);
    }

    const ScriptCommands = struct {
        static_pokemons: []*script.Command,
        given_items: []*script.Command,
    };

    fn findScriptCommands(version: common.Version, scripts: *const nds.fs.Narc, allocator: *mem.Allocator) !ScriptCommands {
        if (version == .Black or version == .White) {
            // We don't support decoding scripts for hg/ss yet.
            return ScriptCommands{
                .static_pokemons = ([*]*script.Command)(undefined)[0..0],
                .given_items = ([*]*script.Command)(undefined)[0..0],
            };
        }

        var static_pokemons = std.ArrayList(*script.Command).init(allocator);
        errdefer static_pokemons.deinit();
        var given_items = std.ArrayList(*script.Command).init(allocator);
        errdefer given_items.deinit();

        var script_offsets = std.ArrayList(isize).init(allocator);
        defer script_offsets.deinit();

        for (scripts.nodes.toSlice()) |node, script_i| {
            const script_file = node.asFile() catch continue;
            const script_data = script_file.data;
            defer script_offsets.resize(0) catch unreachable;

            for (script.getScriptOffsets(script_data)) |relative_offset, i| {
                const offset = relative_offset.value() + @intCast(isize, i + 1) * @sizeOf(lu32);
                if (@intCast(isize, script_data.len) < offset)
                    continue;
                if (offset < 0)
                    continue;
                try script_offsets.append(offset);
            }

            var offset_i: usize = 0;
            while (offset_i < script_offsets.count()) : (offset_i += 1) {
                const offset = script_offsets.at(offset_i);
                if (@intCast(isize, script_data.len) < offset)
                    return error.Error;
                if (offset < 0)
                    return error.Error;

                var decoder = script.CommandDecoder{
                    .bytes = script_data,
                    .i = @intCast(usize, offset),
                };
                while (decoder.next() catch continue) |command| {
                    switch (command.tag) {
                        // TODO: We're not finding any given items yet
                        .WildBattle => try static_pokemons.append(command),
                        .Jump => {
                            const off = command.data.Jump.offset.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .If => {
                            const off = command.data.If.offset.value();
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
            .given_items = given_items.toOwnedSlice(),
        };
    }

    fn nodeAsFile(node: nds.fs.Narc.Node) !*nds.fs.Narc.File {
        switch (node.kind) {
            nds.fs.Narc.Node.Kind.File => |file| return file,
            nds.fs.Narc.Node.Kind.Folder => return error.NotFile,
        }
    }

    fn getInfo(gamecode: []const u8) !offsets.Info {
        for (offsets.infos) |info| {
            //if (!mem.eql(u8, info.game_title, game_title))
            //    continue;
            if (!mem.eql(u8, info.gamecode, gamecode))
                continue;

            return info;
        }

        return error.NotGen5Game;
    }

    fn getNarc(file_system: *nds.fs.Nitro, path: []const u8) !*const nds.fs.Narc {
        const file = file_system.getFile(path) orelse return error.FileNotFound;

        const Tag = @TagType(nds.fs.Nitro.File);
        switch (file.*) {
            Tag.Binary => return error.FileNotNarc,
            Tag.Narc => |res| return res,
        }
    }
};
