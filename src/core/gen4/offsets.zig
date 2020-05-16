const common = @import("../common.zig");

pub const StarterLocation = union(enum) {
    arm9: usize,
    overlay9: Overlay,

    pub const Overlay = struct {
        offset: usize,
        file: usize,
    };
};

pub const Info = struct {
    game_title: [11:0]u8,
    gamecode: [4]u8,
    version: common.Version,

    starters: StarterLocation,
    hm_tm_prefix: []const u8,
    pokemons: []const []const u8,
    level_up_moves: []const []const u8,
    moves: []const []const u8,
    trainers: []const []const u8,
    parties: []const []const u8,
    evolutions: []const []const u8,
    wild_pokemons: []const []const u8,
    scripts: []const []const u8,
    itemdata: []const []const u8,
};

pub const infos = [_]Info{
    hg_info,
    ss_info,
    diamond_info,
    pearl_info,
    platinum_info,
};

const hg_info = Info{
    .game_title = "POKEMON HG\x00".*,
    .gamecode = "IPKE".*,
    .version = .heart_gold,

    .starters = StarterLocation{ .arm9 = 0x00108514 },
    .hm_tm_prefix = "\x1E\x00\x32\x00",
    .pokemons = &[_][]const u8{ "a", "0", "0", "2" },
    .level_up_moves = &[_][]const u8{ "a", "0", "3", "3" },
    .moves = &[_][]const u8{ "a", "0", "1", "1" },
    .trainers = &[_][]const u8{ "a", "0", "5", "5" },
    .parties = &[_][]const u8{ "a", "0", "5", "6" },
    .evolutions = &[_][]const u8{ "a", "0", "3", "4" },
    .wild_pokemons = &[_][]const u8{ "a", "0", "3", "7" },
    .scripts = &[_][]const u8{ "a", "0", "1", "2" },
    .itemdata = &[_][]const u8{ "a", "0", "1", "7" },
};

const ss_info = Info{
    .game_title = "POKEMON SS\x00".*,
    .gamecode = "IPGE".*,
    .version = .soul_silver,

    .starters = hg_info.starters,
    .hm_tm_prefix = hg_info.hm_tm_prefix,
    .pokemons = hg_info.pokemons,
    .level_up_moves = hg_info.level_up_moves,
    .moves = hg_info.moves,
    .trainers = hg_info.trainers,
    .parties = hg_info.parties,
    .evolutions = hg_info.evolutions,
    .wild_pokemons = &[_][]const u8{ "a", "1", "3", "6" },
    .scripts = hg_info.scripts,
    .itemdata = hg_info.itemdata,
};

const diamond_info = Info{
    .game_title = "POKEMON D\x00\x00".*,
    .gamecode = "ADAE".*,
    .version = .diamond,

    .starters = StarterLocation{
        .overlay9 = StarterLocation.Overlay{
            .offset = 0x1B88,
            .file = 64,
        },
    },
    .hm_tm_prefix = "\xD1\x00\xD2\x00\xD3\x00\xD4\x00",
    .pokemons = &[_][]const u8{ "poketool", "personal", "personal.narc" },
    .level_up_moves = &[_][]const u8{ "poketool", "personal", "wotbl.narc" },
    .moves = &[_][]const u8{ "poketool", "waza", "waza_tbl.narc" },
    .trainers = &[_][]const u8{ "poketool", "trainer", "trdata.narc" },
    .parties = &[_][]const u8{ "poketool", "trainer", "trpoke.narc" },
    .evolutions = &[_][]const u8{ "poketool", "personal", "evo.narc" },
    .wild_pokemons = &[_][]const u8{ "fielddata", "encountdata", "d_enc_data.narc" },
    .scripts = &[_][]const u8{ "fielddata", "script", "scr_seq_release.narc" },
    .itemdata = &[_][]const u8{ "itemtool", "itemdata", "item_data.narc" },
};

const pearl_info = Info{
    .game_title = "POKEMON P\x00\x00".*,
    .gamecode = "APAE".*,
    .version = .pearl,

    .starters = diamond_info.starters,
    .hm_tm_prefix = diamond_info.hm_tm_prefix,
    .pokemons = &[_][]const u8{ "poketool", "personal_pearl", "personal.narc" },
    .level_up_moves = diamond_info.level_up_moves,
    .moves = diamond_info.moves,
    .trainers = diamond_info.trainers,
    .parties = diamond_info.parties,
    .evolutions = diamond_info.evolutions,
    .wild_pokemons = &[_][]const u8{ "fielddata", "encountdata", "p_enc_data.narc" },
    .scripts = diamond_info.scripts,
    .itemdata = diamond_info.itemdata,
};

const platinum_info = Info{
    .game_title = "POKEMON PL\x00".*,
    .gamecode = "CPUE".*,
    .version = .platinum,

    .starters = StarterLocation{
        .overlay9 = StarterLocation.Overlay{
            .offset = 0x1BC0,
            .file = 78,
        },
    },
    .hm_tm_prefix = diamond_info.hm_tm_prefix,
    .pokemons = &[_][]const u8{ "poketool", "personal", "pl_personal.narc" },
    .level_up_moves = diamond_info.level_up_moves,
    .moves = &[_][]const u8{ "poketool", "waza", "pl_waza_tbl.narc" },
    .trainers = diamond_info.trainers,
    .parties = diamond_info.parties,
    .evolutions = diamond_info.evolutions,
    .wild_pokemons = &[_][]const u8{ "fielddata", "encountdata", "pl_enc_data.narc" },
    .scripts = &[_][]const u8{ "fielddata", "script", "scr_seq.narc" },
    .itemdata = &[_][]const u8{ "itemtool", "itemdata", "pl_item_data.narc" },
};

pub const tm_count = 92;
pub const hm_count = 8;
pub const starters_len = 12;
