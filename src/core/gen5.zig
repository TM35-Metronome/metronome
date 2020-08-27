const std = @import("std");

const common = @import("common.zig");
const rom = @import("rom.zig");

pub const offsets = @import("gen5/offsets.zig");
pub const script = @import("gen5/script.zig");

const debug = std.debug;
const fmt = std.fmt;
const io = std.io;
const math = std.math;
const mem = std.mem;
const unicode = std.unicode;

const nds = rom.nds;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu128 = rom.int.lu128;

pub const BasePokemon = extern struct {
    stats: common.Stats,
    types: [2]u8,

    catch_rate: u8,
    stage: u8,

    evs_yield: common.EvYield,
    items: [3]lu16,

    gender_ratio: u8,
    egg_cycles: u8,
    base_friendship: u8,

    growth_rate: common.GrowthRate,

    egg_group1: common.EggGroup,
    egg_group2: common.EggGroup,

    abilities: [3]u8,

    flag: u8,
    form_id: lu16,
    forme: lu16,
    form_count: u8,

    color: common.Color,

    base_exp_yield: lu16,
    height: lu16,
    weight: lu16,

    // Memory layout
    // TMS 01-92, HMS 01-06, TMS 93-95
    machine_learnset: lu128,

    // TODO: Tutor data only exists in BW2
    //special_tutors: lu32,
    //driftveil_tutor: lu32,
    //lentimas_tutor: lu32,
    //humilau_tutor: lu32,
    //nacrene_tutor: lu32,

    comptime {
        debug.assert(@sizeOf(@This()) == 56);
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
    level: u8 = 0,
    padding: u8 = 0,
    species: lu16 = lu16.init(0),
    form: lu16 = lu16.init(0),

    comptime {
        debug.assert(@sizeOf(@This()) == 8);
    }

    const GenderAbilityPair = packed struct {
        gender: u4 = 0,
        ability: u4 = 0,
    };

    pub fn toParent(base: *PartyMemberBase, comptime Parent: type) *Parent {
        return @fieldParentPtr(Parent, "base", base);
    }
};

pub const PartyMemberNone = extern struct {
    base: PartyMemberBase = PartyMemmberBase{},

    comptime {
        debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const PartyMemberItem = extern struct {
    base: PartyMemberBase = PartyMemmberBase{},
    item: lu16 = lu16.init(0),

    comptime {
        debug.assert(@sizeOf(@This()) == 10);
    }
};

pub const PartyMemberMoves = extern struct {
    base: PartyMemberBase = PartyMemmberBase{},
    moves: [4]lu16 = [_]lu16{lu16.init(0)} ** 4,

    comptime {
        debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const PartyMemberBoth = extern struct {
    base: PartyMemberBase = PartyMemberBase{},
    item: lu16 = lu16.init(0),
    moves: [4]lu16 = [_]lu16{lu16.init(0)} ** 4,

    comptime {
        debug.assert(@sizeOf(@This()) == 18);
    }
};

pub const Trainer = extern struct {
    party_type: PartyType,
    class: u8,
    battle_type: u8, // TODO: This should probably be an enum
    party_size: u8,
    items: [4]lu16,
    ai: lu32,
    healer: bool,
    cash: u8,
    post_battle_item: lu16,

    comptime {
        debug.assert(@sizeOf(@This()) == 20);
    }

    pub fn partyMember(trainer: Trainer, party: []u8, i: usize) ?*PartyMemberBase {
        const member_size: usize = switch (trainer.party_type) {
            .none => @sizeOf(PartyMemberNone),
            .item => @sizeOf(PartyMemberItem),
            .moves => @sizeOf(PartyMemberMoves),
            .both => @sizeOf(PartyMemberBoth),
        };

        const start = i * member_size;
        const end = start + member_size;
        if (party.len < end)
            return null;

        return mem.bytesAsValue(PartyMemberBase, party[start..end][0..@sizeOf(PartyMemberBase)]);
    }
};

pub const Move = packed struct {
    type: u8,
    effect_category: u8,
    category: common.MoveCategory,
    power: u8,
    accuracy: u8,
    pp: u8,
    priority: u8,
    min_hits: u4,
    max_hits: u4,
    result_effect: lu16,
    effect_chance: u8,
    status: u8,
    min_turns: u8,
    max_turns: u8,
    crit: u8,
    flinch: u8,
    effect: lu16,
    target_hp: u8,
    user_hp: u8,
    target: u8,
    // TODO: Arrays of uneven elements doesn't quite work in
    //       packed structs.
    stats_affected1: u8,
    stats_affected2: u8,
    stats_affected3: u8,
    stats_affected_magnetude1: u8,
    stats_affected_magnetude2: u8,
    stats_affected_magnetude3: u8,
    stats_affected_chance1: u8,
    stats_affected_chance2: u8,
    stats_affected_chance3: u8,

    // TODO: Figure out if this is actually how the last fields are layed out.
    padding1: [2]u8,
    flags: lu16,
    padding2: [2]u8,

    comptime {
        debug.assert(@sizeOf(@This()) == 36);
    }
};

pub const LevelUpMove = extern struct {
    id: lu16,
    level: lu16,

    pub const term = LevelUpMove{
        .id = lu16.init(math.maxInt(u16)),
        .level = lu16.init(math.maxInt(u16)),
    };

    comptime {
        debug.assert(@sizeOf(@This()) == 4);
    }
};

// TODO: Verify layout
pub const Evolution = extern struct {
    method: Method,
    padding: u8,
    param: lu16,
    target: lu16,

    comptime {
        debug.assert(@sizeOf(@This()) == 6);
    }

    pub const Method = packed enum(u8) {
        unused = 0x00,
        friend_ship = 0x01,
        unknown_0x02 = 0x02,
        unknown_0x03 = 0x03,
        level_up = 0x04,
        trade = 0x05,
        trade_holding_item = 0x06,
        trade_with_pokemon = 0x07,
        use_item = 0x08,
        attack_gth_defense = 0x09,
        attack_eql_defense = 0x0A,
        attack_lth_defense = 0x0B,
        personality_value1 = 0x0C,
        personality_value2 = 0x0D,
        level_up_may_spawn_pokemon = 0x0E,
        level_up_spawn_if_cond = 0x0F,
        beauty = 0x10,
        use_item_on_male = 0x11,
        use_item_on_female = 0x12,
        level_up_holding_item_during_daytime = 0x13,
        level_up_holding_item_during_the_night = 0x14,
        level_up_knowning_move = 0x15,
        level_up_with_other_pokemon_in_party = 0x16,
        level_up_male = 0x17,
        level_up_female = 0x18,
        level_up_in_special_magnetic_field = 0x19,
        level_up_near_moss_rock = 0x1A,
        level_up_near_ice_rock = 0x1B,
        _,
    };
};

pub const EvolutionTable = extern struct {
    items: [7]Evolution,
    terminator: lu16,

    comptime {
        debug.assert(@sizeOf(@This()) == 44);
    }
};

pub const Species = extern struct {
    value: lu16,

    comptime {
        debug.assert(@sizeOf(@This()) == 2);
    }

    pub fn species(s: Species) u10 {
        return @truncate(u10, s.value.value());
    }

    pub fn setSpecies(s: *Species, spe: u10) void {
        s.value = lu16.init((@as(u16, s.form()) << @as(u4, 10)) | spe);
    }

    pub fn form(s: Species) u6 {
        return @truncate(u6, s.value.value() >> 10);
    }

    pub fn setForm(s: *Species, f: u10) void {
        s.value = lu16.init((@as(u16, f) << @as(u4, 10)) | s.species());
    }
};

pub const WildPokemon = extern struct {
    species: Species,
    min_level: u8,
    max_level: u8,

    comptime {
        debug.assert(@sizeOf(@This()) == 4);
    }
};

pub const WildPokemons = extern struct {
    rates: [7]u8,
    pad: u8,
    grass: [12]WildPokemon,
    dark_grass: [12]WildPokemon,
    rustling_grass: [12]WildPokemon,
    surf: [5]WildPokemon,
    ripple_surf: [5]WildPokemon,
    fishing: [5]WildPokemon,
    ripple_fishing: [5]WildPokemon,

    comptime {
        debug.assert(@sizeOf(@This()) == 232);
    }
};

pub const Pocket = packed enum(u4) {
    items = 0x00,
    tms_hms = 0x01,
    key_items = 0x02,
    balls = 0x08,
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
    category3: u8,
    index: u8,
    anti_index: u8,
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
        debug.assert(@sizeOf(@This()) == 36);
    }
};

// All comments on fields are based on research done on Route 19 in b2
pub const MapHeader = extern struct {
    // Something related to the map itself. Setting this to 5
    // made it so the player stood in a blue void.
    unknown00: u8,

    // Setting to 0,5,255 had seemingly no effect
    unknown01: u8,

    // Setting to 5 removed the snow on the route, even though it was
    // winter. Seemed like the fall map
    unknown02: u8,

    // Setting to 5 removed the snow on the route, even though it was
    // winter. Seemed like the summer map
    unknown03: u8,

    // Something related to the map itself. Setting this to 5
    // made it so the player stood in a blue void.
    unknown04: u8,

    // Setting to 0,5,255: "An error has occurred. Please turn off the power."
    unknown05: u8,

    // Setting to 5: No effect it seems
    // Setting to 255: Freeze when talking to sign,npcs
    // Seems to be an index to the script of the map
    unknown06: lu16,

    // Setting to 0,5,255: No effect it seems
    unknown08: u8,

    // Setting to 0,5,255: No effect it seems
    unknown09: u8,

    // Setting to 0: No text on sign, npc says "it seems you can't use it yet."
    // Setting to 255: "An error has occurred. Please turn off the power."
    // Seems related to text or something
    unknown0a: lu16,

    // Setting to 0,5,255: No effect it seems
    unknown0c: u8,

    // Setting to 0,5,255: No effect it seems
    unknown0d: u8,

    // Setting to 0,5,255: No effect it seems
    unknown0e: u8,

    // Setting to 0,5,255: No effect it seems
    unknown0f: u8,

    // Setting to 0,5,255: No effect it seems
    unknown10: u8,

    // Setting to 0,5,255: No effect it seems
    unknown11: u8,
    music: lu16,
    wild_pokemons: lu16,

    // Seems to be related to signs somehow
    unknown16: lu16,

    // Setting to 0,5,255: No effect it seems
    unknown18: u8,

    // Setting to 0,5,255: No effect it seems
    unknown19: u8,
    name_index: u8,

    // Setting to 0,5,255: No effect it seems
    unknown1b: u8,

    // Setting to 0,5,255: No effect it seems
    unknown1c: u8,
    camera_angle: u8,

    // Setting to 0,5,255: No effect it seems
    unknown1e: u8,
    battle_scene: u8,

    // Setting to 0: No effect it seems
    // Something related to the map itself. Setting this to 255
    // gave a blue void.
    unknown20: u8,

    // Setting to 0: No effect it seems
    // Setting to 5,255: "An error has occurred. Please turn off the power."
    unknown21: u8,

    // Setting to 0: No effect it seems
    // Setting to 5: No effect it seems
    // Setting to 255: After loading, "An error has occurred. Please turn off the power."
    unknown22: u8,

    // Setting to 0: No effect it seems
    // Setting to 5,255: After moving "An error has occurred. Please turn off the power."
    unknown23: u8,

    // Setting to 0,5,255: No effect it seems
    unknown24: u8,

    // Setting to 0,5,255: No effect it seems
    unknown25: u8,

    // Setting to 0,5,255: No effect it seems
    unknown26: u8,

    // Setting to 0,5,255: No effect it seems
    unknown27: u8,

    // Setting to 0,5,255: No effect it seems
    unknown28: u8,

    // Setting to 0,5,255: No effect it seems
    unknown29: u8,

    // Setting to 0,5,255: No effect it seems
    unknown2a: u8,

    // Setting to 0,5,255: No effect it seems
    unknown2b: u8,

    // Setting to 0,5,255: No effect it seems
    unknown2c: u8,

    // Setting to 0,5,255: No effect it seems
    unknown2d: u8,

    // Setting to 0,5,255: No effect it seems
    unknown2e: u8,

    // Setting to 0,5,255: No effect it seems
    unknown2f: u8,

    comptime {
        debug.assert(@sizeOf(@This()) == 48);
    }
};

const HiddenHollow = extern struct {
    pokemons: [2][4]HollowPokemons,
    items: [6]lu16,

    comptime {
        debug.assert(@sizeOf(@This()) == 220);
    }
};

const HollowPokemons = extern struct {
    species: [4]lu16,
    unknown: [4]lu16,
    genders: [4]u8,
    forms: [4]u8,
    pad: [2]u8,

    comptime {
        debug.assert(@sizeOf(@This()) == 26);
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

const EncryptedStringTable = struct {
    data: []u8,

    fn sectionCount(table: EncryptedStringTable) u16 {
        return table.header().sections.value();
    }

    fn entryCount(table: EncryptedStringTable, section: usize) u16 {
        return table.header().entries.value();
    }

    fn getEncryptedString(table: EncryptedStringTable, section_i: usize, entry_i: usize) []lu16 {
        const h = table.header();
        const section_offset = table.sectionOffsets()[section_i].value();
        const entry = table.entries(section_offset)[entry_i];
        const offset = section_offset + entry.offset.value();
        const res = table.data[offset..][0 .. entry.count.value() * @sizeOf(lu16)];
        return mem.bytesAsSlice(lu16, res);
    }

    const Header = packed struct {
        sections: lu16,
        entries: lu16,
        file_size: lu32,
        unknown2: lu32,
    };

    const Entry = packed struct {
        offset: lu32,
        count: lu16,
        unknown: lu16,
    };

    fn header(table: EncryptedStringTable) *Header {
        return @ptrCast(*Header, table.data[0..@sizeOf(Header)]);
    }

    fn sectionOffsets(table: EncryptedStringTable) []lu32 {
        const h = table.header();
        const rest = table.data[@sizeOf(Header)..];
        return mem.bytesAsSlice(lu32, rest[0 .. @sizeOf(lu32) * h.sections.value()]);
    }

    fn entries(table: EncryptedStringTable, section_offset: u32) []Entry {
        const h = table.header();
        const unknown = mem.bytesAsValue(lu32, table.data[section_offset..][0..@sizeOf(lu32)]);
        const rest = table.data[section_offset + @sizeOf(lu32) ..];
        return mem.bytesAsSlice(Entry, rest[0 .. @sizeOf(Entry) * h.entries.value()]);
    }

    fn size(sections: u32, strings: u32, chars: u32) u32 {
        return @sizeOf(Header) + // Header
            @sizeOf(lu32) * sections + // Section offsets
            @sizeOf(lu32) * sections + // Entry counts
            @sizeOf(Entry) * strings + // Entries
            strings * @sizeOf(lu16) + // String terminators
            chars * @sizeOf(lu16); // String chars
    }
};

fn decrypt(data: []const lu16, out: var) !void {
    const H = struct {
        fn output(out2: var, char: u16) !bool {
            const Pair = struct {
                len: usize,
                codepoint: u21,
            };
            const pair: Pair = switch (char) {
                0xffff => return true,
                0x0, 0xf000, 0xfff0...0xfffd => {
                    try out2.print("\\x{x:0>4}", .{char});
                    return false;
                },
                0xfffe => .{ .len = 1, .codepoint = '\n' },
                else => .{
                    .len = unicode.utf8CodepointSequenceLength(char) catch unreachable,
                    .codepoint = char,
                },
            };

            var buf: [4]u8 = undefined;
            _ = try unicode.utf8Encode(pair.codepoint, buf[0..pair.len]);
            try out2.writeAll(buf[0..pair.len]);
            return false;
        }
    };

    const key = getKey(data);
    const first = data[0].value() ^ keyForI(key, data.len, 0);
    const compressed = first == 0xF100;
    const start = @boolToInt(compressed);

    var bits: u5 = 0;
    var container: u32 = 0;
    for (data[start..]) |c, i| {
        const decoded = c.value() ^ keyForI(key, data.len, i + start);
        if (compressed) {
            container |= @as(u32, decoded) << bits;
            bits += 16;

            while (bits >= 9) : (bits -= 9) {
                const char = @intCast(u16, container & 0x1FF);
                if (char == 0x1Ff)
                    return;
                if (try H.output(out, char))
                    return;
                container >>= 9;
            }
        } else {
            if (try H.output(out, decoded))
                return;
        }
    }
}

fn getKey(data: []const lu16) u16 {
    const last = data[data.len - 1].value();
    debug.assert(last ^ (last ^ 0xFFFF) == 0xFFFF);
    return last ^ 0xFFFF;
}

fn encode(data: []const u8, out: var) !void {
    var n: usize = 0;
    while (n < data.len) {
        if (mem.startsWith(u8, data[n..], "\n")) {
            try out.writeAll(&lu16.init(0xfffe).bytes);
            n += 1;
            continue;
        }
        if (mem.startsWith(u8, data[n..], "\\x")) {
            const hex = data[n + 2 ..][0..4];
            const parsed = try fmt.parseUnsigned(u16, hex, 16);
            try out.writeAll(&lu16.init(parsed).bytes);
            n += 6;
            continue;
        }

        const ulen = unicode.utf8ByteSequenceLength(data[n]) catch unreachable;
        if (data.len < n + ulen)
            break;

        const codepoint = unicode.utf8Decode(data[n..][0..ulen]) catch unreachable;
        try out.writeAll(&lu16.init(@intCast(u16, codepoint)).bytes);
        n += ulen;
    }
    try out.writeAll(&lu16.init(0xffff).bytes);
}

fn encrypt(data: []lu16, key: u16) void {
    for (data) |*c, i|
        c.* = lu16.init(c.value() ^ keyForI(key, data.len, i));
}

fn keyForI(key: u16, len: usize, i: usize) u16 {
    const it = len - (i + 1);
    var res: u32 = key;

    for (@as([*]void, undefined)[0..it]) |_|
        res = (res >> 3) | (res << 13) & 0xffff;

    return @intCast(u16, res);
}

pub fn String(comptime len: usize) type {
    return struct {
        key: u16 = 0,
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
        type_names: []String(8),
        pokemon_names: []String(16),
        trainer_names: []String(16),
        move_names: []String(16),
        ability_names: []String(16),
        item_names: []String(16),
        map_names: []String(32),
        pokedex_category_names: []String(32),
        item_names_on_the_ground: []String(64),
        item_descriptions: []String(128),
        move_descriptions: []String(256),

        pub fn deinit(owned: Owned, allocator: *mem.Allocator) void {
            allocator.free(owned.arm9);
            allocator.free(owned.trainer_parties);
            allocator.free(owned.pokemon_names);
            allocator.free(owned.pokedex_category_names);
            allocator.free(owned.trainer_names);
            allocator.free(owned.move_names);
            allocator.free(owned.move_descriptions);
            allocator.free(owned.ability_names);
            allocator.free(owned.item_names);
            allocator.free(owned.item_names_on_the_ground);
            allocator.free(owned.item_descriptions);
            allocator.free(owned.type_names);
            allocator.free(owned.map_names);
        }
    };

    // The fields below are pointers into the nds rom and will
    // be invalidated oppon calling `apply`.
    pub const Pointers = struct {
        starters: [3][]*lu16,
        moves: []Move,
        trainers: []Trainer,
        items: []Item,
        tms1: []lu16,
        hms: []lu16,
        tms2: []lu16,
        evolutions: []EvolutionTable,
        map_headers: []MapHeader,
        hidden_hollows: ?[]HiddenHollow,

        wild_pokemons: nds.fs.Fs,
        pokemons: nds.fs.Fs,
        level_up_moves: nds.fs.Fs,
        scripts: nds.fs.Fs,

        static_pokemons: []StaticPokemon,
        given_pokemons: []StaticPokemon,
        pokeball_items: []PokeballItem,

        pub fn deinit(ptrs: Pointers, allocator: *mem.Allocator) void {
            for (ptrs.starters) |starter_ptrs|
                allocator.free(starter_ptrs);
            allocator.free(ptrs.static_pokemons);
            allocator.free(ptrs.given_pokemons);
            allocator.free(ptrs.pokeball_items);
        }
    };

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
        const file_system = nds_rom.fileSystem();
        const info = try identify(io.fixedBufferStream(nds_rom.data.items).inStream());
        const arm9 = try nds_rom.getDecodedArm9(allocator);
        errdefer allocator.free(arm9);

        const text = try file_system.getNarc(info.text);
        const trainers = try (try file_system.getNarc(info.trainers)).toSlice(1, Trainer);
        const trainer_parties_narc = try file_system.getNarc(info.parties);
        const trainer_parties = try allocator.alloc([6]PartyMemberBoth, trainer_parties_narc.fat.len);
        errdefer allocator.free(trainer_parties);

        for (trainer_parties) |*party, i| {
            const party_data = trainer_parties_narc.fileData(.{ .i = @intCast(u32, i) });
            const party_size = if (i != 0 and i - 1 < trainers.len) trainers[i - 1].party_size else 0;

            var j: usize = 0;
            while (j < party_size) : (j += 1) {
                const base = trainers[i - 1].partyMember(party_data, j) orelse break;
                party[j].base = base.*;

                switch (trainers[i - 1].party_type) {
                    .none => {
                        party[j].item = lu16.init(0);
                        party[j].moves = [_]lu16{lu16.init(0)} ** 4;
                    },
                    .item => {
                        party[j].item = base.toParent(PartyMemberItem).item;
                        party[j].moves = [_]lu16{lu16.init(0)} ** 4;
                    },
                    .moves => {
                        party[j].item = lu16.init(0);
                        party[j].moves = base.toParent(PartyMemberMoves).moves;
                    },
                    .both => {
                        const member = base.toParent(PartyMemberBoth);
                        party[j].item = member.item;
                        party[j].moves = member.moves;
                    },
                }
            }
            mem.set(PartyMemberBoth, party[party_size..], PartyMemberBoth{});
        }

        const type_names = try decryptStringTable(8, allocator, text, info.type_names);
        errdefer allocator.free(type_names);
        const pokemon_names = try decryptStringTable(16, allocator, text, info.pokemon_names);
        errdefer allocator.free(pokemon_names);
        const item_names = try decryptStringTable(16, allocator, text, info.item_names);
        errdefer allocator.free(item_names);
        const ability_names = try decryptStringTable(16, allocator, text, info.ability_names);
        errdefer allocator.free(ability_names);
        const move_names = try decryptStringTable(16, allocator, text, info.move_names);
        errdefer allocator.free(move_names);
        const trainer_names = try decryptStringTable(16, allocator, text, info.trainer_names);
        errdefer allocator.free(trainer_names);
        const map_names = try decryptStringTable(32, allocator, text, info.map_names);
        errdefer allocator.free(map_names);
        const pokedex_category_names = try decryptStringTable(32, allocator, text, info.pokedex_category_names);
        errdefer allocator.free(pokedex_category_names);
        const item_names_on_the_ground = try decryptStringTable(64, allocator, text, info.item_names_on_the_ground);
        errdefer allocator.free(item_names_on_the_ground);
        const item_descriptions = try decryptStringTable(128, allocator, text, info.item_descriptions);
        errdefer allocator.free(item_descriptions);
        const move_descriptions = try decryptStringTable(256, allocator, text, info.move_descriptions);
        errdefer allocator.free(move_descriptions);
        return fromRomEx(allocator, nds_rom, info, .{
            .arm9 = arm9,
            .trainer_parties = trainer_parties,
            .map_names = map_names,
            .type_names = type_names,
            .item_descriptions = item_descriptions,
            .item_names_on_the_ground = item_names_on_the_ground,
            .item_names = item_names,
            .ability_names = ability_names,
            .move_descriptions = move_descriptions,
            .move_names = move_names,
            .trainer_names = trainer_names,
            .pokedex_category_names = pokedex_category_names,
            .pokemon_names = pokemon_names,
        });
    }

    pub fn fromRomEx(
        allocator: *mem.Allocator,
        nds_rom: *nds.Rom,
        info: offsets.Info,
        owned: Owned,
    ) !Game {
        const arm9 = owned.arm9;
        const file_system = nds_rom.fileSystem();

        const hm_tm_prefix_index = mem.indexOf(u8, arm9, offsets.hm_tm_prefix) orelse return error.CouldNotFindTmsOrHms;
        const hm_tm_index = hm_tm_prefix_index + offsets.hm_tm_prefix.len;
        const hm_tm_len = (offsets.tm_count + offsets.hm_count) * @sizeOf(u16);
        const hm_tms = mem.bytesAsSlice(lu16, arm9[hm_tm_index..][0..hm_tm_len]);

        const map_file = try file_system.getNarc(info.map_file);
        const scripts = try file_system.getNarc(info.scripts);
        const commands = try findScriptCommands(info.version, scripts, allocator);
        errdefer {
            allocator.free(commands.static_pokemons);
            allocator.free(commands.given_pokemons);
            allocator.free(commands.pokeball_items);
        }

        const map_header_bytes = map_file.fileData(.{ .i = info.map_headers });
        return Game{
            .info = info,
            .allocator = allocator,
            .rom = nds_rom,
            .owned = owned,
            .ptrs = .{
                .starters = blk: {
                    var res: [3][]*lu16 = undefined;
                    var filled: usize = 0;
                    errdefer for (res[0..filled]) |item|
                        allocator.free(item);

                    for (info.starters) |offs, i| {
                        res[i] = try allocator.alloc(*lu16, offs.len);
                        filled += 1;

                        for (offs) |offset, j| {
                            const fat = scripts.fat[offset.file];
                            const file_data = scripts.data[fat.start.value()..fat.end.value()];
                            res[i][j] = mem.bytesAsValue(lu16, file_data[offset.offset..][0..2]);
                        }
                    }

                    break :blk res;
                },
                .moves = try (try file_system.getNarc(info.moves)).toSlice(0, Move),
                .trainers = try (try file_system.getNarc(info.trainers)).toSlice(1, Trainer),
                .items = try (try file_system.getNarc(info.itemdata)).toSlice(0, Item),
                .evolutions = try (try file_system.getNarc(info.evolutions)).toSlice(0, EvolutionTable),
                .map_headers = mem.bytesAsSlice(MapHeader, map_header_bytes[0..]),
                .tms1 = hm_tms[0..92],
                .hms = hm_tms[92..98],
                .tms2 = hm_tms[98..],
                .static_pokemons = commands.static_pokemons,
                .given_pokemons = commands.given_pokemons,
                .pokeball_items = commands.pokeball_items,

                .wild_pokemons = try file_system.getNarc(info.wild_pokemons),
                .pokemons = try file_system.getNarc(info.pokemons),
                .level_up_moves = try file_system.getNarc(info.level_up_moves),
                .hidden_hollows = if (info.hidden_hollows) |h| try (try file_system.getNarc(h)).toSlice(0, HiddenHollow) else null,
                .scripts = scripts,
            },
        };
    }

    pub fn apply(game: *Game) !void {
        try game.rom.replaceSection(game.rom.arm9(), game.owned.arm9);
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

    /// Applies the `trainer_parties` owned field to the rom.
    fn applyTrainerParties(game: Game) !void {
        const FullParty = [6]PartyMemberBoth;
        const full_party_size = @sizeOf(FullParty);
        const PNone = PartyMemberNone;
        const PItem = PartyMemberItem;
        const PMoves = PartyMemberMoves;
        const allocator = game.allocator;

        const file_system = game.rom.fileSystem();
        const trainer_parties_narc = try file_system.openFileData(nds.fs.root, game.info.parties);
        const trainers = try (try file_system.getNarc(game.info.trainers)).toSlice(1, Trainer);
        const trainer_parties = game.owned.trainer_parties;

        // Calculate size of the new trainer party narc
        const content_size = full_party_size * trainer_parties.len;
        const size = nds.fs.narcSize(trainer_parties.len, content_size);

        // Here we check if we're able to perform the application inline
        // in the rom. If we're not able to, the we allocate a buffer,
        // and create the narc in that instead.
        const can_apply_inline = trainer_parties_narc.len >= size;
        const buf = if (can_apply_inline)
            trainer_parties_narc
        else
            try allocator.alloc(u8, size);
        defer if (!can_apply_inline)
            allocator.free(buf);

        var builder = nds.fs.SimpleNarcBuilder.init(buf, trainer_parties.len);

        // We make sure that the new narc we create always has room for a full
        // party for all trainers. By doing this, all future applies can always
        // be done inline, and allocations can be avoided. This also makes patches
        // generated simpler.
        for (builder.fat()) |*f, i|
            f.* = nds.Range.init(full_party_size * i, full_party_size * (i + 1));

        for (trainer_parties) |party, i| {
            const party_type = if (i != 0 and i - 1 < trainers.len) trainers[i - 1].party_type else .none;
            const rest = buf[builder.stream.pos + i * full_party_size ..];
            switch (party_type) {
                .none => {
                    for (mem.bytesAsSlice(PNone, rest[0..@sizeOf([6]PNone)])) |*m, j| {
                        m.* = PartyMemberNone{ .base = party[j].base };
                    }
                    mem.set(u8, rest[@sizeOf([6]PNone)..full_party_size], 0);
                },
                .item => {
                    for (mem.bytesAsSlice(PItem, rest[0..@sizeOf([6]PItem)])) |*m, j| {
                        m.* = PartyMemberItem{
                            .base = party[j].base,
                            .item = party[j].item,
                        };
                    }
                    mem.set(u8, rest[@sizeOf([6]PItem)..full_party_size], 0);
                },
                .moves => {
                    for (mem.bytesAsSlice(PMoves, rest[0..@sizeOf([6]PMoves)])) |*m, j| {
                        m.* = PartyMemberMoves{
                            .base = party[j].base,
                            .moves = party[j].moves,
                        };
                    }
                    mem.set(u8, rest[@sizeOf([6]PMoves)..full_party_size], 0);
                },
                .both => mem.bytesAsValue(FullParty, rest[0..full_party_size]).* = party,
            }
        }

        // If we where not able to perform the application inline, then
        // we will have to replace the old narc with the new one.
        const res = builder.finish();
        if (!can_apply_inline)
            try game.rom.replaceSection(trainer_parties_narc, res);
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
            getter: fn ([]const u8) Str,

            const Str = struct { key: u16, str: []const u8 };

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
                        fn getter(buf: []const u8) Str {
                            debug.assert(buf.len == @sizeOf(S));
                            const unaligned = mem.bytesAsValue(S, buf[0..@sizeOf(S)]);
                            const str = @alignCast(@alignOf(S), unaligned);
                            return .{ .key = str.key, .str = str.span() };
                        }
                    }.getter,
                };
            }

            fn len(table: @This()) u32 {
                return @intCast(u32, table.slice.len) / table.elem_size;
            }

            fn at(table: @This(), i: usize) Str {
                const rest = table.slice[i * table.elem_size ..];
                return table.getter(rest[0..table.elem_size]);
            }
        };
        const tables = [_]StringTable{
            StringTable.init(info.type_names, 8, game.owned.type_names),
            StringTable.init(info.pokemon_names, 16, game.owned.pokemon_names),
            StringTable.init(info.item_names, 16, game.owned.item_names),
            StringTable.init(info.ability_names, 16, game.owned.ability_names),
            StringTable.init(info.move_names, 16, game.owned.move_names),
            StringTable.init(info.trainer_names, 16, game.owned.trainer_names),
            StringTable.init(info.map_names, 32, game.owned.map_names),
            StringTable.init(info.pokedex_category_names, 32, game.owned.pokedex_category_names),
            StringTable.init(info.item_names_on_the_ground, 64, game.owned.item_names_on_the_ground),
            StringTable.init(info.item_descriptions, 128, game.owned.item_descriptions),
            StringTable.init(info.move_descriptions, 256, game.owned.move_descriptions),
        };

        const file_system = game.rom.fileSystem();
        const text_bytes = try file_system.openFileData(nds.fs.root, game.info.text);
        const text = try nds.fs.Fs.fromNarc(text_bytes);

        // We then calculate the size of the content for our new narch. We also
        // check that we can perform the application inline.
        var can_apply_inline = true;
        var content_size: usize = 0;
        for (text.fat) |f, i| {
            for (tables) |table| {
                if (i != table.file)
                    continue;

                const size = EncryptedStringTable.size(
                    1,
                    table.len(),
                    table.chars * table.len(),
                );
                // If any of the new encrypted tables does not fit in their
                // old file, then we cannot apply inline.
                can_apply_inline = can_apply_inline and f.len() >= size;
                content_size += size;
                break;
            } else {
                content_size += f.len();
            }
        }

        const size = nds.fs.narcSize(text.fat.len, content_size);
        const buf = if (can_apply_inline)
            text_bytes
        else
            try allocator.alloc(u8, size);
        defer if (!can_apply_inline)
            allocator.free(buf);

        var builder = nds.fs.SimpleNarcBuilder.init(buf, text.fat.len);
        const fat = builder.fat();
        const stream = builder.stream.outStream();
        const files_offset = builder.stream.pos;
        for (text.fat) |f, i| {
            // If we can apply inline, then we assert that we never change
            // the start location of any of the files in the narc. This is
            // important, orelse we will have overriden some data, which
            // should not happen when application is possible.
            const start = builder.stream.pos;
            defer fat[i] = nds.Range.init(start - files_offset, builder.stream.pos - files_offset);
            debug.assert(!can_apply_inline or start - files_offset == f.start.value());

            for (tables) |table| {
                if (i != table.file)
                    continue;

                const Header = EncryptedStringTable.Header;
                const Entry = EncryptedStringTable.Entry;
                const file_size = EncryptedStringTable.size(
                    1,
                    table.len(),
                    table.chars * table.len(),
                );
                const entries_count = @intCast(u16, table.len());
                const entry_size = table.chars + 1; // Always make room for a terminator
                try stream.writeAll(&mem.toBytes(Header{
                    .sections = lu16.init(1),
                    .entries = lu16.init(entries_count),
                    .file_size = lu32.init(file_size),
                    .unknown2 = lu32.init(0),
                }));

                const section_start = @sizeOf(Header) + @sizeOf(lu32);
                try stream.writeAll(&lu32.init(section_start).bytes);
                try stream.writeAll(&lu32.init(entries_count *
                    (@sizeOf(Entry) + entry_size * 2)).bytes);

                const entries_start = builder.stream.pos;
                for (@as([*]void, undefined)[0..entries_count]) |_, j| {
                    try stream.writeAll(&mem.toBytes(Entry{
                        .offset = lu32.init(0),
                        .count = lu16.init(0),
                        .unknown = lu16.init(0),
                    }));
                }

                const entries = mem.bytesAsSlice(Entry, buf[entries_start..builder.stream.pos]);
                for (entries) |*entry, j| {
                    const pos = builder.stream.pos;
                    const str = table.at(j);
                    try encode(str.str, stream);

                    const str_end = builder.stream.pos;
                    const encoded_str = mem.bytesAsSlice(lu16, buf[pos..str_end]);
                    encrypt(encoded_str, str.key);

                    const str_len = @intCast(u16, (str_end - pos) / 2);
                    entry.offset = lu32.init(@intCast(u32, (pos - start) - section_start));
                    entry.count = lu16.init(str_len);

                    // Pad the string, so that each entry is always entry_size
                    // apart. This ensure that patches generated from tm35-apply
                    // are small.
                    try stream.writeByteNTimes(0, (entry_size - str_len) * 2);
                    debug.assert(builder.stream.pos - pos == entry_size * 2);
                }

                // Assert that we got the file size right.
                debug.assert(builder.stream.pos - start == file_size);
                debug.assert(builder.stream.pos - start == file_size);
                break;
            } else if (can_apply_inline) {
                // When appling inline, we don't need to copy files
                // we don't change, so we just skip over them.
                builder.stream.pos += f.len();
            } else {
                try stream.writeAll(text.data[f.start.value()..f.end.value()]);
            }
        }

        debug.assert(buf.len == builder.stream.pos);
        const res = builder.finish();
        if (!can_apply_inline)
            try game.rom.replaceSection(text_bytes, res);
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
            var var_800C: ?*lu16 = null;

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
                    // If we hit var 0x800C, the var_800C_tmp will be set and
                    // var_800C will become var_800C_tmp. Then the next iteration
                    // of this loop will set var_8008 to null again. This allows us
                    // to store this state for only the next iteration of the loop.
                    var var_800C_tmp: ?*lu16 = null;
                    defer var_800C = var_800C_tmp;

                    switch (command.tag) {
                        .wild_battle => try static_pokemons.append(.{
                            .species = &command.data().wild_battle.species,
                            .level = &command.data().wild_battle.level,
                        }),
                        .wild_battle_store_result => try static_pokemons.append(.{
                            .species = &command.data().wild_battle_store_result.species,
                            .level = &command.data().wild_battle_store_result.level,
                        }),
                        .give_pokemon => try given_pokemons.append(.{
                            .species = &command.data().give_pokemon.species,
                            .level = &command.data().give_pokemon.level,
                        }),

                        // In scripts, field items are two set_var_eq_val commands
                        // followed by a jump to the code that gives this item:
                        //   set_var_eq_val 0x800C // Item given
                        //   set_var_eq_val 0x800D // Amount of items
                        //   jump ???
                        .set_var_eq_val => switch (command.data().set_var_eq_val.container.value()) {
                            0x800C => var_800C_tmp = &command.data().set_var_eq_val.value,
                            0x800D => if (var_800C) |item| {
                                const amount = &command.data().set_var_eq_val.value;
                                try pokeball_items.append(PokeballItem{
                                    .item = item,
                                    .amount = amount,
                                });
                            },
                            else => {},
                        },
                        .jump, .@"if" => {
                            const off = switch (command.tag) {
                                .jump => command.data().jump.offset.value(),
                                .@"if" => command.data().@"if".offset.value(),
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
        debug.assert(table.sectionCount() == 1);

        const count = table.entryCount(0);
        const res = try allocator.alloc(String(len), count);
        errdefer allocator.free(res);

        mem.set(String(len), res, String(len){});
        for (res) |*str, i| {
            var fba = io.fixedBufferStream(&str.buf);
            const stream = fba.outStream();
            const encrypted_string = table.getEncryptedString(0, i);
            try decrypt(encrypted_string, stream);
            str.key = getKey(encrypted_string);
        }

        return res;
    }
};
