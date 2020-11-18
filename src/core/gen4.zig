const std = @import("std");

const common = @import("common.zig");
const rom = @import("rom.zig");

pub const encodings = @import("gen4/encodings.zig");
pub const offsets = @import("gen4/offsets.zig");
pub const script = @import("gen4/script.zig");

comptime {
    _ = encodings;
}

const debug = std.debug;
const io = std.io;
const math = std.math;
const mem = std.mem;

const nds = rom.nds;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu128 = rom.int.lu128;

pub const BasePokemon = extern struct {
    stats: common.Stats,
    types: [2]u8,

    catch_rate: u8,
    base_exp_yield: u8,

    ev_yield: common.EvYield,
    items: [2]lu16,

    gender_ratio: u8,
    egg_cycles: u8,
    base_friendship: u8,
    growth_rate: common.GrowthRate,
    egg_groups: [2]common.EggGroup,

    abilities: [2]u8,
    flee_rate: u8,

    color: common.Color,
    unknown: [2]u8,

    // Memory layout
    // TMS 01-92, HMS 01-08
    machine_learnset: lu128,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 44);
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

pub const EvolutionTable = extern struct {
    items: [7]Evolution,
    terminator: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 44);
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
    iv: u8 = 0,
    gender_ability: GenderAbilityPair = GenderAbilityPair{},
    level: lu16 = lu16.init(0),
    species: lu16 = lu16.init(0),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
    }

    pub const GenderAbilityPair = packed struct {
        gender: u4 = 0,
        ability: u4 = 0,
    };

    pub fn toParent(base: *PartyMemberBase, comptime Parent: type) *Parent {
        return @fieldParentPtr(Parent, "base", base);
    }
};

pub const PartyMemberNone = extern struct {
    base: PartyMemberBase = PartyMemberBase{},

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
    }
};

pub const PartyMemberItem = extern struct {
    base: PartyMemberBase = PartyMemberBase{},
    item: lu16 = lu16.init(0),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const PartyMemberMoves = extern struct {
    base: PartyMemberBase = PartyMemberBase{},
    moves: [4]lu16 = [_]lu16{lu16.init(0)} ** 4,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 14);
    }
};

pub const PartyMemberBoth = extern struct {
    base: PartyMemberBase = PartyMemberBase{},
    item: lu16 = lu16.init(0),
    moves: [4]lu16 = [_]lu16{lu16.init(0)} ** 4,

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
    pad: [3]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 20);
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

        return &mem.bytesAsSlice(PartyMemberBase, party[start..][0..@sizeOf(PartyMemberBase)])[0];
    }
};

// TODO: This is the first data structure I had to decode from scratch as I couldn't find a proper
//       resource for it... Fill it out!
pub const Move = extern struct {
    u8_0: u8,
    u8_1: u8,
    category: common.MoveCategory,
    power: u8,
    type: u8,
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

    pub const term = LevelUpMove{
        .id = math.maxInt(u9),
        .level = math.maxInt(u7),
    };

    comptime {
        std.debug.assert(@sizeOf(@This()) == 2);
    }
};

