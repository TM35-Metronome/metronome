pub const Pokemon = extern struct {
    stats: common.Stats,
    types: [2]u8,

    catch_rate: u8,
    base_exp_yield: u8,

    ev: common.EvYield,
    items: [2]u16,

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
    machine_learnset: u128 align(4),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 44);
    }
};

pub const Evolution = extern struct {
    method: common.EvoMethod,
    padding: u8,
    param: u16,
    target: u16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
    }
};

pub const MoveTutor = extern struct {
    move: u16,
    cost: u8,
    tutor: u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 4);
    }
};

pub const PartyMemberBase = extern struct {
    iv: u8 = 0,
    gender_ability: GenderAbilityPair = GenderAbilityPair{},
    level: u16 = 0,
    species: u16 = 0,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
    }

    pub const GenderAbilityPair = packed struct {
        gender: u4 = 0,
        ability: u4 = 0,
    };

    pub fn toParent(base: *align(1) PartyMemberBase, comptime Parent: type) *align(1) Parent {
        return @ptrCast(base);
        // return @fieldParentPtr(Parent, "base", base);
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
    item: u16 = 0,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const PartyMemberMoves = extern struct {
    base: PartyMemberBase = PartyMemberBase{},
    moves: [4]u16 = [_]u16{0} ** 4,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 14);
    }
};

pub const PartyMemberBoth = extern struct {
    base: PartyMemberBase = PartyMemberBase{},
    item: u16 = 0,
    moves: [4]u16 = [_]u16{0} ** 4,

    pub fn ability(member: PartyMemberBoth) u8 {
        return member.base.gender_ability.ability;
    }

    pub fn setAbility(member: *PartyMemberBoth, a: u8) void {
        member.base.gender_ability.ability = @intCast(a);
    }

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const Party = struct {
    type: common.PartyType = .none,
    size: u8 = 0,
    members: [6]PartyMemberBoth = .{.{}} ** 6,
};

/// In HG/SS/Plat, this struct is always padded with a u16 at the end, no matter the party_type
pub fn HgSsPlatMember(comptime T: type) type {
    return extern struct {
        member: T,
        pad: u16,

        comptime {
            std.debug.assert(@sizeOf(@This()) == @sizeOf(T) + 2);
        }
    };
}

pub const Trainer = extern struct {
    party_type: common.PartyType,
    class: u8,
    battle_type: u8, // TODO: This should probably be an enum
    party_size: u8,
    items: [4]u16,
    ai: u32,
    battle_type2: u8,
    pad: [3]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 20);
    }

    pub fn partyMember(
        trainer: Trainer,
        version: common.Version,
        party: []u8,
        i: usize,
    ) ?*align(1) PartyMemberBase {
        return switch (version) {
            .diamond,
            .pearl,
            => switch (trainer.party_type) {
                .none => partyMemberHelper(party, @sizeOf(PartyMemberNone), i),
                .item => partyMemberHelper(party, @sizeOf(PartyMemberItem), i),
                .moves => partyMemberHelper(party, @sizeOf(PartyMemberMoves), i),
                .both => partyMemberHelper(party, @sizeOf(PartyMemberBoth), i),
            },

            .platinum,
            .heart_gold,
            .soul_silver,
            => switch (trainer.party_type) {
                .none => partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberNone)), i),
                .item => partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberItem)), i),
                .moves => partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberMoves)), i),
                .both => partyMemberHelper(party, @sizeOf(HgSsPlatMember(PartyMemberBoth)), i),
            },

            else => unreachable,
        };
    }

    fn partyMemberHelper(party: []u8, member_size: usize, i: usize) ?*align(1) PartyMemberBase {
        const start = i * member_size;
        const end = start + member_size;
        if (party.len < end)
            return null;

        return &std.mem.bytesAsSlice(PartyMemberBase, party[start..][0..@sizeOf(PartyMemberBase)])[0];
    }
};

// TODO: This is the first data structure I had to decode from scratch as I couldn't find a proper
//       resource for it... Fill it out!
pub const Move = extern struct {
    u8_0: u8,
    u8_1: u8,
    category: Category,
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

    pub const Category = enum(u8) {
        physical = 0x00,
        special = 0x01,
        status = 0x02,
    };

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const LevelUpMove = packed struct {
    id: u9,
    level: u7,

    pub const term = LevelUpMove{
        .id = std.math.maxInt(u9),
        .level = std.math.maxInt(u7),
    };

    comptime {
        std.debug.assert(@sizeOf(@This()) == 2);
    }
};

pub const WildPokemon = struct {
    m: struct {
        species: *align(1) u16,
        min_level: *align(1) u8,
        max_level: *align(1) u8,
    },

    pub fn species(pokemon: WildPokemon) u16 {
        return pokemon.m.species.*;
    }

    pub fn setSpecies(pokemon: WildPokemon, s: u16) void {
        pokemon.m.species.* = s;
    }

    pub fn level(pokemon: WildPokemon) u8 {
        return (pokemon.m.min_level.* + pokemon.m.max_level.*) / 2;
    }

    pub fn setLevel(pokemon: WildPokemon, l: u8) void {
        pokemon.m.min_level.* = l;
        pokemon.m.max_level.* = l;
    }
};

pub const DpptWildPokemons = extern struct {
    grass_rate: u32,
    grass: [12]Grass,
    replace: [2 + 2 + 2 + 4 + 6 + 10]Replacement,
    // swarm_replace: [2]Replacement, // Replaces grass[0, 1]
    // day_replace: [2]Replacement, // Replaces grass[2, 3]
    // night_replace: [2]Replacement, // Replaces grass[2, 3]
    // radar_replace: [4]Replacement, // Replaces grass[4, 5, 10, 11]
    // unknown_replace: [6]Replacement, // ???
    // gba_replace: [10]Replacement, // Each even replaces grass[8], each uneven replaces grass[9]

    sea: [5]Sea,
    // surf: Sea,
    // sea_unknown: Sea,
    // old_rod: Sea,
    // good_rod: Sea,
    // super_rod: Sea,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 424);
    }

    pub const Grass = extern struct {
        level: u8,
        pad1: [3]u8,
        species: u16,
        pad2: [2]u8,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 8);
        }
    };

    pub const Sea = extern struct {
        rate: u32,
        mons: [5]SeaMon,
    };

    pub const SeaMon = extern struct {
        max_level: u8,
        min_level: u8,
        pad1: [2]u8,
        species: u16,
        pad2: [2]u8,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 8);
        }
    };

    pub const Replacement = extern struct {
        species: u16,
        pad: [2]u8,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 4);
        }
    };
};

