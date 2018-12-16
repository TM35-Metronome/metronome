const common = @import("tm35-common");

pub const Info = struct {
    game_title: [12]u8,
    gamecode: [4]u8,
    version: common.Version,

    hm_tm_prefix: []const u8,
    pokemons: []const u8,
    level_up_moves: []const u8,
    moves: []const u8,
    trainers: []const u8,
    parties: []const u8,
    evolutions: []const u8,
    wild_pokemons: []const u8,
};

pub const infos = []Info{
    hg_info,
    ss_info,
    diamond_info,
    pearl_info,
    platinum_info,
};

const hg_info = Info{
    .game_title = "POKEMON HG\x00\x00",
    .gamecode = "IPKE",
    .version = common.Version.HeartGold,

    .hm_tm_prefix = "\x1E\x00\x32\x00",
    .pokemons = "/a/0/0/2",
    .level_up_moves = "/a/0/3/3",
    .moves = "/a/0/1/1",
    .trainers = "/a/0/5/5",
    .parties = "/a/0/5/6",
    .evolutions = "/a/0/3/4",
    .wild_pokemons = "a/0/3/7",
};

const ss_info = blk: {
    var res = hg_info;
    res.game_title = "POKEMON SS\x00\x00";
    res.gamecode = "IPGE";
    res.version = common.Version.SoulSilver;
    res.wild_pokemons = "a/1/3/6";

    break :blk res;
};

const diamond_info = Info{
    .game_title = "POKEMON D\x00\x00\x00",
    .gamecode = "ADAE",
    .version = common.Version.Diamond,
    .hm_tm_prefix = "\xD1\x00\xD2\x00\xD3\x00\xD4\x00",

    .pokemons = "/poketool/personal/personal.narc",
    .level_up_moves = "/poketool/personal/wotbl.narc",
    .moves = "/poketool/waza/waza_tbl.narc",
    .trainers = "/poketool/trainer/trdata.narc",
    .parties = "/poketool/trainer/trpoke.narc",
    .evolutions = "/poketool/personal/evo.narc",
    .wild_pokemons = "fielddata/encountdata/d_enc_data.narc",
};

const pearl_info = blk: {
    var res = diamond_info;
    res.game_title = "POKEMON P\x00\x00\x00";
    res.gamecode = "APAE";
    res.version = common.Version.Pearl;
    res.pokemons = "/poketool/personal_pearl/personal.narc";
    res.wild_pokemons = "fielddata/encountdata/p_enc_data.narc";
    break :blk res;
};

const platinum_info = blk: {
    var res = diamond_info;
    res.game_title = "POKEMON PL\x00\x00";
    res.gamecode = "CPUE";
    res.version = common.Version.Platinum;
    res.pokemons = "/poketool/personal/pl_personal.narc";
    res.moves = "/poketool/waza/pl_waza_tbl.narc";
    res.wild_pokemons = "fielddata/encountdata/pl_enc_data.narc";
    break :blk res;
};

pub const tm_count = 92;
pub const hm_count = 8;
