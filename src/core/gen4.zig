const std = @import("std");

const common = @import("common.zig");
const rom = @import("rom.zig");

pub const encodings = @import("gen4/encodings.zig");
pub const offsets = @import("gen4/offsets.zig");
pub const script = @import("gen4/script.zig");

comptime {
    _ = encodings;
}

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

    egg_group1: common.EggGroup,
    egg_group2: common.EggGroup,

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

const PokeballItem = struct {
    item: *lu16,
    amount: *lu16,
};

pub const StringTable = struct {
    data: []u8,

    pub fn count(table: StringTable) u16 {
        return table.header().count.value();
    }

    pub fn getEncryptedString(table: StringTable, i: u32) []u8 {
        const key = @truncate(u16, @as(u32, table.header().key.value()) * 0x2FD);
        const encrypted_slice = table.slices()[i];
        const slice = decryptSlice(key, i, encrypted_slice);
        return table.data[slice.start.value()..][0 .. slice.len.value() * @sizeOf(lu16)];
    }

    pub fn getStringStream(table: StringTable, i: u32) Stream {
        const string = table.getEncryptedString(i);
        return .{
            .data = string,
            .key = @truncate(u16, 0x91BD3 * (i + 1)),
        };
    }

    const Header = packed struct {
        count: lu16,
        key: lu16,
    };

    fn header(table: StringTable) *Header {
        return @ptrCast(*Header, table.data[0..@sizeOf(Header)]);
    }

    fn slices(table: StringTable) []nds.Slice {
        const data = table.data[@sizeOf(Header)..][0 .. table.count() * @sizeOf(nds.Slice)];
        return mem.bytesAsSlice(nds.Slice, data);
    }

    fn decryptSlice(key: u16, i: u32, slice: nds.Slice) nds.Slice {
        const key2 = (@as(u32, key) * (i + 1)) & 0xFFFF;
        const key3 = key2 | (key2 << 16);
        return nds.Slice.init(slice.start.value() ^ key3, slice.len.value() ^ key3);
    }

    fn decryptChar(key: u16, i: u32, char: lu16) lu16 {
        const key2 = @truncate(u16, key + i * 0x493D);
        return lu16.init(char.value() ^ key2);
    }

    const Stream = struct {
        data: []u8,
        key: u16,
        pos: u32 = 0,

        pub const ReadError = error{};
        pub const WriteError = error{NoSpaceLeft};

        pub const InStream = io.InStream(*Stream, ReadError, read);
        pub const OutStream = io.OutStream(*Stream, WriteError, write);

        pub fn read(stream: *Stream, buf: []u8) ReadError!usize {
            const rest = stream.data[stream.pos..];
            const n = math.min(rest.len, buf.len) & (math.maxInt(usize) - 1);
            mem.copy(u8, buf[0..n], rest[0..n]);
            for (mem.bytesAsSlice(lu16, buf[0..n])) |*c, i|
                c.* = decryptChar(stream.key, (stream.pos / 2) + @intCast(u32, i), c.*);

            const end1 = mem.indexOf(u8, buf[0..n], "\xfe\xff") orelse n;
            const end2 = mem.indexOf(u8, buf[0..n], "\xff\xff") orelse n;
            const end = math.min(end1, end2);
            stream.pos += @intCast(u32, end);
            return end;
        }

        pub fn write(stream: *Stream, buf: []const u8) WriteError!usize {
            const rest = stream.data[stream.pos..];
            if (buf.len == 0)
                return 0;
            if (rest.len == 0)
                return error.NoSpaceLeft;

            const n = math.min(rest.len, buf.len) & (math.maxInt(usize) - 1);
            mem.copy(u8, rest[0..n], buf[0..n]);
            for (mem.bytesAsSlice(lu16, rest[0..n])) |*c, i|
                c.* = decryptChar(stream.key, (stream.pos / 2) + @intCast(u32, i), c.*);

            stream.pos += @intCast(u32, n);
            return n;
        }

        pub fn inStream(self: *Stream) InStream {
            return .{ .context = self };
        }

        pub fn outStream(self: *Stream) OutStream {
            return .{ .context = self };
        }
    };
};