pub const HgssWildPokemons = extern struct {
    rates: [6]u8,
    // grass_rate: u8,
    // sea_rates: [5]u8,
    unknown: [2]u8,
    grass_levels: [12]u8,
    grass_morning: [12]u16,
    grass_day: [12]u16,
    grass_night: [12]u16,
    radio: [4]u16,

    sea: [5 + 2 + 5 + 5 + 5]Sea,
    // surf: [5]Sea,
    // sea_unknown: [2]Sea,
    // old_rod: [5]Sea,
    // good_rod: [5]Sea,
    // super_rod: [5]Sea,
    swarm: [4]u16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 196);
    }

    pub const Sea = extern struct {
        min_level: u8,
        max_level: u8,
        species: u16,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 4);
        }
    };
};

pub const Pocket = enum(u4) {
    items = 0x00,
    tms_hms = 0x01,
    berries = 0x02,
    key_items = 0x03,
    poke_balls = 0x09,
    _,
};

// https://github.com/projectpokemon/PPRE/blob/master/pokemon/itemtool/itemdata.py
pub const Item = extern struct {
    price: u16,
    battle_effect: common.ItemBattleEffect,
    gain: u8,
    berry: u8,
    fling_effect: u8,
    fling_power: u8,
    natural_gift_power: u8,
    flag: u8,
    _pocket: u8,
    unknown: [26]u8,

    pub fn pocket(item: Item) Pocket {
        return @enumFromInt(item._pocket & 0x0F);
    }

    pub fn setPocket(item: *align(1) Item, p: Pocket) void {
        item._pocket = (item._pocket & 0xf0) | @intFromEnum(p);
    }

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
    m: struct {
        species: *align(1) u16,
        level: *align(1) u16,
    },

    pub fn species(pokemon: StaticPokemon) u16 {
        return pokemon.m.species.*;
    }

    pub fn setSpecies(pokemon: *StaticPokemon, s: u16) void {
        pokemon.m.species.* = s;
    }

    pub fn level(pokemon: StaticPokemon) u8 {
        return pokemon.m.level.*;
    }

    pub fn setLevel(pokemon: *StaticPokemon, l: u8) void {
        pokemon.m.level.* = l;
    }
};

const PokeballItem = struct {
    item: *align(1) u16,
    amount: *align(1) u16,
};

pub const EncryptedStringTable = struct {
    data: []u8,

    pub fn count(table: EncryptedStringTable) u16 {
        return table.header().count;
    }

    pub fn getEncryptedString(table: EncryptedStringTable, i: u32) []align(1) u16 {
        const key: u16 = @truncate(@as(u32, table.header().key) * 0x2FD);
        const encrypted_slice = table.slices()[i];
        const slice = decryptSlice(key, i, encrypted_slice);
        const res = table.data[slice.start..][0 .. slice.len * @sizeOf(u16)];
        return std.mem.bytesAsSlice(u16, res);
    }

    const Header = packed struct {
        count: u16,
        key: u16,
    };

    fn header(table: EncryptedStringTable) *align(1) Header {
        return @ptrCast(table.data[0..@sizeOf(Header)]);
    }

    fn slices(table: EncryptedStringTable) []align(1) rom.nds.Slice {
        const data = table.data[@sizeOf(Header)..][0 .. table.count() * @sizeOf(rom.nds.Slice)];
        return std.mem.bytesAsSlice(rom.nds.Slice, data);
    }

    fn decryptSlice(key: u16, i: u32, slice: rom.nds.Slice) rom.nds.Slice {
        const key2 = (@as(u32, key) * (i + 1)) & 0xFFFF;
        const key3 = key2 | (key2 << 16);
        return rom.nds.Slice.init(slice.start ^ key3, slice.len ^ key3);
    }

    fn size(strings: u32, chars: u32) u32 {
        return @sizeOf(Header) + // Header
            @sizeOf(rom.nds.Slice) * strings + // String offsets
            strings * @sizeOf(u16) + // String terminators
            chars * @sizeOf(u16); // String chars
    }
};

