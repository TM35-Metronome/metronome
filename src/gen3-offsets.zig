const common = @import("tm35-common");
const debug = std.debug;
const fun = @import("fun-with-zig");
const gen3 = @import("gen3-types.zig");
const generic = fun.generic;
const mem = std.mem;
const std = @import("std");

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu64 = fun.platform.lu64;

pub fn Offset(comptime T: type) type {
    return struct {
        offset: usize,

        pub fn init(data_slice: []const u8, ptr: *const T) @This() {
            const data_ptr = @ptrToInt(data_slice.ptr);
            const item_ptr = @ptrToInt(items.ptr);
            debug.assert(data_ptr <= item_ptr);
            debug.assert(item_ptr + @sizeOf(Item) <= data_ptr + data_slice.len);

            return @This(){ .offset = item_ptr - data_ptr };
        }

        pub fn ptr(offset: @This(), data: []u8) *T {
            return &@bytesToSlice(T, data[offset.offset..][0..@sizeOf(T)])[0];
        }
    };
}

pub fn Section(comptime Item: type) type {
    return struct {
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
            return @bytesToSlice(Item, data[sec.start..sec.end()]);
        }
    };
}

pub const StarterOffset = Offset(lu16);
pub const TrainerSection = Section(gen3.Trainer);
pub const MoveSection = Section(gen3.Move);
pub const MachineLearnsetSection = Section(lu64);
pub const BaseStatsSection = Section(gen3.BasePokemon);
pub const EvolutionSection = Section([5]common.Evolution);
pub const LevelUpLearnsetPointerSection = Section(gen3.Ptr(gen3.LevelUpMove));
pub const HmSection = Section(lu16);
pub const TmSection = Section(lu16);
pub const ItemSection = Section(gen3.Item);
pub const WildPokemonHeaderSection = Section(gen3.WildPokemonHeader);
pub const MapHeaderSection = Section(gen3.MapHeader);

pub const Info = struct {
    game_title: [12]u8,
    gamecode: [4]u8,
    version: common.Version,

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
    items: ItemSection,
    wild_pokemon_headers: WildPokemonHeaderSection,
    map_headers: MapHeaderSection,
};

pub const infos = []Info{
    emerald_us_info,
    ruby_us_info,
    sapphire_us_info,
    fire_us_info,
    leaf_us_info,
};

const emerald_us_info = Info{
    .game_title = "POKEMON EMER",
    .gamecode = "BPEE",
    .version = common.Version.Emerald,
    .starters = []StarterOffset{
        StarterOffset{ .offset = 0x005B1DF8 },
        StarterOffset{ .offset = 0x005B1DFA },
        StarterOffset{ .offset = 0x005B1DFC },
    },
    .starters_repeat = []StarterOffset{
        StarterOffset{ .offset = 0x005B1DF8 },
        StarterOffset{ .offset = 0x005B1DFA },
        StarterOffset{ .offset = 0x005B1DFC },
    },
    .trainers = TrainerSection{
        .start = 0x00310030,
        .len = 855,
    },
    .moves = MoveSection{
        .start = 0x0031C898,
        .len = 355,
    },
    .machine_learnsets = MachineLearnsetSection{
        .start = 0x0031E898,
        .len = 412,
    },
    .pokemons = BaseStatsSection{
        .start = 0x003203CC,
        .len = 412,
    },
    .evolutions = EvolutionSection{
        .start = 0x0032531C,
        .len = 412,
    },
    .level_up_learnset_pointers = LevelUpLearnsetPointerSection{
        .start = 0x0032937C,
        .len = 412,
    },
    .hms = HmSection{
        .start = 0x00329EEA,
        .len = 8,
    },
    .tms = TmSection{
        .start = 0x00615B94,
        .len = 50,
    },
    .items = ItemSection{
        .start = 0x005839A0,
        .len = 377,
    },
    .wild_pokemon_headers = WildPokemonHeaderSection{
        .start = 0x00552D48,
        .len = 124,
    },
};

pub const ruby_us_info = Info{
    .game_title = "POKEMON RUBY",
    .gamecode = "AXVE",
    .version = common.Version.Ruby,
    .starters = []StarterOffset{
        StarterOffset{ .offset = 0x003F76E0 },
        StarterOffset{ .offset = 0x003F76E2 },
        StarterOffset{ .offset = 0x003F76E4 },
    },
    .starters_repeat = []StarterOffset{
        StarterOffset{ .offset = 0x003F76E0 },
        StarterOffset{ .offset = 0x003F76E2 },
        StarterOffset{ .offset = 0x003F76E4 },
    },
    .trainers = TrainerSection{
        .start = 0x001F0514,
        .len = 337,
    },
    .moves = MoveSection{
        .start = 0x001FB144,
        .len = 355,
    },
    .machine_learnsets = MachineLearnsetSection{
        .start = 0x001FD108,
        .len = 412,
    },
    .pokemons = BaseStatsSection{
        .start = 0x001FEC30,
        .len = 412,
    },
    .evolutions = EvolutionSection{
        .start = 0x00203B80,
        .len = 412,
    },
    .level_up_learnset_pointers = LevelUpLearnsetPointerSection{
        .start = 0x00207BE0,
        .len = 412,
    },
    .hms = HmSection{
        .start = 0x00208332,
        .len = 8,
    },
    .tms = TmSection{
        .start = 0x0037651C,
        .len = 50,
    },
    .items = ItemSection{
        .start = 0x003C5580,
        .len = 349,
    },
    .wild_pokemon_headers = WildPokemonHeaderSection{
        .start = 0x0039D46C,
        .len = 97,
    },
};

