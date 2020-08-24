const std = @import("std");

const common = @import("common.zig");
const rom = @import("rom.zig");

pub const offsets = @import("gen5/offsets.zig");
pub const script = @import("gen5/script.zig");

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
        std.debug.assert(@sizeOf(@This()) == 56);
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
        std.debug.assert(@sizeOf(@This()) == 8);
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
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const PartyMemberItem = extern struct {
    base: PartyMemberBase = PartyMemmberBase{},
    item: lu16 = lu16.init(0),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 10);
    }
};

pub const PartyMemberMoves = extern struct {
    base: PartyMemberBase = PartyMemmberBase{},
    moves: [4]lu16 = [_]lu16{lu16.init(0)} ** 4,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const PartyMemberBoth = extern struct {
    base: PartyMemberBase = PartyMemberBase{},
    item: lu16 = lu16.init(0),
    moves: [4]lu16 = [_]lu16{lu16.init(0)} ** 4,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 18);
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
        std.debug.assert(@sizeOf(@This()) == 20);
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
        std.debug.assert(@sizeOf(@This()) == 36);
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
        std.debug.assert(@sizeOf(@This()) == 4);
    }
};

// TODO: Verify layout
pub const Evolution = extern struct {
    method: Method,
    padding: u8,
    param: lu16,
    target: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
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
        std.debug.assert(@sizeOf(@This()) == 44);
    }
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
        std.debug.assert(@sizeOf(@This()) == 4);
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
        std.debug.assert(@sizeOf(@This()) == 232);
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
        std.debug.assert(@sizeOf(@This()) == 48);
    }
};

const HiddenHollow = extern struct {
    pokemons: [2][4]HollowPokemons,
    items: [6]lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 220);
    }
};

const HollowPokemons = extern struct {
    species: [4]lu16,
    unknown: [4]lu16,
    genders: [4]u8,
    forms: [4]u8,
    pad: [2]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 26);
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

