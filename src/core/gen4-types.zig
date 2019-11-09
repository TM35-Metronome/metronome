const common = @import("common.zig");
const fun = @import("fun");
const offsets = @import("gen4-offsets.zig");
const nds = @import("nds.zig");
const pokemon = @import("index.zig");
const std = @import("std");

const mem = std.mem;

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu128 = fun.platform.lu128;

pub const BasePokemon = extern struct {
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
    egg_group2: common.EggGroup,

    abilities: [2]u8,
    flee_rate: u8,

    color: common.Color,

    // Memory layout
    // TMS 01-92, HMS 01-08
    machine_learnset: lu128,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 42);
    }
};

pub const Evolution = extern struct {
    method: Evolution.Method,
    padding: u8,
    param: lu16,
    target: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
    }

    pub const Method = packed enum(u8) {
        // TODO: It is said, that their is 26 evo methods, but not what they are called
        //       (https://projectpokemon.org/home/forums/topic/41694-hgss-pokemon-file-specifications/)
        // TODO: Verify that 0 is unused
        Unused = 0x00,
        Unknown_0x01 = 0x01,
        Unknown_0x02 = 0x02,
        Unknown_0x03 = 0x03,
        Unknown_0x04 = 0x04,
        Unknown_0x05 = 0x05,
        Unknown_0x06 = 0x06,
        Unknown_0x07 = 0x07,
        Unknown_0x08 = 0x08,
        Unknown_0x09 = 0x09,
        Unknown_0x0A = 0x0A,
        Unknown_0x0B = 0x0B,
        Unknown_0x0C = 0x0C,
        Unknown_0x0D = 0x0D,
        Unknown_0x0E = 0x0E,
        Unknown_0x0F = 0x0F,
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

pub const MoveTutor = extern struct {
    move: lu16,
    cost: u8,
    tutor: u8,

    comptime {
        @compileLog(@This(), @sizeOf(@This()));
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const PartyType = packed enum(u8) {
    None = 0b00,
    Item = 0b10,
    Moves = 0b01,
    Both = 0b11,
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

pub const PartyMemberBase = extern struct {
    iv: u8,
    gender_ability: GenderAbilityPair, // 4 msb are gender, 4 lsb are ability
    level: lu16,
    species: Species,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
    }

    pub const GenderAbilityPair = packed struct {
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
        std.debug.assert(@sizeOf(@This()) == 6);
    }
};

pub const PartyMemberItem = extern struct {
    base: PartyMemberBase,
    item: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const PartyMemberMoves = extern struct {
    base: PartyMemberBase,
    moves: [4]lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 14);
    }
};

pub const PartyMemberBoth = extern struct {
    base: PartyMemberBase,
    item: lu16,
    moves: [4]lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

/// In HG/SS/Plat, this struct is always padded with a u16 at the end, no matter the party_type
pub fn HgSsPlatMember(comptime T: type) type {
    return extern struct {
        member: T,
        pad: lu16,

        comptime {
            std.debug.assert(@sizeOf(@This()) == @sizeOf(T) + 2);
        }
    };
}

pub const Trainer = extern struct {
    party_type: PartyType,
    class: u8,
    battle_type: u8, // TODO: This should probably be an enum
    party_size: u8,
    items: [4]lu16,
    ai: lu32,
    battle_type2: u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 17);
    }

    pub fn partyMember(trainer: Trainer, version: common.Version, party: []u8, i: usize) ?*PartyMemberBase {
        return switch (version) {
            common.Version.Diamond,
            common.Version.Pearl,
            => switch (trainer.party_type) {
                .None => trainer.partyMemberHelper(party, @sizeOf(PartyMemberNone), i),
                .Item => trainer.partyMemberHelper(party, @sizeOf(PartyMemberItem), i),
                .Moves => trainer.partyMemberHelper(party, @sizeOf(PartyMemberMoves), i),
                .Both => trainer.partyMemberHelper(party, @sizeOf(PartyMemberBoth), i),
            },

            common.Version.Platinum,
            common.Version.HeartGold,
            common.Version.SoulSilver,
            => switch (trainer.party_type) {
                .None => trainer.partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberNone)), i),
                .Item => trainer.partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberItem)), i),
                .Moves => trainer.partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberMoves)), i),
                .Both => trainer.partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberBoth)), i),
            },

            else => unreachable,
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
pub const Move = extern struct {
    u8_0: u8,
    u8_1: u8,
    category: common.MoveCategory,
    power: u8,
    type: Type,
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

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const LevelUpMove = extern struct {
    move_id: u9,
    level: u7,

    comptime {
        @compileLog(@sizeOf(@This()));
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const DpptWildPokemons = extern struct {
    grass_rate: lu32,
    grass: [12]Grass,
    swarm_replacements: [2]Replacement, // Replaces grass[0, 1]
    day_replacements: [2]Replacement, // Replaces grass[2, 3]
    night_replacements: [2]Replacement, // Replaces grass[2, 3]
    radar_replacements: [4]Replacement, // Replaces grass[4, 5, 10, 11]
    unknown_replacements: [6]Replacement, // ???
    gba_replacements: [10]Replacement, // Each even replaces grass[8], each uneven replaces grass[9]

    surf_rate: lu32,
    surf: [5]Sea,

    sea_unknown_rate: lu32,
    sea_unknown: [5]Sea,

    old_rod_rate: lu32,
    old_rod: [5]Sea,

    good_rod_rate: lu32,
    good_rod: [5]Sea,

    super_rod_rate: lu32,
    super_rod: [5]Sea,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 424);
    }

    pub const Grass = extern struct {
        level: u8,
        pad1: [3]u8,
        species: Species,
        pad2: [2]u8,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 8);
        }
    };

    pub const Sea = extern struct {
        max_level: u8,
        min_level: u8,
        pad1: [2]u8,
        species: Species,
        pad2: [2]u8,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 8);
        }
    };

    pub const Replacement = extern struct {
        species: Species,
        pad: [2]u8,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 4);
        }
    };
};

