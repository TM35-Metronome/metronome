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

pub fn Offset(comptime _T: type, comptime _alignment: u29) type {
    return struct {
        pub const T = _T;
        pub const alignment = _alignment;

        offset: usize,

        pub fn fromOffset(offset: usize) @This() {
            debug.assert(offset % alignment == 0);
            return .{ .offset = offset };
        }

        pub fn fromPtr(
            data_slice: []align(alignment) const u8,
            p: *align(alignment) const T,
        ) @This() {
            const data_ptr = @intFromPtr(data_slice.ptr);
            const item_ptr = @intFromPtr(p);
            debug.assert(data_ptr <= item_ptr);
            debug.assert(item_ptr + @sizeOf(T) <= data_ptr + data_slice.len);

            return .{ .offset = item_ptr - data_ptr };
        }

        pub fn end(offset: @This()) usize {
            return offset.offset + @sizeOf(T);
        }

        pub fn ptr(offset: @This(), data: []align(alignment) u8) *align(alignment) T {
            return &mem.bytesAsSlice(T, data[offset.offset..][0..@sizeOf(T)])[0];
        }
    };
}

pub fn Section(comptime _Item: type, comptime _alignment: u29) type {
    return struct {
        pub const Item = _Item;
        pub const alignment = _alignment;

        start: usize,
        len: usize,

        pub fn fromOffset(start: usize, len: usize) @This() {
            debug.assert(start % alignment == 0);
            return .{ .start = start, .len = len };
        }

        pub fn fromSlice(
            data_slice: []align(alignment) const u8,
            items: []align(alignment) const Item,
        ) @This() {
            const data_ptr = @intFromPtr(data_slice.ptr);
            const item_ptr = @intFromPtr(items.ptr);
            debug.assert(data_ptr <= item_ptr);
            debug.assert(item_ptr + items.len * @sizeOf(Item) <= data_ptr + data_slice.len);

            return .{ .start = item_ptr - data_ptr, .len = items.len };
        }

        pub fn end(sec: @This()) usize {
            return sec.start + @sizeOf(Item) * sec.len;
        }

        pub fn slice(sec: @This(), data: []align(alignment) u8) []align(alignment) Item {
            const result = mem.bytesAsSlice(Item, data[sec.start..sec.end()]);

            // This is safe because:
            // * We have asserted when initializing that the offset is aligned
            // * The data slice is also aligned
            return @alignCast(result);
        }
    };
}

pub const AbilityNames = Section([13]u8, 1);
pub const BaseStatss = Section(gen3.BasePokemon, @alignOf(gen3.BasePokemon));
pub const EmeraldPokedexs = Section(gen3.EmeraldPokedexEntry, @alignOf(gen3.EmeraldPokedexEntry));
pub const Evolutions = Section([5]gen3.Evolution, @alignOf(gen3.Evolution));
pub const Hms = Section(lu16, @alignOf(lu16));
pub const Items = Section(gen3.Item, @alignOf(gen3.Item));
pub const LevelUpLearnsetPointers = Section(gen3.Ptr([*]gen3.LevelUpMove), @alignOf(gen3.Ptr([*]gen3.LevelUpMove)));
pub const MachineLearnsets = Section(lu64, 4);
pub const MapHeaders = Section(gen3.MapHeader, @alignOf(gen3.MapHeader));
pub const MoveNames = Section([13]u8, 1);
pub const Moves = Section(gen3.Move, @alignOf(gen3.Move));
pub const PokemonNames = Section([11]u8, 1);
pub const RSFrLgPokedexs = Section(gen3.RSFrLgPokedexEntry, @alignOf(gen3.RSFrLgPokedexEntry));
pub const SpeciesToNationalDexs = Section(lu16, @alignOf(u16));
pub const Starter = Offset(lu16, 1);
pub const TextDelays = Section(u8, 1);
pub const Tms = Section(lu16, @alignOf(lu16));
pub const Trainers = Section(gen3.Trainer, @alignOf(gen3.Trainer));
pub const TypeEffectivenesss = Section(common.TypeEffectiveness, @alignOf(common.TypeEffectiveness));
pub const TypeNames = Section([7]u8, 1);
pub const WildPokemonHeaders = Section(gen3.WildPokemonHeader, @alignOf(gen3.WildPokemonHeader));

