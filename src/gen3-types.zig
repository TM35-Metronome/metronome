const common = @import("tm35-common");
const fun = @import("fun-with-zig");
const gba = @import("gba.zig");
const offsets = @import("gen3-offsets.zig");
const std = @import("std");

const math = std.math;
const mem = std.mem;
const os = std.os;

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu64 = fun.platform.lu64;

pub fn Ptr(comptime T: type) type {
    return packed struct {
        const Self = @This();

        v: lu32,

        pub fn initNull() Self {
            return Self{ .v = lu32.init(0) };
        }

        pub fn init(i: u32) !Self {
            const v = math.add(u32, i, 0x8000000) catch return error.InvalidPointer;
            return Self{ .v = lu32.init(v) };
        }

        pub fn toMany(ptr: Self, data: []u8) ![*]T {
            return (try ptr.toSlice(data, 0)).ptr;
        }

        pub fn toSlice(ptr: Self, data: []u8, len: u32) ![]T {
            if (ptr.isNull()) {
                if (len == 0)
                    return @bytesToSlice(T, data[0..0]);

                return error.InvalidPointer;
            }

            const start = try ptr.toInt();
            const end = start + len * @sizeOf(T);
            if (data.len < start or data.len < end)
                return error.InvalidPointer;

            return @bytesToSlice(T, data[start..end]);
        }

        pub fn isNull(ptr: Self) bool {
            return ptr.v.value() == 0;
        }

        pub fn toInt(ptr: Self) !u32 {
            return math.sub(u32, ptr.v.value(), 0x8000000) catch return error.InvalidPointer;
        }
    };
}

pub fn Ref(comptime T: type) type {
    return packed struct {
        const Self = @This();

        ptr: Ptr(T),

        pub fn initNull() Self {
            return Self{ .ptr = Ptr(T).initNull() };
        }

        pub fn init(i: u32) !Self {
            return Self{ .ptr = try Ptr(T).init(i) };
        }

        pub fn toSingle(ref: Self, data: []u8) !*T {
            return &(try ref.ptr.toSlice(data, 1))[0];
        }

        pub fn isNull(ref: Self) bool {
            return ref.ptr.isNull();
        }

        pub fn toInt(ref: Self) !u32 {
            return try ref.ptr.toInt();
        }
    };
}

pub fn Slice(comptime T: type) type {
    return packed struct {
        const Self = @This();

        l: lu32,
        ptr: Ptr(T),

        pub fn initEmpty() Self {
            return Self{
                .l = lu32.init(0),
                .ptr = Ptr(T).initNull(),
            };
        }

        pub fn init(ptr: u32, l: u32) !Self {
            return Self{
                .l = lu32.init(l),
                .ptr = try Ptr(T).init(ptr),
            };
        }

        pub fn toSlice(slice: Self, data: []u8) ![]T {
            return slice.ptr.toSlice(data, slice.len());
        }

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
    const has_item = 0b10;
    const has_moves = 0b01;

    party_type: PartyType,
    class: u8,
    encounter_music: u8,
    trainer_picture: u8,
    name: [12]u8,
    items: [4]lu16,
    is_double: lu32,
    ai: lu32,
    party: Party,
};

pub const PartyType = packed enum(u8) {
    Base = 0b00,
    Item = 0b10,
    Moves = 0b01,
    Both = 0b11,
};

pub const Party = packed union {
    Base: Slice(PartyMemberBase),
    Item: Slice(PartyMemberItem),
    Moves: Slice(PartyMemberMoves),
    Both: Slice(PartyMemberBoth),
};

pub const PartyMemberBase = packed struct {
    iv: lu16,
    level: lu16,
    species: lu16,
};

pub const PartyMemberItem = packed struct {
    base: PartyMemberBase,
    item: lu16,
};

pub const PartyMemberMoves = packed struct {
    base: PartyMemberBase,
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
    move_id: u9,
    level: u7,
};

// TODO: Confirm layout
pub const WildPokemon = packed struct {
    min_level: u8,
    max_level: u8,
    species: lu16,
};

// TODO: Confirm layout
pub fn WildPokemonInfo(comptime len: usize) type {
    return packed struct {
        encounter_rate: u8,
        pad: [3]u8,
        wild_pokemons: Ref([len]WildPokemon),
    };
}

// TODO: Confirm layout
pub const WildPokemonHeader = packed struct {
    map_group: u8,
    map_num: u8,
    pad: [2]u8,
    land: Ref(WildPokemonInfo(12)),
    surf: Ref(WildPokemonInfo(5)),
    rock_smash: Ref(WildPokemonInfo(5)),
    fishing: Ref(WildPokemonInfo(10)),
};

pub const Game = struct {
    allocator: *mem.Allocator,
    version: common.Version,
    data: []u8,

    // All these fields point into data
    header: *gba.Header,

    trainers: []Trainer,
    moves: []Move,
    machine_learnsets: []lu64,
    base_stats: []BasePokemon,
    evolutions: [][5]common.Evolution,
    level_up_learnset_pointers: []Ptr(LevelUpMove),
    hms: []lu16,
    tms: []lu16,
    items: []Item,
    wild_pokemon_headers: []WildPokemonHeader,

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

        return Game{
            .version = info.version,
            .allocator = allocator,
            .data = rom,
            .header = @ptrCast(*gba.Header, &rom[0]),
            .trainers = info.trainers.slice(rom),
            .moves = info.moves.slice(rom),
            .machine_learnsets = info.machine_learnsets.slice(rom),
            .base_stats = info.base_stats.slice(rom),
            .evolutions = info.evolutions.slice(rom),
            .level_up_learnset_pointers = info.level_up_learnset_pointers.slice(rom),
            .hms = info.hms.slice(rom),
            .tms = info.tms.slice(rom),
            .items = info.items.slice(rom),
            .wild_pokemon_headers = info.wild_pokemon_headers.slice(rom),
        };
    }

    pub fn writeToStream(game: Game, in_stream: var) !void {
        try game.header.validate();
        try in_stream.write(game.data);
    }

    pub fn deinit(game: *Game) void {
        game.allocator.free(game.data);
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
