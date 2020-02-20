const common = @import("../common.zig");

pub const NarcOffset = struct {
    file: usize,
    offset: usize,
};

pub const Info = struct {
    game_title: [12]u8,
    gamecode: [4]u8,
    version: common.Version,

    starters: [3][]const NarcOffset,
    scripts: []const u8,
    pokemons: []const u8,
    evolutions: []const u8,
    level_up_moves: []const u8,
    moves: []const u8,
    trainers: []const u8,
    parties: []const u8,
    wild_pokemons: []const u8,
    itemdata: []const u8,
};

pub const infos = [_]Info{
    black2_info,
    white2_info,
    black_info,
    white_info,
};

const black2_info = Info{
    .game_title = "POKEMON B2\x00\x00",
    .gamecode = "IREO",
    .version = common.Version.Black2,

    .starters = [_][]const NarcOffset{
        [_]NarcOffset{
            NarcOffset{ .file = 854, .offset = 0x58B },
            NarcOffset{ .file = 854, .offset = 0x590 },
            NarcOffset{ .file = 854, .offset = 0x595 },
        },
        [_]NarcOffset{
            NarcOffset{ .file = 854, .offset = 0x5C0 },
            NarcOffset{ .file = 854, .offset = 0x5C5 },
            NarcOffset{ .file = 854, .offset = 0x5CA },
        },
        [_]NarcOffset{
            NarcOffset{ .file = 854, .offset = 0x5E2 },
            NarcOffset{ .file = 854, .offset = 0x5E7 },
            NarcOffset{ .file = 854, .offset = 0x5EC },
        },
    },
    .scripts = "/a/0/5/6",
    .pokemons = "/a/0/1/6",
    .evolutions = "/a/0/1/9",
    .level_up_moves = "/a/0/1/8",
    .moves = "/a/0/2/1",
    .trainers = "/a/0/9/1",
    .parties = "/a/0/9/2",
    .wild_pokemons = "/a/1/2/7",
    .itemdata = "/a/0/2/4",
};

const white2_info = Info{
    .game_title = "POKEMON W2\x00\x00",
    .gamecode = "IRDO",
    .version = common.Version.White2,

    .starters = black2_info.starters,
    .scripts = black2_info.scripts,
    .pokemons = black2_info.pokemons,
    .evolutions = black2_info.evolutions,
    .level_up_moves = black2_info.level_up_moves,
    .moves = black2_info.moves,
    .trainers = black2_info.trainers,
    .parties = black2_info.parties,
    .wild_pokemons = black2_info.wild_pokemons,
    .itemdata = black2_info.itemdata,
};

const black_info = Info{
    .game_title = "POKEMON B\x00\x00\x00",
    .gamecode = "IRBO",
    .version = common.Version.Black,

    .starters = [_][]const NarcOffset{
        [_]NarcOffset{
            NarcOffset{ .file = 782, .offset = 0x27f },
            NarcOffset{ .file = 782, .offset = 0x284 },
            NarcOffset{ .file = 782, .offset = 0x361 },
            NarcOffset{ .file = 782, .offset = 0x5FD },
            NarcOffset{ .file = 304, .offset = 0x0F9 },
            NarcOffset{ .file = 304, .offset = 0x19C },
        },
        [_]NarcOffset{
            NarcOffset{ .file = 782, .offset = 0x2af },
            NarcOffset{ .file = 782, .offset = 0x2b4 },
            NarcOffset{ .file = 782, .offset = 0x356 },
            NarcOffset{ .file = 782, .offset = 0x5F2 },
            NarcOffset{ .file = 304, .offset = 0x11C },
            NarcOffset{ .file = 304, .offset = 0x1C4 },
        },
        [_]NarcOffset{
            NarcOffset{ .file = 782, .offset = 0x2cc },
            NarcOffset{ .file = 782, .offset = 0x2d1 },
            NarcOffset{ .file = 782, .offset = 0x338 },
            NarcOffset{ .file = 782, .offset = 0x5D4 },
            NarcOffset{ .file = 304, .offset = 0x12C },
            NarcOffset{ .file = 304, .offset = 0x1D9 },
        },
    },
    .scripts = "/a/0/5/7",
    .pokemons = black2_info.pokemons,
    .evolutions = black2_info.evolutions,
    .level_up_moves = black2_info.level_up_moves,
    .moves = black2_info.moves,
    .trainers = "/a/0/9/2",
    .parties = "/a/0/9/3",
    .wild_pokemons = "/a/1/2/6",
    .itemdata = black2_info.itemdata,
};

const white_info = Info{
    .game_title = "POKEMON W\x00\x00\x00",
    .gamecode = "IRAO",
    .version = common.Version.Black,

    .starters = black_info.starters,
    .scripts = black_info.scripts,
    .pokemons = black_info.pokemons,
    .evolutions = black_info.evolutions,
    .level_up_moves = black_info.level_up_moves,
    .moves = black_info.moves,
    .trainers = black_info.trainers,
    .parties = black_info.parties,
    .wild_pokemons = black_info.wild_pokemons,
    .itemdata = black_info.itemdata,
};

pub const tm_count = 95;
pub const hm_count = 6;
pub const hm_tm_prefix = "\x87\x03\x88\x03";
