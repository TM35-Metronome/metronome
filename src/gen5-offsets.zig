const common = @import("tm35-common");

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
};

pub const infos = []Info{
    black2_info,
    white2_info,
    black_info,
    white_info,
};

const black2_info = Info{
    .game_title = "POKEMON B2\x00\x00",
    .gamecode = "IREO",
    .version = common.Version.Black2,

    .starters = [][]const NarcOffset{
        []NarcOffset{
            NarcOffset{ .file = 854, .offset = 0x58B },
            NarcOffset{ .file = 854, .offset = 0x590 },
            NarcOffset{ .file = 854, .offset = 0x595 },
        },
        []NarcOffset{
            NarcOffset{ .file = 854, .offset = 0x5C0 },
            NarcOffset{ .file = 854, .offset = 0x5C5 },
            NarcOffset{ .file = 854, .offset = 0x5CA },
        },
        []NarcOffset{
            NarcOffset{ .file = 854, .offset = 0x5E2 },
            NarcOffset{ .file = 854, .offset = 0x5E7 },
            NarcOffset{ .file = 854, .offset = 0x5EC },
        },
    },
    .scripts = "a/0/5/6",
    .pokemons = "a/0/1/6",
    .evolutions = "a/0/1/9",
    .level_up_moves = "a/0/1/8",
    .moves = "a/0/2/1",
    .trainers = "a/0/9/1",
    .parties = "a/0/9/2",
    .wild_pokemons = "a/1/2/7",
};

const white2_info = blk: {
    var res = black2_info;
    res.game_title = "POKEMON W2\x00\x00";
    res.gamecode = "IRDO";
    res.version = common.Version.White2;

    break :blk res;
};

const black_info = blk: {
    var res = black2_info;
    res.game_title = "POKEMON B\x00\x00\x00";
    res.gamecode = "IRBO";
    res.version = common.Version.Black;
    res.starters = [][]const NarcOffset{
        []NarcOffset{
            NarcOffset{ .file = 782, .offset = 0x27f },
            NarcOffset{ .file = 782, .offset = 0x284 },
            NarcOffset{ .file = 782, .offset = 0x361 },
            NarcOffset{ .file = 782, .offset = 0x5FD },
            NarcOffset{ .file = 304, .offset = 0x0F9 },
            NarcOffset{ .file = 304, .offset = 0x19C },
        },
        []NarcOffset{
            NarcOffset{ .file = 782, .offset = 0x2af },
            NarcOffset{ .file = 782, .offset = 0x2b4 },
            NarcOffset{ .file = 782, .offset = 0x356 },
            NarcOffset{ .file = 782, .offset = 0x5F2 },
            NarcOffset{ .file = 304, .offset = 0x11C },
            NarcOffset{ .file = 304, .offset = 0x1C4 },
        },
        []NarcOffset{
            NarcOffset{ .file = 782, .offset = 0x2cc },
            NarcOffset{ .file = 782, .offset = 0x2d1 },
            NarcOffset{ .file = 782, .offset = 0x338 },
            NarcOffset{ .file = 782, .offset = 0x5D4 },
            NarcOffset{ .file = 304, .offset = 0x12C },
            NarcOffset{ .file = 304, .offset = 0x1D9 },
        },
    };
    res.scripts = "a/0/5/7";
    res.trainers = "a/0/9/2";
    res.parties = "a/0/9/3";
    res.wild_pokemons = "a/1/2/6";

    break :blk res;
};

const white_info = blk: {
    var res = black_info;
    res.game_title = "POKEMON W\x00\x00\x00";
    res.gamecode = "IRAO";
    res.version = common.Version.Black;

    break :blk res;
};

pub const tm_count = 95;
pub const hm_count = 6;
pub const hm_tm_prefix = "\x87\x03\x88\x03";
