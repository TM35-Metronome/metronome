const common = @import("common.zig");
const rom = @import("rom.zig");
const std = @import("std");

const fs = std.fs;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;

const gba = rom.gba;

const li16 = rom.int.li16;
const li32 = rom.int.li32;
const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu64 = rom.int.lu64;

pub const encodings = @import("gen3/encodings.zig");
pub const offsets = @import("gen3/offsets.zig");
pub const script = @import("gen3/script.zig");

pub const Language = enum {
    en_us,
};

pub fn Ptr(comptime P: type) type {
    return rom.ptr.RelativePointer(P, u32, .Little, 0x8000000, 0);
}

pub fn Slice(comptime S: type) type {
    return rom.ptr.RelativeSlice(S, u32, .Little, .len_first, 0x8000000);
}

pub const BasePokemon = extern struct {
    stats: common.Stats,
    types: [2]u8,

    catch_rate: u8,
    base_exp_yield: u8,

    ev: common.PaddedEvYield,
    items: [2]lu16,

    gender_ratio: u8,
    egg_cycles: u8,
    base_friendship: u8,

    growth_rate: common.GrowthRate,
    egg_groups: [2]common.EggGroup,

    abilities: [2]u8,
    safari_zone_rate: u8,

    color: common.Color,

    padding: [2]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 28);
    }
};

pub const Gender = enum(u1) {
    male = 0,
    female = 1,
};

pub const Trainer = extern struct {
    party_type: common.PartyType,
    class: u8,
    // encounter_music: packed struct {
    //     music: u7,
    //     gender: Gender,
    // },
    encounter_music: u8,
    trainer_picture: u8,
    name: [12]u8,
    items: [4]lu16,
    battle_type: lu32,
    ai: lu32,
    party: Party,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 40);
    }

    pub fn partyBytes(trainer: Trainer, data: []u8) ![]u8 {
        return switch (trainer.party_type) {
            .none => mem.sliceAsBytes(try trainer.party.none.toSlice(data)),
            .item => mem.sliceAsBytes(try trainer.party.item.toSlice(data)),
            .moves => mem.sliceAsBytes(try trainer.party.moves.toSlice(data)),
            .both => mem.sliceAsBytes(try trainer.party.both.toSlice(data)),
        };
    }

    pub fn partyAt(trainer: Trainer, index: usize, data: []u8) !*PartyMemberBase {
        return switch (trainer.party_type) {
            .none => &(try trainer.party.none.toSlice(data))[index].base,
            .item => &(try trainer.party.item.toSlice(data))[index].base,
            .moves => &(try trainer.party.moves.toSlice(data))[index].base,
            .both => &(try trainer.party.both.toSlice(data))[index].base,
        };
    }

    pub fn partyLen(trainer: Trainer) u8 {
        return switch (trainer.party_type) {
            .none => @intCast(u8, trainer.party.none.len()),
            .item => @intCast(u8, trainer.party.item.len()),
            .moves => @intCast(u8, trainer.party.moves.len()),
            .both => @intCast(u8, trainer.party.both.len()),
        };
    }
};

pub const Party = extern union {
    none: Slice([]PartyMemberNone),
    item: Slice([]PartyMemberItem),
    moves: Slice([]PartyMemberMoves),
    both: Slice([]PartyMemberBoth),

    pub fn memberSize(party_type: common.PartyType) usize {
        return switch (party_type) {
            .none => @sizeOf(PartyMemberNone),
            .item => @sizeOf(PartyMemberItem),
            .moves => @sizeOf(PartyMemberMoves),
            .both => @sizeOf(PartyMemberBoth),
        };
    }

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const PartyMemberBase = extern struct {
    iv: lu16 = lu16.init(0),
    level: lu16 = lu16.init(0),
    species: lu16 = lu16.init(0),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
    }

    pub fn toParent(base: *PartyMemberBase, comptime Parent: type) *Parent {
        return @fieldParentPtr(Parent, "base", base);
    }
};

pub const PartyMemberNone = extern struct {
    base: PartyMemberBase = PartyMemberBase{},
    pad: lu16 = lu16.init(0),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
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
    pad: lu16 = lu16.init(0),
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
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const Move = extern struct {
    effect: u8,
    power: u8,
    type: u8,
    accuracy: u8,
    pp: u8,
    side_effect_chance: u8,
    target: u8,
    priority: u8,
    flags0: u8,
    flags1: u8,
    flags2: u8,

    // The last byte is normally unused, but there exists patches
    // to make this last byte define the moves category (phys/spec/status).
    category: common.MoveCategory,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 12);
    }
};

pub const FRLGPocket = enum(u8) {
    none = 0x00,
    items = 0x01,
    key_items = 0x02,
    poke_balls = 0x03,
    tms_hms = 0x04,
    berries = 0x05,
};

