const common = @import("common.zig");
const rom = @import("rom.zig");
const std = @import("std");

const math = std.math;
const mem = std.mem;
const os = std.os;
const fs = std.fs;

const gba = rom.gba;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu64 = rom.int.lu64;

pub const offsets = @import("gen3-offsets.zig");
pub const script = @import("gen3-script.zig");

/// A pointer to an unknown number of elements.
/// In GBA games pointers are 32 bits and the game rom is loaded into address
/// 0x8000000. This makes 0x8000000 the null pointer. This struct helps abstract
/// this away and translate game pointers into real pointers.
pub fn Ptr(comptime T: type) type {
    return extern struct {
        const Self = @This();

        v: lu32,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 4);
        }

        /// Initialize a 'null' 'Ptr'
        pub fn initNull() Self {
            return Self{ .v = lu32.init(0) };
        }

        /// Initialize a 'Ptr' with the address 'addr' (relative to the rom).
        pub fn init(addr: u32) !Self {
            const v = math.add(u32, addr, 0x8000000) catch return error.InvalidPointer;
            return Self{ .v = lu32.init(v) };
        }

        /// Slice 'data' from 'ptr' to 'ptr' + 'len'.
        pub fn toSlice(ptr: Self, data: []u8, len: u32) ![]T {
            if (ptr.isNull()) {
                if (len == 0)
                    return @bytesToSlice(T, data[0..0]);

                return error.InvalidPointer;
            }

            const slice = try ptr.toSliceEnd(data);
            if (slice.len < len)
                return error.InvalidPointer;

            return slice[0..len];
        }

        /// Slice 'data' from 'ptr' to the maximum length allowed
        /// within 'data'.
        pub fn toSliceEnd(ptr: Self, data: []u8) ![]T {
            if (ptr.isNull())
                return error.InvalidPointer;

            const start = try ptr.toInt();
            const byte_len = data.len - start;
            const len = byte_len - (byte_len % @sizeOf(T));
            return @bytesToSlice(T, data[start..][0..len]);
        }

        /// Slice 'data' from 'ptr' to the first item where 'isTerm'
        /// return 'true'.
        pub fn toSliceTerminated(ptr: Self, data: []u8, isTerm: fn (T) bool) ![]T {
            const slice = try ptr.toSliceEnd(data);
            for (slice) |item, len| {
                if (isTerm(item))
                    return slice[0..len];
            }

            return error.DidNotFindTerminator;
        }

        /// Check if the pointer is 'null'.
        pub fn isNull(ptr: Self) bool {
            return ptr.v.value() == 0;
        }

        /// Convert 'ptr' to its integer form (relative to the rom).
        pub fn toInt(ptr: Self) !u32 {
            return math.sub(u32, ptr.v.value(), 0x8000000) catch return error.InvalidPointer;
        }
    };
}

/// Like 'Ptr' but only to a single 'T'.
pub fn Ref(comptime T: type) type {
    return extern struct {
        const Self = @This();

        ptr: Ptr(T),

        comptime {
            std.debug.assert(@sizeOf(@This()) == 4);
        }

        /// Initialize a 'null' 'Ref'
        pub fn initNull() Self {
            return Self{ .ptr = Ptr(T).initNull() };
        }

        /// Initialize a 'Ref' with the address 'addr' (relative to the rom).
        pub fn init(addr: u32) !Self {
            return Self{ .ptr = try Ptr(T).init(addr) };
        }

        /// Convert to '*T' at the address of 'ref' inside 'data'.
        pub fn toSingle(ref: Self, data: []u8) !*T {
            return &(try ref.ptr.toSlice(data, 1))[0];
        }

        /// Check if the pointer is 'null'.
        pub fn isNull(ref: Self) bool {
            return ref.ptr.isNull();
        }

        /// Convert 'ptr' to its integer form (relative to the rom).
        pub fn toInt(ref: Self) !u32 {
            return try ref.ptr.toInt();
        }
    };
}

