const fun = @import("../fun-with-zig/src/index.zig");

const lu16 = fun.platform.lu16;

pub const Version = extern enum {
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

pub const Stats = packed struct {
    hp: u8,
    attack: u8,
    defense: u8,
    speed: u8,
    sp_attack: u8,
    sp_defense: u8,
};

pub const MoveCategory = enum(u8) {
    Physical = 0x00,
    Status = 0x01,
    Special = 0x02,
};

pub const GrowthRate = enum(u8) {
    MediumFast = 0x00,
    Erratic = 0x01,
    Fluctuating = 0x02,
    MediumSlow = 0x03,
    Fast = 0x04,
    Slow = 0x05,
};

pub const EggGroup = enum(u4) {
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

pub const Color = enum(u7) {
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
