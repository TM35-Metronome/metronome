const std = @import("std");
const util = @import("util");

const common = @import("../common.zig");
const gen3 = @import("../gen3.zig");
const rom = @import("../rom.zig");

const debug = std.debug;
const mem = std.mem;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu64 = rom.int.lu64;

pub fn Offset(comptime _T: type) type {
    return struct {
        pub const T = _T;

        offset: usize,

        pub fn init(data_slice: []const u8, ptr: *const T) @This() {
            const data_ptr = @ptrToInt(data_slice.ptr);
            const item_ptr = @ptrToInt(items.ptr);
            debug.assert(data_ptr <= item_ptr);
            debug.assert(item_ptr + @sizeOf(Item) <= data_ptr + data_slice.len);

            return @This(){ .offset = item_ptr - data_ptr };
        }

        pub fn end(offset: @This()) usize {
            return sec.offset + @sizeOf(T);
        }

        pub fn ptr(offset: @This(), data: []u8) *T {
            return &mem.bytesAsSlice(T, data[offset.offset..][0..@sizeOf(T)])[0];
        }
    };
}

pub fn Section(comptime _Item: type) type {
    return struct {
        pub const Item = _Item;

        start: usize,
        len: usize,

        pub fn init(data_slice: []const u8, items: []const Item) @This() {
            const data_ptr = @ptrToInt(data_slice.ptr);
            const item_ptr = @ptrToInt(items.ptr);
            debug.assert(data_ptr <= item_ptr);
            debug.assert(item_ptr + items.len * @sizeOf(Item) <= data_ptr + data_slice.len);

            return @This(){
                .start = item_ptr - data_ptr,
                .len = items.len,
            };
        }

        pub fn end(sec: @This()) usize {
            return sec.start + @sizeOf(Item) * sec.len;
        }

        pub fn slice(sec: @This(), data: []u8) []Item {
            return mem.bytesAsSlice(Item, data[sec.start..sec.end()]);
        }
    };
}

pub const StarterOffset = Offset(lu16);
pub const TrainerSection = Section(gen3.Trainer);
pub const MoveSection = Section(gen3.Move);
pub const MachineLearnsetSection = Section(lu64);
pub const BaseStatsSection = Section(gen3.BasePokemon);
pub const EvolutionSection = Section([5]gen3.Evolution);
pub const LevelUpLearnsetPointerSection = Section(gen3.Ptr([*]gen3.LevelUpMove));
pub const HmSection = Section(lu16);
pub const TmSection = Section(lu16);
pub const SpeciesToNationalDexSection = Section(lu16);
pub const EmeraldPokedexSection = Section(gen3.EmeraldPokedexEntry);
pub const RSFrLgPokedexSection = Section(gen3.RSFrLgPokedexEntry);
pub const ItemSection = Section(gen3.Item);
pub const WildPokemonHeaderSection = Section(gen3.WildPokemonHeader);
pub const MapHeaderSection = Section(gen3.MapHeader);
pub const PokemonNameSection = Section([11]u8);
pub const AbilityNameSection = Section([13]u8);
pub const MoveNameSection = Section([13]u8);
pub const TypeNameSection = Section([7]u8);
pub const TextDelaySection = Section(u8);

pub const Info = struct {
    game_title: util.TerminatedArray(12, u8, 0),
    gamecode: [4]u8,
    version: common.Version,
    software_version: u8,

    text_delays: TextDelaySection,
    starters: [3]StarterOffset,

    // In some games, the starters are repeated in multible places.
    // For games where this isn't true, we just repeat the same offsets
    // twice
    starters_repeat: [3]StarterOffset,
    trainers: TrainerSection,
    moves: MoveSection,
    machine_learnsets: MachineLearnsetSection,
    pokemons: BaseStatsSection,
    evolutions: EvolutionSection,
    level_up_learnset_pointers: LevelUpLearnsetPointerSection,
    hms: HmSection,
    tms: TmSection,
    pokedex: union {
        rsfrlg: RSFrLgPokedexSection,
        emerald: EmeraldPokedexSection,
    },
    species_to_national_dex: SpeciesToNationalDexSection,
    items: ItemSection,
    wild_pokemon_headers: WildPokemonHeaderSection,
    map_headers: MapHeaderSection,
    pokemon_names: PokemonNameSection,
    ability_names: AbilityNameSection,
    move_names: AbilityNameSection,
    type_names: TypeNameSection,
};

pub const infos = [_]Info{
    emerald_us_info,
    ruby_us_info,
    sapphire_us_info,
    fire_us_info,
    leaf_us_info,
};

