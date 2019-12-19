const common = @import("../common.zig");

pub const StarterLocation = union(enum) {
    Arm9: usize,
    Overlay9: Overlay,

    pub const Overlay = struct {
        offset: usize,
        file: usize,
    };
};

pub const Info = struct {
    game_title: [12]u8,
    gamecode: [4]u8,
    version: common.Version,

    starters: StarterLocation,
    hm_tm_prefix: []const u8,
    pokemons: []const u8,
    level_up_moves: []const u8,
    moves: []const u8,
    trainers: []const u8,
    parties: []const u8,
    evolutions: []const u8,
    wild_pokemons: []const u8,
    scripts: []const u8,
};

pub const infos = [_]Info{
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

    .starters = StarterLocation{ .Arm9 = 0x00108514 },
    .hm_tm_prefix = "\x1E\x00\x32\x00",
    .pokemons = "/a/0/0/2",
    .level_up_moves = "/a/0/3/3",
    .moves = "/a/0/1/1",
    .trainers = "/a/0/5/5",
    .parties = "/a/0/5/6",
    .evolutions = "/a/0/3/4",
    .wild_pokemons = "a/0/3/7",
    .scripts = "a/0/1/2",
};

const ss_info = Info{
    .game_title = "POKEMON SS\x00\x00",
    .gamecode = "IPGE",
    .version = common.Version.SoulSilver,

    .starters = hg_info.starters,
    .hm_tm_prefix = hg_info.hm_tm_prefix,
    .pokemons = hg_info.pokemons,
    .level_up_moves = hg_info.level_up_moves,
    .moves = hg_info.moves,
    .trainers = hg_info.trainers,
    .parties = hg_info.parties,
    .evolutions = hg_info.evolutions,
    .wild_pokemons = "a/1/3/6",
    .scripts = hg_info.scripts,
};

const diamond_info = Info{
    .game_title = "POKEMON D\x00\x00\x00",
    .gamecode = "ADAE",
    .version = common.Version.Diamond,

    .starters = StarterLocation{
        .Overlay9 = StarterLocation.Overlay{
            .offset = 0x1B88,
            .file = 64,
        },
    },
    .hm_tm_prefix = "\xD1\x00\xD2\x00\xD3\x00\xD4\x00",
    .pokemons = "/poketool/personal/personal.narc",
    .level_up_moves = "/poketool/personal/wotbl.narc",
    .moves = "/poketool/waza/waza_tbl.narc",
    .trainers = "/poketool/trainer/trdata.narc",
    .parties = "/poketool/trainer/trpoke.narc",
    .evolutions = "/poketool/personal/evo.narc",
    .wild_pokemons = "fielddata/encountdata/d_enc_data.narc",
    .scripts = "fielddata/script/scr_seq_release.narc",
};

const pearl_info = Info{
    .game_title = "POKEMON P\x00\x00\x00",
    .gamecode = "APAE",
    .version = common.Version.Pearl,

    .starters = diamond_info.starters,
    .hm_tm_prefix = diamond_info.hm_tm_prefix,
    .pokemons = "/poketool/personal_pearl/personal.narc",
    .level_up_moves = diamond_info.level_up_moves,
    .moves = diamond_info.moves,
    .trainers = diamond_info.trainers,
    .parties = diamond_info.parties,
    .evolutions = diamond_info.evolutions,
    .wild_pokemons = "fielddata/encountdata/p_enc_data.narc",
    .scripts = diamond_info.scripts,
};

const platinum_info = Info{
    .game_title = "POKEMON PL\x00\x00",
    .gamecode = "CPUE",
    .version = common.Version.Platinum,

    .starters = StarterLocation{
        .Overlay9 = StarterLocation.Overlay{
            .offset = 0x1BC0,
            .file = 78,
        },
    },
    .hm_tm_prefix = diamond_info.hm_tm_prefix,
    .pokemons = "/poketool/personal/pl_personal.narc",
    .level_up_moves = diamond_info.level_up_moves,
    .moves = "/poketool/waza/pl_waza_tbl.narc",
    .trainers = diamond_info.trainers,
    .parties = diamond_info.parties,
    .evolutions = diamond_info.evolutions,
    .wild_pokemons = "fielddata/encountdata/pl_enc_data.narc",
    .scripts = "fielddata/script/scr_seq.narc",
};

pub const tm_count = 92;
pub const hm_count = 8;
pub const starters_len = 12;