pub const Info = struct {
    game_title: util.TerminatedArray(12, u8, 0),
    gamecode: [4]u8,
    version: common.Version,
    software_version: u8,

    text_delays: TextDelays,
    starters: [3]Starter,

    // In some games, the starters are repeated in multiple places.
    // For games where this isn't true, we just repeat the same offsets
    // twice
    starters_repeat: [3]Starter,
    trainers: Trainers,
    moves: Moves,
    machine_learnsets: MachineLearnsets,
    pokemons: BaseStatss,
    evolutions: Evolutions,
    level_up_learnset_pointers: LevelUpLearnsetPointers,
    type_effectiveness: TypeEffectivenesss,
    hms: Hms,
    tms: Tms,
    pokedex: union {
        rsfrlg: RSFrLgPokedexs,
        emerald: EmeraldPokedexs,
    },
    species_to_national_dex: SpeciesToNationalDexs,
    items: Items,
    wild_pokemon_headers: WildPokemonHeaders,
    map_headers: MapHeaders,
    pokemon_names: PokemonNames,
    ability_names: AbilityNames,
    move_names: AbilityNames,
    type_names: TypeNames,
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

    .text_delays = TextDelays.fromOffset(6353044, 3),
    .trainers = Trainers.fromOffset(3211312, 855),
    .moves = Moves.fromOffset(3262616, 355),
    .machine_learnsets = MachineLearnsets.fromOffset(3270808, 412),
    .pokemons = BaseStatss.fromOffset(3277772, 412),
    .evolutions = Evolutions.fromOffset(3298076, 412),
    .level_up_learnset_pointers = LevelUpLearnsetPointers.fromOffset(3314556, 412),
    .type_effectiveness = TypeEffectivenesss.fromOffset(3255528, 111),
    .hms = Hms.fromOffset(3317482, 8),
    .tms = Tms.fromOffset(6380436, 50),
    .pokedex = .{ .emerald = EmeraldPokedexs.fromOffset(5682608, 387) },
    .species_to_national_dex = SpeciesToNationalDexs.fromOffset(3267714, 411),
    .items = Items.fromOffset(5781920, 377),
    .wild_pokemon_headers = WildPokemonHeaders.fromOffset(5582152, 124),
    .map_headers = MapHeaders.fromOffset(4727992, 518),
    .pokemon_names = PokemonNames.fromOffset(3245512, 412),
    .ability_names = AbilityNames.fromOffset(3258075, 78),
    .move_names = MoveNames.fromOffset(3250044, 355),
    .type_names = TypeNames.fromOffset(3255864, 18),

    .starters = .{
        Starter.fromOffset(0x005B1DF8),
        Starter.fromOffset(0x005B1DFA),
        Starter.fromOffset(0x005B1DFC),
    },
    .starters_repeat = .{
        Starter.fromOffset(0x005B1DF8),
        Starter.fromOffset(0x005B1DFA),
        Starter.fromOffset(0x005B1DFC),
    },
};

pub const fire_us_info = Info{
    .game_title = .{ .data = "POKEMON FIRE".* },
    .gamecode = "BPRE".*,
    .version = .fire_red,
    .software_version = 1,

    .text_delays = TextDelays.fromOffset(4322456, 3),
    .trainers = Trainers.fromOffset(2353976, 743),
    .moves = Moves.fromOffset(2428020, 355),
    .machine_learnsets = MachineLearnsets.fromOffset(2436152, 412),
    .pokemons = BaseStatss.fromOffset(2443252, 412),
    .evolutions = Evolutions.fromOffset(2463684, 412),
    .level_up_learnset_pointers = LevelUpLearnsetPointers.fromOffset(2480164, 412),
    .type_effectiveness = TypeEffectivenesss.fromOffset(2420928, 111),
    .hms = Hms.fromOffset(2482308, 8),
    .tms = Tms.fromOffset(4564484, 50),
    .pokedex = .{ .rsfrlg = RSFrLgPokedexs.fromOffset(4516016, 387) },
    .species_to_national_dex = SpeciesToNationalDexs.fromOffset(2433118, 411),
    .items = Items.fromOffset(4042904, 374),
    .wild_pokemon_headers = WildPokemonHeaders.fromOffset(3972392, 132),
    .map_headers = MapHeaders.fromOffset(3469816, 425),
    .pokemon_names = PokemonNames.fromOffset(2383696, 412),
    .ability_names = AbilityNames.fromOffset(2423984, 78),
    .move_names = MoveNames.fromOffset(2388228, 355),
    .type_names = TypeNames.fromOffset(2421264, 18),

    .starters = .{
        Starter.fromOffset(0x00169C2D),
        Starter.fromOffset(0x00169C2D + 515),
        Starter.fromOffset(0x00169C2D + 461),
    },
    .starters_repeat = .{
        Starter.fromOffset(0x00169C2D + 5 + 461),
        Starter.fromOffset(0x00169C2D + 5),
        Starter.fromOffset(0x00169C2D + 5 + 515),
    },
};