pub const StringTable = struct {
    data: []u8,

    pub fn sectionCount(table: StringTable) u16 {
        return table.header().sections.value();
    }

    pub fn entryCount(table: StringTable, section: usize) u16 {
        return table.header().entries.value();
    }

    pub fn getEncryptedString(table: StringTable, section_i: usize, entry_i: usize) []lu16 {
        const section_offset = table.sectionOffsets()[section_i];
        const entry = table.entries(section_offset)[entry_i];
        const offset = section_offset.value() + entry.offset.value();
        const res = table.data[offset..][0 .. entry.count.value() * @sizeOf(lu16)];
        return mem.bytesAsSlice(lu16, res);
    }

    pub fn getStringStream(table: StringTable, section: usize, entry: usize) Stream {
        const string = table.getEncryptedString(section, entry);
        const last = string[string.len - 1].value();
        std.debug.assert(last ^ (last ^ 0xFFFF) == 0xFFFF);
        return .{
            .data = string,
            .key = string[string.len - 1].value() ^ 0xFFFF,
        };
    }

    const Header = packed struct {
        sections: lu16,
        entries: lu16,
        unknown1: lu32,
        unknown2: lu32,
    };

    const Entry = packed struct {
        offset: lu32,
        count: lu16,
        unknown: lu16,
    };

    fn header(table: StringTable) *Header {
        return @ptrCast(*Header, table.data[0..@sizeOf(Header)]);
    }

    fn sectionOffsets(table: StringTable) []lu32 {
        const h = table.header();
        const rest = table.data[@sizeOf(Header)..];
        return mem.bytesAsSlice(lu32, rest[0 .. @sizeOf(lu32) * h.sections.value()]);
    }

    fn entries(table: StringTable, section_offset: lu32) []Entry {
        const h = table.header();
        // TODO: There is a lu32 at the start of the section. Is this the len of
        //       all entries in this section?
        const rest = table.data[section_offset.value() + @sizeOf(lu32) ..];
        return mem.bytesAsSlice(Entry, rest[0 .. @sizeOf(Entry) * h.entries.value()]);
    }

    const Stream = struct {
        data: []lu16,
        key: u16,
        pos: usize = 0,

        pub const ReadError = error{
            Utf8CannotEncodeSurrogateHalf,
            CodepointTooLarge,
            NoSpaceLeft,
        };
        pub const WriteError = error{
            NoSpaceLeft,
            Overflow,
            InvalidCharacter,
        };

        pub const InStream = io.InStream(*Stream, ReadError, read);
        pub const OutStream = io.OutStream(*Stream, WriteError, write);

        pub fn read(stream: *Stream, buf: []u8) ReadError!usize {
            const rest = stream.data[stream.pos..];
            var n: usize = 0;
            for (rest) |c, i| {
                const decoded = c.value() ^ stream.keyForI(stream.pos);

                const Pair = struct {
                    len: usize,
                    codepoint: u21,
                };
                const pair: Pair = switch (decoded) {
                    0xffff => break,
                    0x0, 0xf000, 0xfff0...0xfffd => {
                        n += (try fmt.bufPrint(buf[n..], "\\x{x:0>4}", .{decoded})).len;
                        stream.pos += 1;
                        continue;
                    },
                    0xfffe => .{ .len = 1, .codepoint = '\n' },
                    else => .{
                        .len = unicode.utf8CodepointSequenceLength(decoded) catch unreachable,
                        .codepoint = decoded,
                    },
                };

                if (buf.len < n + pair.len)
                    break;
                n += try unicode.utf8Encode(pair.codepoint, buf[n..]);
                stream.pos += 1;
            }

            return n;
        }

        pub fn write(stream: *Stream, buf: []const u8) WriteError!usize {
            var n: usize = 0;
            while (n < buf.len) {
                if (mem.startsWith(u8, buf[n..], "\xff\xff")) {
                    if (stream.data.len <= stream.pos)
                        return error.NoSpaceLeft;
                    mem.set(lu16, stream.data[stream.pos..], lu16.init(0xffff));
                    for (stream.data) |*c, i|
                        c.* = lu16.init(c.value() ^ stream.keyForI(i));
                    stream.pos = stream.data.len;
                    return n + 2;
                }
                if (mem.startsWith(u8, buf[n..], "\n")) {
                    stream.data[stream.pos] = lu16.init(0xfffe);
                    stream.pos += 1;
                    n += 1;
                    continue;
                }
                if (mem.startsWith(u8, buf[n..], "\\x")) {
                    const hex = buf[n + 2 ..][0..4];
                    const parsed = try fmt.parseUnsigned(u16, hex, 16);
                    stream.data[stream.pos] = lu16.init(parsed);
                    stream.pos += 1;
                    n += 6;
                    continue;
                }

                const len = unicode.utf8ByteSequenceLength(buf[n]) catch unreachable;
                if (buf.len < n + len)
                    break;

                const codepoint = unicode.utf8Decode(buf[n..][0..len]) catch unreachable;
                if (stream.data.len <= stream.pos)
                    return error.NoSpaceLeft;

                stream.data[stream.pos] = lu16.init(@intCast(u16, codepoint));
                stream.pos += 1;
                n += len;
            }

            return n;
        }

        fn keyForI(stream: Stream, i: usize) u16 {
            const it = stream.data.len - (i + 1);
            var key: u32 = stream.key;

            for (stream.data[0..it]) |_|
                key = (key >> 3) | (key << 13) & 0xffff;

            return @intCast(u16, key);
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
    info: offsets.Info,
    allocator: *mem.Allocator,
    rom: *nds.Rom,

    // These fields are owned by the game and will be applied to
    // the rom oppon calling `apply`.
    arm9: []u8,
    trainer_parties: [][6]PartyMemberBoth,

    // The fields below are pointers into the nds rom and will
    // be invalidated oppon calling `apply`.
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

    text: nds.fs.Fs,
    pokemon_names: StringTable,
    pokedex_category_names: StringTable,
    trainer_names: StringTable,
    move_names: StringTable,
    move_descriptions: StringTable,
    ability_names: StringTable,
    item_names: StringTable,
    item_names_on_the_ground: StringTable,
    item_descriptions: StringTable,
    type_names: StringTable,
    map_names: StringTable,

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
        const arm9 = try nds_rom.getDecodedArm9(allocator);
        const file_system = nds_rom.fileSystem();

        const trainers = try (try getNarc(file_system, info.trainers)).toSlice(1, Trainer);
        const trainer_parties_narc = try getNarc(file_system, info.parties);
        const trainer_parties = try allocator.alloc([6]PartyMemberBoth, trainer_parties_narc.fat.len);
        mem.set([6]PartyMemberBoth, trainer_parties, [_]PartyMemberBoth{.{}} ** 6);

        for (trainer_parties) |*party, i| {
            const party_data = trainer_parties_narc.fileData(.{ .i = @intCast(u32, i) });
            const party_size = if (i != 0 and i - 1 < trainers.len) trainers[i - 1].party_size else 0;

            var j: usize = 0;
            while (j < party_size) : (j += 1) {
                const base = trainers[i - 1].partyMember(party_data, j) orelse break;
                party[j].base = base.*;

                switch (trainers[i - 1].party_type) {
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

        return fromRomEx(allocator, nds_rom, info, arm9, trainer_parties);
    }

    pub fn fromRomEx(
        allocator: *mem.Allocator,
        nds_rom: *nds.Rom,
        info: offsets.Info,
        arm9: []u8,
        parties: [][6]PartyMemberBoth,
    ) !Game {
        const file_system = nds_rom.fileSystem();

        const hm_tm_prefix_index = mem.indexOf(u8, arm9, offsets.hm_tm_prefix) orelse return error.CouldNotFindTmsOrHms;
        const hm_tm_index = hm_tm_prefix_index + offsets.hm_tm_prefix.len;
        const hm_tm_len = (offsets.tm_count + offsets.hm_count) * @sizeOf(u16);
        const hm_tms = mem.bytesAsSlice(lu16, arm9[hm_tm_index..][0..hm_tm_len]);

        const map_file = try getNarc(file_system, info.map_file);
        const text = try getNarc(file_system, info.text);
        const scripts = try getNarc(file_system, info.scripts);
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

            .arm9 = arm9,
            .trainer_parties = parties,

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
            .moves = try (try getNarc(file_system, info.moves)).toSlice(0, Move),
            .trainers = try (try getNarc(file_system, info.trainers)).toSlice(1, Trainer),
            .items = try (try getNarc(file_system, info.itemdata)).toSlice(0, Item),
            .evolutions = try (try getNarc(file_system, info.evolutions)).toSlice(0, EvolutionTable),
            .map_headers = mem.bytesAsSlice(MapHeader, map_header_bytes[0..]),
            .tms1 = hm_tms[0..92],
            .hms = hm_tms[92..98],
            .tms2 = hm_tms[98..],
            .static_pokemons = commands.static_pokemons,
            .given_pokemons = commands.given_pokemons,
            .pokeball_items = commands.pokeball_items,

            .wild_pokemons = try getNarc(file_system, info.wild_pokemons),
            .pokemons = try getNarc(file_system, info.pokemons),
            .level_up_moves = try getNarc(file_system, info.level_up_moves),
            .hidden_hollows = if (info.hidden_hollows) |h| try (try getNarc(file_system, h)).toSlice(0, HiddenHollow) else null,
            .scripts = scripts,
            .text = text,

            .pokemon_names = StringTable{ .data = text.fileData(.{ .i = info.pokemon_names }) },
            .pokedex_category_names = StringTable{ .data = text.fileData(.{ .i = info.pokedex_category_names }) },
            .trainer_names = StringTable{ .data = text.fileData(.{ .i = info.trainer_names }) },
            .move_names = StringTable{ .data = text.fileData(.{ .i = info.move_names }) },
            .move_descriptions = StringTable{ .data = text.fileData(.{ .i = info.move_descriptions }) },
            .ability_names = StringTable{ .data = text.fileData(.{ .i = info.ability_names }) },
            .item_names = StringTable{ .data = text.fileData(.{ .i = info.item_names }) },
            .item_names_on_the_ground = StringTable{ .data = text.fileData(.{ .i = info.item_names_on_the_ground }) },
            .item_descriptions = StringTable{ .data = text.fileData(.{ .i = info.item_descriptions }) },
            .type_names = StringTable{ .data = text.fileData(.{ .i = info.type_names }) },
            .map_names = StringTable{ .data = text.fileData(.{ .i = info.map_names }) },
        };
    }

    pub fn apply(game: *Game) !void {
        try game.rom.replaceSection(game.rom.arm9(), game.arm9);
        try game.applyTrainerParties();

        for (game.starters) |starter_ptrs|
            game.allocator.free(starter_ptrs);
        game.allocator.free(game.static_pokemons);
        game.allocator.free(game.given_pokemons);
        game.allocator.free(game.pokeball_items);

        game.* = try fromRomEx(
            game.allocator,
            game.rom,
            game.info,
            game.arm9,
            game.trainer_parties,
        );
    }

    fn applyTrainerParties(game: Game) !void {
        const PNone = PartyMemberNone;
        const PItem = PartyMemberItem;
        const PMoves = PartyMemberMoves;
        const PBoth = PartyMemberBoth;
        const allocator = game.allocator;
        const file_system = game.rom.fileSystem();
        const trainer_parties_narc = try file_system.openFileData(nds.fs.root, game.info.parties);
        const trainers = try (try getNarc(file_system, game.info.trainers)).toSlice(1, Trainer);
        const trainer_parties = game.trainer_parties;

        const content_size = @sizeOf([6]PartyMemberBoth) * trainer_parties.len;
        const size = nds.fs.narcSize(trainer_parties.len, content_size);

        const buf = if (trainer_parties_narc.len < size)
            try allocator.alloc(u8, size)
        else
            trainer_parties_narc;
        defer if (buf.ptr != trainer_parties_narc.ptr)
            allocator.free(buf);

        var builder = nds.fs.SimpleNarcBuilder.init(buf, trainer_parties.len);
        const fat = builder.fat();
        const stream = builder.stream.outStream();
        const files_offset = builder.stream.pos;
        const parties_buf = buf[builder.stream.pos..];
        for (builder.fat()) |*f, i|
            f.* = nds.Range.init(@sizeOf([6]PBoth) * i, @sizeOf([6]PBoth) * (i + 1));

        for (trainer_parties) |party, i| {
            const party_type = if (i != 0 and i - 1 < trainers.len) trainers[i - 1].party_type else .none;
            const start = builder.stream.pos - files_offset;

            const rest = parties_buf[i * @sizeOf([6]PBoth) ..];
            switch (party_type) {
                .none => {
                    for (mem.bytesAsSlice(PNone, rest[0..@sizeOf([6]PNone)])) |*m, j| {
                        m.* = PartyMemberNone{ .base = party[j].base };
                    }
                    mem.set(u8, rest[@sizeOf([6]PNone)..@sizeOf([6]PBoth)], 0);
                },
                .item => {
                    for (mem.bytesAsSlice(PItem, rest[0..@sizeOf([6]PItem)])) |*m, j| {
                        m.* = PartyMemberItem{
                            .base = party[j].base,
                            .item = party[j].item,
                        };
                    }
                    mem.set(u8, rest[@sizeOf([6]PItem)..@sizeOf([6]PBoth)], 0);
                },
                .moves => {
                    for (mem.bytesAsSlice(PMoves, rest[0..@sizeOf([6]PMoves)])) |*m, j| {
                        m.* = PartyMemberMoves{
                            .base = party[j].base,
                            .moves = party[j].moves,
                        };
                    }
                    mem.set(u8, rest[@sizeOf([6]PMoves)..@sizeOf([6]PBoth)], 0);
                },
                .both => {
                    mem.bytesAsValue([6]PBoth, rest[0..@sizeOf([6]PBoth)]).* = party;
                },
            }
        }

        const res = builder.finish();
        if (buf.ptr != trainer_parties_narc.ptr)
            try game.rom.replaceSection(trainer_parties_narc, res);
    }

    pub fn deinit(game: Game) void {
        for (game.starters) |starter_ptrs|
            game.allocator.free(starter_ptrs);
        game.allocator.free(game.arm9);
        game.allocator.free(game.trainer_parties);
        game.allocator.free(game.static_pokemons);
        game.allocator.free(game.given_pokemons);
        game.allocator.free(game.pokeball_items);
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

    fn nodeAsFile(node: nds.fs.Narc.Node) !*nds.fs.Narc.File {
        switch (node.kind) {
            .file => |file| return file,
            .folder => return error.NotFile,
        }
    }

    fn getNarc(fs: nds.fs.Fs, path: []const u8) !nds.fs.Fs {
        const file = try fs.openFileData(nds.fs.root, path);
        return try nds.fs.Fs.fromNarc(file);
    }
};