const emerald_us_info = Info{
    .game_title = .{ .data = "POKEMON EMER".* },
    .gamecode = "BPEE".*,
    .version = .emerald,
    .software_version = 0,

    .text_delays = .{
        .start = 6353044,
        .len = 3,
    },
    .trainers = .{
        .start = 3211312,
        .len = 855,
    },
    .moves = .{
        .start = 3262616,
        .len = 355,
    },
    .machine_learnsets = .{
        .start = 3270808,
        .len = 412,
    },
    .pokemons = .{
        .start = 3277772,
        .len = 412,
    },
    .evolutions = .{
        .start = 3298076,
        .len = 412,
    },
    .level_up_learnset_pointers = .{
        .start = 3314556,
        .len = 412,
    },
    .hms = .{
        .start = 3317482,
        .len = 8,
    },
    .tms = .{
        .start = 6380436,
        .len = 50,
    },
    .pokedex = .{
        .emerald = .{
            .start = 5682608,
            .len = 387,
        },
    },
    .species_to_national_dex = .{
        .start = 3267714,
        .len = 411,
    },
    .items = .{
        .start = 5781920,
        .len = 377,
    },
    .wild_pokemon_headers = .{
        .start = 5582152,
        .len = 124,
    },
    .map_headers = .{
        .start = 4727992,
        .len = 518,
    },
    .pokemon_names = .{
        .start = 3245512,
        .len = 412,
    },
    .ability_names = .{
        .start = 3258075,
        .len = 78,
    },
    .move_names = .{
        .start = 3250044,
        .len = 355,
    },
    .type_names = .{
        .start = 3255864,
        .len = 18,
    },

    .starters = .{
        .{ .offset = 0x005B1DF8 },
        .{ .offset = 0x005B1DFA },
        .{ .offset = 0x005B1DFC },
    },
    .starters_repeat = .{
        .{ .offset = 0x005B1DF8 },
        .{ .offset = 0x005B1DFA },
        .{ .offset = 0x005B1DFC },
    },
};

pub const fire_us_info = Info{
    .game_title = .{ .data = "POKEMON FIRE".* },
    .gamecode = "BPRE".*,
    .version = .fire_red,
    .software_version = 1,

    .text_delays = .{
        .start = 4322456,
        .len = 3,
    },
    .trainers = .{
        .start = 2353976,
        .len = 743,
    },
    .moves = .{
        .start = 2428020,
        .len = 355,
    },
    .machine_learnsets = .{
        .start = 2436152,
        .len = 412,
    },
    .pokemons = .{
        .start = 2443252,
        .len = 412,
    },
    .evolutions = .{
        .start = 2463684,
        .len = 412,
    },
    .level_up_learnset_pointers = .{
        .start = 2480164,
        .len = 412,
    },
    .hms = .{
        .start = 2482308,
        .len = 8,
    },
    .tms = .{
        .start = 4564484,
        .len = 50,
    },
    .pokedex = .{
        .rsfrlg = .{
            .start = 4516016,
            .len = 387,
        },
    },
    .species_to_national_dex = .{
        .start = 2433118,
        .len = 411,
    },
    .items = .{
        .start = 4042904,
        .len = 374,
    },
    .wild_pokemon_headers = .{
        .start = 3972392,
        .len = 132,
    },
    .map_headers = .{
        .start = 3469816,
        .len = 425,
    },
    .pokemon_names = .{
        .start = 2383696,
        .len = 412,
    },
    .ability_names = .{
        .start = 2423984,
        .len = 78,
    },
    .move_names = .{
        .start = 2388228,
        .len = 355,
    },
    .type_names = .{
        .start = 2421264,
        .len = 18,
    },

    .starters = .{
        .{ .offset = 0x00169C2D },
        .{ .offset = 0x00169C2D + 515 },
        .{ .offset = 0x00169C2D + 461 },
    },
    .starters_repeat = .{
        .{ .offset = 0x00169C2D + 5 + 461 },
        .{ .offset = 0x00169C2D + 5 },
        .{ .offset = 0x00169C2D + 5 + 515 },
    },
};

pub const leaf_us_info = Info{
    .game_title = .{ .data = "POKEMON LEAF".* },
    .gamecode = "BPGE".*,
    .version = .leaf_green,
    .software_version = 1,

    .text_delays = .{
        .start = 4322004,
        .len = 3,
    },
    .trainers = .{
        .start = 2353940,
        .len = 743,
    },
    .moves = .{
        .start = 2427984,
        .len = 355,
    },
    .machine_learnsets = .{
        .start = 2436116,
        .len = 412,
    },
    .pokemons = .{
        .start = 2443216,
        .len = 412,
    },
    .evolutions = .{
        .start = 2463652,
        .len = 412,
    },
    .level_up_learnset_pointers = .{
        .start = 2480132,
        .len = 412,
    },
    .hms = .{
        .start = 2482276,
        .len = 8,
    },
    .tms = .{
        .start = 4562996,
        .len = 50,
    },
    .pokedex = .{
        .rsfrlg = .{
            .start = 4514528,
            .len = 387,
        },
    },
    .species_to_national_dex = .{
        .start = 2433082,
        .len = 411,
    },
    .items = .{
        .start = 4042452,
        .len = 374,
    },
    .wild_pokemon_headers = .{
        .start = 3971940,
        .len = 132,
    },
    .map_headers = .{
        .start = 3469784,
        .len = 425,
    },
    .pokemon_names = .{
        .start = 2383660,
        .len = 412,
    },
    .ability_names = .{
        .start = 2423948,
        .len = 78,
    },
    .move_names = .{
        .start = 2388192,
        .len = 355,
    },
    .type_names = .{
        .start = 2421228,
        .len = 18,
    },

    .starters = .{
        .{ .offset = 0x00169C09 },
        .{ .offset = 0x00169C09 + 515 },
        .{ .offset = 0x00169C09 + 461 },
    },
    .starters_repeat = .{
        .{ .offset = 0x00169C09 + 5 + 461 },
        .{ .offset = 0x00169C09 + 5 },
        .{ .offset = 0x00169C09 + 5 + 515 },
    },
};