pub const RSEPocket = enum(u8) {
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
    battle_effect: u8,
    battle_effect_param: u8,
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

pub const EmeraldPokedexEntry = extern struct {
    category_name: [12]u8,
    height: lu16,
    weight: lu16,
    description: Ptr([*]u8),
    unused: lu16,
    pokemon_scale: lu16,
    pokemon_offset: li16,
    trainer_scale: lu16,
    trainer_offset: li16,
    padding: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 32);
    }
};

pub const RSFrLgPokedexEntry = extern struct {
    category_name: [12]u8,
    height: lu16,
    weight: lu16,
    description: Ptr([*]u8),
    unused_description: Ptr([*]u8),
    unused: lu16,
    pokemon_scale: lu16,
    pokemon_offset: li16,
    trainer_scale: lu16,
    trainer_offset: li16,
    padding: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 36);
    }
};

pub const Pokedex = union {
    emerald: []EmeraldPokedexEntry,
    rsfrlg: []RSFrLgPokedexEntry,
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
    map_layout: Ptr(*MapLayout),
    map_events: Ptr(*MapEvents),
    map_scripts: Ptr([*]MapScript),
    map_connections: Ptr(*anyopaque),
    music: lu16,
    map_data_id: lu16,
    map_sec: u8,
    cave: u8,
    weather: u8,
    map_type: u8,
    pad: u8,
    escape_rope: u8,
    flags: Flags,
    map_battle_scene: u8,

    pub const Flags = packed struct {
        allow_cycling: bool,
        allow_escaping: bool,
        allow_running: bool,
        show_map_name: bool,
        unused: u4,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 1);
        }
    };

    comptime {
        std.debug.assert(@sizeOf(@This()) == 28);
    }
};

pub const MapLayout = extern struct {
    width: li32,
    height: li32,
    border: Ptr(*lu16),
    map: Ptr(*lu16),
    primary_tileset: Ptr(*Tileset),
    secondary_tileset: Ptr(*Tileset),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 24);
    }
};

pub const Tileset = extern struct {
    is_compressed: u8,
    is_secondary: u8,
    padding: [2]u8,
    tiles: Ptr(*anyopaque),
    palettes: Ptr(*anyopaque),
    metatiles: Ptr(*lu16),
    metatiles_attributes: Ptr(*[512]lu16),
    callback: Ptr(*anyopaque),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 24);
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
    script: Ptr(?[*]u8),
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
    type: u8,
    _addr: [4]u8,

    pub fn addr(s: *align(1) MapScript) *align(1) Addr {
        return @ptrCast(*align(1) Addr, &s._addr);
    }

    const Addr = extern union {
        @"0": void,
        @"2": Ptr([*]MapScript2),
        other: Ptr([*]u8),
    };

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

const StaticPokemon = struct {
    species: *align(1) lu16,
    level: *u8,
};

const PokeballItem = struct {
    item: *align(1) lu16,
    amount: *align(1) lu16,
};

const TrainerParty = struct {
    size: u32 = 0,
    members: [6]PartyMemberBoth = [_]PartyMemberBoth{PartyMemberBoth{}} ** 6,
};

const ScriptData = struct {

    // These keep track of the pointer to what VAR_0x8000 and VAR_0x8001
    // was last set to by the script. This variables are used by callstd
    // to give and obtain items.
    VAR_0x8000: ?*align(1) lu16 = null,
    VAR_0x8001: ?*align(1) lu16 = null,
    static_pokemons: std.ArrayList(StaticPokemon),
    given_pokemons: std.ArrayList(StaticPokemon),
    pokeball_items: std.ArrayList(PokeballItem),
    text: std.ArrayList(*align(1) Ptr([*:0xff]u8)),

    fn processCommand(
        script_data: *@This(),
        gba_data: []u8,
        command: *align(1) script.Command,
    ) !void {
        switch (command.kind) {
            .setwildbattle => try script_data.static_pokemons.append(.{
                .species = &command.setwildbattle.species,
                .level = &command.setwildbattle.level,
            }),
            .givemon => try script_data.given_pokemons.append(.{
                .species = &command.givemon.species,
                .level = &command.givemon.level,
            }),
            .setorcopyvar => {
                if (command.setorcopyvar.dest.value() == 0x8000)
                    script_data.VAR_0x8000 = &command.setorcopyvar.src;
                if (command.setorcopyvar.dest.value() == 0x8001)
                    script_data.VAR_0x8001 = &command.setorcopyvar.src;
            },
            .callstd => switch (command.callstd.function) {
                script.STD_OBTAIN_ITEM, script.STD_FIND_ITEM => {
                    try script_data.pokeball_items.append(PokeballItem{
                        .item = script_data.VAR_0x8000 orelse return,
                        .amount = script_data.VAR_0x8001 orelse return,
                    });
                },
                else => {},
            },
            .loadword => switch (command.loadword.destination) {
                0 => {
                    _ = command.loadword.value.toSliceZ(gba_data) catch return;
                    try script_data.text.append(&command.loadword.value);
                },
                else => {},
            },
            .message => {
                _ = command.message.text.toSliceZ(gba_data) catch return;
                try script_data.text.append(&command.message.text);
            },
            else => {},
        }
    }

    fn deinit(data: @This()) void {
        data.static_pokemons.deinit();
        data.given_pokemons.deinit();
        data.pokeball_items.deinit();
        data.text.deinit();
    }
};

