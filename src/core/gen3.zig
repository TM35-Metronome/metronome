const common = @import("common.zig");
const rom = @import("rom.zig");
const std = @import("std");

const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const fs = std.fs;

const gba = rom.gba;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu64 = rom.int.lu64;

pub const encodings = @import("gen3/encodings.zig");
pub const offsets = @import("gen3/offsets.zig");
pub const script = @import("gen3/script.zig");

test "" {
    std.meta.refAllDecls(@This());
}

pub const Language = enum {
    en_us,
};

pub fn encode(lang: Language, str: []const u8, out: []u8) !void {
    const map = switch (lang) {
        .en_us => &encodings.en_us,
    };

    var fos = io.fixedBufferStream(out);
    try rom.encoding.encode(map, 0, str, fos.outStream());
    try fos.outStream().writeByte(0xff);
}

pub fn decode(lang: Language, str: []const u8, out_stream: var) !void {
    const map = switch (lang) {
        .en_us => &encodings.en_us,
    };

    const end = mem.indexOfScalar(u8, str, 0xff) orelse str.len;
    try rom.encoding.encode(map, 1, str[0..end], out_stream);
}

pub fn Ptr(comptime P: type) type {
    return rom.ptr.RelativePointer(P, u32, .Little, 0x8000000, 0);
}

pub fn Slice(comptime S: type) type {
    return rom.ptr.RelativeSlice(S, u32, .Little, .len_first, 0x8000000);
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

    color: common.Color,

    padding: [2]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 28);
    }
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
            .none => &(try trainer.party.none.toSlice(data))[index].base,
            .item => &(try trainer.party.item.toSlice(data))[index].base,
            .moves => &(try trainer.party.moves.toSlice(data))[index].base,
            .both => &(try trainer.party.both.toSlice(data))[index].base,
        };
    }

    pub fn partyLen(trainer: Trainer) usize {
        return switch (trainer.party_type) {
            .none => trainer.party.none.len(),
            .item => trainer.party.item.len(),
            .moves => trainer.party.moves.len(),
            .both => trainer.party.both.len(),
        };
    }
};

pub const PartyType = packed enum(u8) {
    none = 0b00,
    item = 0b10,
    moves = 0b01,
    both = 0b11,
};

pub const Party = packed union {
    none: Slice([]PartyMemberNone),
    item: Slice([]PartyMemberItem),
    moves: Slice([]PartyMemberMoves),
    both: Slice([]PartyMemberBoth),

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

pub const FRLGPocket = packed enum(u8) {
    none = 0x00,
    items = 0x01,
    key_items = 0x02,
    poke_balls = 0x03,
    tms_hms = 0x04,
    berries = 0x05,
};

pub const RSEPocket = packed enum(u8) {
    none = 0x00,
    items = 0x01,
    poke_balls = 0x02,
    tms_hms = 0x03,
    berries = 0x04,
    key_items = 0x05,
};

pub const Pocket = packed union {
    frlg: FRLGPocket,
    rse: RSEPocket,
};

pub const Item = extern struct {
    name: [14]u8,
    id: lu16,
    price: lu16,
    hold_effect: u8,
    hold_effect_param: u8,
    description: Ptr([*:0xff]u8),
    importance: u8,
    unknown: u8,
    pocket: Pocket,
    type: u8,
    field_use_func: Ptr(*u8),
    battle_usage: lu32,
    battle_use_func: Ptr(*u8),
    secondary_id: lu32,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 44);
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
        wild_pokemons: Ptr(*[len]WildPokemon),

        comptime {
            std.debug.assert(@sizeOf(@This()) == 8);
        }
    };
}

pub const WildPokemonHeader = extern struct {
    map_group: u8,
    map_num: u8,
    pad: [2]u8,
    land: Ptr(*WildPokemonInfo(12)),
    surf: Ptr(*WildPokemonInfo(5)),
    rock_smash: Ptr(*WildPokemonInfo(5)),
    fishing: Ptr(*WildPokemonInfo(10)),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 20);
    }
};