pub const DpptWildPokemons = extern struct {
    grass_rate: lu32,
    grass: [12]Grass,
    swarm_replace: [2]Replacement, // Replaces grass[0, 1]
    day_replace: [2]Replacement, // Replaces grass[2, 3]
    night_replace: [2]Replacement, // Replaces grass[2, 3]
    radar_replace: [4]Replacement, // Replaces grass[4, 5, 10, 11]
    unknown_replace: [6]Replacement, // ???
    gba_replace: [10]Replacement, // Each even replaces grass[8], each uneven replaces grass[9]

    surf: Sea,
    sea_unknown: Sea,
    old_rod: Sea,
    good_rod: Sea,
    super_rod: Sea,

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
        rate: lu32,
        mons: [5]SeaMon,
    };

    pub const SeaMon = extern struct {
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

pub const Pocket = packed enum(u4) {
    items = 0x00,
    tms_hms = 0x01,
    berries = 0x02,
    key_items = 0x03,
    balls = 0x09,
    _,
};

// https://github.com/projectpokemon/PPRE/blob/master/pokemon/itemtool/itemdata.py
pub const Item = packed struct {
    price: lu16,
    battle_effect: u8,
    gain: u8,
    berry: u8,
    fling_effect: u8,
    fling_power: u8,
    natural_gift_power: u8,
    flag: u8,
    pocket: Pocket,
    unknown: u4,
    type: u8,
    category: u8,
    category2: lu16,
    index: u8,
    statboosts: Boost,
    ev_yield: common.EvYield,
    hp_restore: u8,
    pp_restore: u8,
    happy1: u8,
    happy2: u8,
    happy3: u8,
    padding1: u8,
    padding2: u8,
    padding3: u8,
    padding4: u8,
    padding5: u8,
    padding6: u8,
    padding7: u8,
    padding8: u8,

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

    comptime {
        std.debug.assert(@sizeOf(@This()) == 36);
    }
};

pub const MapHeader = extern struct {
    unknown00: u8,
    unknown01: u8,
    unknown02: u8,
    unknown03: u8,
    unknown04: u8,
    unknown05: u8,
    unknown06: u8,
    unknown07: u8,
    unknown08: u8,
    unknown09: u8,
    unknown0a: u8,
    unknown0b: u8,
    unknown0c: u8,
    unknown0d: u8,
    unknown0e: u8,
    unknown0f: u8,
    unknown10: u8,
    unknown11: u8,
    unknown12: u8,
    unknown13: u8,
    unknown14: u8,
    unknown15: u8,
    unknown16: u8,
    unknown17: u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 24);
    }
};

const StaticPokemon = struct {
    species: *lu16,
    level: *lu16,
};

const PokeballItem = struct {
    item: *lu16,
    amount: *lu16,
};

pub const EncryptedStringTable = struct {
    data: []u8,

    pub fn count(table: EncryptedStringTable) u16 {
        return table.header().count.value();
    }

    pub fn getEncryptedString(table: EncryptedStringTable, i: u32) []lu16 {
        const key = @truncate(u16, @as(u32, table.header().key.value()) * 0x2FD);
        const encrypted_slice = table.slices()[i];
        const slice = decryptSlice(key, i, encrypted_slice);
        const res = table.data[slice.start.value()..][0 .. slice.len.value() * @sizeOf(lu16)];
        return mem.bytesAsSlice(lu16, res);
    }

    const Header = packed struct {
        count: lu16,
        key: lu16,
    };

    fn header(table: EncryptedStringTable) *Header {
        return @ptrCast(*Header, table.data[0..@sizeOf(Header)]);
    }

    fn slices(table: EncryptedStringTable) []nds.Slice {
        const data = table.data[@sizeOf(Header)..][0 .. table.count() * @sizeOf(nds.Slice)];
        return mem.bytesAsSlice(nds.Slice, data);
    }

    fn decryptSlice(key: u16, i: u32, slice: nds.Slice) nds.Slice {
        const key2 = (@as(u32, key) * (i + 1)) & 0xFFFF;
        const key3 = key2 | (key2 << 16);
        return nds.Slice.init(slice.start.value() ^ key3, slice.len.value() ^ key3);
    }

    fn size(strings: u32, chars: u32) u32 {
        return @sizeOf(Header) + // Header
            @sizeOf(nds.Slice) * strings + // String offsets
            strings * @sizeOf(lu16) + // String terminators
            chars * @sizeOf(lu16); // String chars
    }
};