/// Like 'Ptr' but with a runtime known number of elements.
pub fn Slice(comptime T: type) type {
    return extern struct {
        const Self = @This();

        l: lu32,
        ptr: Ptr(T),

        comptime {
            std.debug.assert(@sizeOf(@This()) == 8);
        }

        /// Initialize an empty 'Slice'.
        pub fn initEmpty() Self {
            return Self{
                .l = lu32.init(0),
                .ptr = Ptr(T).initNull(),
            };
        }

        /// Initialize a 'Slice' from an 'addr' and a 'len'.
        pub fn init(addr: u32, l: u32) !Self {
            return Self{
                .l = lu32.init(l),
                .ptr = try Ptr(T).init(addr),
            };
        }

        /// Convert to a slice into 'data'.
        pub fn toSlice(slice: Self, data: []u8) ![]T {
            return slice.ptr.toSlice(data, slice.len());
        }

        /// Get the length of 'slice'.
        pub fn len(slice: Self) u32 {
            return slice.l.value();
        }
    };
}

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
    safari_zone_rate: u8,

    color_flip: ColorFlip,

    padding: [2]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 28);
    }

    pub const ColorFlip = packed struct {
        color: common.Color,
        flip: bool,
    };
};

pub const Trainer = extern struct {
    party_type: PartyType,
    class: u8,
    encounter_music: u8,
    trainer_picture: u8,
    name: [12]u8,
    items: [4]lu16,
    is_double: lu32,
    ai: lu32,
    party: Party,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 40);
    }

    pub fn partyAt(trainer: *Trainer, index: usize, data: []u8) !*PartyMemberBase {
        return switch (trainer.party_type) {
            PartyType.None => &(try trainer.party.None.toSlice(data))[index].base,
            PartyType.Item => &(try trainer.party.Item.toSlice(data))[index].base,
            PartyType.Moves => &(try trainer.party.Moves.toSlice(data))[index].base,
            PartyType.Both => &(try trainer.party.Both.toSlice(data))[index].base,
        };
    }

    pub fn partyLen(trainer: Trainer) usize {
        return switch (trainer.party_type) {
            PartyType.None => trainer.party.None.len(),
            PartyType.Item => trainer.party.Item.len(),
            PartyType.Moves => trainer.party.Moves.len(),
            PartyType.Both => trainer.party.Both.len(),
        };
    }
};

pub const PartyType = packed enum(u8) {
    None = 0b00,
    Item = 0b10,
    Moves = 0b01,
    Both = 0b11,
};

pub const Party = packed union {
    None: Slice(PartyMemberNone),
    Item: Slice(PartyMemberItem),
    Moves: Slice(PartyMemberMoves),
    Both: Slice(PartyMemberBoth),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const PartyMemberBase = extern struct {
    iv: lu16,
    level: lu16,
    species: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
    }

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
    pad: lu16,
    moves: [4]lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
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

pub const Move = extern struct {
    effect: u8,
    power: u8,
    type: Type,
    accuracy: u8,
    pp: u8,
    side_effect_chance: u8,
    target: u8,
    priority: u8,
    flags: lu32,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 12);
    }
};

pub const Item = extern struct {
    name: [14]u8,
    id: lu16,
    price: lu16,
    hold_effect: u8,
    hold_effect_param: u8,
    description: Ptr(u8),
    importance: u8,
    unknown: u8,
    pocked: u8,
    type: u8,
    field_use_func: Ref(u8),
    battle_usage: lu32,
    battle_use_func: Ref(u8),
    secondary_id: lu32,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 44);
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

pub const LevelUpMove = packed struct {
    id: u9,
    level: u7,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 2);
    }
};

pub const WildPokemon = extern struct {
    min_level: u8,
    max_level: u8,
    species: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 4);
    }
};

pub fn WildPokemonInfo(comptime len: usize) type {
    return extern struct {
        encounter_rate: u8,
        pad: [3]u8,
        wild_pokemons: Ref([len]WildPokemon),

        comptime {
            std.debug.assert(@sizeOf(@This()) == 8);
        }
    };
}

pub const WildPokemonHeader = extern struct {
    map_group: u8,
    map_num: u8,
    pad: [2]u8,
    land: Ref(WildPokemonInfo(12)),
    surf: Ref(WildPokemonInfo(5)),
    rock_smash: Ref(WildPokemonInfo(5)),
    fishing: Ref(WildPokemonInfo(10)),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 20);
    }
};

