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
const testing = std.testing;
const unicode = std.unicode;

const nds = rom.nds;

const lu128 = rom.int.lu128;
const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;

pub const BasePokemon = extern struct {
    stats: common.Stats,
    types: [2]u8,

    catch_rate: u8,
    stage: u8,

    ev: common.PaddedEvYield,
    items: [3]lu16,

    gender_ratio: u8,
    egg_cycles: u8,
    base_friendship: u8,

    growth_rate: common.GrowthRate,
    egg_groups: [2]common.EggGroup,

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
    machine_learnset: lu128 align(4),

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

    pub fn toParent(base: *align(1) PartyMemberBase, comptime Parent: type) *align(1) Parent {
        return @ptrCast(base);
        // return @fieldParentPtr(Parent, "base", base);
    }
};

pub const PartyMemberNone = extern struct {
    base: PartyMemberBase = PartyMemberBase{},

    comptime {
        debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const PartyMemberItem = extern struct {
    base: PartyMemberBase = PartyMemberBase{},
    item: lu16 = lu16.init(0),

    comptime {
        debug.assert(@sizeOf(@This()) == 10);
    }
};

pub const PartyMemberMoves = extern struct {
    base: PartyMemberBase = PartyMemberBase{},
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
    party_type: common.PartyType,
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

    pub fn partyMember(trainer: Trainer, party: []u8, i: usize) ?*align(1) PartyMemberBase {
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

pub const Move = extern struct {
    type: u8,
    effect_category: u8,
    category: Category,
    power: u8,
    accuracy: u8,
    pp: u8,
    priority: u8,
    // min_hits: u4,
    // max_hits: u4,
    min_max_hits: u8,
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

    // TODO: Figure out if this is actually how the last fields are laid out.
    padding1: [2]u8,
    flags: lu16,
    padding2: [2]u8,

    pub const Category = enum(u8) {
        status = 0x00,
        physical = 0x01,
        special = 0x02,
    };

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

    pub const Method = enum(u8) {
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
        return @truncate(s.value.value());
    }

    pub fn setSpecies(s: *align(1) Species, spe: u10) void {
        s.value = lu16.init((@as(u16, s.form()) << @as(u4, 10)) | spe);
    }

    pub fn form(s: Species) u6 {
        return @truncate(s.value.value() >> 10);
    }

    pub fn setForm(s: *align(1) Species, f: u10) void {
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

pub const Pocket = enum(u4) {
    items = 0,
    tms_hms = 1,
    key_items = 2,
    poke_balls = 8,
    _,
};

// https://github.com/projectpokemon/PPRE/blob/master/pokemon/itemtool/itemdata.py
pub const Item = extern struct {
    price: lu16,
    battle_effect: u8,
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
    pokemons: [8]HollowPokemons,
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
    species: *align(1) lu16,
    level: *align(1) lu16,
};

const PokeballItem = struct {
    item: *align(1) lu16,
    amount: *align(1) lu16,
};

const EncryptedStringTable = struct {
    data: []u8,

    fn sectionCount(table: EncryptedStringTable) u16 {
        return table.header().sections.value();
    }

    fn entryCount(table: EncryptedStringTable) u16 {
        return table.header().entries.value();
    }

    fn getEncryptedString(
        table: EncryptedStringTable,
        section_i: usize,
        entry_i: usize,
    ) []align(1) lu16 {
        const section_offset = table.sectionOffsets()[section_i].value();
        const entry = table.entries(section_offset)[entry_i];
        const offset = section_offset + entry.offset.value();
        const res = table.data[offset..][0 .. entry.count.value() * @sizeOf(lu16)];
        return mem.bytesAsSlice(lu16, res);
    }

    const Header = extern struct {
        sections: lu16,
        entries: lu16,
        file_size: lu32,
        unknown2: lu32,
    };

    const Entry = extern struct {
        offset: lu32,
        count: lu16,
        unknown: lu16,
    };

    fn header(table: EncryptedStringTable) *align(1) Header {
        return @ptrCast(table.data[0..@sizeOf(Header)]);
    }

    fn sectionOffsets(table: EncryptedStringTable) []align(1) lu32 {
        const h = table.header();
        const rest = table.data[@sizeOf(Header)..];
        return mem.bytesAsSlice(lu32, rest[0 .. @sizeOf(lu32) * h.sections.value()]);
    }

    fn entries(table: EncryptedStringTable, section_offset: u32) []align(1) Entry {
        const h = table.header();
        _ = mem.bytesAsValue(lu32, table.data[section_offset..][0..@sizeOf(lu32)]);
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

fn decrypt(data: []align(1) const lu16, out: anytype) !u16 {
    const H = struct {
        fn output(out2: anytype, char: u16) !bool {
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
    const table = KeyTable.init(key);
    const res = table.get(data.len, 0);
    const first = data[0].value() ^ res;
    const compressed = first == 0xF100;
    const start = @intFromBool(compressed);

    var bits: u5 = 0;
    var container: u32 = 0;
    for (data[start..], start..) |c, i| {
        const decoded = c.value() ^ table.get(data.len, i);
        if (compressed) {
            container |= @as(u32, decoded) << bits;
            bits += 16;

            while (bits >= 9) : (bits -= 9) {
                const char: u16 = @intCast(container & 0x1FF);
                if (char == 0x1Ff)
                    return res;
                if (try H.output(out, char))
                    return res;
                container >>= 9;
            }
        } else {
            if (try H.output(out, decoded))
                return res;
        }
    }

    return res;
}

fn getKey(data: []align(1) const lu16) u16 {
    const last = data[data.len - 1].value();
    debug.assert(last ^ (last ^ 0xFFFF) == 0xFFFF);
    return last ^ 0xFFFF;
}

fn encode(data: []const u8, out: anytype) !void {
    var n: usize = 0;
    while (n < data.len) {
        if (mem.startsWith(u8, data[n..], "\n")) {
            try out.writeInt(u16, 0xfffe, .little);
            n += 1;
            continue;
        }
        if (mem.startsWith(u8, data[n..], "\\x")) {
            const hex = data[n + 2 ..][0..4];
            const parsed = try fmt.parseUnsigned(u16, hex, 16);
            try out.writeInt(u16, parsed, .little);
            n += 6;
            continue;
        }

        const ulen = unicode.utf8ByteSequenceLength(data[n]) catch unreachable;
        if (data.len < n + ulen)
            break;

        const codepoint = unicode.utf8Decode(data[n..][0..ulen]) catch unreachable;
        try out.writeInt(u16, @as(u16, @intCast(codepoint)), .little);
        n += ulen;
    }
    try out.writeInt(u16, 0xffff, .little);
}

fn encrypt(data: []align(1) lu16, _key: u16) void {
    var key = _key;
    for (data) |*c| {
        c.* = lu16.init(c.value() ^ key);
        key = (key << 3) | (key >> 13);
    }
}

const KeyTable = struct {
    const table_size = 16;

    table: [table_size]u16,
    len: usize,

    pub fn init(_key: u16) KeyTable {
        var table: [table_size]u16 = undefined;
        var key = _key;
        for (&table, 1..) |*entry, i| {
            entry.* = key;
            key = (key >> 3) | (key << 13);
            if (key == _key)
                return .{ .table = table, .len = i };
        }

        unreachable;
    }

    fn get(table: KeyTable, len: usize, i: usize) u16 {
        return table.table[(len - (i + 1)) % table.len];
    }
};

// This is the old correct version. We use this for testing the KeyTable
fn keyForI(key: u16, len: usize, i: usize) u16 {
    const it = len - (i + 1);
    var res: u16 = key;

    for (0..it) |_|
        res = (res >> 3) | (res << 13);

    return res;
}

test "KeyTable" {
    var j: usize = 0;
    while (j <= math.maxInt(u16)) : (j += 1)
        _ = KeyTable.init(@intCast(j));

    for ([_]u16{ 0xf0f0, 0x0f0f, 0xdead, 0xbeef }) |key| {
        const table = KeyTable.init(key);
        var len: usize = 0;
        while (len < 40) : (len += 1) {
            var i: usize = 0;
            while (i < len) : (i += 1)
                try testing.expectEqual(keyForI(key, len, i), table.get(len, i));
        }
    }
}

pub const StringTable = struct {
    file_this_was_extracted_from: u16,
    buf: []u8 = &[_]u8{},
    keys: []u16 = &[_]u16{},

    pub fn create(
        allocator: mem.Allocator,
        file_this_was_extracted_from: u16,
        number_of_strings: usize,
        max_string_len: usize,
    ) !StringTable {
        const buf = try allocator.alloc(u8, number_of_strings * max_string_len);
        errdefer allocator.free(buf);
        const keys = try allocator.alloc(u16, number_of_strings);
        errdefer allocator.free(keys);
        return StringTable{
            .file_this_was_extracted_from = file_this_was_extracted_from,
            .buf = buf,
            .keys = keys,
        };
    }

    pub fn destroy(table: StringTable, allocator: mem.Allocator) void {
        allocator.free(table.buf);
        allocator.free(table.keys);
    }

    pub fn maxStringLen(table: StringTable) usize {
        return table.buf.len / table.keys.len;
    }

    pub fn get(table: StringTable, i: usize) []u8 {
        const len = table.maxStringLen();
        return table.buf[len * i ..][0..len];
    }

    pub fn getSpan(table: StringTable, i: usize) []u8 {
        const res = table.get(i);
        const end = mem.indexOfScalar(u8, res, 0) orelse res.len;
        return res[0..end];
    }

    pub fn encryptedSize(table: StringTable) u32 {
        return EncryptedStringTable.size(
            1,
            @intCast(table.keys.len),
            @intCast(table.maxStringLen() * table.keys.len),
        );
    }
};

pub const Game = struct {
    info: offsets.Info,
    allocator: mem.Allocator,
    rom: *nds.Rom,
    owned: Owned,
    ptrs: Pointers,

    // These fields are owned by the game and will be applied to
    // the rom oppon calling `apply`.
    pub const Owned = struct {
        old_arm_len: usize,
        arm9: []u8,
        trainer_parties: [][6]PartyMemberBoth,
        text: Text,
        story: Story,

        pub fn deinit(owned: Owned, allocator: mem.Allocator) void {
            allocator.free(owned.arm9);
            allocator.free(owned.trainer_parties);
            owned.text.deinit(allocator);
            owned.story.deinit(allocator);
        }
    };

    pub const Text = struct {
        type_names: StringTable,
        pokemon_names: StringTable,
        trainer_names: StringTable,
        move_names: StringTable,
        ability_names: StringTable,
        item_names: StringTable,
        map_names: StringTable,
        pokedex_category_names: StringTable,
        item_names_on_the_ground: StringTable,
        item_descriptions: StringTable,
        move_descriptions: StringTable,

        pub const Array = [std.meta.fields(Text).len]StringTable;

        pub fn deinit(text: Text, allocator: mem.Allocator) void {
            for (text.asArray()) |table|
                table.destroy(allocator);
        }

        pub fn asArray(text: Text) Array {
            var res: Array = undefined;
            inline for (std.meta.fields(Text), 0..) |field, i|
                res[i] = @field(text, field.name);

            return res;
        }
    };

    pub const Story = struct {
        starter_choice: StringTable,

        pub const Array = [std.meta.fields(Story).len]StringTable;

        pub fn deinit(story: Story, allocator: mem.Allocator) void {
            for (story.asArray()) |table|
                table.destroy(allocator);
        }

        pub fn asArray(story: Story) Array {
            var res: Array = undefined;
            inline for (std.meta.fields(Story), 0..) |field, i|
                res[i] = @field(story, field.name);

            return res;
        }
    };

    // The fields below are pointers into the nds rom and will
    // be invalidated oppon calling `apply`.
    pub const Pointers = struct {
        starters: [3][]*align(1) lu16,
        moves: []align(1) Move,
        trainers: []align(1) Trainer,
        items: []align(1) Item,
        tms1: []align(1) lu16,
        hms: []align(1) lu16,
        tms2: []align(1) lu16,
        evolutions: []align(1) EvolutionTable,
        map_headers: []align(1) MapHeader,
        hidden_hollows: ?[]align(1) HiddenHollow,

        wild_pokemons: nds.fs.Fs,
        pokemons: nds.fs.Fs,
        level_up_moves: nds.fs.Fs,
        scripts: nds.fs.Fs,

        static_pokemons: []StaticPokemon,
        given_pokemons: []StaticPokemon,
        pokeball_items: []PokeballItem,

        pub fn deinit(ptrs: Pointers, allocator: mem.Allocator) void {
            for (ptrs.starters) |starter_ptrs|
                allocator.free(starter_ptrs);
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

    pub fn fromRom(allocator: mem.Allocator, nds_rom: *nds.Rom) !Game {
        const file_system = nds_rom.fileSystem();
        var fbs = io.fixedBufferStream(nds_rom.data.items);
        const info = try identify(fbs.reader());
        const arm9 = try nds.blz.decode(allocator, nds_rom.arm9());
        errdefer allocator.free(arm9);

        const text = try file_system.openNarc(nds.fs.root, info.text);
        const story = try file_system.openNarc(nds.fs.root, info.story);
        const trainers = try (try file_system.openNarc(nds.fs.root, info.trainers)).toSlice(1, Trainer);
        const trainer_parties_narc = try file_system.openNarc(nds.fs.root, info.parties);
        const trainer_parties = try allocator.alloc([6]PartyMemberBoth, trainer_parties_narc.fat.len);
        errdefer allocator.free(trainer_parties);

        for (trainer_parties, 0..) |*party, i| {
            const party_data = trainer_parties_narc.fileData(.{ .i = @intCast(i) });
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
            @memset(party[party_size..], PartyMemberBoth{});
        }

        const type_names = try decryptStringTable(allocator, 8, text, info.type_names);
        errdefer type_names.destroy(allocator);
        const pokemon_names = try decryptStringTable(allocator, 16, text, info.pokemon_names);
        errdefer pokemon_names.destroy(allocator);
        const item_names = try decryptStringTable(allocator, 16, text, info.item_names);
        errdefer item_names.destroy(allocator);
        const ability_names = try decryptStringTable(allocator, 16, text, info.ability_names);
        errdefer ability_names.destroy(allocator);
        const move_names = try decryptStringTable(allocator, 16, text, info.move_names);
        errdefer move_names.destroy(allocator);
        const trainer_names = try decryptStringTable(allocator, 16, text, info.trainer_names);
        errdefer trainer_names.destroy(allocator);
        const map_names = try decryptStringTable(allocator, 32, text, info.map_names);
        errdefer map_names.destroy(allocator);
        const pokedex_category_names = try decryptStringTable(allocator, 32, text, info.pokedex_category_names);
        errdefer pokedex_category_names.destroy(allocator);
        const item_names_on_the_ground = try decryptStringTable(allocator, 64, text, info.item_names_on_the_ground);
        errdefer item_names_on_the_ground.destroy(allocator);
        const item_descriptions = try decryptStringTable(allocator, 128, text, info.item_descriptions);
        errdefer item_descriptions.destroy(allocator);
        const move_descriptions = try decryptStringTable(allocator, 256, text, info.move_descriptions);
        errdefer move_descriptions.destroy(allocator);

        const starter_choice = try decryptStringTable(allocator, 256 * 2, story, info.starter_choice);
        errdefer starter_choice.destroy(allocator);

        return fromRomEx(allocator, nds_rom, info, .{
            .old_arm_len = nds_rom.arm9().len,
            .arm9 = arm9,
            .trainer_parties = trainer_parties,
            .text = .{
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
            },
            .story = .{
                .starter_choice = starter_choice,
            },
        });
    }

    pub fn fromRomEx(
        allocator: mem.Allocator,
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

        const map_file = try file_system.openNarc(nds.fs.root, info.map_file);
        const scripts = try file_system.openNarc(nds.fs.root, info.scripts);

        const starters = blk: {
            var res: [3][]*align(1) lu16 = undefined;
            var filled: usize = 0;
            errdefer for (res[0..filled]) |item|
                allocator.free(item);

            for (info.starters, &res) |offs, *res_offs| {
                res_offs.* = try allocator.alloc(*lu16, offs.len);
                filled += 1;

                for (offs, res_offs.*) |offset, *res_offset| {
                    const fat = scripts.fat[offset.file];
                    const file_data = scripts.data[fat.start.value()..fat.end.value()];
                    res_offset.* = mem.bytesAsValue(lu16, file_data[offset.offset..][0..2]);
                }
            }

            break :blk res;
        };

        const commands = try findScriptCommands(scripts, allocator, starters);
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
                .starters = starters,
                .moves = try (try file_system.openNarc(nds.fs.root, info.moves)).toSlice(0, Move),
                .trainers = try (try file_system.openNarc(nds.fs.root, info.trainers)).toSlice(1, Trainer),
                .items = try (try file_system.openNarc(nds.fs.root, info.itemdata)).toSlice(0, Item),
                .evolutions = try (try file_system.openNarc(nds.fs.root, info.evolutions)).toSlice(0, EvolutionTable),
                .map_headers = mem.bytesAsSlice(MapHeader, map_header_bytes[0..]),
                .tms1 = hm_tms[0..92],
                .hms = hm_tms[92..98],
                .tms2 = hm_tms[98..],
                .static_pokemons = commands.static_pokemons,
                .given_pokemons = commands.given_pokemons,
                .pokeball_items = commands.pokeball_items,

                .wild_pokemons = try file_system.openNarc(nds.fs.root, info.wild_pokemons),
                .pokemons = try file_system.openNarc(nds.fs.root, info.pokemons),
                .level_up_moves = try file_system.openNarc(nds.fs.root, info.level_up_moves),
                .hidden_hollows = if (info.hidden_hollows) |h| try (try file_system.openNarc(nds.fs.root, h)).toSlice(0, HiddenHollow) else null,
                .scripts = scripts,
            },
        };
    }

    pub fn apply(game: *Game) !void {
        game.updateStarterDialog();
        try game.applyArm9();
        try game.applyTrainerParties();
        try game.applyStrings(&game.owned.story.asArray(), game.info.story);
        try game.applyStrings(&game.owned.text.asArray(), game.info.text);

        game.ptrs.deinit(game.allocator);
        game.* = try fromRomEx(
            game.allocator,
            game.rom,
            game.info,
            game.owned,
        );
    }

    fn updateStarterDialog(game: Game) void {
        for (game.ptrs.starters, game.info.starter_choice_indexs) |starter_ptrs, index| {
            const starter = starter_ptrs[0].value();
            const text = game.owned.story.starter_choice.get(index);
            @memset(text, 0);

            const starter_name = game.owned.text.pokemon_names.getSpan(starter);
            mem.copy(u8, text, starter_name);
        }
    }

    fn applyArm9(game: Game) !void {
        const arm9 = try nds.blz.encode(game.allocator, game.owned.arm9, 0x4000);
        defer game.allocator.free(arm9);

        // In the secure area, there is an offset that points to the end of the compressed arm9.
        // We have to find that offset and replace it with the new size.
        const secure_area = arm9[0..0x4000];

        var len_bytes: [3]u8 = undefined;
        mem.writeInt(u24, &len_bytes, @as(u24, @intCast(game.owned.old_arm_len + 0x4000)), .little);
        if (mem.indexOf(u8, secure_area, &len_bytes)) |off| {
            mem.writeInt(
                u24,
                secure_area[off..][0..3],
                @as(u24, @intCast(arm9.len + 0x4000)),
                .little,
            );
        }

        mem.copy(
            u8,
            try game.rom.resizeSection(game.rom.arm9(), arm9.len),
            arm9,
        );
    }

    /// Applies the `trainer_parties` owned field to the rom.
    fn applyTrainerParties(game: Game) !void {
        const FullParty = [6]PartyMemberBoth;
        const full_party_size = @sizeOf(FullParty);
        const PNone = PartyMemberNone;
        const PItem = PartyMemberItem;
        const PMoves = PartyMemberMoves;

        const file_system = game.rom.fileSystem();
        const trainer_parties_narc = try file_system.openFileData(nds.fs.root, game.info.parties);
        const trainer_parties = game.owned.trainer_parties;

        const content_size = @sizeOf(FullParty) *
            trainer_parties.len;
        const size = nds.fs.narcSize(trainer_parties.len, content_size);

        const buf = try game.rom.resizeSection(trainer_parties_narc, size);
        const trainers = try (try file_system.openNarc(nds.fs.root, game.info.trainers)).toSlice(1, Trainer);

        var builder = nds.fs.SimpleNarcBuilder.init(buf, trainer_parties.len);

        // We make sure that the new narc we create always has room for a full
        // party for all trainers. By doing this, all future applies can always
        // be done inline, and allocations can be avoided. This also makes patches
        // generated simpler.
        for (builder.fat(), 0..) |*f, i|
            f.* = nds.Range.init(full_party_size * i, full_party_size * (i + 1));

        for (trainer_parties, 0..) |party, i| {
            const party_type = if (i != 0 and i - 1 < trainers.len) trainers[i - 1].party_type else .none;
            const rest = buf[builder.stream.pos + i * full_party_size ..];
            switch (party_type) {
                .none => {
                    for (mem.bytesAsSlice(PNone, rest[0..@sizeOf([6]PNone)]), party) |*m, p| {
                        m.* = PartyMemberNone{ .base = p.base };
                    }
                    @memset(rest[@sizeOf([6]PNone)..full_party_size], 0);
                },
                .item => {
                    for (mem.bytesAsSlice(PItem, rest[0..@sizeOf([6]PItem)]), party) |*m, p| {
                        m.* = PartyMemberItem{
                            .base = p.base,
                            .item = p.item,
                        };
                    }
                    @memset(rest[@sizeOf([6]PItem)..full_party_size], 0);
                },
                .moves => {
                    for (mem.bytesAsSlice(PMoves, rest[0..@sizeOf([6]PMoves)]), party) |*m, p| {
                        m.* = PartyMemberMoves{
                            .base = p.base,
                            .moves = p.moves,
                        };
                    }
                    @memset(rest[@sizeOf([6]PMoves)..full_party_size], 0);
                },
                .both => mem.bytesAsValue(FullParty, rest[0..full_party_size]).* = party,
            }
        }

        _ = builder.finish();
    }

    /// Applies all decrypted strings to the game.
    fn applyStrings(game: Game, strings: []const StringTable, string_file: []const u8) !void {
        const buf = blk: {
            const file_system = game.rom.fileSystem();
            const text_bytes = try file_system.openFileData(nds.fs.root, string_file);
            const text = try nds.fs.Fs.fromNarc(text_bytes);

            // We then calculate the size of the content for our new narc
            var extra_bytes: usize = 0;
            for (strings) |table| {
                extra_bytes += math.sub(
                    u32,
                    table.encryptedSize(),
                    text.fat[table.file_this_was_extracted_from].len(),
                ) catch 0;
            }

            break :blk try game.rom.resizeSection(
                text_bytes,
                text_bytes.len + extra_bytes,
            );
        };

        const text = try nds.fs.Fs.fromNarc(buf);
        for (strings) |table| {
            const new_file_size = table.encryptedSize();
            const file = &text.fat[table.file_this_was_extracted_from];

            const file_needs_a_resize = file.len() < new_file_size;
            if (file_needs_a_resize) {
                const extra = new_file_size - file.len();
                mem.copyBackwards(
                    u8,
                    text.data[file.end.value() + extra ..],
                    text.data[file.end.value() .. text.data.len - extra],
                );

                const old_file_end = file.end.value();
                file.* = nds.Range.init(file.start.value(), file.end.value() + extra);

                for (text.fat) |*f| {
                    const start = f.start.value();
                    const end = f.end.value();
                    const file_is_before_the_file_we_moved = start < old_file_end;
                    if (file_is_before_the_file_we_moved)
                        continue;

                    f.* = nds.Range.init(start + extra, end + extra);
                }
            }

            const Header = EncryptedStringTable.Header;
            const Entry = EncryptedStringTable.Entry;
            const bytes = text.data[file.start.value()..file.end.value()];
            debug.assert(bytes.len == new_file_size);

            // Non of the writes here can fail as long as we calculated the size
            // of the file correctly above
            var fbs = io.fixedBufferStream(bytes);
            const writer = fbs.writer();
            const number_of_entries: u16 = @intCast(table.keys.len);
            writer.writeAll(&mem.toBytes(Header{
                .sections = lu16.init(1),
                .entries = lu16.init(number_of_entries),
                .file_size = lu32.init(new_file_size),
                .unknown2 = lu32.init(0),
            })) catch unreachable;

            const chars_per_entry = table.maxStringLen() + 1; // Always make room for a terminator
            const bytes_per_entry = chars_per_entry * 2;
            const start_of_section = @sizeOf(Header) + @sizeOf(lu32);
            writer.writeInt(u32, start_of_section, .little) catch unreachable;
            writer.writeInt(u32, @as(u32, @intCast(number_of_entries *
                (@sizeOf(Entry) + bytes_per_entry))), .little) catch unreachable;

            const start_of_entry_table = writer.context.pos;
            for (0..number_of_entries) |_| {
                writer.writeAll(&mem.toBytes(Entry{
                    .offset = lu32.init(0),
                    .count = lu16.init(0),
                    .unknown = lu16.init(0),
                })) catch unreachable;
            }

            const entries = mem.bytesAsSlice(Entry, bytes[start_of_entry_table..writer.context.pos]);
            for (entries, 0..) |*entry, j| {
                const start_of_str = writer.context.pos;
                const str = table.getSpan(j);
                try encode(str, writer);

                const end_of_str = writer.context.pos;
                const encoded_str = mem.bytesAsSlice(lu16, bytes[start_of_str..end_of_str]);
                encrypt(encoded_str, table.keys[j]);

                const length_of_str: u16 = @intCast((end_of_str - start_of_str) / 2);
                entry.offset = lu32.init(@intCast(start_of_str - start_of_section));
                entry.count = lu16.init(length_of_str);

                // Pad the string, so that each entry is always entry_size
                // apart. This ensure that patches generated from tm35-apply
                // are small.
                writer.writeByteNTimes(0, (chars_per_entry - length_of_str) * 2) catch unreachable;
                debug.assert(writer.context.pos - start_of_str == bytes_per_entry);
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

    fn findScriptCommands(
        scripts: nds.fs.Fs,
        allocator: mem.Allocator,
        starters: [3][]*align(1) lu16,
    ) !ScriptCommands {
        var static_pokemons = std.ArrayList(StaticPokemon).init(allocator);
        errdefer static_pokemons.deinit();
        var given_pokemons = std.ArrayList(StaticPokemon).init(allocator);
        errdefer given_pokemons.deinit();
        var pokeball_items = std.ArrayList(PokeballItem).init(allocator);
        errdefer pokeball_items.deinit();

        var script_offsets = std.ArrayList(usize).init(allocator);
        defer script_offsets.deinit();

        var set_var_offsets = std.ArrayList(usize).init(allocator);
        defer set_var_offsets.deinit();

        var given_pokemons_to_resolve = std.AutoArrayHashMap(usize, *align(1) lu16).init(allocator);
        defer given_pokemons_to_resolve.deinit();

        for (scripts.fat) |fat| {
            const script_data = scripts.data[fat.start.value()..fat.end.value()];
            defer script_offsets.shrinkRetainingCapacity(0);
            defer set_var_offsets.shrinkRetainingCapacity(0);
            defer given_pokemons_to_resolve.shrinkRetainingCapacity(0);

            for (script.getScriptOffsets(script_data), 1..) |relative, i| {
                const position = @as(isize, @intCast(i)) * @sizeOf(lu32);
                const offset = math.cast(usize, relative.value() + position) orelse continue;
                if (script_data.len < offset)
                    continue;
                try script_offsets.append(offset);
            }

            var offset_i: usize = 0;
            while (offset_i < script_offsets.items.len) : (offset_i += 1) {
                const offset = script_offsets.items[offset_i];
                var command_offset = offset;
                var decoder = script.CommandDecoder{
                    .bytes = script_data,
                    .i = offset,
                };
                while (decoder.next() catch continue) |command| : (command_offset = decoder.i) {
                    switch (command.kind) {
                        .wild_battle => try static_pokemons.append(.{
                            .species = &command.wild_battle.species,
                            .level = &command.wild_battle.level,
                        }),
                        .wild_battle_store_result => try static_pokemons.append(.{
                            .species = &command.wild_battle_store_result.species,
                            .level = &command.wild_battle_store_result.level,
                        }),
                        .give_pokemon_1 => if (command.give_pokemon_1.species.value() & 0x8000 == 0) {
                            try given_pokemons.append(.{
                                .species = &command.give_pokemon_1.species,
                                .level = &command.give_pokemon_1.level,
                            });
                        } else {
                            try given_pokemons_to_resolve.put(
                                command.give_pokemon_1.species.value(),
                                &command.give_pokemon_1.level,
                            );
                        },
                        .give_pokemon_2 => if (command.give_pokemon_2.species.value() & 0x8000 == 0) {
                            try given_pokemons.append(.{
                                .species = &command.give_pokemon_2.species,
                                .level = &command.give_pokemon_2.level,
                            });
                        } else {
                            try given_pokemons_to_resolve.put(
                                command.give_pokemon_2.species.value(),
                                &command.give_pokemon_2.level,
                            );
                        },
                        .give_pokemon_4 => if (command.give_pokemon_4.species.value() & 0x8000 == 0) {
                            try given_pokemons.append(.{
                                .species = &command.give_pokemon_4.species,
                                .level = &command.give_pokemon_4.level,
                            });
                        } else {
                            try given_pokemons_to_resolve.put(
                                command.give_pokemon_4.species.value(),
                                &command.give_pokemon_4.level,
                            );
                        },
                        .set_var_eq_val,
                        .set_var_2a,
                        => try set_var_offsets.append(command_offset),
                        .jump, .when, .@"if", .call_routine => {
                            const off = switch (command.kind) {
                                .jump => command.jump.offset.value(),
                                .when => command.when.offset.value(),
                                .@"if" => command.@"if".offset.value(),
                                .call_routine => command.call_routine.offset.value(),
                                else => unreachable,
                            };
                            if (math.cast(usize, off + @as(isize, @intCast(decoder.i)))) |loc| {
                                if (loc < script_data.len and
                                    mem.indexOfScalar(usize, script_offsets.items, loc) == null)
                                    try script_offsets.append(loc);
                            }
                        },
                        else => {},
                    }
                }
            }

            for (set_var_offsets.items) |offset| {
                var decoder = script.CommandDecoder{
                    .bytes = script_data,
                    .i = @intCast(offset),
                };

                const first = (decoder.next() catch unreachable).?;
                switch (first.kind) {
                    .set_var_eq_val => if (given_pokemons_to_resolve.get(
                        first.set_var_eq_val.container.value(),
                    )) |level| {
                        try given_pokemons.append(.{
                            .species = &first.set_var_eq_val.value,
                            .level = level,
                        });
                    } else {
                        const item = &first.set_var_eq_val;
                        const amount = script.expectNext(&decoder, .set_var_eq_val) orelse continue;
                        _ = script.expectNext(&decoder, .call_routine) orelse continue;
                        _ = script.expectNext(&decoder, .wait_moment) orelse continue;
                        _ = script.expectNext(&decoder, .unlock_all) orelse continue;
                        _ = script.expectNext(&decoder, .end) orelse continue;
                        if (item.container.value() != 32780 or
                            amount.set_var_eq_val.container.value() != 32781)
                            continue;

                        try pokeball_items.append(.{
                            .item = &item.value,
                            .amount = &amount.set_var_eq_val.value,
                        });
                    },
                    .set_var_2a => {
                        const amount = script.expectNext(&decoder, .set_var_2a) orelse continue;
                        const unknown = script.expectNext(&decoder, .set_var_2a) orelse continue;
                        _ = script.expectNext(&decoder, .call_std) orelse continue;
                        _ = script.expectNext(&decoder, .wait_moment) orelse continue;
                        _ = script.expectNext(&decoder, .unlock_all) orelse continue;
                        _ = script.expectNext(&decoder, .end) orelse continue;
                        if (first.set_var_2a.container.value() != 32768 or
                            amount.set_var_2a.container.value() != 32769 or
                            unknown.set_var_2a.container.value() != 32770)
                            continue;

                        try pokeball_items.append(.{
                            .item = &first.set_var_2a.value,
                            .amount = &amount.set_var_2a.value,
                        });
                    },
                    else => {},
                }
            }
        }

        // Remove starters from given Pokémons
        var i: usize = 0;
        while (i < given_pokemons.items.len) {
            const given_pokemon = given_pokemons.items[i];
            for (starters) |starters_inner| {
                for (starters_inner) |starter| {
                    if (starter == given_pokemon.species) {
                        _ = given_pokemons.swapRemove(i);
                        continue;
                    }
                }
            }

            i += 1;
        }

        return ScriptCommands{
            .static_pokemons = try static_pokemons.toOwnedSlice(),
            .given_pokemons = try given_pokemons.toOwnedSlice(),
            .pokeball_items = try pokeball_items.toOwnedSlice(),
        };
    }

    fn decryptStringTable(allocator: mem.Allocator, max_string_len: usize, text: nds.fs.Fs, file: u16) !StringTable {
        const table = EncryptedStringTable{ .data = text.fileData(.{ .i = file }) };
        debug.assert(table.sectionCount() == 1);

        const count = table.entryCount();
        const res = try StringTable.create(
            allocator,
            file,
            count,
            max_string_len,
        );
        errdefer res.destroy(allocator);

        @memset(res.buf, 0);
        for (res.keys, 0..) |*key, i| {
            const buf = res.get(i);

            var fbs = io.fixedBufferStream(buf);
            const encrypted_string = table.getEncryptedString(0, i);
            key.* = try decrypt(encrypted_string, fbs.writer());
        }

        return res;
    }
};