fn decryptAndDecode(data: []align(1) const u16, key: u16, out: anytype) !void {
    const first = decryptChar(key, @intCast(0), data[0]);
    const compressed = first == 0xF100;
    const start = @intFromBool(compressed);

    var bits: u5 = 0;
    var container: u32 = 0;
    for (data[start..], start..) |c, i| {
        const decoded = decryptChar(key, @intCast(i), c);
        if (compressed) {
            container |= @as(u32, decoded) << bits;
            bits += 16;

            while (bits >= 9) : (bits -= 9) {
                const char: u16 = @intCast(container & 0x1FF);
                if (char == 0x1Ff)
                    return;
                try encodings.decodeBytes(
                    &@as([2]u8, @bitCast(char)),
                    out,
                );
                container >>= 9;
            }
        } else {
            if (decoded == 0xffff)
                return;
            try encodings.decodeBytes(
                &@as([2]u8, @bitCast(decoded)),
                out,
            );
        }
    }
}

fn encrypt(data: []align(1) u16, key: u16) void {
    for (data, 0..) |*c, i|
        c.* = decryptChar(key, @intCast(i), c.*);
}

fn decryptChar(key: u16, i: u32, char: u16) u16 {
    return char ^ @as(u16, @truncate(key + i * 0x493D));
}

fn getKey(i: u32) u16 {
    return @truncate(0x91BD3 * (i + 1));
}

pub const StringTable = struct {
    file_this_was_extracted_from: u16,
    number_of_strings: u16,
    buf: []u8 = &[_]u8{},

    pub fn create(
        allocator: std.mem.Allocator,
        file_this_was_extracted_from: u16,
        number_of_strings: u16,
        max_string_len: usize,
    ) !StringTable {
        const buf = try allocator.alloc(u8, number_of_strings * max_string_len);
        errdefer allocator.free(buf);
        return StringTable{
            .file_this_was_extracted_from = file_this_was_extracted_from,
            .number_of_strings = number_of_strings,
            .buf = buf,
        };
    }

    pub fn destroy(table: StringTable, allocator: std.mem.Allocator) void {
        allocator.free(table.buf);
    }

    pub fn maxStringLen(table: StringTable) usize {
        return table.buf.len / table.number_of_strings;
    }

    pub fn get(table: StringTable, i: usize) []u8 {
        const len = table.maxStringLen();
        return table.buf[len * i ..][0..len];
    }

    pub fn getSpan(table: StringTable, i: usize) []u8 {
        const res = table.get(i);
        const end = std.mem.indexOfScalar(u8, res, 0) orelse res.len;
        return res[0..end];
    }

    pub fn encryptedSize(table: StringTable) u32 {
        return EncryptedStringTable.size(
            @intCast(table.number_of_strings),
            @intCast(table.maxStringLen() * table.number_of_strings),
        );
    }
};

pub const Version = enum {
    hgss,
    dppt,
};

pub const WildAreas = struct {
    version: Version,
    fs: rom.nds.fs.Fs,

    pub fn at(areas: WildAreas, i: usize) !WildArea {
        const file = rom.nds.fs.File{ .i = @intCast(i) };
        return switch (areas.version) {
            .hgss => .{ .hgss = try areas.fs.fileAs(file, HgssWildPokemons) },
            .dppt => .{ .dppt = try areas.fs.fileAs(file, DpptWildPokemons) },
        };
    }

    pub fn len(areas: WildAreas) usize {
        return areas.fs.fat.len;
    }
};

pub const WildArea = union(Version) {
    hgss: *align(1) HgssWildPokemons,
    dppt: *align(1) DpptWildPokemons,

    pub fn at(arena: WildArea, i: usize) !WildPokemon {
        var off = i;
        switch (arena) {
            .hgss => |hgss| {
                inline for (.{ "grass_morning", "grass_day", "grass_night" }) |field| {
                    if (off < @field(hgss, field).len)
                        return .{ .m = .{
                            .species = &@field(hgss, field)[off],
                            .min_level = &hgss.grass_levels[off],
                            .max_level = &hgss.grass_levels[off],
                        } };

                    off -= @field(hgss, field).len;
                }

                if (off < hgss.radio.len)
                    return .{ .m = .{
                        .species = &hgss.radio[off],
                        .min_level = &hgss.grass_levels[off],
                        .max_level = &hgss.grass_levels[off],
                    } };

                off -= hgss.radio.len;
                if (off < hgss.sea.len)
                    return .{ .m = .{
                        .species = &hgss.sea[off].species,
                        .min_level = &hgss.sea[off].min_level,
                        .max_level = &hgss.sea[off].max_level,
                    } };

                off -= hgss.sea.len;
                if (off < hgss.swarm.len)
                    return .{ .m = .{
                        .species = &hgss.swarm[off],
                        .min_level = &hgss.grass_levels[off],
                        .max_level = &hgss.grass_levels[off],
                    } };

                unreachable;
            },
            .dppt => |dppt| {
                if (off < dppt.grass.len)
                    return .{ .m = .{
                        .species = &dppt.grass[off].species,
                        .min_level = &dppt.grass[off].level,
                        .max_level = &dppt.grass[off].level,
                    } };

                off -= dppt.grass.len;
                if (off < dppt.replace.len) {
                    const level_index = switch (off) {
                        // swarm_replace: [2]Replacement, // Replaces grass[0, 1]
                        // day_replace: [2]Replacement, // Replaces grass[2, 3]
                        // night_replace: [2]Replacement, // Replaces grass[2, 3]
                        0, 1, 10, 11 => off,
                        2, 4, 6 => 2,
                        3, 5, 7 => 3,
                        // radar_replace: [4]Replacement, // Replaces grass[4, 5, 10, 11]
                        8 => 4,
                        9 => 5,
                        // unknown_replace: [6]Replacement, // ???
                        12, 13, 14, 15, 16, 17 => 0,
                        // gba_replace: [10]Replacement, // Each even replaces grass[8], each uneven replaces grass[9]
                        else => 8 + off / 2,
                    };
                    return .{ .m = .{
                        .species = &dppt.replace[off].species,
                        .min_level = &dppt.grass[level_index].level,
                        .max_level = &dppt.grass[level_index].level,
                    } };
                }

                off -= dppt.replace.len;
                const sea_len = dppt.sea[0].mons.len;
                if (off < (dppt.sea.len * sea_len))
                    return .{ .m = .{
                        .species = &dppt.sea[off / sea_len].mons[off % sea_len].species,
                        .min_level = &dppt.sea[off / sea_len].mons[off % sea_len].min_level,
                        .max_level = &dppt.sea[off / sea_len].mons[off % sea_len].max_level,
                    } };

                unreachable;
            },
        }
    }

    pub fn len(area: WildArea) usize {
        switch (area) {
            // TODO: Radio, Swarm
            .hgss => |hgss| return hgss.grass_morning.len +
                hgss.grass_day.len +
                hgss.grass_night.len +
                hgss.sea.len,
            .dppt => |dppt| return dppt.grass.len +
                dppt.replace.len +
                (dppt.sea.len * dppt.sea[0].mons.len),
        }
    }
};