fn decryptAndDecode(data: []const lu16, key: u16, out: anytype) !void {
    const H = struct {
        fn output(out2: anytype, char: u16) !bool {
            if (char == 0xffff)
                return true;
            return false;
        }
    };

    const first = decryptChar(key, @intCast(u32, 0), data[0].value());
    const compressed = first == 0xF100;
    const start = @boolToInt(compressed);

    var bits: u5 = 0;
    var container: u32 = 0;
    for (data[start..]) |c, i| {
        const decoded = decryptChar(key, @intCast(u32, i + start), c.value());
        if (compressed) {
            container |= @as(u32, decoded) << bits;
            bits += 16;

            while (bits >= 9) : (bits -= 9) {
                const char = @intCast(u16, container & 0x1FF);
                if (char == 0x1Ff)
                    return;
                try encodings.decode2(&@bitCast([2]u8, lu16.init(char)), out);
                container >>= 9;
            }
        } else {
            if (decoded == 0xffff)
                return;
            try encodings.decode2(&@bitCast([2]u8, lu16.init(decoded)), out);
        }
    }
}

fn encrypt(data: []lu16, key: u16) void {
    for (data) |*c, i|
        c.* = lu16.init(decryptChar(key, @intCast(u32, i), c.value()));
}

fn decryptChar(key: u16, i: u32, char: u16) u16 {
    return char ^ @truncate(u16, key + i * 0x493D);
}

fn getKey(i: u32) u16 {
    return @truncate(u16, 0x91BD3 * (i + 1));
}

pub fn String(comptime len: usize) type {
    return struct {
        buf: [len]u8 = [_]u8{0} ** len,

        pub fn span(str: *const @This()) []const u8 {
            const end = mem.indexOfScalar(u8, &str.buf, 0) orelse len;
            return str.buf[0..end];
        }
    };
}