pub const Evolution = packed struct {
    method: Evolution.Method,
    param: lu16,
    target: lu16,
    padding: [2]u8,

    pub const Method = enum(u16) {
        Unused = lu16.init(0x00).value(),
        FriendShip = lu16.init(0x01).value(),
        FriendShipDuringDay = lu16.init(0x02).value(),
        FriendShipDuringNight = lu16.init(0x03).value(),
        LevelUp = lu16.init(0x04).value(),
        Trade = lu16.init(0x05).value(),
        TradeHoldingItem = lu16.init(0x06).value(),
        UseItem = lu16.init(0x07).value(),
        AttackGthDefense = lu16.init(0x08).value(),
        AttackEqlDefense = lu16.init(0x09).value(),
        AttackLthDefense = lu16.init(0x0A).value(),
        PersonalityValue1 = lu16.init(0x0B).value(),
        PersonalityValue2 = lu16.init(0x0C).value(),
        LevelUpMaySpawnPokemon = lu16.init(0x0D).value(),
        LevelUpSpawnIfCond = lu16.init(0x0E).value(),
        Beauty = lu16.init(0x0F).value(),
    };

    comptime {
        std.debug.assert(@sizeOf(Evolution) == 8);
    }
};

pub const MapHeader = extern struct {
    map_data: Ref(c_void),
    map_events: Ref(MapEvents),
    map_scripts: Ptr(MapScript),
    map_connections: Ref(c_void),
    music: lu16,
    map_data_id: lu16,
    map_sec: u8,
    cave: u8,
    weather: u8,
    map_type: u8,
    pad: u8,
    escape_rope: u8,
    flags: u8,
    map_battle_scene: u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 28);
    }
};

pub const MapEvents = extern struct {
    obj_events_len: u8,
    warps_len: u8,
    coord_events_len: u8,
    bg_events_len: u8,
    obj_events: Ptr(ObjectEvent),
    warps: Ptr(Warp),
    coord_events: Ptr(CoordEvent),
    bg_events: Ptr(BgEvent),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 20);
    }
};

pub const ObjectEvent = extern struct {
    index: u8,
    gfx: u8,
    replacement: u8,
    pad1: u8,
    x: lu16,
    y: lu16,
    evelavtion: u8,
    movement_type: u8,
    radius: Point,
    pad2: u8,
    trainer_type: lu16,
    sight_radius_tree_etc: lu16,
    script: Ptr(u8),
    event_flag: lu16,
    pad3: [2]u8,

    pub const Point = packed struct {
        y: u4,
        x: u4,
    };

    comptime {
        std.debug.assert(@sizeOf(@This()) == 24);
    }
};

pub const Warp = extern struct {
    x: lu16,
    y: lu16,
    byte: u8,
    warp: u8,
    map_num: u8,
    map_group: u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const CoordEvent = extern struct {
    x: lu16,
    y: lu16,
    elevation: u8,
    pad1: u8,
    trigger: lu16,
    index: lu16,
    pad2: [2]u8,
    scripts: Ptr(u8),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const BgEvent = extern struct {
    x: lu16,
    y: lu16,
    elevation: u8,
    kind: u8,
    pad: [2]u8,
    unknown: [4]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 12);
    }
};

pub const MapScript = extern struct {
    @"type": u8,
    addr: packed union {
        @"0": void,
        @"2": Ptr(MapScript2),
        Other: Ptr(u8),
    },

    comptime {
        std.debug.assert(@sizeOf(@This()) == 5);
    }
};