pub const sapphire_us_info = Info{
    .game_title = "POKEMON SAPP",
    .gamecode = "AXPE",
    .version = common.Version.Sapphire,
    .starters = []StarterOffset{
        StarterOffset{ .offset = 0x003F773C },
        StarterOffset{ .offset = 0x003F773E },
        StarterOffset{ .offset = 0x003F7740 },
    },
    .starters_repeat = []StarterOffset{
        StarterOffset{ .offset = 0x003F773C },
        StarterOffset{ .offset = 0x003F773E },
        StarterOffset{ .offset = 0x003F7740 },
    },
    .trainers = TrainerSection{
        .start = 0x001F04A4,
        .len = 337,
    },
    .moves = MoveSection{
        .start = 0x001FB0D4,
        .len = 355,
    },
    .machine_learnsets = MachineLearnsetSection{
        .start = 0x001FD098,
        .len = 412,
    },
    .pokemons = BaseStatsSection{
        .start = 0x001FEBC0,
        .len = 412,
    },
    .evolutions = EvolutionSection{
        .start = 0x00203B10,
        .len = 412,
    },
    .level_up_learnset_pointers = LevelUpLearnsetPointerSection{
        .start = 0x00207B70,
        .len = 412,
    },
    .hms = HmSection{
        .start = 0x002082C2,
        .len = 8,
    },
    .tms = TmSection{
        .start = 0x003764AC,
        .len = 50,
    },
    .items = ItemSection{
        .start = 0x003C55DC,
        .len = 349,
    },
    .wild_pokemon_headers = WildPokemonHeaderSection{
        .start = 0x0039D2B4,
        .len = 97,
    },
};

pub const fire_us_info = Info{
    .game_title = "POKEMON FIRE",
    .gamecode = "BPRE",
    .version = common.Version.FireRed,
    .starters = []StarterOffset{
        StarterOffset{ .offset = 0x00169C2D },
        StarterOffset{ .offset = 0x00169C2D + 515 },
        StarterOffset{ .offset = 0x00169C2D + 461 },
    },
    .starters_repeat = []StarterOffset{
        StarterOffset{ .offset = 0x00169C2D + 5 + 461 },
        StarterOffset{ .offset = 0x00169C2D + 5 },
        StarterOffset{ .offset = 0x00169C2D + 5 + 515 },
    },
    .trainers = TrainerSection{
        .start = 0x0023EB38,
        .len = 743,
    },
    .moves = MoveSection{
        .start = 0x00250C74,
        .len = 355,
    },
    .machine_learnsets = MachineLearnsetSection{
        .start = 0x00252C38,
        .len = 412,
    },
    .pokemons = BaseStatsSection{
        .start = 0x002547F4,
        .len = 412,
    },
    .evolutions = EvolutionSection{
        .start = 0x002597C4,
        .len = 412,
    },
    .level_up_learnset_pointers = LevelUpLearnsetPointerSection{
        .start = 0x0025D824,
        .len = 412,
    },
    .hms = HmSection{
        .start = 0x0025E084,
        .len = 8,
    },
    .tms = TmSection{
        .start = 0x0045A604,
        .len = 50,
    },
    .items = ItemSection{
        .start = 0x003DB098,
        .len = 374,
    },
    .wild_pokemon_headers = WildPokemonHeaderSection{
        .start = 0x003C9D28,
        .len = 132,
    },
};

pub const leaf_us_info = Info{
    .game_title = "POKEMON LEAF",
    .gamecode = "BPGE",
    .version = common.Version.LeafGreen,
    .starters = []StarterOffset{
        StarterOffset{ .offset = 0x00169C09 },
        StarterOffset{ .offset = 0x00169C09 + 515 },
        StarterOffset{ .offset = 0x00169C09 + 461 },
    },
    .starters_repeat = []StarterOffset{
        StarterOffset{ .offset = 0x00169C09 + 5 + 461 },
        StarterOffset{ .offset = 0x00169C09 + 5 },
        StarterOffset{ .offset = 0x00169C09 + 5 + 515 },
    },
    .trainers = TrainerSection{
        .start = 0x0023EB14,
        .len = 743,
    },
    .moves = MoveSection{
        .start = 0x00250C50,
        .len = 355,
    },
    .machine_learnsets = MachineLearnsetSection{
        .start = 0x00252C14,
        .len = 412,
    },
    .pokemons = BaseStatsSection{
        .start = 0x002547D0,
        .len = 412,
    },
    .evolutions = EvolutionSection{
        .start = 0x002597A4,
        .len = 412,
    },
    .level_up_learnset_pointers = LevelUpLearnsetPointerSection{
        .start = 0x0025D804,
        .len = 412,
    },
    .hms = HmSection{
        .start = 0x0025E064,
        .len = 8,
    },
    .tms = TmSection{
        .start = 0x0045A034,
        .len = 50,
    },
    .items = ItemSection{
        .start = 0x003DAED4,
        .len = 374,
    },
    .wild_pokemon_headers = WildPokemonHeaderSection{
        .start = 0x003C9B64,
        .len = 132,
    },
};