pub const leaf_us_info = Info{
    .game_title = .{ .data = "POKEMON LEAF".* },
    .gamecode = "BPGE".*,
    .version = .leaf_green,
    .software_version = 1,

    .text_delays = TextDelays.fromOffset(4322004, 3),
    .trainers = Trainers.fromOffset(2353940, 743),
    .moves = Moves.fromOffset(2427984, 355),
    .machine_learnsets = MachineLearnsets.fromOffset(2436116, 412),
    .pokemons = BaseStatss.fromOffset(2443216, 412),
    .evolutions = Evolutions.fromOffset(2463652, 412),
    .level_up_learnset_pointers = LevelUpLearnsetPointers.fromOffset(2480132, 412),
    .type_effectiveness = TypeEffectivenesss.fromOffset(2420892, 111),
    .hms = Hms.fromOffset(2482276, 8),
    .tms = Tms.fromOffset(4562996, 50),
    .pokedex = .{ .rsfrlg = RSFrLgPokedexs.fromOffset(4514528, 387) },
    .species_to_national_dex = SpeciesToNationalDexs.fromOffset(2433082, 411),
    .items = Items.fromOffset(4042452, 374),
    .wild_pokemon_headers = WildPokemonHeaders.fromOffset(3971940, 132),
    .map_headers = MapHeaders.fromOffset(3469784, 425),
    .pokemon_names = PokemonNames.fromOffset(2383660, 412),
    .ability_names = AbilityNames.fromOffset(2423948, 78),
    .move_names = MoveNames.fromOffset(2388192, 355),
    .type_names = TypeNames.fromOffset(2421228, 18),

    .starters = .{
        Starter.fromOffset(0x00169C09),
        Starter.fromOffset(0x00169C09 + 515),
        Starter.fromOffset(0x00169C09 + 461),
    },
    .starters_repeat = .{
        Starter.fromOffset(0x00169C09 + 5 + 461),
        Starter.fromOffset(0x00169C09 + 5),
        Starter.fromOffset(0x00169C09 + 5 + 515),
    },
};

pub const ruby_us_info = Info{
    .game_title = .{ .data = "POKEMON RUBY".* },
    .gamecode = "AXVE".*,
    .version = .ruby,
    .software_version = 1,

    .text_delays = TextDelays.fromOffset(1993712, 3),
    .trainers = Trainers.fromOffset(2032916, 337),
    .moves = Moves.fromOffset(2076996, 355),
    .machine_learnsets = MachineLearnsets.fromOffset(2085128, 412),
    .pokemons = BaseStatss.fromOffset(2092080, 412),
    .evolutions = Evolutions.fromOffset(2112384, 412),
    .level_up_learnset_pointers = LevelUpLearnsetPointers.fromOffset(2128864, 412),
    .type_effectiveness = TypeEffectivenesss.fromOffset(2070328, 111),
    .hms = Hms.fromOffset(2130738, 8),
    .tms = Tms.fromOffset(3630364, 50),
    .pokedex = .{ .rsfrlg = RSFrLgPokedexs.fromOffset(3872884, 387) },
    .species_to_national_dex = SpeciesToNationalDexs.fromOffset(2082094, 411),
    .items = Items.fromOffset(3954048, 349),
    .wild_pokemon_headers = WildPokemonHeaders.fromOffset(3789932, 97),
    .map_headers = MapHeaders.fromOffset(3167328, 394),
    .pokemon_names = PokemonNames.fromOffset(2060676, 412),
    .ability_names = AbilityNames.fromOffset(2073184, 78),
    .move_names = MoveNames.fromOffset(2065208, 355),
    .type_names = TypeNames.fromOffset(2070664, 18),

    .starters = .{
        Starter.fromOffset(0x003F76E0),
        Starter.fromOffset(0x003F76E2),
        Starter.fromOffset(0x003F76E4),
    },
    .starters_repeat = .{
        Starter.fromOffset(0x003F76E0),
        Starter.fromOffset(0x003F76E2),
        Starter.fromOffset(0x003F76E4),
    },
};

pub const sapphire_us_info = Info{
    .game_title = .{ .data = "POKEMON SAPP".* },
    .gamecode = "AXPE".*,
    .version = .sapphire,
    .software_version = 1,

    .text_delays = TextDelays.fromOffset(1993600, 3),
    .trainers = Trainers.fromOffset(2032804, 337),
    .moves = Moves.fromOffset(2076884, 355),
    .machine_learnsets = MachineLearnsets.fromOffset(2085016, 412),
    .pokemons = BaseStatss.fromOffset(2091968, 412),
    .evolutions = Evolutions.fromOffset(2112272, 412),
    .level_up_learnset_pointers = LevelUpLearnsetPointers.fromOffset(2128752, 412),
    .type_effectiveness = TypeEffectivenesss.fromOffset(2070216, 111),
    .hms = Hms.fromOffset(2130626, 8),
    .tms = Tms.fromOffset(3630252, 50),
    .pokedex = .{ .rsfrlg = RSFrLgPokedexs.fromOffset(3872976, 387) },
    .species_to_national_dex = SpeciesToNationalDexs.fromOffset(2081982, 411),
    .items = Items.fromOffset(3954140, 349),
    .wild_pokemon_headers = WildPokemonHeaders.fromOffset(3789492, 97),
    .map_headers = MapHeaders.fromOffset(3167216, 394),
    .pokemon_names = PokemonNames.fromOffset(2060564, 412),
    .ability_names = AbilityNames.fromOffset(2073072, 78),
    .move_names = MoveNames.fromOffset(2065096, 355),
    .type_names = TypeNames.fromOffset(2070552, 18),

    .starters = .{
        Starter.fromOffset(0x003F773C),
        Starter.fromOffset(0x003F773E),
        Starter.fromOffset(0x003F7740),
    },
    .starters_repeat = .{
        Starter.fromOffset(0x003F773C),
        Starter.fromOffset(0x003F773E),
        Starter.fromOffset(0x003F7740),
    },
};
