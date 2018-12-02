const common = @import("tm35-common");
const fun = @import("fun-with-zig");
const offsets = @import("gen4-offsets.zig");
const nds = @import("tm35-nds");
const pokemon = @import("index.zig");
const std = @import("std");

const mem = std.mem;

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu128 = fun.platform.lu128;

pub const BasePokemon = packed struct {
    stats: common.Stats,
    types: [2]Type,

    catch_rate: u8,
    base_exp_yield: u8,

    ev_yield: common.EvYield,
    items: [2]lu16,

    gender_ratio: u8,
    egg_cycles: u8,
    base_friendship: u8,
    growth_rate: common.GrowthRate,

    egg_group1: common.EggGroup,
    egg_group1_pad: u4,
    egg_group2: common.EggGroup,
    egg_group2_pad: u4,

    abilities: [2]u8,
    flee_rate: u8,

    color: common.Color,
    color_padding: bool,

    // Memory layout
    // TMS 01-92, HMS 01-08
    machine_learnset: lu128,
};

pub const MoveTutor = packed struct {
    move: lu16,
    cost: u8,
    tutor: u8,
};

pub const PartyType = enum(u8) {
    None = 0b00,
    Item = 0b10,
    Moves = 0b01,
    Both = 0b11,
};

pub const PartyMemberBase = packed struct {
    iv: u8,
    gender: u4,
    ability: u4,
    level: lu16,
    species: u10,
    form: u6,
};

pub const PartyMemberNone = packed struct {
    base: PartyMemberBase,
};

pub const PartyMemberItem = packed struct {
    base: PartyMemberBase,
    item: lu16,
};

pub const PartyMemberMoves = packed struct {
    base: PartyMemberBase,
    moves: [4]lu16,
};

pub const PartyMemberBoth = packed struct {
    base: PartyMemberBase,
    item: lu16,
    moves: [4]lu16,
};

/// In HG/SS/Plat, this struct is always padded with a u16 at the end, no matter the party_type
pub fn HgSsPlatMember(comptime T: type) type {
    return struct {
        member: T,
        pad: lu16,
    };
}

pub const Trainer = packed struct {
    party_type: PartyType,
    class: u8,
    battle_type: u8, // TODO: This should probably be an enum
    party_size: u8,
    items: [4]lu16,
    ai: lu32,
    battle_type2: u8,
};

pub const Type = enum(u8) {
    Normal = 0x00,
    Fighting = 0x01,
    Flying = 0x02,
    Poison = 0x03,
    Ground = 0x04,
    Rock = 0x05,
    Bug = 0x06,
    Ghost = 0x07,
    Steel = 0x08,
    Unknown = 0x09,
    Fire = 0x0A,
    Water = 0x0B,
    Grass = 0x0C,
    Electric = 0x0D,
    Psychic = 0x0E,
    Ice = 0x0F,
    Dragon = 0x10,
    Dark = 0x11,
};

// TODO: This is the first data structure I had to decode from scratch as I couldn't find a proper
//       resource for it... Fill it out!
pub const Move = packed struct {
    u8_0: u8,
    u8_1: u8,
    category: common.MoveCategory,
    power: u8,
    @"type": Type,
    accuracy: u8,
    pp: u8,
    u8_7: u8,
    u8_8: u8,
    u8_9: u8,
    u8_10: u8,
    u8_11: u8,
    u8_12: u8,
    u8_13: u8,
    u8_14: u8,
    u8_15: u8,
};

pub const LevelUpMove = packed struct {
    move_id: u9,
    level: u7,
};

pub const DpptWildPokemons = packed struct {
    grass_rate: lu32,
    grass: [12]Grass,
    swarm_replacements: [2]Replacement, // Replaces grass[0, 1]
    day_replacements: [2]Replacement, // Replaces grass[2, 3]
    night_replacements: [2]Replacement, // Replaces grass[2, 3]
    radar_replacements: [4]Replacement, // Replaces grass[4, 5, 10, 11]
    unknown_replacements: [6]Replacement, // ???
    gba_replacements: [10]Replacement, // Each even replaces grass[8], each uneven replaces grass[9]
    surf: [5]Sea,
    sea_unknown: [5]Sea,
    old_rod: [5]Sea,
    good_rod: [5]Sea,
    super_rod: [5]Sea,

    pub const Grass = packed struct {
        level: u8,
        pad1: [3]u8,
        species: lu16,
        pad2: [2]u8,
    };

    pub const Sea = packed struct {
        min_level: u8,
        max_level: u8,
        pad1: [2]u8,
        species: lu16,
        pad2: [2]u8,
    };

    pub const Replacement = packed struct {
        species: lu16,
        pad: [2]u8,
    };
};

pub const HgssWildPokemons = packed struct {
    grass_rate: u8,
    sea_rates: [5]u8,
    unknown: [2]u8,
    grass_levels: [12]u8,
    grass_morning: [12]lu16,
    grass_day: [12]lu16,
    grass_night: [12]lu16,
    radio: [4]lu16,
    surf: [5]Sea,
    sea_unknown: [2]Sea,
    old_rod: [5]Sea,
    good_rod: [5]Sea,
    super_rod: [5]Sea,
    swarm: [4]lu16,

    pub const Sea = packed struct {
        min_level: u8,
        max_level: u8,
        species: lu16,
    };
};

pub const Game = struct {
    version: common.Version,
    pokemons: *const nds.fs.Narc,
    moves: *const nds.fs.Narc,
    level_up_moves: *const nds.fs.Narc,
    trainers: *const nds.fs.Narc,
    parties: *const nds.fs.Narc,
    wild_pokemons: *const nds.fs.Narc,
    tms: []lu16,
    hms: []lu16,

    pub fn fromRom(rom: nds.Rom) !Game {
        const info = try getInfo(rom.header.game_title, rom.header.gamecode);
        const hm_tm_prefix_index = mem.indexOf(u8, rom.arm9, info.hm_tm_prefix) orelse return error.CouldNotFindTmsOrHms;
        const hm_tm_index = hm_tm_prefix_index + info.hm_tm_prefix.len;
        const hm_tms_len = (offsets.tm_count + offsets.hm_count) * @sizeOf(u16);
        const hm_tms = @bytesToSlice(lu16, rom.arm9[hm_tm_index..][0..hm_tms_len]);

        return Game{
            .version = info.version,
            .pokemons = try getNarc(rom.root, info.pokemons),
            .level_up_moves = try getNarc(rom.root, info.level_up_moves),
            .moves = try getNarc(rom.root, info.moves),
            .trainers = try getNarc(rom.root, info.trainers),
            .parties = try getNarc(rom.root, info.parties),
            .wild_pokemons = try getNarc(rom.root, info.wild_pokemons),
            .tms = hm_tms[0..92],
            .hms = hm_tms[92..],
        };
    }

    fn getInfo(game_title: []const u8, gamecode: []const u8) !offsets.Info {
        for (offsets.infos) |info| {
            //if (!mem.eql(u8, info.game_title, game_title))
            //    continue;
            if (!mem.eql(u8, info.gamecode, gamecode))
                continue;

            return info;
        }

        return error.NotGen4Game;
    }

    pub fn getNarc(file_system: *nds.fs.Nitro, path: []const u8) !*const nds.fs.Narc {
        const file = file_system.getFile(path) orelse return error.FileNotFound;

        const Tag = @TagType(nds.fs.Nitro.File);
        switch (file.*) {
            Tag.Binary => return error.FileNotNarc,
            Tag.Narc => |res| return res,
        }
    }
};