pub const LevelUpMoves = struct {
    fs: rom.nds.fs.Fs,

    pub fn at(moves: @This(), i: usize) ![]align(1) LevelUpMove {
        const bytes = try moves.fs.fileData(.{ .i = @intCast(i) });
        const level_up_moves = std.mem.bytesAsSlice(LevelUpMove, bytes);

        for (level_up_moves, 0..) |move, j| {
            if (std.meta.eql(move, LevelUpMove.term))
                return level_up_moves[0..j];
        }

        return level_up_moves;
    }

    pub fn len(moves: @This()) usize {
        return moves.fs.fat.len;
    }
};

pub const Evolutions = rom.nds.fs.Indexable([7]Evolution);
pub const Items = rom.nds.fs.Indexable(Item);
pub const Moves = rom.nds.fs.Indexable(Move);
pub const Pokemons = rom.nds.fs.Indexable(Pokemon);
pub const Trainers = rom.nds.fs.Indexable(Trainer);

pub const Parties = common.IndexableSlice(Party);

pub const Game = struct {
    info: offsets.Info,
    allocator: std.mem.Allocator,
    rom: *rom.nds.Rom,
    owned: Owned,
    ptrs: Pointers,

    // These fields are owned by the game and will be applied to
    // the rom oppon calling `apply`.
    pub const Owned = struct {
        old_arm_len: usize,
        arm9: []u8,
        trainer_parties: []Party,
        text: Text,

        pub fn deinit(owned: Owned, allocator: std.mem.Allocator) void {
            allocator.free(owned.arm9);
            allocator.free(owned.trainer_parties);
            owned.text.deinit(allocator);
        }
    };

    pub const Text = struct {
        type_names: StringTable,
        pokemon_names: StringTable,
        //trainer_names:StringTable,
        move_names: StringTable,
        ability_names: StringTable,
        item_names: StringTable,
        item_descriptions: StringTable,
        move_descriptions: StringTable,

        pub const Array = [std.meta.fields(Text).len]StringTable;

        pub fn deinit(text: Text, allocator: std.mem.Allocator) void {
            for (text.asArray()) |table|
                table.destroy(allocator);
        }

        pub fn asArray(text: Text) Array {
            var res: Array = undefined;
            inline for (std.meta.fields(Text), &res) |field, *r|
                r.* = @field(text, field.name);

            return res;
        }
    };

    // The fields below are pointers into the nds rom and will
    // be invalidated oppon calling `apply`.
    pub const Pointers = struct {
        starters: [3]u16,
        wild_pokemons: union {
            dppt: []align(1) DpptWildPokemons,
            hgss: []align(1) HgssWildPokemons,
        },
        tms: []align(1) u16,
        hms: []align(1) u16,

        pokedex: rom.nds.fs.Fs,
        pokedex_heights: []align(1) u32,
        pokedex_weights: []align(1) u32,
        species_to_national_dex: []align(1) u16,

        text: rom.nds.fs.Fs,
        scripts: rom.nds.fs.Fs,
        static_pokemons: []StaticPokemon,
        given_pokemons: []StaticPokemon,
        pokeball_items: []PokeballItem,

        pub fn deinit(ptrs: Pointers, allocator: std.mem.Allocator) void {
            allocator.free(ptrs.static_pokemons);
            allocator.free(ptrs.given_pokemons);
            allocator.free(ptrs.pokeball_items);
        }
    };

    pub fn identify(reader: anytype) !offsets.Info {
        const header = try reader.readStruct(rom.nds.Header);
        for (offsets.infos) |info| {
            //if (!std.mem.eql(u8, info.game_title, game_title))
            //    continue;
            if (!std.mem.eql(u8, &info.gamecode, &header.gamecode))
                continue;

            return info;
        }

        return error.UnknownGame;
    }

    pub fn fromRom(allocator: std.mem.Allocator, nds_rom: *rom.nds.Rom) !Game {
        var fbs = std.io.fixedBufferStream(nds_rom.data.items);
        const info = try identify(fbs.reader());
        const arm9 = if (info.arm9_is_encoded)
            try rom.nds.blz.decode(allocator, nds_rom.arm9())
        else
            try allocator.dupe(u8, nds_rom.arm9());
        errdefer allocator.free(arm9);

        const file_system = try nds_rom.fileSystem();

        const all_trainers = (try file_system.openNarc(rom.nds.fs.root, info.trainers)).indexable(Trainer);
        const trainer_parties_narc = try file_system.openNarc(rom.nds.fs.root, info.parties);
        const trainer_parties = try allocator.alloc(Party, trainer_parties_narc.fat.len);
        errdefer allocator.free(trainer_parties);

        @memset(trainer_parties, Party{});

        for (trainer_parties, 0..) |*party, i| {
            const trainer = all_trainers.at(i) catch continue;
            const party_data = try trainer_parties_narc.fileData(.{ .i = @intCast(i) });

            party.type = trainer.party_type;
            party.size = trainer.party_size;

            for (party.members[0..trainer.party_size], 0..trainer.party_size) |*member, j| {
                const base = trainer.partyMember(info.version, party_data, j) orelse break;
                member.base = base.*;

                switch (trainer.party_type) {
                    .none => {},
                    .item => member.item = base.toParent(PartyMemberItem).item,
                    .moves => member.moves = base.toParent(PartyMemberMoves).moves,
                    .both => {
                        member.item = base.toParent(PartyMemberBoth).item;
                        member.moves = base.toParent(PartyMemberBoth).moves;
                    },
                }
            }
        }

        const text = try file_system.openNarc(rom.nds.fs.root, info.text);
        const type_names = try decryptStringTable(allocator, 16, text, info.type_names);
        errdefer type_names.destroy(allocator);
        const pokemon_names = try decryptStringTable(allocator, 16, text, info.pokemon_names);
        errdefer pokemon_names.destroy(allocator);
        const item_names = try decryptStringTable(allocator, 16, text, info.item_names);
        errdefer item_names.destroy(allocator);
        const ability_names = try decryptStringTable(allocator, 16, text, info.ability_names);
        errdefer ability_names.destroy(allocator);
        const move_names = try decryptStringTable(allocator, 16, text, info.move_names);
        errdefer move_names.destroy(allocator);
        //const trainer_names = try decryptStringTable( allocator, 32,text, info.trainer_names);
        //errdefer trainer_names.destroy(allocator);
        const item_descriptions = try decryptStringTable(allocator, 128, text, info.item_descriptions);
        errdefer item_descriptions.destroy(allocator);
        const move_descriptions = try decryptStringTable(allocator, 256, text, info.move_descriptions);
        errdefer move_descriptions.destroy(allocator);
        return fromRomEx(allocator, nds_rom, info, .{
            .old_arm_len = nds_rom.arm9().len,
            .arm9 = arm9,
            .trainer_parties = trainer_parties,
            .text = .{
                .type_names = type_names,
                .item_descriptions = item_descriptions,
                .item_names = item_names,
                .ability_names = ability_names,
                .move_descriptions = move_descriptions,
                .move_names = move_names,
                //.trainer_names = trainer_names,
                .pokemon_names = pokemon_names,
            },
        });
    }

    pub fn fromRomEx(
        allocator: std.mem.Allocator,
        nds_rom: *rom.nds.Rom,
        info: offsets.Info,
        owned: Owned,
    ) !Game {
        const file_system = try nds_rom.fileSystem();

        const hm_tm_prefix_index = std.mem.indexOf(u8, owned.arm9, info.hm_tm_prefix) orelse return error.CouldNotFindTmsOrHms;
        const hm_tm_index = hm_tm_prefix_index + info.hm_tm_prefix.len;
        const hm_tms_len = (offsets.tm_count + offsets.hm_count) * @sizeOf(u16);
        const hm_tms = std.mem.bytesAsSlice(u16, owned.arm9[hm_tm_index..][0..hm_tms_len]);

        const text = try file_system.openNarc(rom.nds.fs.root, info.text);
        const scripts = try file_system.openNarc(rom.nds.fs.root, info.scripts);
        const pokedex = try file_system.openNarc(rom.nds.fs.root, info.pokedex);
        const commands = try findScriptCommands(info.version, scripts, allocator);
        errdefer {
            allocator.free(commands.static_pokemons);
            allocator.free(commands.given_pokemons);
            allocator.free(commands.pokeball_items);
        }

        const starts = try getStarter(nds_rom, info, owned);
        return Game{
            .info = info,
            .allocator = allocator,
            .rom = nds_rom,
            .owned = owned,
            .ptrs = .{
                .starters = .{
                    starts[0].*,
                    starts[1].*,
                    starts[2].*,
                },
                .wild_pokemons = blk: {
                    const narc = try file_system.openNarc(rom.nds.fs.root, info.wild_pokemons);
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

                .pokedex = pokedex,
                .pokedex_heights = std.mem.bytesAsSlice(u32, try pokedex.fileData(.{ .i = info.pokedex_heights })),
                .pokedex_weights = std.mem.bytesAsSlice(u32, try pokedex.fileData(.{ .i = info.pokedex_weights })),
                .species_to_national_dex = std.mem.bytesAsSlice(u16, try pokedex.fileData(.{ .i = info.species_to_national_dex })),

                .text = text,
                .scripts = scripts,
                .static_pokemons = commands.static_pokemons,
                .given_pokemons = commands.given_pokemons,
                .pokeball_items = commands.pokeball_items,
            },
        };
    }

    pub fn starters(game: *Game) *[3]u16 {
        return &game.ptrs.starters;
    }

    pub fn staticPokemons(game: *Game) []StaticPokemon {
        return game.ptrs.static_pokemons;
    }

    pub fn givenPokemons(game: *Game) []StaticPokemon {
        return game.ptrs.given_pokemons;
    }

    pub fn pokemons(game: Game) !Pokemons {
        const file_system = try game.rom.fileSystem();
        return .{ .fs = try file_system.openNarc(rom.nds.fs.root, game.info.evolutions) };
    }

    pub fn evolutions(game: Game) !Evolutions {
        const file_system = try game.rom.fileSystem();
        return .{ .fs = try file_system.openNarc(rom.nds.fs.root, game.info.pokemons) };
    }

    pub fn levelUpMoves(game: Game) !LevelUpMoves {
        const file_system = try game.rom.fileSystem();
        return .{ .fs = try file_system.openNarc(rom.nds.fs.root, game.info.level_up_moves) };
    }

    pub fn moves(game: Game) !Moves {
        const file_system = try game.rom.fileSystem();
        return .{ .fs = try file_system.openNarc(rom.nds.fs.root, game.info.moves) };
    }

    pub fn trainers(game: Game) !Trainers {
        const file_system = try game.rom.fileSystem();
        return .{ .fs = try file_system.openNarc(rom.nds.fs.root, game.info.trainers) };
    }

    pub fn trainerParties(game: Game) !Parties {
        return .{ .slice = game.owned.trainer_parties };
    }

    pub fn items(game: Game) !Items {
        const file_system = try game.rom.fileSystem();
        return .{ .fs = try file_system.openNarc(rom.nds.fs.root, game.info.items) };
    }

    pub fn wildAreas(game: Game) !WildAreas {
        const file_system = try game.rom.fileSystem();
        return .{
            .version = switch (game.info.version) {
                .heart_gold, .soul_silver => .hgss,
                .diamond, .pearl, .platinum => .dppt,
                else => unreachable,
            },
            .fs = try file_system.openNarc(rom.nds.fs.root, game.info.wild_pokemons),
        };
    }

    // TODO: Validate
    pub fn validSpecies(game: Game, out: *std.ArrayList(u16)) !void {
        const all = try game.pokemons();
        try out.ensureUnusedCapacity(all.len());

        var species: u16 = 0;
        while (species < all.len()) : (species += 1) {
            const pokemon = try all.at(species);
            if (species == 0)
                continue;
            if (pokemon.catch_rate == 0)
                continue;
            if (species >= game.ptrs.species_to_national_dex.len + 1)
                continue;

            out.appendAssumeCapacity(species);
        }
    }

    pub fn apply(game: *Game) !void {
        try game.applyStarters();

        if (game.info.arm9_is_encoded) {
            const arm9 = try rom.nds.blz.encode(game.allocator, game.owned.arm9, 0x4000);
            defer game.allocator.free(arm9);

            // In the secure area, there is an offset that points to the end of the compressed arm9.
            // We have to find that offset and replace it with the new size.
            const secure_area = arm9[0..0x4000];

            var len_bytes: [3]u8 = undefined;
            std.mem.writeInt(u24, &len_bytes, @as(u24, @intCast(game.owned.old_arm_len)), .little);
            if (std.mem.indexOf(u8, secure_area, &len_bytes)) |off| {
                std.mem.writeInt(
                    u24,
                    secure_area[off..][0..3],
                    @as(u24, @intCast(arm9.len)),
                    .little,
                );
            }
            @memcpy(try game.rom.resizeSection(game.rom.arm9(), arm9.len), arm9);
        } else {
            @memcpy(try game.rom.resizeSection(game.rom.arm9(), game.owned.arm9.len), game.owned.arm9);
        }

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

    fn applyStarters(game: Game) !void {
        const starts = try getStarter(game.rom, game.info, game.owned);
        for (game.ptrs.starters, starts) |starter, out|
            out.* = starter;
    }

    fn getStarter(
        nds_rom: *rom.nds.Rom,
        info: offsets.Info,
        owned: Owned,
    ) ![3]*align(1) u16 {
        const file_system = try nds_rom.fileSystem();
        const arm9_overlay_table = nds_rom.arm9OverlayTable();
        switch (info.starters) {
            .arm9 => |offset| {
                if (owned.arm9.len < offset + offsets.starters_len)
                    return error.CouldNotFindStarters;
                const starters_section = std.mem.bytesAsSlice(u16, owned.arm9[offset..][0..offsets.starters_len]);
                return [_]*align(1) u16{
                    &starters_section[0],
                    &starters_section[2],
                    &starters_section[4],
                };
            },
            .overlay9 => |overlay| {
                const overlay_entry = arm9_overlay_table[overlay.file];
                const file_data = try file_system.fileData(.{ .i = overlay_entry.file_id });
                const starters_section = std.mem.bytesAsSlice(u16, file_data[overlay.offset..][0..offsets.starters_len]);
                return [_]*align(1) u16{
                    &starters_section[0],
                    &starters_section[2],
                    &starters_section[4],
                };
            },
        }
    }

    fn applyTrainerParties(game: Game) !void {
        const file_system = try game.rom.fileSystem();
        const trainer_parties_narc = try file_system.openFileData(rom.nds.fs.root, game.info.parties);
        const trainer_parties = game.owned.trainer_parties;

        const content_size = @sizeOf([6]HgSsPlatMember(PartyMemberBoth)) *
            trainer_parties.len;
        const size = rom.nds.fs.narcSize(trainer_parties.len, content_size);

        const buf = try game.rom.resizeSection(trainer_parties_narc, size);
        const all_trainers = (try file_system.openNarc(rom.nds.fs.root, game.info.trainers)).indexable(Trainer);

        var builder = rom.nds.fs.SimpleNarcBuilder.init(
            buf,
            trainer_parties.len,
        );
        const fat = builder.fat();
        const writer = builder.stream.writer();
        const files_offset = builder.stream.pos;

        for (trainer_parties, 0..) |party, i| {
            const trainer = all_trainers.at(i) catch continue;
            const start = builder.stream.pos - files_offset;
            defer fat[i] = rom.nds.Range.init(start, builder.stream.pos - files_offset);

            trainer.party_size = party.size;
            trainer.party_type = party.type;

            for (party.members[0..party.size]) |member| {
                switch (party.type) {
                    .none => writer.writeAll(&std.mem.toBytes(PartyMemberNone{
                        .base = member.base,
                    })) catch unreachable,
                    .item => writer.writeAll(&std.mem.toBytes(PartyMemberItem{
                        .base = member.base,
                        .item = member.item,
                    })) catch unreachable,
                    .moves => writer.writeAll(&std.mem.toBytes(PartyMemberMoves{
                        .base = member.base,
                        .moves = member.moves,
                    })) catch unreachable,
                    .both => writer.writeAll(&std.mem.toBytes(member)) catch unreachable,
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
        const file_system = try game.rom.fileSystem();
        const old_text_bytes = try file_system.openFileData(rom.nds.fs.root, game.info.text);

        const old_text = try rom.nds.fs.Fs.fromNarc(old_text_bytes);

        // We then calculate the size of the content for our new narc
        var extra_bytes: usize = 0;
        for (game.owned.text.asArray()) |table| {
            extra_bytes += std.math.sub(
                u32,
                table.encryptedSize(),
                old_text.fat[table.file_this_was_extracted_from].len(),
            ) catch 0;
        }

        const buf = try game.rom.resizeSection(old_text_bytes, old_text_bytes.len + extra_bytes);
        const text = try rom.nds.fs.Fs.fromNarc(buf);

        // First, resize all tables that need a resize
        for (game.owned.text.asArray()) |table| {
            const new_file_size = table.encryptedSize();
            const file = &text.fat[table.file_this_was_extracted_from];

            const file_needs_a_resize = file.len() < new_file_size;
            if (file_needs_a_resize) {
                const extra = new_file_size - file.len();
                std.mem.copyBackwards(
                    u8,
                    text.data[file.end + extra ..],
                    text.data[file.end .. text.data.len - extra],
                );

                const old_file_end = file.end;
                file.* = rom.nds.Range.init(file.start, file.end + extra);

                for (text.fat) |*f| {
                    const start = f.start;
                    const end = f.end;
                    const file_is_before_the_file_we_moved = start < old_file_end;
                    if (file_is_before_the_file_we_moved)
                        continue;

                    f.* = rom.nds.Range.init(start + extra, end + extra);
                }
            }

            const Header = EncryptedStringTable.Header;
            const bytes = text.data[file.start..file.end];
            std.debug.assert(bytes.len == new_file_size);

            // Non of the writes here can fail as long as we calculated the size
            // of the file correctly above
            var fbs = std.io.fixedBufferStream(bytes);
            const writer = fbs.writer();
            const chars_per_entry = table.maxStringLen() + 1; // Always make room for a terminator
            const bytes_per_entry = chars_per_entry * 2;
            try writer.writeAll(&std.mem.toBytes(Header{
                .count = table.number_of_strings,
                .key = 0,
            }));

            const start_of_entry_table = writer.context.pos;
            for (@as([*]void, undefined)[0..table.number_of_strings]) |_| {
                try writer.writeAll(&std.mem.toBytes(rom.nds.Slice{
                    .start = 0,
                    .len = 0,
                }));
            }

            const entries = std.mem.bytesAsSlice(rom.nds.Slice, bytes[start_of_entry_table..writer.context.pos]);
            for (entries, 0..) |*entry, i| {
                const start_of_str = writer.context.pos;
                const str = table.getSpan(i);
                encodings.encode(str, writer) catch unreachable;
                try writer.writeAll("\xff\xff");

                const end_of_str = writer.context.pos;
                const encoded_str = std.mem.bytesAsSlice(u16, bytes[start_of_str..end_of_str]);
                encrypt(encoded_str, getKey(@intCast(i)));

                const length_of_str: u32 = @intCast((end_of_str - start_of_str) / 2);
                entry.start = @intCast(start_of_str);
                entry.len = length_of_str;

                // Pad the string, so that each entry is always entry_size
                // apart. This ensure that patches generated from tm35-apply
                // are small.
                writer.writeByteNTimes(0, (chars_per_entry - length_of_str) * 2) catch unreachable;
                std.debug.assert(writer.context.pos - start_of_str == bytes_per_entry);
            }

            // Assert that we got the file size right.
            std.debug.assert(writer.context.pos == bytes.len);
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

    fn findScriptCommands(version: common.Version, scripts: rom.nds.fs.Fs, allocator: std.mem.Allocator) !ScriptCommands {
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

        for (scripts.fat) |fat| {
            const script_data = scripts.data[fat.start..fat.end];
            defer script_offsets.shrinkRetainingCapacity(0);

            for (script.getScriptOffsets(script_data), 1..) |relative_offset, i| {
                const offset = relative_offset + @as(isize, @intCast(i)) * @sizeOf(u32);
                if (@as(isize, @intCast(script_data.len)) < offset)
                    continue;
                if (offset < 0)
                    continue;
                try script_offsets.append(offset);
            }

            // The variable 0x8008 is the variables that stores items given
            // from Pokéballs.
            var var_8008: ?*align(1) u16 = null;

            var offset_i: usize = 0;
            while (offset_i < script_offsets.items.len) : (offset_i += 1) {
                const offset = script_offsets.items[offset_i];
                if (@as(isize, @intCast(script_data.len)) < offset)
                    return error.Error;
                if (offset < 0)
                    return error.Error;

                var decoder = script.CommandDecoder{
                    .bytes = script_data,
                    .i = @intCast(offset),
                };
                while (decoder.next() catch continue) |command| {
                    // If we hit var 0x8008, the var_8008_tmp will be set and
                    // Var_8008 will become var_8008_tmp. Then the next iteration
                    // of this loop will set var_8008 to null again. This allows us
                    // to store this state for only the next iteration of the loop.
                    var var_8008_tmp: ?*align(1) u16 = null;
                    defer var_8008 = var_8008_tmp;

                    switch (command.kind) {
                        .wild_battle => try static_pokemons.append(.{ .m = .{
                            .species = &command.wild_battle.species,
                            .level = &command.wild_battle.level,
                        } }),
                        .wild_battle2 => try static_pokemons.append(.{ .m = .{
                            .species = &command.wild_battle2.species,
                            .level = &command.wild_battle2.level,
                        } }),
                        .wild_battle3 => try static_pokemons.append(.{ .m = .{
                            .species = &command.wild_battle3.species,
                            .level = &command.wild_battle3.level,
                        } }),
                        .give_pokemon => try given_pokemons.append(.{ .m = .{
                            .species = &command.give_pokemon.species,
                            .level = &command.give_pokemon.level,
                        } }),

                        // In scripts, field items are two SetVar commands
                        // followed by a jump to the code that gives this item:
                        //   SetVar 0x8008 // Item given
                        //   SetVar 0x8009 // Amount of items
                        //   Jump ???
                        .set_var => switch (command.set_var.destination) {
                            0x8008 => var_8008_tmp = &command.set_var.value,
                            0x8009 => if (var_8008) |item| {
                                const amount = &command.set_var.value;
                                try pokeball_items.append(.{
                                    .item = item,
                                    .amount = amount,
                                });
                            },
                            else => {},
                        },
                        .jump, .compare_last_result_jump, .call, .compare_last_result_call => {
                            const off = switch (command.kind) {
                                .compare_last_result_call => command.compare_last_result_call.adr,
                                .call => command.call.adr,
                                .jump => command.jump.adr,
                                .compare_last_result_jump => command.compare_last_result_jump.adr,
                                else => unreachable,
                            };
                            const location = off + @as(isize, @intCast(decoder.i));
                            if (std.mem.indexOfScalar(isize, script_offsets.items, location) == null)
                                try script_offsets.append(location);
                        },
                        else => {},
                    }
                }
            }
        }

        return ScriptCommands{
            .static_pokemons = try static_pokemons.toOwnedSlice(),
            .given_pokemons = try given_pokemons.toOwnedSlice(),
            .pokeball_items = try pokeball_items.toOwnedSlice(),
        };
    }

    fn decryptStringTable(
        allocator: std.mem.Allocator,
        max_string_len: usize,
        text: rom.nds.fs.Fs,
        file: u16,
    ) !StringTable {
        const table = EncryptedStringTable{ .data = try text.fileData(.{ .i = file }) };
        const res = try StringTable.create(
            allocator,
            file,
            table.count(),
            max_string_len,
        );
        errdefer res.destroy(allocator);

        @memset(res.buf, 0);

        var i: usize = 0;
        while (i < res.number_of_strings) : (i += 1) {
            const id: u32 = @intCast(i);
            const buf = res.get(i);
            var fbs = std.io.fixedBufferStream(buf);
            const encrypted_string = table.getEncryptedString(id);
            try decryptAndDecode(encrypted_string, getKey(id), fbs.writer());
        }

        return res;
    }
};

test {
    _ = encodings;
    _ = offsets;
    _ = script;
    _ = common;
    _ = rom;
}

pub const encodings = @import("gen4/encodings.zig");
pub const offsets = @import("gen4/offsets.zig");
pub const script = @import("gen4/script.zig");

const std = @import("std");
const common = @import("common.zig");
const rom = @import("rom.zig");