pub const Game = struct {
    info: offsets.Info,
    allocator: *mem.Allocator,
    rom: *nds.Rom,
    owned: Owned,
    ptrs: Pointers,

    // These fields are owned by the game and will be applied to
    // the rom oppon calling `apply`.
    pub const Owned = struct {
        arm9: []u8,
        trainer_parties: [][6]PartyMemberBoth,
        type_names: []String(16),
        pokemon_names: []String(16),
        //trainer_names: []String(32),
        move_names: []String(16),
        ability_names: []String(16),
        item_names: []String(16),
        item_descriptions: []String(128),
        move_descriptions: []String(256),

        pub fn deinit(owned: Owned, allocator: *mem.Allocator) void {
            allocator.free(owned.arm9);
            allocator.free(owned.trainer_parties);
            allocator.free(owned.pokemon_names);
            //allocator.free(owned.trainer_names);
            allocator.free(owned.move_names);
            allocator.free(owned.move_descriptions);
            allocator.free(owned.ability_names);
            allocator.free(owned.item_names);
            allocator.free(owned.item_descriptions);
            allocator.free(owned.type_names);
        }
    };

    // The fields below are pointers into the nds rom and will
    // be invalidated oppon calling `apply`.
    pub const Pointers = struct {
        starters: [3]*lu16,
        pokemons: []BasePokemon,
        moves: []Move,
        trainers: []Trainer,
        wild_pokemons: union {
            dppt: []DpptWildPokemons,
            hgss: []HgssWildPokemons,
        },
        items: []Item,
        tms: []lu16,
        hms: []lu16,
        evolutions: []EvolutionTable,

        level_up_moves: nds.fs.Fs,

        pokedex: nds.fs.Fs,
        pokedex_heights: []lu32,
        pokedex_weights: []lu32,
        species_to_national_dex: []lu16,

        scripts: nds.fs.Fs,
        static_pokemons: []StaticPokemon,
        given_pokemons: []StaticPokemon,
        pokeball_items: []PokeballItem,

        pub fn deinit(ptrs: Pointers, allocator: *mem.Allocator) void {
            allocator.free(ptrs.static_pokemons);
            allocator.free(ptrs.given_pokemons);
            allocator.free(ptrs.pokeball_items);
        }
    };

    pub fn identify(reader: anytype) !offsets.Info {
        const header = try reader.readStruct(nds.Header);
        for (offsets.infos) |info| {
            //if (!mem.eql(u8, info.game_title, game_title))
            //    continue;
            if (!mem.eql(u8, &info.gamecode, &header.gamecode))
                continue;

            return info;
        }

        return error.UnknownGame;
    }

    pub fn fromRom(allocator: *mem.Allocator, nds_rom: *nds.Rom) !Game {
        const info = try identify(io.fixedBufferStream(nds_rom.data.items).reader());
        const arm9 = try nds_rom.getDecodedArm9(allocator);
        const file_system = nds_rom.fileSystem();

        const trainers = try (try file_system.getNarc(info.trainers)).toSlice(0, Trainer);
        const trainer_parties_narc = try file_system.getNarc(info.parties);
        const trainer_parties = try allocator.alloc([6]PartyMemberBoth, trainer_parties_narc.fat.len);
        mem.set([6]PartyMemberBoth, trainer_parties, [_]PartyMemberBoth{.{}} ** 6);

        for (trainer_parties) |*party, i| {
            const party_data = trainer_parties_narc.fileData(.{ .i = @intCast(u32, i) });
            const party_size = if (i < trainers.len) trainers[i].party_size else 0;

            var j: usize = 0;
            while (j < party_size) : (j += 1) {
                const base = trainers[i].partyMember(info.version, party_data, j) orelse break;
                party[j].base = base.*;

                switch (trainers[i].party_type) {
                    .none => {},
                    .item => party[j].item = base.toParent(PartyMemberItem).item,
                    .moves => party[j].moves = base.toParent(PartyMemberMoves).moves,
                    .both => {
                        const member = base.toParent(PartyMemberBoth);
                        party[j].item = member.item;
                        party[j].moves = member.moves;
                    },
                }
            }
        }

        const text = try file_system.getNarc(info.text);
        const type_names = try decryptStringTable(16, allocator, text, info.type_names);
        errdefer allocator.free(type_names);
        const pokemon_names = try decryptStringTable(16, allocator, text, info.pokemon_names);
        errdefer allocator.free(pokemon_names);
        const item_names = try decryptStringTable(16, allocator, text, info.item_names);
        errdefer allocator.free(item_names);
        const ability_names = try decryptStringTable(16, allocator, text, info.ability_names);
        errdefer allocator.free(ability_names);
        const move_names = try decryptStringTable(16, allocator, text, info.move_names);
        errdefer allocator.free(move_names);
        //const trainer_names = try decryptStringTable(32, allocator, text, info.trainer_names);
        //errdefer allocator.free(trainer_names);
        const item_descriptions = try decryptStringTable(128, allocator, text, info.item_descriptions);
        errdefer allocator.free(item_descriptions);
        const move_descriptions = try decryptStringTable(256, allocator, text, info.move_descriptions);
        errdefer allocator.free(move_descriptions);
        return fromRomEx(allocator, nds_rom, info, .{
            .arm9 = arm9,
            .trainer_parties = trainer_parties,
            .type_names = type_names,
            .item_descriptions = item_descriptions,
            .item_names = item_names,
            .ability_names = ability_names,
            .move_descriptions = move_descriptions,
            .move_names = move_names,
            //.trainer_names = trainer_names,
            .pokemon_names = pokemon_names,
        });
    }

    pub fn fromRomEx(
        allocator: *mem.Allocator,
        nds_rom: *nds.Rom,
        info: offsets.Info,
        owned: Owned,
    ) !Game {
        const file_system = nds_rom.fileSystem();
        const arm9_overlay_table = nds_rom.arm9OverlayTable();

        const hm_tm_prefix_index = mem.indexOf(u8, owned.arm9, info.hm_tm_prefix) orelse return error.CouldNotFindTmsOrHms;
        const hm_tm_index = hm_tm_prefix_index + info.hm_tm_prefix.len;
        const hm_tms_len = (offsets.tm_count + offsets.hm_count) * @sizeOf(u16);
        const hm_tms = mem.bytesAsSlice(lu16, owned.arm9[hm_tm_index..][0..hm_tms_len]);

        const text = try file_system.getNarc(info.text);
        const scripts = try file_system.getNarc(info.scripts);
        const pokedex = try file_system.getNarc(info.pokedex);
        const commands = try findScriptCommands(info.version, scripts, allocator);
        errdefer {
            allocator.free(commands.static_pokemons);
            allocator.free(commands.given_pokemons);
            allocator.free(commands.pokeball_items);
        }

        return Game{
            .info = info,
            .allocator = allocator,
            .rom = nds_rom,
            .owned = owned,
            .ptrs = .{
                .starters = switch (info.starters) {
                    .arm9 => |offset| blk: {
                        if (owned.arm9.len < offset + offsets.starters_len)
                            return error.CouldNotFindStarters;
                        const starters_section = mem.bytesAsSlice(lu16, owned.arm9[offset..][0..offsets.starters_len]);
                        break :blk [_]*lu16{
                            &starters_section[0],
                            &starters_section[2],
                            &starters_section[4],
                        };
                    },
                    .overlay9 => |overlay| blk: {
                        const overlay_entry = arm9_overlay_table[overlay.file];
                        const fat_entry = file_system.fat[overlay_entry.file_id.value()];
                        const file_data = file_system.data[fat_entry.start.value()..fat_entry.end.value()];
                        const starters_section = mem.bytesAsSlice(lu16, file_data[overlay.offset..][0..offsets.starters_len]);
                        break :blk [_]*lu16{
                            &starters_section[0],
                            &starters_section[2],
                            &starters_section[4],
                        };
                    },
                },
                .pokemons = try (try file_system.getNarc(info.pokemons)).toSlice(0, BasePokemon),
                .moves = try (try file_system.getNarc(info.moves)).toSlice(0, Move),
                .trainers = try (try file_system.getNarc(info.trainers)).toSlice(0, Trainer),
                .items = try (try file_system.getNarc(info.itemdata)).toSlice(0, Item),
                .evolutions = try (try file_system.getNarc(info.evolutions)).toSlice(0, EvolutionTable),
                .wild_pokemons = blk: {
                    const narc = try file_system.getNarc(info.wild_pokemons);
                    switch (info.version) {
                        .diamond,
                        .pearl,
                        .platinum,
                        => break :blk .{ .dppt = try narc.toSlice(0, DpptWildPokemons) },
                        .heart_gold,
                        .soul_silver,
                        => break :blk .{ .hgss = try narc.toSlice(0, HgssWildPokemons) },
                        else => unreachable,
                    }
                },
                .tms = hm_tms[0..92],
                .hms = hm_tms[92..],

                .level_up_moves = try file_system.getNarc(info.level_up_moves),

                .pokedex = pokedex,
                .pokedex_heights = mem.bytesAsSlice(lu32, pokedex.fileData(.{ .i = info.pokedex_heights })),
                .pokedex_weights = mem.bytesAsSlice(lu32, pokedex.fileData(.{ .i = info.pokedex_weights })),
                .species_to_national_dex = mem.bytesAsSlice(lu16, pokedex.fileData(.{ .i = info.species_to_national_dex })),

                .scripts = scripts,
                .static_pokemons = commands.static_pokemons,
                .given_pokemons = commands.given_pokemons,
                .pokeball_items = commands.pokeball_items,
            },
        };
    }

    pub fn apply(game: *Game) !void {
        mem.copy(
            u8,
            try game.rom.resizeSection(game.rom.arm9(), game.owned.arm9.len),
            game.owned.arm9,
        );
        try game.applyTrainerParties();
        try game.applyStrings();
        game.ptrs.deinit(game.allocator);

        game.* = try fromRomEx(
            game.allocator,
            game.rom,
            game.info,
            game.owned,
        );
    }

    fn applyTrainerParties(game: Game) !void {
        const allocator = game.allocator;
        const file_system = game.rom.fileSystem();
        const trainer_parties_narc = try file_system.openFileData(nds.fs.root, game.info.parties);
        const trainer_parties = game.owned.trainer_parties;

        const content_size = @sizeOf([6]HgSsPlatMember(PartyMemberBoth)) *
            trainer_parties.len;
        const size = nds.fs.narcSize(trainer_parties.len, content_size);

        const buf = try game.rom.resizeSection(trainer_parties_narc, size);
        const trainers = try (try file_system.getNarc(game.info.trainers)).toSlice(0, Trainer);

        var builder = nds.fs.SimpleNarcBuilder.init(
            buf,
            trainer_parties.len,
        );
        const fat = builder.fat();
        const writer = builder.stream.writer();
        const files_offset = builder.stream.pos;

        for (trainer_parties) |party, i| {
            const party_size = if (i < trainers.len) trainers[i].party_size else 0;
            const start = builder.stream.pos - files_offset;
            defer fat[i] = nds.Range.init(start, builder.stream.pos - files_offset);

            for (party[0..party_size]) |member| {
                switch (trainers[i].party_type) {
                    .none => writer.writeAll(&mem.toBytes(PartyMemberNone{
                        .base = member.base,
                    })) catch unreachable,
                    .item => writer.writeAll(&mem.toBytes(PartyMemberItem{
                        .base = member.base,
                        .item = member.item,
                    })) catch unreachable,
                    .moves => writer.writeAll(&mem.toBytes(PartyMemberMoves{
                        .base = member.base,
                        .moves = member.moves,
                    })) catch unreachable,
                    .both => writer.writeAll(&mem.toBytes(member)) catch unreachable,
                }
                // Write padding
                switch (game.info.version) {
                    .diamond, .pearl => {},

                    .platinum,
                    .heart_gold,
                    .soul_silver,
                    => writer.writeAll("\x00\x00") catch unreachable,

                    else => unreachable,
                }
            }

            const len = (builder.stream.pos - files_offset) - start;
            writer.writeByteNTimes(
                0,
                @sizeOf([6]HgSsPlatMember(PartyMemberBoth)) - len,
            ) catch unreachable;
        }

        _ = builder.finish();
    }

    /// Applies all decrypted strings to the game.
    fn applyStrings(game: Game) !void {
        // First, we construct an array of all tables we have decrypted. We do
        // this to avoid code duplication in many cases. This table type erases
        // the tables.
        const allocator = game.allocator;
        const info = game.info;
        const StringTable = struct {
            file: u16,
            chars: u32,
            elem_size: u32,
            slice: []const u8,
            getter: fn ([]const u8) []const u8,

            fn init(file: u16, comptime l: u32, strs: []const String(l)) @This() {
                const S = String(l);
                const slice = mem.sliceAsBytes(strs);
                debug.assert(strs.len * @sizeOf(S) == slice.len);
                return .{
                    .file = file,
                    .chars = l,
                    .elem_size = @sizeOf(S),
                    .slice = slice,
                    .getter = struct {
                        fn getter(buf: []const u8) []const u8 {
                            debug.assert(buf.len == @sizeOf(S));
                            const unaligned = mem.bytesAsValue(S, buf[0..@sizeOf(S)]);
                            const str = @alignCast(@alignOf(S), unaligned);
                            return str.span();
                        }
                    }.getter,
                };
            }

            fn len(table: @This()) u16 {
                return @intCast(u16, table.slice.len / table.elem_size);
            }

            fn at(table: @This(), i: usize) []const u8 {
                const rest = table.slice[i * table.elem_size ..];
                return table.getter(rest[0..table.elem_size]);
            }
        };
        const tables = [_]StringTable{
            StringTable.init(info.type_names, 16, game.owned.type_names),
            StringTable.init(info.pokemon_names, 16, game.owned.pokemon_names),
            StringTable.init(info.item_names, 16, game.owned.item_names),
            StringTable.init(info.ability_names, 16, game.owned.ability_names),
            StringTable.init(info.move_names, 16, game.owned.move_names),
            //StringTable.init(info.trainer_names, 32, game.owned.trainer_names),
            StringTable.init(info.item_descriptions, 128, game.owned.item_descriptions),
            StringTable.init(info.move_descriptions, 256, game.owned.move_descriptions),
        };

        const file_system = game.rom.fileSystem();
        const old_text_bytes = try file_system.openFileData(nds.fs.root, game.info.text);
        const old_text = try nds.fs.Fs.fromNarc(old_text_bytes);

        // We then calculate the size of the content for our new narc
        var extra_bytes: usize = 0;
        for (tables) |table| {
            extra_bytes += math.sub(
                u32,
                EncryptedStringTable.size(
                    table.len(),
                    table.chars * table.len(),
                ),
                old_text.fat[table.file].len(),
            ) catch 0;
        }

        const buf = try game.rom.resizeSection(old_text_bytes, old_text_bytes.len + extra_bytes);
        const text = try nds.fs.Fs.fromNarc(buf);

        // First, resize all tables that need a resize
        for (tables) |table, i| {
            const Header = EncryptedStringTable.Header;
            const file_size = EncryptedStringTable.size(
                table.len(),
                table.chars * table.len(),
            );

            const file = text.fat[table.file];
            if (file.len() < file_size) {
                const extra = file_size - file.len();
                mem.copyBackwards(
                    u8,
                    text.data[file.end.value() + extra ..],
                    text.data[file.end.value() .. text.data.len - extra],
                );
                for (text.fat) |*f| {
                    const start = f.start.value();
                    const end = f.end.value();
                    f.* = nds.Range.init(
                        start + extra * @boolToInt(start >= file.end.value()),
                        end + extra * @boolToInt(start >= file.end.value()) +
                            extra * @boolToInt(start == file.start.value() and
                            end == file.end.value()),
                    );
                }
            }
        }

        for (tables) |table, i| {
            const Header = EncryptedStringTable.Header;
            const file_size = EncryptedStringTable.size(
                table.len(),
                table.chars * table.len(),
            );
            const file = text.fat[table.file];
            const bytes = text.data[file.start.value()..file.end.value()];

            // TODO: we don't need a writer
            const writer = io.fixedBufferStream(bytes).writer();
            debug.assert(bytes.len == file_size);

            const string_size = table.chars + 1; // Always make room for a terminator
            try writer.writeAll(&mem.toBytes(Header{
                .count = lu16.init(table.len()),
                .key = lu16.init(0),
            }));

            const slices_start = writer.context.pos;
            for (@as([*]void, undefined)[0..table.len()]) |_, j| {
                try writer.writeAll(&mem.toBytes(nds.Slice{
                    .start = lu32.init(0),
                    .len = lu32.init(0),
                }));
            }

            const slices = mem.bytesAsSlice(nds.Slice, bytes[slices_start..writer.context.pos]);
            for (slices) |*slice, j| {
                const pos = writer.context.pos;
                const str = table.at(j);
                try encodings.encode(str, writer);
                try writer.writeAll("\xff\xff");

                const str_end = writer.context.pos;
                const encoded_str = mem.bytesAsSlice(lu16, bytes[pos..str_end]);
                encrypt(encoded_str, getKey(@intCast(u32, j)));

                const str_len = @intCast(u16, (str_end - pos) / 2);
                slice.start = lu32.init(@intCast(u32, pos));
                slice.len = lu32.init(str_len);

                // Pad the string, so that each entry is always entry_size
                // apart. This ensure that patches generated from tm35-apply
                // are small.
                try writer.writeByteNTimes(0, (string_size - str_len) * 2);
                debug.assert(writer.context.pos - pos == string_size * 2);
            }

            // Assert that we got the file size right.
            debug.assert(writer.context.pos == bytes.len);
        }
    }
    pub fn deinit(game: Game) void {
        game.owned.deinit(game.allocator);
        game.ptrs.deinit(game.allocator);
    }

    const ScriptCommands = struct {
        static_pokemons: []StaticPokemon,
        given_pokemons: []StaticPokemon,
        pokeball_items: []PokeballItem,
    };

    fn findScriptCommands(version: common.Version, scripts: nds.fs.Fs, allocator: *mem.Allocator) !ScriptCommands {
        if (version == .heart_gold or version == .soul_silver) {
            // We don't support decoding scripts for hg/ss yet.
            return ScriptCommands{
                .static_pokemons = &[_]StaticPokemon{},
                .given_pokemons = &[_]StaticPokemon{},
                .pokeball_items = &[_]PokeballItem{},
            };
        }

        var static_pokemons = std.ArrayList(StaticPokemon).init(allocator);
        errdefer static_pokemons.deinit();
        var given_pokemons = std.ArrayList(StaticPokemon).init(allocator);
        errdefer given_pokemons.deinit();
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
            var var_8008: ?*lu16 = null;

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
                    // If we hit var 0x8008, the var_8008_tmp will be set and
                    // Var_8008 will become var_8008_tmp. Then the next iteration
                    // of this loop will set var_8008 to null again. This allows us
                    // to store this state for only the next iteration of the loop.
                    var var_8008_tmp: ?*lu16 = null;
                    defer var_8008 = var_8008_tmp;

                    switch (command.tag) {
                        .wild_battle => try static_pokemons.append(.{
                            .species = &command.data().wild_battle.species,
                            .level = &command.data().wild_battle.level,
                        }),
                        .wild_battle2 => try static_pokemons.append(.{
                            .species = &command.data().wild_battle2.species,
                            .level = &command.data().wild_battle2.level,
                        }),
                        .wild_battle3 => try static_pokemons.append(.{
                            .species = &command.data().wild_battle3.species,
                            .level = &command.data().wild_battle3.level,
                        }),
                        .give_pokemon => try given_pokemons.append(.{
                            .species = &command.data().give_pokemon.species,
                            .level = &command.data().give_pokemon.level,
                        }),

                        // In scripts, field items are two SetVar commands
                        // followed by a jump to the code that gives this item:
                        //   SetVar 0x8008 // Item given
                        //   SetVar 0x8009 // Amount of items
                        //   Jump ???
                        .set_var => switch (command.data().set_var.destination.value()) {
                            0x8008 => var_8008_tmp = &command.data().set_var.value,
                            0x8009 => if (var_8008) |item| {
                                const amount = &command.data().set_var.value;
                                try pokeball_items.append(PokeballItem{
                                    .item = item,
                                    .amount = amount,
                                });
                            },
                            else => {},
                        },
                        .jump, .compare_last_result_jump, .call, .compare_last_result_call => {
                            const off = switch (command.tag) {
                                .compare_last_result_call => command.data().compare_last_result_call.adr.value(),
                                .call => command.data().call.adr.value(),
                                .jump => command.data().jump.adr.value(),
                                .compare_last_result_jump => command.data().compare_last_result_jump.adr.value(),
                                else => unreachable,
                            };
                            const location = off + @intCast(isize, decoder.i);
                            if (mem.indexOfScalar(isize, script_offsets.items, location) == null)
                                try script_offsets.append(location);
                        },
                        else => {},
                    }
                }
            }
        }

        return ScriptCommands{
            .static_pokemons = static_pokemons.toOwnedSlice(),
            .given_pokemons = given_pokemons.toOwnedSlice(),
            .pokeball_items = pokeball_items.toOwnedSlice(),
        };
    }

    fn decryptStringTable(comptime len: usize, allocator: *mem.Allocator, text: nds.fs.Fs, file: u16) ![]String(len) {
        const table = EncryptedStringTable{ .data = text.fileData(.{ .i = file }) };
        const res = try allocator.alloc(String(len), table.count());
        errdefer allocator.free(res);

        mem.set(String(len), res, String(len){});
        for (res) |*str, i| {
            const id = @intCast(u32, i);
            const writer = io.fixedBufferStream(&str.buf).writer();
            const encrypted_string = table.getEncryptedString(id);
            try decryptAndDecode(encrypted_string, getKey(id), writer);
        }

        return res;
    }
};
