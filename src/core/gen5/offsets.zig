const common = @import("../common.zig");

pub const NarcOffset = struct {
    file: usize,
    offset: usize,
};

pub const OverlayOffset = struct {
    overlay: usize,
    offset: usize,
};

pub const Info = struct {
    game_title: [11:0]u8,
    gamecode: [4]u8,
    version: common.Version,

    starters: [3][]const NarcOffset,
    instant_text_patch: []const common.Patch,
    type_effectiveness: OverlayOffset,

    scripts: []const u8,
    pokemons: []const u8,
    evolutions: []const u8,
    level_up_moves: []const u8,
    moves: []const u8,
    trainers: []const u8,
    parties: []const u8,
    wild_pokemons: []const u8,
    itemdata: []const u8,
    hidden_hollows: ?[]const u8,

    map_file: []const u8,
    map_headers: u16,

    text: []const u8,
    pokemon_names: u16,
    pokedex_category_names: u16,
    trainer_names: u16,
    move_names: u16,
    move_descriptions: u16,
    ability_names: u16,
    item_names: u16,
    item_names_on_the_ground: u16,
    item_descriptions: u16,
    type_names: u16,
    map_names: u16,

    story: []const u8,
    starter_choice: u16,
    starter_choice_indexs: [3]usize,
};

pub const infos = [_]Info{
    black2_info,
    white2_info,
    black_info,
    white_info,
};

const black2_info = Info{
    .game_title = "POKEMON B2\x00".*,
    .gamecode = "IREO".*,
    .version = .black2,

    .starters = [_][]const NarcOffset{
        &[_]NarcOffset{
            NarcOffset{ .file = 854, .offset = 0x58B },
            NarcOffset{ .file = 854, .offset = 0x590 },
            NarcOffset{ .file = 854, .offset = 0x595 },
        },
        &[_]NarcOffset{
            NarcOffset{ .file = 854, .offset = 0x5C0 },
            NarcOffset{ .file = 854, .offset = 0x5C5 },
            NarcOffset{ .file = 854, .offset = 0x5CA },
        },
        &[_]NarcOffset{
            NarcOffset{ .file = 854, .offset = 0x5E2 },
            NarcOffset{ .file = 854, .offset = 0x5E7 },
            NarcOffset{ .file = 854, .offset = 0x5EC },
        },
    },
    .instant_text_patch = &[_]common.Patch{
        .{ .offset = 0x01e544, .replacement = "\xc0\x46\xc0\x46" },
        .{ .offset = 0x01e5fc, .replacement = "\xc5\xd1" },
    },
    .type_effectiveness = .{ .overlay = 167, .offset = 0x3dc40 },

    .scripts = "/a/0/5/6",
    .pokemons = "/a/0/1/6",
    .evolutions = "/a/0/1/9",
    .level_up_moves = "/a/0/1/8",
    .moves = "/a/0/2/1",
    .trainers = "/a/0/9/1",
    .parties = "/a/0/9/2",
    .wild_pokemons = "/a/1/2/7",
    .itemdata = "/a/0/2/4",
    .hidden_hollows = "/a/2/7/3",

    .map_file = "a/0/1/2",
    .map_headers = 0,

    .text = "a/0/0/2",
    .pokemon_names = 90,
    .pokedex_category_names = 464,
    .trainer_names = 382,
    .move_names = 403,
    .move_descriptions = 402,
    .ability_names = 374,
    .item_names = 64,
    .item_names_on_the_ground = 481,
    .item_descriptions = 63,
    .type_names = 489,
    .map_names = 109,

    .story = "/a/0/0/3",
    .starter_choice = 169,
    .starter_choice_indexs = .{ 37, 36, 35 },
};

const white2_info = Info{
    .game_title = "POKEMON W2\x00".*,
    .gamecode = "IRDO".*,
    .version = .white2,

    .starters = black2_info.starters,
    .instant_text_patch = &[_]common.Patch{
        .{ .offset = 0x01e570, .replacement = "\xc0\x46\xc0\x46" },
        .{ .offset = 0x01e628, .replacement = "\xc5\xd1" },
    },
    .type_effectiveness = .{ .overlay = 167, .offset = 0x3dc40 },

    .scripts = black2_info.scripts,
    .pokemons = black2_info.pokemons,
    .evolutions = black2_info.evolutions,
    .level_up_moves = black2_info.level_up_moves,
    .moves = black2_info.moves,
    .trainers = black2_info.trainers,
    .parties = black2_info.parties,
    .wild_pokemons = black2_info.wild_pokemons,
    .itemdata = black2_info.itemdata,
    .hidden_hollows = black2_info.hidden_hollows,

    .map_file = black2_info.map_file,
    .map_headers = black2_info.map_headers,

    .text = black2_info.text,
    .pokemon_names = black2_info.pokemon_names,
    .pokedex_category_names = black2_info.pokedex_category_names,
    .trainer_names = black2_info.trainer_names,
    .move_names = black2_info.move_names,
    .move_descriptions = black2_info.move_descriptions,
    .ability_names = black2_info.ability_names,
    .item_names = black2_info.item_names,
    .item_names_on_the_ground = black2_info.item_names_on_the_ground,
    .item_descriptions = black2_info.item_descriptions,
    .type_names = black2_info.type_names,
    .map_names = black2_info.map_names,

    .story = black2_info.story,
    .starter_choice = black2_info.starter_choice,
    .starter_choice_indexs = black2_info.starter_choice_indexs,
};