pub const MapScript2 = extern struct {
    word1: lu16,
    word2: lu16,
    addr: Ptr(u8),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const Game = struct {
    allocator: *mem.Allocator,
    version: common.Version,
    data: []u8,

    // All these fields point into data
    header: *gba.Header,

    starters: [3]*lu16,
    starters_repeat: [3]*lu16,
    trainers: []Trainer,
    moves: []Move,
    machine_learnsets: []lu64,
    pokemons: []BasePokemon,
    evolutions: [][5]Evolution,
    level_up_learnset_pointers: []Ptr(LevelUpMove),
    hms: []lu16,
    tms: []lu16,
    items: []Item,
    wild_pokemon_headers: []WildPokemonHeader,
    map_headers: []MapHeader,
    static_pokemons: []*script.Command,
    given_items: []*script.Command,

    pub fn fromFile(file: fs.File, allocator: *mem.Allocator) !Game {
        var file_in_stream = file.inStream();
        var in_stream = &file_in_stream.stream;

        const header = try in_stream.readStruct(gba.Header);
        try header.validate();
        try file.seekTo(0);

        const info = try getInfo(header.game_title, header.gamecode);
        const size = try file.getEndPos();

        if (size % 0x1000000 != 0 or size > 1024 * 1024 * 32)
            return error.InvalidRomSize;

        const gda_rom = try allocator.alloc(u8, size);
        errdefer allocator.free(gda_rom);

        try in_stream.readNoEof(gda_rom);

        const map_headers = info.map_headers.slice(gda_rom);
        const ScriptData = struct {
            static_pokemons: std.ArrayList(*script.Command),
            given_items: std.ArrayList(*script.Command),

            fn processCommand(data: *@This(), command: *script.Command) !void {
                if (command.tag == script.Command.Kind.setwildbattle)
                    try data.static_pokemons.append(command);
                if (command.tag == script.Command.Kind.giveitem)
                    try data.given_items.append(command);
            }

            fn deinit(data: *@This()) void {
                data.static_pokemons.deinit();
                data.given_items.deinit();
                data.* = undefined;
            }
        };
        var script_data = ScriptData{
            .static_pokemons = std.ArrayList(*script.Command).init(allocator),
            .given_items = std.ArrayList(*script.Command).init(allocator),
        };
        errdefer script_data.deinit();

        @setEvalBranchQuota(100000);
        for (map_headers) |map_header| {
            const scripts = try map_header.map_scripts.toSliceTerminated(gda_rom, struct {
                fn isTerm(ms: MapScript) bool {
                    return ms.@"type" == 0;
                }
            }.isTerm);

            for (scripts) |s| {
                if (s.@"type" == 2 or s.@"type" == 4)
                    continue;

                const script_bytes = try s.addr.Other.toSliceEnd(gda_rom);
                var decoder = script.CommandDecoder{ .bytes = script_bytes };
                while (try decoder.next()) |command|
                    try script_data.processCommand(command);
            }

            const events = try map_header.map_events.toSingle(gda_rom);
            for (try events.obj_events.toSlice(gda_rom, events.obj_events_len)) |obj_event| {
                const script_bytes = obj_event.script.toSliceEnd(gda_rom) catch continue;
                var decoder = script.CommandDecoder{ .bytes = script_bytes };
                while (try decoder.next()) |command|
                    try script_data.processCommand(command);
            }

            for (try events.coord_events.toSlice(gda_rom, events.coord_events_len)) |coord_event| {
                const script_bytes = coord_event.scripts.toSliceEnd(gda_rom) catch continue;
                var decoder = script.CommandDecoder{ .bytes = script_bytes };
                while (try decoder.next()) |command|
                    try script_data.processCommand(command);
            }
        }

        return Game{
            .version = info.version,
            .allocator = allocator,
            .data = gda_rom,
            .header = @ptrCast(*gba.Header, &gda_rom[0]),
            .starters = [_]*lu16{
                info.starters[0].ptr(gda_rom),
                info.starters[1].ptr(gda_rom),
                info.starters[2].ptr(gda_rom),
            },
            .starters_repeat = [3]*lu16{
                info.starters_repeat[0].ptr(gda_rom),
                info.starters_repeat[1].ptr(gda_rom),
                info.starters_repeat[2].ptr(gda_rom),
            },
            .trainers = info.trainers.slice(gda_rom),
            .moves = info.moves.slice(gda_rom),
            .machine_learnsets = info.machine_learnsets.slice(gda_rom),
            .pokemons = info.pokemons.slice(gda_rom),
            .evolutions = info.evolutions.slice(gda_rom),
            .level_up_learnset_pointers = info.level_up_learnset_pointers.slice(gda_rom),
            .hms = info.hms.slice(gda_rom),
            .tms = info.tms.slice(gda_rom),
            .items = info.items.slice(gda_rom),
            .wild_pokemon_headers = info.wild_pokemon_headers.slice(gda_rom),
            .map_headers = map_headers,
            .static_pokemons = script_data.static_pokemons.toOwnedSlice(),
            .given_items = script_data.given_items.toOwnedSlice(),
        };
    }

    pub fn writeToStream(game: Game, out_stream: var) !void {
        try game.header.validate();
        try out_stream.write(game.data);
    }

    pub fn deinit(game: *Game) void {
        game.allocator.free(game.data);
        game.allocator.free(game.static_pokemons);
        game.allocator.free(game.given_items);
        game.* = undefined;
    }

    fn getInfo(game_title: []const u8, gamecode: []const u8) !offsets.Info {
        for (offsets.infos) |info| {
            if (!mem.eql(u8, info.game_title, game_title))
                continue;
            if (!mem.eql(u8, info.gamecode, gamecode))
                continue;

            return info;
        }

        return error.NotGen3Game;
    }
};
