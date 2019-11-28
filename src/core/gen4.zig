const std = @import("std");

const common = @import("common.zig");
const rom = @import("rom.zig");

pub const offsets = @import("gen4/offsets.zig");

const mem = std.mem;

const nds = rom.nds;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu128 = rom.int.lu128;

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
    method: common.EvoMethod,
    padding: u8,
    param: lu16,
    target: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
    }
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
    //move_id: u9,
    //level: u7,
    data: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 2);
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

    pub fn fromRom(nds_rom: nds.Rom) !Game {
        const info = try getInfo(nds_rom.header.game_title, nds_rom.header.gamecode);
        const hm_tm_prefix_index = mem.indexOf(u8, nds_rom.arm9, info.hm_tm_prefix) orelse return error.CouldNotFindTmsOrHms;
        const hm_tm_index = hm_tm_prefix_index + info.hm_tm_prefix.len;
        const hm_tms_len = (offsets.tm_count + offsets.hm_count) * @sizeOf(u16);
        const hm_tms = @bytesToSlice(lu16, nds_rom.arm9[hm_tm_index..][0..hm_tms_len]);

        return Game{
            .version = info.version,
            .starters = switch (info.starters) {
                .Arm9 => |offset| blk: {
                    if (nds_rom.arm9.len < offset + offsets.starters_len)
                        unreachable; //return error.CouldNotFindStarters;
                    const starters_section = @bytesToSlice(lu16, nds_rom.arm9[offset..][0..offsets.starters_len]);
                    break :blk [_]*lu16{
                        &starters_section[0],
                        &starters_section[2],
                        &starters_section[4],
                    };
                },
                .Overlay9 => |overlay| blk: {
                    if (nds_rom.arm9_overlay_files.len <= overlay.file)
                        return error.CouldNotFindStarters;

                    const file = nds_rom.arm9_overlay_files[overlay.file];
                    if (file.len < overlay.offset + offsets.starters_len)
                        return error.CouldNotFindStarters;

                    const starters_section = @bytesToSlice(lu16, file[overlay.offset..][0..offsets.starters_len]);
                    break :blk [_]*lu16{
                        &starters_section[0],
                        &starters_section[2],
                        &starters_section[4],
                    };
                },
            },
            .pokemons = try getNarc(nds_rom.root, info.pokemons),
            .evolutions = try getNarc(nds_rom.root, info.evolutions),
            .level_up_moves = try getNarc(nds_rom.root, info.level_up_moves),
            .moves = try getNarc(nds_rom.root, info.moves),
            .trainers = try getNarc(nds_rom.root, info.trainers),
            .parties = try getNarc(nds_rom.root, info.parties),
            .wild_pokemons = try getNarc(nds_rom.root, info.wild_pokemons),
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