pub const Game = struct {
    allocator: mem.Allocator,
    version: common.Version,

    free_offset: usize,
    data: []align(4) u8,

    // These fields are owned by the game and will be applied to
    // the rom oppon calling `apply`.
    trainer_parties: []TrainerParty,

    // All these fields point into data
    header: *gba.Header,

    starters: [3]*align(1) lu16,
    starters_repeat: [3]*align(1) lu16,
    text_delays: []u8,
    trainers: []Trainer,
    moves: []Move,
    machine_learnsets: []align(4) lu64,
    pokemons: []BasePokemon,
    evolutions: [][5]Evolution,
    level_up_learnset_pointers: []Ptr([*]LevelUpMove),
    hms: []lu16,
    tms: []lu16,
    items: []Item,
    pokedex: Pokedex,
    species_to_national_dex: []lu16,
    wild_pokemon_headers: []WildPokemonHeader,
    map_headers: []MapHeader,
    pokemon_names: [][11]u8,
    ability_names: [][13]u8,
    move_names: [][13]u8,
    type_names: [][7]u8,

    static_pokemons: []StaticPokemon,
    given_pokemons: []StaticPokemon,
    pokeball_items: []PokeballItem,
    text: []*align(1) Ptr([*:0xff]u8),

    pub fn identify(reader: anytype) !offsets.Info {
        const header = try reader.readStruct(gba.Header);
        for (offsets.infos) |info| {
            if (!mem.eql(u8, info.game_title.slice(), header.game_title.slice()))
                continue;
            if (!mem.eql(u8, &info.gamecode, &header.gamecode))
                continue;

            try header.validate();
            return info;
        }

        return error.UnknownGame;
    }

    pub fn fromFile(file: fs.File, allocator: mem.Allocator) !Game {
        const reader = file.reader();
        const info = try identify(reader);
        const size = try file.getEndPos();
        try file.seekTo(0);

        if (size % 0x1000000 != 0 or size > 1024 * 1024 * 32)
            return error.InvalidRomSize;

        const gba_rom = try allocator.allocWithOptions(u8, 1024 * 1024 * 32, 4, null);
        errdefer allocator.free(gba_rom);

        const free_offset = try reader.readAll(gba_rom);
        @memset(gba_rom[free_offset..], 0xff);

        const trainers = info.trainers.slice(gba_rom);
        const trainer_parties = try allocator.alloc(TrainerParty, trainers.len);
        @memset(trainer_parties, TrainerParty{});

        for (trainer_parties, trainers) |*party, trainer| {
            party.size = trainer.partyLen();

            for (party.members[0..party.size], 0..) |*member, i| {
                const base = try trainer.partyAt(i, gba_rom);
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

        var script_data = ScriptData{
            .static_pokemons = std.ArrayList(StaticPokemon).init(allocator),
            .given_pokemons = std.ArrayList(StaticPokemon).init(allocator),
            .pokeball_items = std.ArrayList(PokeballItem).init(allocator),
            .text = std.ArrayList(*align(1) Ptr([*:0xff]u8)).init(allocator),
        };
        errdefer script_data.deinit();

        const map_headers = info.map_headers.slice(gba_rom);
        @setEvalBranchQuota(100000);
        for (map_headers) |map_header| {
            const scripts = try map_header.map_scripts.toSliceEnd(gba_rom);

            for (scripts) |*s| {
                if (s.type == 0)
                    break;
                if (s.type == 2 or s.type == 4)
                    continue;

                const script_bytes = try s.addr().other.toSliceEnd(gba_rom);
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

            for (try events.obj_events.toSlice(gba_rom, events.obj_events_len)) |obj_event| {
                const script_bytes = obj_event.script.toSliceEnd(gba_rom) catch continue;
                var decoder = script.CommandDecoder{ .bytes = script_bytes };
                while (try decoder.next()) |command|
                    try script_data.processCommand(gba_rom, command);
            }
        }

        return Game{
            .version = info.version,
            .allocator = allocator,
            .free_offset = free_offset,
            .data = gba_rom,

            .trainer_parties = trainer_parties,

            .header = @ptrCast(*gba.Header, &gba_rom[0]),
            .starters = [3]*align(1) lu16{
                info.starters[0].ptr(gba_rom),
                info.starters[1].ptr(gba_rom),
                info.starters[2].ptr(gba_rom),
            },
            .starters_repeat = [3]*align(1) lu16{
                info.starters_repeat[0].ptr(gba_rom),
                info.starters_repeat[1].ptr(gba_rom),
                info.starters_repeat[2].ptr(gba_rom),
            },
            .text_delays = info.text_delays.slice(gba_rom),
            .trainers = trainers,
            .moves = info.moves.slice(gba_rom),
            .machine_learnsets = info.machine_learnsets.slice(gba_rom),
            .pokemons = info.pokemons.slice(gba_rom),
            .evolutions = info.evolutions.slice(gba_rom),
            .level_up_learnset_pointers = info.level_up_learnset_pointers.slice(gba_rom),
            .hms = info.hms.slice(gba_rom),
            .tms = info.tms.slice(gba_rom),
            .items = info.items.slice(gba_rom),
            .pokedex = switch (info.version) {
                .emerald => .{ .emerald = info.pokedex.emerald.slice(gba_rom) },
                .ruby,
                .sapphire,
                .fire_red,
                .leaf_green,
                => .{ .rsfrlg = info.pokedex.rsfrlg.slice(gba_rom) },
                else => unreachable,
            },
            .species_to_national_dex = info.species_to_national_dex.slice(gba_rom),
            .wild_pokemon_headers = info.wild_pokemon_headers.slice(gba_rom),
            .pokemon_names = info.pokemon_names.slice(gba_rom),
            .ability_names = info.ability_names.slice(gba_rom),
            .move_names = info.move_names.slice(gba_rom),
            .type_names = info.type_names.slice(gba_rom),
            .map_headers = map_headers,
            .static_pokemons = try script_data.static_pokemons.toOwnedSlice(),
            .given_pokemons = try script_data.given_pokemons.toOwnedSlice(),
            .pokeball_items = try script_data.pokeball_items.toOwnedSlice(),
            .text = try script_data.text.toOwnedSlice(),
        };
    }

    pub fn apply(game: *Game) !void {
        try game.applyTrainerParties();
    }

    fn applyTrainerParties(game: *Game) !void {
        const trainer_parties = game.trainer_parties;
        const trainers = game.trainers;

        for (trainer_parties, trainers) |party, *trainer| {
            const party_bytes = try trainer.partyBytes(game.data);
            const party_type = trainer.party_type;
            const party_size = party.size * Party.memberSize(party_type);

            if (party_size == 0) {
                const p = &trainer.party.none;
                p.inner.len = lu32.init(party.size);
                continue;
            }

            const bytes = if (party_bytes.len < party_size)
                try game.requestFreeBytes(party_size)
            else
                party_bytes;

            var fbs = io.fixedBufferStream(bytes);
            const writer = fbs.writer();
            for (party.members[0..party.size]) |member| {
                switch (party_type) {
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
            }

            const p = &trainer.party.none;
            p.inner.ptr.inner = (try Ptr([*]u8).init(bytes.ptr, game.data)).inner;
            p.inner.len = lu32.init(party.size);
        }
    }

    pub fn write(game: Game, writer: anytype) !void {
        try game.header.validate();
        try writer.writeAll(game.data);
    }

    pub fn requestFreeBytes(game: *Game, size: usize) ![]u8 {
        const Range = struct { start: usize, end: usize };

        for ([_]Range{
            .{ .start = game.free_offset, .end = game.data.len },
            .{ .start = 0, .end = game.free_offset },
        }) |range| {
            var i = mem.alignForward(usize, range.start, 4);
            outer: while (i + size <= range.end) : (i += 4) {
                // We ensure that the byte before our start byte is
                // also 0xff. This is because we want to ensure that
                // data that is terminated with 0xff does not get
                // its terminator given away as free space.
                const prev_byte = if (i == 0) 0xff else game.data[i - 1];
                if (prev_byte != 0xff)
                    continue :outer;

                const res = game.data[i..][0..size];
                for (res) |b| {
                    if (b != 0xff)
                        continue :outer;
                }

                game.free_offset = i + size;
                return res;
            }
        }

        return error.NoFreeSpaceAvailable;
    }

    pub fn deinit(game: Game) void {
        game.allocator.free(game.data);

        game.allocator.free(game.static_pokemons);
        game.allocator.free(game.given_pokemons);
        game.allocator.free(game.pokeball_items);
        game.allocator.free(game.trainer_parties);
    }
};