pub const Evolution = extern struct {
    method: common.EvoMethod,
    padding1: u8,
    param: lu16,
    target: lu16,
    padding2: [2]u8,

    comptime {
        std.debug.assert(@sizeOf(Evolution) == 8);
    }
};

pub const MapHeader = extern struct {
    map_data: Ptr(*c_void),
    map_events: Ptr(*MapEvents),
    map_scripts: Ptr([*]MapScript),
    map_connections: Ptr(*c_void),
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
    obj_events: Ptr([*]ObjectEvent),
    warps: Ptr([*]Warp),
    coord_events: Ptr([*]CoordEvent),
    bg_events: Ptr([*]BgEvent),

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
    script: Ptr([*]u8),
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
    scripts: Ptr([*]u8),

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
        @"2": Ptr([*]MapScript2),
        other: Ptr([*]u8),
    },

    comptime {
        std.debug.assert(@sizeOf(@This()) == 5);
    }
};

pub const MapScript2 = extern struct {
    word1: lu16,
    word2: lu16,
    addr: Ptr([*]u8),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

const PokeballItem = struct {
    item: *lu16,
    amount: *lu16,
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
    level_up_learnset_pointers: []Ptr([*]LevelUpMove),
    hms: []lu16,
    tms: []lu16,
    items: []Item,
    wild_pokemon_headers: []WildPokemonHeader,
    map_headers: []MapHeader,
    pokemon_names: [][11]u8,

    static_pokemons: []*script.Command,
    pokeball_items: []PokeballItem,
    text: []*Ptr([*:0xff]u8),

    pub fn fromFile(file: fs.File, allocator: *mem.Allocator) !Game {
        const in_stream = file.inStream();

        const header = try in_stream.readStruct(gba.Header);
        try header.validate();
        try file.seekTo(0);

        const info = try getOffsets(&header.game_title, &header.gamecode);
        const size = try file.getEndPos();

        if (size % 0x1000000 != 0 or size > 1024 * 1024 * 32)
            return error.InvalidRomSize;

        const gba_rom = try allocator.alloc(u8, size);
        errdefer allocator.free(gba_rom);

        try in_stream.readNoEof(gba_rom);

        const map_headers = info.map_headers.slice(gba_rom);
        const ScriptData = struct {

            // These keep track of the pointer to what VAR_0x8000 and VAR_0x8001
            // was last set to by the script. This variables are used by callstd
            // to give and optain items.
            VAR_0x8000: ?*lu16 = null,
            VAR_0x8001: ?*lu16 = null,
            static_pokemons: std.ArrayList(*script.Command),
            pokeball_items: std.ArrayList(PokeballItem),
            text: std.ArrayList(*Ptr([*:0xff]u8)),

            fn processCommand(script_data: *@This(), gba_data: []u8, command: *script.Command) !void {
                const tag = command.tag;
                const data = command.data();
                switch (tag) {
                    .setwildbattle => try script_data.static_pokemons.append(command),
                    .setorcopyvar => {
                        if (data.setorcopyvar.destination.value() == 0x8000)
                            script_data.VAR_0x8000 = &data.setorcopyvar.source;
                        if (data.setorcopyvar.destination.value() == 0x8001)
                            script_data.VAR_0x8001 = &data.setorcopyvar.source;
                    },
                    .callstd => switch (data.callstd.function) {
                        script.STD_OBTAIN_ITEM, script.STD_FIND_ITEM => {
                            try script_data.pokeball_items.append(PokeballItem{
                                .item = script_data.VAR_0x8000 orelse return,
                                .amount = script_data.VAR_0x8001 orelse return,
                            });
                        },
                        else => {},
                    },
                    .loadword => switch (data.loadword.destination) {
                        0 => {
                            const v = data.loadword.value.toSliceZ(gba_data) catch return;
                            try script_data.text.append(&data.loadword.value);
                        },
                        else => {},
                    },
                    .message => {
                        const v = data.message.text.toSliceZ(gba_data) catch return;
                        try script_data.text.append(&data.message.text);
                    },
                    else => {},
                }
            }

            fn deinit(data: @This()) void {
                data.static_pokemons.deinit();
                data.pokeball_items.deinit();
                data.text.deinit();
            }
        };
        var script_data = ScriptData{
            .static_pokemons = std.ArrayList(*script.Command).init(allocator),
            .pokeball_items = std.ArrayList(PokeballItem).init(allocator),
            .text = std.ArrayList(*Ptr([*:0xff]u8)).init(allocator),
        };
        errdefer script_data.deinit();

        @setEvalBranchQuota(100000);
        for (map_headers) |map_header| {
            const scripts = try map_header.map_scripts.toSliceEnd(gba_rom);

            for (scripts) |s| {
                if (s.@"type" == 0)
                    break;
                if (s.@"type" == 2 or s.@"type" == 4)
                    continue;

                const script_bytes = try s.addr.other.toSliceEnd(gba_rom);
                var decoder = script.CommandDecoder{ .bytes = script_bytes };
                while (try decoder.next()) |command|
                    try script_data.processCommand(gba_rom, command);
            }

            const events = try map_header.map_events.toPtr(gba_rom);
            for (try events.obj_events.toSlice(gba_rom, events.obj_events_len)) |obj_event| {
                const script_bytes = obj_event.script.toSliceEnd(gba_rom) catch continue;
                var decoder = script.CommandDecoder{ .bytes = script_bytes };
                while (try decoder.next()) |command|
                    try script_data.processCommand(gba_rom, command);
            }

            for (try events.coord_events.toSlice(gba_rom, events.coord_events_len)) |coord_event| {
                const script_bytes = coord_event.scripts.toSliceEnd(gba_rom) catch continue;
                var decoder = script.CommandDecoder{ .bytes = script_bytes };
                while (try decoder.next()) |command|
                    try script_data.processCommand(gba_rom, command);
            }
        }

        return Game{
            .version = info.version,
            .allocator = allocator,
            .data = gba_rom,
            .header = @ptrCast(*gba.Header, &gba_rom[0]),
            .starters = [_]*lu16{
                info.starters[0].ptr(gba_rom),
                info.starters[1].ptr(gba_rom),
                info.starters[2].ptr(gba_rom),
            },
            .starters_repeat = [3]*lu16{
                info.starters_repeat[0].ptr(gba_rom),
                info.starters_repeat[1].ptr(gba_rom),
                info.starters_repeat[2].ptr(gba_rom),
            },
            .trainers = info.trainers.slice(gba_rom),
            .moves = info.moves.slice(gba_rom),
            .machine_learnsets = info.machine_learnsets.slice(gba_rom),
            .pokemons = info.pokemons.slice(gba_rom),
            .evolutions = info.evolutions.slice(gba_rom),
            .level_up_learnset_pointers = info.level_up_learnset_pointers.slice(gba_rom),
            .hms = info.hms.slice(gba_rom),
            .tms = info.tms.slice(gba_rom),
            .items = info.items.slice(gba_rom),
            .wild_pokemon_headers = info.wild_pokemon_headers.slice(gba_rom),
            .pokemon_names = info.pokemon_names.slice(gba_rom),
            .map_headers = map_headers,
            .static_pokemons = script_data.static_pokemons.toOwnedSlice(),
            .pokeball_items = script_data.pokeball_items.toOwnedSlice(),
            .text = script_data.text.toOwnedSlice(),
        };
    }

    pub fn writeToStream(game: Game, out_stream: var) !void {
        try game.header.validate();
        try out_stream.writeAll(game.data);
    }

    pub fn deinit(game: *Game) void {
        game.allocator.free(game.data);
        game.allocator.free(game.static_pokemons);
        game.allocator.free(game.pokeball_items);
        game.* = undefined;
    }

    fn getOffsets(game_title: []const u8, gamecode: []const u8) !offsets.Info {
        for (offsets.infos) |info| {
            if (!mem.eql(u8, &info.game_title, game_title))
                continue;
            if (!mem.eql(u8, &info.gamecode, gamecode))
                continue;

            return info;
        }

        return error.NotGen3Game;
    }
};