pub const HgssWildPokemons = extern struct {
    grass_rate: u8,
    sea_rates: [5]u8,
    unknown: [2]u8,
    grass_levels: [12]u8,
    grass_morning: [12]Species,
    grass_day: [12]Species,
    grass_night: [12]Species,
    radio: [4]Species,
    surf: [5]Sea,
    sea_unknown: [2]Sea,
    old_rod: [5]Sea,
    good_rod: [5]Sea,
    super_rod: [5]Sea,
    swarm: [4]Species,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 196);
    }

    pub const Sea = extern struct {
        min_level: u8,
        max_level: u8,
        species: Species,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 4);
        }
    };
};

pub const Game = struct {
    version: common.Version,
    starters: [3]*lu16,
    pokemons: *const nds.fs.Narc,
    evolutions: *const nds.fs.Narc,
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
            .starters = switch (info.starters) {
                offsets.StarterLocation.Arm9 => |offset| blk: {
                    const starters_section = @bytesToSlice(lu16, rom.arm9[offset..][0..offsets.starters_len]);
                    break :blk [_]*lu16{
                        &starters_section[0],
                        &starters_section[2],
                        &starters_section[4],
                    };
                },
                offsets.StarterLocation.Overlay9 => |overlay| blk: {
                    const file = rom.arm9_overlay_files[overlay.file];
                    const starters_section = @bytesToSlice(lu16, file[overlay.offset..][0..offsets.starters_len]);
                    break :blk [_]*lu16{
                        &starters_section[0],
                        &starters_section[2],
                        &starters_section[4],
                    };
                },
            },
            .pokemons = try getNarc(rom.root, info.pokemons),
            .evolutions = try getNarc(rom.root, info.evolutions),
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
