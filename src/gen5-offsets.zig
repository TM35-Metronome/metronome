const common = @import("tm35-common");

pub const Info = struct {
    game_title: [12]u8,
    gamecode: [4]u8,
    version: common.Version,

    pokemons: []const u8,
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

    .pokemons = "a/0/1/6",
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