pub const ruby_us_info = Info{
    .game_title = .{ .data = "POKEMON RUBY".* },
    .gamecode = "AXVE".*,
    .version = .ruby,
    .software_version = 1,

    .text_delays = .{
        .start = 1993712,
        .len = 3,
    },
    .trainers = .{
        .start = 2032916,
        .len = 337,
    },
    .moves = .{
        .start = 2076996,
        .len = 355,
    },
    .machine_learnsets = .{
        .start = 2085128,
        .len = 412,
    },
    .pokemons = .{
        .start = 2092080,
        .len = 412,
    },
    .evolutions = .{
        .start = 2112384,
        .len = 412,
    },
    .level_up_learnset_pointers = .{
        .start = 2128864,
        .len = 412,
    },
    .hms = .{
        .start = 2130738,
        .len = 8,
    },
    .tms = .{
        .start = 3630364,
        .len = 50,
    },
    .pokedex = .{
        .rsfrlg = .{
            .start = 3872884,
            .len = 387,
        },
    },
    .species_to_national_dex = .{
        .start = 2082094,
        .len = 411,
    },
    .items = .{
        .start = 3954048,
        .len = 349,
    },
    .wild_pokemon_headers = .{
        .start = 3789932,
        .len = 97,
    },
    .map_headers = .{
        .start = 3167328,
        .len = 394,
    },
    .pokemon_names = .{
        .start = 2060676,
        .len = 412,
    },
    .ability_names = .{
        .start = 2073184,
        .len = 78,
    },
    .move_names = .{
        .start = 2065208,
        .len = 355,
    },
    .type_names = .{
        .start = 2070664,
        .len = 18,
    },

    .starters = .{
        .{ .offset = 0x003F76E0 },
        .{ .offset = 0x003F76E2 },
        .{ .offset = 0x003F76E4 },
    },
    .starters_repeat = .{
        .{ .offset = 0x003F76E0 },
        .{ .offset = 0x003F76E2 },
        .{ .offset = 0x003F76E4 },
    },
};

pub const sapphire_us_info = Info{
    .game_title = .{ .data = "POKEMON SAPP".* },
    .gamecode = "AXPE".*,
    .version = .sapphire,
    .software_version = 1,

    .text_delays = .{
        .start = 1993600,
        .len = 3,
    },
    .trainers = .{
        .start = 2032804,
        .len = 337,
    },
    .moves = .{
        .start = 2076884,
        .len = 355,
    },
    .machine_learnsets = .{
        .start = 2085016,
        .len = 412,
    },
    .pokemons = .{
        .start = 2091968,
        .len = 412,
    },
    .evolutions = .{
        .start = 2112272,
        .len = 412,
    },
    .level_up_learnset_pointers = .{
        .start = 2128752,
        .len = 412,
    },
    .hms = .{
        .start = 2130626,
        .len = 8,
    },
    .tms = .{
        .start = 3630252,
        .len = 50,
    },
    .pokedex = .{
        .rsfrlg = .{
            .start = 3872976,
            .len = 387,
        },
    },
    .species_to_national_dex = .{
        .start = 2081982,
        .len = 411,
    },
    .items = .{
        .start = 3954140,
        .len = 349,
    },
    .wild_pokemon_headers = .{
        .start = 3789492,
        .len = 97,
    },
    .map_headers = .{
        .start = 3167216,
        .len = 394,
    },
    .pokemon_names = .{
        .start = 2060564,
        .len = 412,
    },
    .ability_names = .{
        .start = 2073072,
        .len = 78,
    },
    .move_names = .{
        .start = 2065096,
        .len = 355,
    },
    .type_names = .{
        .start = 2070552,
        .len = 18,
    },

    .starters = .{
        .{ .offset = 0x003F773C },
        .{ .offset = 0x003F773E },
        .{ .offset = 0x003F7740 },
    },
    .starters_repeat = .{
        .{ .offset = 0x003F773C },
        .{ .offset = 0x003F773E },
        .{ .offset = 0x003F7740 },
    },
};