pub const Game = struct {
    version: common.Version,
    allocator: *mem.Allocator,

    instant_text_patch: []const common.Patch,

    arm9: []u8,
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
    parties: nds.fs.Fs,

    pokedex: nds.fs.Fs,
    pokedex_heights: []lu32,
    pokedex_weights: []lu32,
    species_to_national_dex: []lu16,

    scripts: nds.fs.Fs,
    static_pokemons: []*script.Command,
    pokeball_items: []PokeballItem,

    text: nds.fs.Fs,
    pokemon_names: StringTable,
    trainer_names: StringTable,
    move_names: StringTable,
    move_descriptions: StringTable,
    ability_names: StringTable,
    item_names: StringTable,
    item_descriptions: StringTable,
    type_names: StringTable,

    pub fn identify(stream: var) !offsets.Info {
        const header = try stream.readStruct(nds.Header);
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
        const info = try identify(io.fixedBufferStream(nds_rom.data.items).inStream());

        try nds_rom.decodeArm9();
        const arm9 = nds_rom.arm9();
        const file_system = nds_rom.fileSystem();
        const arm9_overlay_table = nds_rom.arm9OverlayTable();

        const hm_tm_prefix_index = mem.indexOf(u8, arm9, info.hm_tm_prefix) orelse return error.CouldNotFindTmsOrHms;
        const hm_tm_index = hm_tm_prefix_index + info.hm_tm_prefix.len;
        const hm_tms_len = (offsets.tm_count + offsets.hm_count) * @sizeOf(u16);
        const hm_tms = mem.bytesAsSlice(lu16, arm9[hm_tm_index..][0..hm_tms_len]);

        const text = try getNarc(file_system, info.text);
        const scripts = try getNarc(file_system, info.scripts);
        const pokedex = try getNarc(file_system, info.pokedex);
        const commands = try findScriptCommands(info.version, scripts, allocator);
        errdefer {
            allocator.free(commands.static_pokemons);
            allocator.free(commands.pokeball_items);
        }

        return Game{
            .version = info.version,
            .allocator = allocator,
            .instant_text_patch = info.instant_text_patch,

            .arm9 = arm9,
            .starters = switch (info.starters) {
                .arm9 => |offset| blk: {
                    if (arm9.len < offset + offsets.starters_len)
                        return error.CouldNotFindStarters;
                    const starters_section = mem.bytesAsSlice(lu16, arm9[offset..][0..offsets.starters_len]);
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
            .pokemons = try (try getNarc(file_system, info.pokemons)).toSlice(0, BasePokemon),
            .moves = try (try getNarc(file_system, info.moves)).toSlice(0, Move),
            .trainers = try (try getNarc(file_system, info.trainers)).toSlice(0, Trainer),
            .items = try (try getNarc(file_system, info.itemdata)).toSlice(0, Item),
            .evolutions = try (try getNarc(file_system, info.evolutions)).toSlice(0, EvolutionTable),
            .wild_pokemons = blk: {
                const narc = try getNarc(file_system, info.wild_pokemons);
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

            .parties = try getNarc(file_system, info.parties),
            .level_up_moves = try getNarc(file_system, info.level_up_moves),

            .pokedex = pokedex,
            .pokedex_heights = mem.bytesAsSlice(lu32, pokedex.fileData(.{ .i = info.pokedex_heights })),
            .pokedex_weights = mem.bytesAsSlice(lu32, pokedex.fileData(.{ .i = info.pokedex_weights })),
            .species_to_national_dex = mem.bytesAsSlice(lu16, pokedex.fileData(.{ .i = info.species_to_national_dex })),

            .scripts = scripts,
            .static_pokemons = commands.static_pokemons,
            .pokeball_items = commands.pokeball_items,

            .text = text,
            .pokemon_names = StringTable{ .data = text.fileData(.{ .i = info.pokemon_names }) },
            .trainer_names = StringTable{ .data = text.fileData(.{ .i = info.trainer_names }) },
            .move_names = StringTable{ .data = text.fileData(.{ .i = info.move_names }) },
            .move_descriptions = StringTable{ .data = text.fileData(.{ .i = info.move_descriptions }) },
            .ability_names = StringTable{ .data = text.fileData(.{ .i = info.ability_names }) },
            .item_names = StringTable{ .data = text.fileData(.{ .i = info.item_names }) },
            .item_descriptions = StringTable{ .data = text.fileData(.{ .i = info.item_descriptions }) },
            .type_names = StringTable{ .data = text.fileData(.{ .i = info.type_names }) },
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

    fn findScriptCommands(version: common.Version, scripts: nds.fs.Fs, allocator: *mem.Allocator) !ScriptCommands {
        if (version == .heart_gold or version == .soul_silver) {
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
                        .wild_battle,
                        .wild_battle2,
                        .wild_battle3,
                        => try static_pokemons.append(command),

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
                        .jump => {
                            const off = command.data().jump.adr.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .compare_last_result_jump => {
                            const off = command.data().compare_last_result_jump.adr.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .call => {
                            const off = command.data().call.adr.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .compare_last_result_call => {
                            const off = command.data().compare_last_result_call.adr.value();
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

    fn getNarc(file_system: nds.fs.Fs, path: []const u8) !nds.fs.Fs {
        const file = try file_system.openFileData(nds.fs.root, path);
        return try nds.fs.Fs.fromNarc(file);
    }
};
