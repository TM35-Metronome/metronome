const common = @import("tm35-common");
const fun = @import("fun-with-zig");
const gba = @import("gba.zig");
const offsets = @import("gen3-offsets.zig");
const script = @import("gen3-script.zig");
const std = @import("std");

const math = std.math;
const mem = std.mem;
const os = std.os;

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu64 = fun.platform.lu64;

/// A pointer to an unknown number of elements.
/// In GBA games pointers are 32 bits and the game rom is loaded into address
/// 0x8000000. This makes 0x8000000 the null pointer. This struct helps abstract
/// this away and translate game pointers into real pointers.
pub fn Ptr(comptime T: type) type {
    return packed struct {
        const Self = @This();

        v: lu32,

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
    return packed struct {
        const Self = @This();

        ptr: Ptr(T),

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
    return packed struct {
        const Self = @This();

        l: lu32,
        ptr: Ptr(T),

        /// Initialize an empty 'Slice'.
        pub fn initEmpty() Self {
            return Self{
                .l = lu32.init(0),
                .ptr = Ptr(T).initNull(),
            };
        }

        /// Initialize a 'Slice' from an 'addr' and a 'len'.
        pub fn init(addr: u32, len: u32) !Self {
            return Self{
                .l = lu32.init(len),
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

pub const BasePokemon = packed struct {
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
    egg_group1_pad: u4,
    egg_group2: common.EggGroup,
    egg_group2_pad: u4,

    abilities: [2]u8,
    safari_zone_rate: u8,

    color: common.Color,
    flip: bool,

    padding: [2]u8,
};

pub const Trainer = packed struct {
    party_type: PartyType,
    class: u8,
    encounter_music: u8,
    trainer_picture: u8,
    name: [12]u8,
    items: [4]lu16,
    is_double: lu32,
    ai: lu32,
    party: Party,

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
};

pub const PartyMemberBase = packed struct {
    iv: lu16,
    level: lu16,
    species: lu16,

    pub fn toParent(base: *PartyMemberBase, comptime Parent: type) *Parent {
        return @fieldParentPtr(Parent, "base", base);
    }
};

pub const PartyMemberNone = packed struct {
    base: PartyMemberBase,
};

pub const PartyMemberItem = packed struct {
    base: PartyMemberBase,
    item: lu16,
};

pub const PartyMemberMoves = packed struct {
    base: PartyMemberBase,
    pad: lu16,
    moves: [4]lu16,
};

pub const PartyMemberBoth = packed struct {
    base: PartyMemberBase,
    item: lu16,
    moves: [4]lu16,
};

pub const Move = packed struct {
    effect: u8,
    power: u8,
    @"type": Type,
    accuracy: u8,
    pp: u8,
    side_effect_chance: u8,
    target: u8,
    priority: u8,
    flags: lu32,
};

pub const Item = packed struct {
    name: [14]u8,
    id: lu16,
    price: lu16,
    hold_effect: u8,
    hold_effect_param: u8,
    description: Ptr(u8),
    importance: u8,
    unknown: u8,
    pocked: u8,
    @"type": u8,
    field_use_func: Ref(u8),
    battle_usage: lu32,
    battle_use_func: Ref(u8),
    secondary_id: lu32,
};

pub const Type = enum(u8) {
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
};

pub const WildPokemon = packed struct {
    min_level: u8,
    max_level: u8,
    species: lu16,
};

pub fn WildPokemonInfo(comptime len: usize) type {
    return packed struct {
        encounter_rate: u8,
        pad: [3]u8,
        wild_pokemons: Ref([len]WildPokemon),
    };
}

pub const WildPokemonHeader = packed struct {
    map_group: u8,
    map_num: u8,
    pad: [2]u8,
    land: Ref(WildPokemonInfo(12)),
    surf: Ref(WildPokemonInfo(5)),
    rock_smash: Ref(WildPokemonInfo(5)),
    fishing: Ref(WildPokemonInfo(10)),
};

pub const MapHeader = packed struct {
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
};

pub const MapEvents = packed struct {
    obj_events_len: u8,
    warps_len: u8,
    coord_events_len: u8,
    bg_events_len: u8,
    obj_events: Ptr(ObjectEvent),
    warps: Ptr(Warp),
    coord_events: Ptr(CoordEvent),
    bg_events: Ptr(BgEvent),
};

pub const ObjectEvent = packed struct {
    index: u8,
    gfx: u8,
    replacement: u8,
    pad1: u8,
    x: lu16,
    y: lu16,
    evelavtion: u8,
    movement_type: u8,
    y_radius: u4,
    x_radius: u4,
    pad2: u8,
    trainer_type: lu16,
    sight_radius_tree_etc: lu16,
    script: Ptr(u8),
    event_flag: lu16,
    pad3: [2]u8,
};

pub const Warp = packed struct {
    x: lu16,
    y: lu16,
    byte: u8,
    warp: u8,
    map_num: u8,
    map_group: u8,
};

pub const CoordEvent = packed struct {
    x: lu16,
    y: lu16,
    elevation: u8,
    pad1: u8,
    trigger: lu16,
    index: lu16,
    pad2: [2]u8,
    scripts: Ptr(u8),
};

pub const BgEvent = packed struct {
    x: lu16,
    y: lu16,
    elevation: u8,
    kind: u8,
    pad: [2]u8,
    unknown: [4]u8,
};

pub const MapScript = packed struct {
    @"type": u8,
    addr: packed union {
        @"0": void,
        @"2": Ptr(MapScript2),
        Other: Ptr(u8),
    },
};

pub const MapScript2 = packed struct {
    word1: lu16,
    word2: lu16,
    addr: Ptr(u8),
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
    evolutions: [][5]common.Evolution,
    level_up_learnset_pointers: []Ptr(LevelUpMove),
    hms: []lu16,
    tms: []lu16,
    items: []Item,
    wild_pokemon_headers: []WildPokemonHeader,
    map_headers: []MapHeader,
    static_pokemons: []*script.Command.setwildbattle,
    given_items: []*script.Command.giveitem,

    pub fn fromFile(file: os.File, allocator: *mem.Allocator) !Game {
        var file_in_stream = file.inStream();
        var in_stream = &file_in_stream.stream;

        const header = try in_stream.readStruct(gba.Header);
        try header.validate();
        try file.seekTo(0);

        const info = try getInfo(header.game_title, header.gamecode);
        const size = try file.getEndPos();

        if (size % 0x1000000 != 0 or size > 1024 * 1024 * 32)
            return error.InvalidRomSize;

        const rom = try allocator.alloc(u8, size);
        errdefer allocator.free(rom);

        try in_stream.readNoEof(rom);

        const map_headers = info.map_headers.slice(rom);
        const ScriptData = struct {
            static_pokemons: std.ArrayList(*script.Command.setwildbattle),
            given_items: std.ArrayList(*script.Command.giveitem),

            fn processCommand(data: *@This(), command: *script.Command) !void {
                if (command.tag == script.Command.Kind.setwildbattle)
                    try data.static_pokemons.append(&command.data.setwildbattle);
                if (command.tag == script.Command.Kind.giveitem)
                    try data.given_items.append(&command.data.giveitem);
            }

            fn deinit(data: *@This()) void {
                data.static_pokemons.deinit();
                data.given_items.deinit();
                data.* = undefined;
            }
        };
        var script_data = ScriptData{
            .static_pokemons = std.ArrayList(*script.Command.setwildbattle).init(allocator),
            .given_items = std.ArrayList(*script.Command.giveitem).init(allocator),
        };
        errdefer script_data.deinit();

        @setEvalBranchQuota(100000);
        for (map_headers) |map_header| {
            const scripts = try map_header.map_scripts.toSliceTerminated(rom, struct {
                fn isTerm(ms: MapScript) bool {
                    return ms.@"type" == 0;
                }
            }.isTerm);

            for (scripts) |s| {
                if (s.@"type" == 2 or s.@"type" == 4)
                    continue;

                const script_bytes = try s.addr.Other.toSliceEnd(rom);
                var decoder = script.CommandDecoder.init(script_bytes);
                while (try decoder.next()) |command|
                    try script_data.processCommand(command);
            }

            const events = try map_header.map_events.toSingle(rom);
            for (try events.obj_events.toSlice(rom, events.obj_events_len)) |obj_event| {
                const script_bytes = obj_event.script.toSliceEnd(rom) catch continue;
                var decoder = script.CommandDecoder.init(script_bytes);
                while (try decoder.next()) |command|
                    try script_data.processCommand(command);
            }

            for (try events.coord_events.toSlice(rom, events.coord_events_len)) |coord_event| {
                const script_bytes = coord_event.scripts.toSliceEnd(rom) catch continue;
                var decoder = script.CommandDecoder.init(script_bytes);
                while (try decoder.next()) |command|
                    try script_data.processCommand(command);
            }
        }

        return Game{
            .version = info.version,
            .allocator = allocator,
            .data = rom,
            .header = @ptrCast(*gba.Header, &rom[0]),
            .starters = []*lu16{
                info.starters[0].ptr(rom),
                info.starters[1].ptr(rom),
                info.starters[2].ptr(rom),
            },
            .starters_repeat = [3]*lu16{
                info.starters_repeat[0].ptr(rom),
                info.starters_repeat[1].ptr(rom),
                info.starters_repeat[2].ptr(rom),
            },
            .trainers = info.trainers.slice(rom),
            .moves = info.moves.slice(rom),
            .machine_learnsets = info.machine_learnsets.slice(rom),
            .pokemons = info.pokemons.slice(rom),
            .evolutions = info.evolutions.slice(rom),
            .level_up_learnset_pointers = info.level_up_learnset_pointers.slice(rom),
            .hms = info.hms.slice(rom),
            .tms = info.tms.slice(rom),
            .items = info.items.slice(rom),
            .wild_pokemon_headers = info.wild_pokemon_headers.slice(rom),
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