const black_info = Info{
    .game_title = "POKEMON B\x00\x00".*,
    .gamecode = "IRBO".*,
    .version = .black,

    .starters = [_][]const NarcOffset{
        &[_]NarcOffset{
            NarcOffset{ .file = 782, .offset = 0x27f },
            NarcOffset{ .file = 782, .offset = 0x284 },
            NarcOffset{ .file = 782, .offset = 0x361 },
            NarcOffset{ .file = 782, .offset = 0x5FD },
            NarcOffset{ .file = 304, .offset = 0x0F9 },
            NarcOffset{ .file = 304, .offset = 0x19C },
        },
        &[_]NarcOffset{
            NarcOffset{ .file = 782, .offset = 0x2af },
            NarcOffset{ .file = 782, .offset = 0x2b4 },
            NarcOffset{ .file = 782, .offset = 0x356 },
            NarcOffset{ .file = 782, .offset = 0x5F2 },
            NarcOffset{ .file = 304, .offset = 0x11C },
            NarcOffset{ .file = 304, .offset = 0x1C4 },
        },
        &[_]NarcOffset{
            NarcOffset{ .file = 782, .offset = 0x2cc },
            NarcOffset{ .file = 782, .offset = 0x2d1 },
            NarcOffset{ .file = 782, .offset = 0x338 },
            NarcOffset{ .file = 782, .offset = 0x5D4 },
            NarcOffset{ .file = 304, .offset = 0x12C },
            NarcOffset{ .file = 304, .offset = 0x1D9 },
        },
    },
    .instant_text_patch = &[_]common.Patch{
        .{ .offset = 0x018fc0, .replacement = "\xc0\x46\xc0\x46" },
        .{ .offset = 0x019078, .replacement = "\xc5\xd1" },
    },
    .type_effectiveness = .{ .overlay = 93, .offset = 0x3a37c },

    .scripts = "/a/0/5/7",
    .pokemons = black2_info.pokemons,
    .evolutions = black2_info.evolutions,
    .level_up_moves = black2_info.level_up_moves,
    .moves = black2_info.moves,
    .trainers = "/a/0/9/2",
    .parties = "/a/0/9/3",
    .wild_pokemons = "/a/1/2/6",
    .itemdata = black2_info.itemdata,
    .hidden_hollows = null,

    .map_file = black2_info.map_file,
    .map_headers = black2_info.map_headers,

    .text = black2_info.text,
    .pokemon_names = 70,
    .pokedex_category_names = 260,
    .trainer_names = 190,
    .move_names = 203,
    .move_descriptions = 202,
    .ability_names = 182,
    .item_names = 54,
    .item_names_on_the_ground = 279,
    .item_descriptions = 53,
    .type_names = 287,
    .map_names = 89,

    .story = black2_info.story,
    .starter_choice = 430,
    .starter_choice_indexs = .{ 18, 17, 16 },
};

const white_info = Info{
    .game_title = "POKEMON W\x00\x00".*,
    .gamecode = "IRAO".*,
    .version = .white,

    .starters = black_info.starters,
    .instant_text_patch = &[_]common.Patch{
        .{ .offset = 0x018fdc, .replacement = "\xc0\x46\xc0\x46" },
        .{ .offset = 0x019094, .replacement = "\xc5\xd1" },
    },
    .type_effectiveness = .{ .overlay = 93, .offset = 0x3a37c },

    .scripts = black_info.scripts,
    .pokemons = black_info.pokemons,
    .evolutions = black_info.evolutions,
    .level_up_moves = black_info.level_up_moves,
    .moves = black_info.moves,
    .trainers = black_info.trainers,
    .parties = black_info.parties,
    .wild_pokemons = black_info.wild_pokemons,
    .itemdata = black_info.itemdata,
    .hidden_hollows = black_info.hidden_hollows,

    .map_file = black_info.map_file,
    .map_headers = black_info.map_headers,

    .text = black_info.text,
    .pokemon_names = black_info.pokemon_names,
    .pokedex_category_names = black_info.pokedex_category_names,
    .trainer_names = black_info.trainer_names,
    .move_names = black_info.move_names,
    .move_descriptions = black_info.move_descriptions,
    .ability_names = black_info.ability_names,
    .item_names = black_info.item_names,
    .item_names_on_the_ground = black_info.item_names_on_the_ground,
    .item_descriptions = black_info.item_descriptions,
    .type_names = black_info.type_names,
    .map_names = black_info.map_names,

    .story = black_info.story,
    .starter_choice = black_info.starter_choice,
    .starter_choice_indexs = black_info.starter_choice_indexs,
};

pub const hm_count = 6;
pub const hm_tm_prefix = "\x87\x03\x88\x03";
pub const tm_count = 95;
