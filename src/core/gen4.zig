const std = @import("std");

const common = @import("common.zig");
const rom = @import("rom.zig");

pub const offsets = @import("gen4/offsets.zig");
pub const script = @import("gen4/script.zig");

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
        std.debug.assert(@sizeOf(@This()) == 8);
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
    gender_ability: GenderAbilityPair, // 4 msb are gender, 4 lsb are ability
    level: lu16,
    species: lu16,

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
        species: lu16,
        pad2: [2]u8,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 8);
        }
    };

    pub const Sea = extern struct {
        max_level: u8,
        min_level: u8,
        pad1: [2]u8,
        species: lu16,
        pad2: [2]u8,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 8);
        }
    };

    pub const Replacement = extern struct {
        species: lu16,
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

    comptime {
        std.debug.assert(@sizeOf(@This()) == 196);
    }

    pub const Sea = extern struct {
        min_level: u8,
        max_level: u8,
        species: lu16,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 4);
        }
    };
};

const GivenItem = struct {
    item: *lu16,
    amount: *lu16,
};

pub const Game = struct {
    version: common.Version,
    allocator: *mem.Allocator,

    starters: [3]*lu16,
    pokemons: *const nds.fs.Narc,
    evolutions: *const nds.fs.Narc,
    moves: *const nds.fs.Narc,
    level_up_moves: *const nds.fs.Narc,
    trainers: *const nds.fs.Narc,
    parties: *const nds.fs.Narc,
    wild_pokemons: *const nds.fs.Narc,
    scripts: *const nds.fs.Narc,
    tms: []lu16,
    hms: []lu16,
    static_pokemons: []*script.Command,
    given_items: []GivenItem,

    pub fn fromRom(allocator: *mem.Allocator, nds_rom: nds.Rom) !Game {
        const info = try getInfo(nds_rom.header.game_title, nds_rom.header.gamecode);
        const hm_tm_prefix_index = mem.indexOf(u8, nds_rom.arm9, info.hm_tm_prefix) orelse return error.CouldNotFindTmsOrHms;
        const hm_tm_index = hm_tm_prefix_index + info.hm_tm_prefix.len;
        const hm_tms_len = (offsets.tm_count + offsets.hm_count) * @sizeOf(u16);
        const hm_tms = @bytesToSlice(lu16, nds_rom.arm9[hm_tm_index..][0..hm_tms_len]);

        const scripts = try getNarc(nds_rom.root, info.scripts);
        const commands = try findScriptCommands(info.version, scripts, allocator);
        errdefer {
            allocator.free(commands.static_pokemons);
            allocator.free(commands.given_items);
        }

        return Game{
            .version = info.version,
            .allocator = allocator,

            .starters = switch (info.starters) {
                .Arm9 => |offset| blk: {
                    if (nds_rom.arm9.len < offset + offsets.starters_len)
                        return error.CouldNotFindStarters;
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
            .scripts = scripts,
            .tms = hm_tms[0..92],
            .hms = hm_tms[92..],
            .static_pokemons = commands.static_pokemons,
            .given_items = commands.given_items,
        };
    }

    pub fn deinit(game: Game) void {
        game.allocator.free(game.static_pokemons);
        game.allocator.free(game.given_items);
    }

    const ScriptCommands = struct {
        static_pokemons: []*script.Command,
        given_items: []GivenItem,
    };

    fn findScriptCommands(version: common.Version, scripts: *const nds.fs.Narc, allocator: *mem.Allocator) !ScriptCommands {
        if (version == .HeartGold or version == .SoulSilver) {
            // We don't support decoding scripts for hg/ss yet.
            return ScriptCommands{
                .static_pokemons = ([*]*script.Command)(undefined)[0..0],
                .given_items = ([*]GivenItem)(undefined)[0..0],
            };
        }

        var static_pokemons = std.ArrayList(*script.Command).init(allocator);
        errdefer static_pokemons.deinit();
        var given_items = std.ArrayList(GivenItem).init(allocator);
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

            // The variable 0x8008 is the variables that stores items given
            // from Pokéballs.
            var Var_8008: ?*lu16 = null;

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
                    // If we hit var 0x8008, the Var_8008_tmp will be set and
                    // Var_8008 will become Var_8008_tmp. Then the next iteration
                    // of this loop will set Var_8008 to null again. This allows us
                    // to store this state for only the next iteration of the loop.
                    var Var_8008_tmp: ?*lu16 = null;
                    defer Var_8008 = Var_8008_tmp;

                    switch (command.tag) {
                        .WildBattle,
                        .WildBattle2,
                        .WildBattle3,
                        => try static_pokemons.append(command),

                        // In scripts, field items are two SetVar commands
                        // followed by a jump to the code that gives this item:
                        //   SetVar 0x8008 // Item given
                        //   SetVar 0x8009 // Amount of items
                        //   Jump ???
                        .SetVar => switch (command.data.SetVar.destination.value()) {
                            0x8008 => Var_8008_tmp = &command.data.SetVar.value,
                            0x8009 => if (Var_8008) |item| {
                                const amount = &command.data.SetVar.value;
                                try given_items.append(GivenItem{
                                    .item = item,
                                    .amount = amount,
                                });
                            },
                            else => {},
                        },
                        .Jump => {
                            const off = command.data.Jump.adr.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .CompareLastResultJump => {
                            const off = command.data.CompareLastResultJump.adr.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .Call => {
                            const off = command.data.Call.adr.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .CompareLastResultCall => {
                            const off = command.data.CompareLastResultCall.adr.value();
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
