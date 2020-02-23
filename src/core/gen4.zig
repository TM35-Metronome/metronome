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
    none = 0b00,
    item = 0b10,
    moves = 0b01,
    both = 0b11,
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
            .diamond,
            .pearl,
            => switch (trainer.party_type) {
                .none => trainer.partyMemberHelper(party, @sizeOf(PartyMemberNone), i),
                .item => trainer.partyMemberHelper(party, @sizeOf(PartyMemberItem), i),
                .moves => trainer.partyMemberHelper(party, @sizeOf(PartyMemberMoves), i),
                .both => trainer.partyMemberHelper(party, @sizeOf(PartyMemberBoth), i),
            },

            .platinum,
            .heart_gold,
            .soul_silver,
            => switch (trainer.party_type) {
                .none => trainer.partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberNone)), i),
                .item => trainer.partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberItem)), i),
                .moves => trainer.partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberMoves)), i),
                .both => trainer.partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberBoth)), i),
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
    normal = 0x00,
    fighting = 0x01,
    flying = 0x02,
    poison = 0x03,
    ground = 0x04,
    rock = 0x05,
    bug = 0x06,
    ghost = 0x07,
    steel = 0x08,
    unknown = 0x09,
    fire = 0x0A,
    water = 0x0B,
    grass = 0x0C,
    electric = 0x0D,
    psychic = 0x0E,
    ice = 0x0F,
    dragon = 0x10,
    dark = 0x11,
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

pub const LevelUpMove = packed struct {
    id: u9,
    level: u7,

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

pub const Pocket = packed struct {
    pocket: PocketKind,
    unknown: u4,
};

pub const PocketKind = packed enum(u4) {
    items = 0x00,
    tm_hms = 0x01,
    berries = 0x02,
    key_items = 0x03,
    unknown_0x04 = 0x04,
    unknown_0x05 = 0x05,
    unknown_0x06 = 0x06,
    unknown_0x07 = 0x07,
    unknown_0x08 = 0x08,
    balls = 0x09,
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
    index: u8,
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

    starters: [3]*lu16,
    pokemons: *const nds.fs.Narc,
    evolutions: *const nds.fs.Narc,
    moves: *const nds.fs.Narc,
    level_up_moves: *const nds.fs.Narc,
    trainers: *const nds.fs.Narc,
    parties: *const nds.fs.Narc,
    wild_pokemons: *const nds.fs.Narc,
    itemdata: *const nds.fs.Narc,
    scripts: *const nds.fs.Narc,
    tms: []lu16,
    hms: []lu16,
    static_pokemons: []*script.Command,
    pokeball_items: []PokeballItem,

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
            allocator.free(commands.pokeball_items);
        }

        return Game{
            .version = info.version,
            .allocator = allocator,

            .starters = switch (info.starters) {
                .arm9 => |offset| blk: {
                    if (nds_rom.arm9.len < offset + offsets.starters_len)
                        return error.CouldNotFindStarters;
                    const starters_section = @bytesToSlice(lu16, nds_rom.arm9[offset..][0..offsets.starters_len]);
                    break :blk [_]*lu16{
                        &starters_section[0],
                        &starters_section[2],
                        &starters_section[4],
                    };
                },
                .overlay9 => |overlay| blk: {
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
            .itemdata = try getNarc(nds_rom.root, info.itemdata),
            .scripts = scripts,
            .tms = hm_tms[0..92],
            .hms = hm_tms[92..],
            .static_pokemons = commands.static_pokemons,
            .pokeball_items = commands.pokeball_items,
        };
    }

    pub fn deinit(game: Game) void {
        game.allocator.free(game.static_pokemons);
        game.allocator.free(game.pokeball_items);
    }

    const ScriptCommands = struct {
        static_pokemons: []*script.Command,
        pokeball_items: []PokeballItem,
    };

    fn findScriptCommands(version: common.Version, scripts: *const nds.fs.Narc, allocator: *mem.Allocator) !ScriptCommands {
        if (version == .heart_gold or version == .soul_silver) {
            // We don't support decoding scripts for hg/ss yet.
            return ScriptCommands{
                .static_pokemons = ([*]*script.Command)(undefined)[0..0],
                .pokeball_items = ([*]PokeballItem)(undefined)[0..0],
            };
        }

        var static_pokemons = std.ArrayList(*script.Command).init(allocator);
        errdefer static_pokemons.deinit();
        var pokeball_items = std.ArrayList(PokeballItem).init(allocator);
        errdefer pokeball_items.deinit();

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
            var var_8008: ?*lu16 = null;

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
                    // If we hit var 0x8008, the var_8008_tmp will be set and
                    // Var_8008 will become var_8008_tmp. Then the next iteration
                    // of this loop will set var_8008 to null again. This allows us
                    // to store this state for only the next iteration of the loop.
                    var var_8008_tmp: ?*lu16 = null;
                    defer var_8008 = var_8008_tmp;

                    switch (command.tag) {
                        .wild_battle,
                        .wild_battle2,
                        .wild_battle3,
                        => try static_pokemons.append(command),

                        // In scripts, field items are two SetVar commands
                        // followed by a jump to the code that gives this item:
                        //   SetVar 0x8008 // Item given
                        //   SetVar 0x8009 // Amount of items
                        //   Jump ???
                        .set_var => switch (command.data.set_var.destination.value()) {
                            0x8008 => var_8008_tmp = &command.data.set_var.value,
                            0x8009 => if (var_8008) |item| {
                                const amount = &command.data.set_var.value;
                                try pokeball_items.append(PokeballItem{
                                    .item = item,
                                    .amount = amount,
                                });
                            },
                            else => {},
                        },
                        .jump => {
                            const off = command.data.jump.adr.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .compare_last_result_jump => {
                            const off = command.data.compare_last_result_jump.adr.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .call => {
                            const off = command.data.call.adr.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .compare_last_result_call => {
                            const off = command.data.compare_last_result_call.adr.value();
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
        switch (file.*) {
            .binary => return error.FileNotNarc,
            .narc => |res| return res,
        }
    }
};
