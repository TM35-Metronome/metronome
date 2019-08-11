const std = @import("std");
const fun = @import("fun");

const lu16 = fun.platform.lu16;

pub const Version = enum {
    Red,
    Blue,
    Yellow,

    Gold,
    Silver,
    Crystal,

    Ruby,
    Sapphire,
    Emerald,
    FireRed,
    LeafGreen,

    Diamond,
    Pearl,
    Platinum,
    HeartGold,
    SoulSilver,

    Black,
    White,
    Black2,
    White2,

    X,
    Y,
    OmegaRuby,
    AlphaSapphire,

    Sun,
    Moon,
    UltraSun,
    UltraMoon,
};

pub const Stats = extern struct {
    hp: u8,
    attack: u8,
    defense: u8,
    speed: u8,
    sp_attack: u8,
    sp_defense: u8,

    comptime {
        std.debug.assert(@sizeOf(Stats) == 6);
    }
};

pub const MoveCategory = packed enum(u8) {
    Physical = 0x00,
    Status = 0x01,
    Special = 0x02,
};

pub const GrowthRate = packed enum(u8) {
    MediumFast = 0x00,
    Erratic = 0x01,
    Fluctuating = 0x02,
    MediumSlow = 0x03,
    Fast = 0x04,
    Slow = 0x05,
};

pub const EggGroup = packed enum(u4) {
    Invalid = 0x00, // TODO: Figure out if there is a 0x00 egg group
    Monster = 0x01,
    Water1 = 0x02,
    Bug = 0x03,
    Flying = 0x04,
    Field = 0x05,
    Fairy = 0x06,
    Grass = 0x07,
    HumanLike = 0x08,
    Water3 = 0x09,
    Mineral = 0x0A,
    Amorphous = 0x0B,
    Water2 = 0x0C,
    Ditto = 0x0D,
    Dragon = 0x0E,
    Undiscovered = 0x0F,
};

pub const Color = packed enum(u7) {
    Red = 0x00,
    Blue = 0x01,
    Yellow = 0x02,
    Green = 0x03,
    Black = 0x04,
    Brown = 0x05,
    Purple = 0x06,
    Gray = 0x07,
    White = 0x08,
    Pink = 0x09,

    // HACK: This is a workaround for invalid colors in games.
    Unknown_0xA = 0xA,
    Unknown_0xB = 0xB,
    Unknown_0xC = 0xC,
    Unknown_0xD = 0xD,
    Unknown_0xE = 0xE,
    Unknown_0xF = 0xF,
    Unknown_0x10 = 0x10,
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
};

// TODO: Figure out if the this have the same layout in all games that have it.
//       They probably have, so let's assume that for now and if a bug
//       is ever encountered related to this, we figure it out.
pub const EvYield = packed struct {
    hp: u2,
    attack: u2,
    defense: u2,
    speed: u2,
    sp_attack: u2,
    sp_defense: u2,
    padding: u4,

    comptime {
        std.debug.assert(@sizeOf(EvYield) == 2);
    }
};

pub const Evolution = packed struct {
    method: Evolution.Method,
    param: lu16,
    target: lu16,
    padding: [2]u8,

    pub const Method = enum(u16) {
        Unused = lu16.init(0x00).value(),
        FriendShip = lu16.init(0x01).value(),
        FriendShipDuringDay = lu16.init(0x02).value(),
        FriendShipDuringNight = lu16.init(0x03).value(),
        LevelUp = lu16.init(0x04).value(),
        Trade = lu16.init(0x05).value(),
        TradeHoldingItem = lu16.init(0x06).value(),
        UseItem = lu16.init(0x07).value(),
        AttackGthDefense = lu16.init(0x08).value(),
        AttackEqlDefense = lu16.init(0x09).value(),
        AttackLthDefense = lu16.init(0x0A).value(),
        PersonalityValue1 = lu16.init(0x0B).value(),
        PersonalityValue2 = lu16.init(0x0C).value(),
        LevelUpMaySpawnPokemon = lu16.init(0x0D).value(),
        LevelUpSpawnIfCond = lu16.init(0x0E).value(),
        Beauty = lu16.init(0x0F).value(),
    };

    comptime {
        std.debug.assert(@sizeOf(Evolution) == 8);
    }
};

pub const legendaries = []u16{
    144, 145, 146, // Articuno, Zapdos, Moltres
    150, 151, 243, // Mewtwo, Mew, Raikou
    244, 245, 249, // Entei, Suicune, Lugia
    250, 251, 377, // Ho-Oh, Celebi, Regirock
    378, 379, 380, // Regice, Registeel, Latias
    381, 382, 383, // Latios, Kyogre, Groudon,
    384, 385, 386, // Rayquaza, Jirachi, Deoxys
    480, 481, 482, // Uxie, Mesprit, Azelf
    483, 484, 485, // Dialga, Palkia, Heatran
    486, 487, 488, // Regigigas, Giratina, Cresselia
    489, 490, 491, // Phione, Manaphy, Darkrai
    492, 493, 494, // Shaymin, Arceus, Victini
    638, 639, 640, // Cobalion, Terrakion, Virizion
    641, 642, 643, // Tornadus, Thundurus, Reshiram
    644, 645, 646, // Zekrom, Landorus, Kyurem
    647, 648, 649, // Keldeo, Meloetta, Genesect
    716, 717, 718, // Xerneas, Yveltal, Zygarde
    719, 720, 721, // Diancie, Hoopa, Volcanion
};
