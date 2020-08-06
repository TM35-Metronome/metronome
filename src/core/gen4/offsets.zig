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
    instant_text_patch: []const common.Patch,
    hm_tm_prefix: []const u8,

    pokemons: []const u8,
    level_up_moves: []const u8,
    moves: []const u8,
    trainers: []const u8,
    parties: []const u8,
    evolutions: []const u8,
    wild_pokemons: []const u8,
    scripts: []const u8,
    itemdata: []const u8,

    pokedex: []const u8,
    pokedex_heights: u16,
    pokedex_weights: u16,
    species_to_national_dex: u16,

    text: []const u8,
    pokemon_names: u16,
    trainer_names: u16,
    move_names: u16,
    move_descriptions: u16,
    ability_names: u16,
    item_names: u16,
    item_descriptions: u16,
    type_names: u16,
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
    .instant_text_patch = &[_]common.Patch{
        .{ .offset = 0x002346, .replacement = "\x00\x21" },
        .{ .offset = 0x0202ee, .replacement = "\x0c\x1c\x18\x48" },
        .{ .offset = 0x02031e, .replacement = "\x10\xbd\x2d\x3c\xe5\xe7" },
        .{ .offset = 0x02032e, .replacement = "\xdf\xd0" },
        .{ .offset = 0x02033a, .replacement = "\xf1\xe7" },
    },
    .hm_tm_prefix = "\x1E\x00\x32\x00",

    .pokemons = "/a/0/0/2",
    .level_up_moves = "/a/0/3/3",
    .moves = "/a/0/1/1",
    .trainers = "/a/0/5/5",
    .parties = "/a/0/5/6",
    .evolutions = "/a/0/3/4",
    .wild_pokemons = "/a/0/3/7",
    .scripts = "/a/0/1/2",
    .itemdata = "/a/0/1/7",

    .pokedex = "/a/0/7/4",
    .pokedex_heights = 0,
    .pokedex_weights = 1,
    .species_to_national_dex = 11,

    .text = "/a/0/2/7",
    .pokemon_names = 237,
    .trainer_names = 729,
    .move_names = 750,
    .move_descriptions = 749,
    .ability_names = 720,
    .item_names = 222,
    .item_descriptions = 221,
    .type_names = 735,
};

const ss_info = Info{
    .game_title = "POKEMON SS\x00".*,
    .gamecode = "IPGE".*,
    .version = .soul_silver,

    .starters = hg_info.starters,
    .instant_text_patch = hg_info.instant_text_patch,
    .hm_tm_prefix = hg_info.hm_tm_prefix,

    .pokemons = hg_info.pokemons,
    .level_up_moves = hg_info.level_up_moves,
    .moves = hg_info.moves,
    .trainers = hg_info.trainers,
    .parties = hg_info.parties,
    .evolutions = hg_info.evolutions,
    .wild_pokemons = "/a/1/3/6",
    .scripts = hg_info.scripts,
    .itemdata = hg_info.itemdata,

    .pokedex = hg_info.pokedex,
    .pokedex_heights = hg_info.pokedex_heights,
    .pokedex_weights = hg_info.pokedex_weights,
    .species_to_national_dex = hg_info.species_to_national_dex,

    .text = hg_info.text,
    .pokemon_names = hg_info.pokemon_names,
    .trainer_names = hg_info.trainer_names,
    .move_names = hg_info.move_names,
    .move_descriptions = hg_info.move_descriptions,
    .ability_names = hg_info.ability_names,
    .item_names = hg_info.item_names,
    .item_descriptions = hg_info.item_descriptions,
    .type_names = hg_info.type_names,
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
    .instant_text_patch = &[_]common.Patch{},
    .hm_tm_prefix = "\xD1\x00\xD2\x00\xD3\x00\xD4\x00",

    .pokemons = "/poketool/personal/personal.narc",
    .level_up_moves = "/poketool/personal/wotbl.narc",
    .moves = "/poketool/waza/waza_tbl.narc",
    .trainers = "/poketool/trainer/trdata.narc",
    .parties = "/poketool/trainer/trpoke.narc",
    .evolutions = "/poketool/personal/evo.narc",
    .wild_pokemons = "/fielddata/encountdata/d_enc_data.narc",
    .scripts = "/fielddata/script/scr_seq_release.narc",
    .itemdata = "/itemtool/itemdata/item_data.narc",

    .pokedex = "application/zukanlist/zkn_data/zukan_data.narc",
    .pokedex_heights = 0,
    .pokedex_weights = 1,
    .species_to_national_dex = 11,

    .text = "/msgdata/msg.narc",
    .pokemon_names = 362,
    .trainer_names = 559,
    .move_names = 588,
    .move_descriptions = 587,
    .ability_names = 552,
    .item_names = 344,
    .item_descriptions = 343,
    .type_names = 565,
};

const pearl_info = Info{
    .game_title = "POKEMON P\x00\x00".*,
    .gamecode = "APAE".*,
    .version = .pearl,

    .starters = diamond_info.starters,
    .instant_text_patch = diamond_info.instant_text_patch,
    .hm_tm_prefix = diamond_info.hm_tm_prefix,

    .pokemons = "/poketool/personal_pearl/personal.narc",
    .level_up_moves = diamond_info.level_up_moves,
    .moves = diamond_info.moves,
    .trainers = diamond_info.trainers,
    .parties = diamond_info.parties,
    .evolutions = diamond_info.evolutions,
    .wild_pokemons = "/fielddata/encountdata/p_enc_data.narc",
    .scripts = diamond_info.scripts,
    .itemdata = diamond_info.itemdata,

    .pokedex = diamond_info.pokedex,
    .pokedex_heights = diamond_info.pokedex_heights,
    .pokedex_weights = diamond_info.pokedex_weights,
    .species_to_national_dex = diamond_info.species_to_national_dex,

    .text = diamond_info.text,
    .pokemon_names = diamond_info.pokemon_names,
    .trainer_names = diamond_info.trainer_names,
    .move_names = diamond_info.move_names,
    .move_descriptions = diamond_info.move_descriptions,
    .ability_names = diamond_info.ability_names,
    .item_names = diamond_info.item_names,
    .item_descriptions = diamond_info.item_descriptions,
    .type_names = diamond_info.type_names,
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
    .instant_text_patch = &[_]common.Patch{
        .{ .offset = 0x0023fc, .replacement = "\x00\x21" },
        .{ .offset = 0x01d97e, .replacement = "\x0c\x1c\x18\x48" },
        .{ .offset = 0x01d9ae, .replacement = "\x10\xbd\x2d\x3c\xe5\xe7" },
        .{ .offset = 0x01d9be, .replacement = "\xdf\xd0" },
        .{ .offset = 0x01d9ca, .replacement = "\xf1\xe7" },
    },
    .hm_tm_prefix = diamond_info.hm_tm_prefix,

    .pokemons = "/poketool/personal/pl_personal.narc",
    .level_up_moves = diamond_info.level_up_moves,
    .moves = "/poketool/waza/pl_waza_tbl.narc",
    .trainers = diamond_info.trainers,
    .parties = diamond_info.parties,
    .evolutions = diamond_info.evolutions,
    .wild_pokemons = "/fielddata/encountdata/pl_enc_data.narc",
    .scripts = "/fielddata/script/scr_seq.narc",
    .itemdata = "/itemtool/itemdata/pl_item_data.narc",

    .pokedex = "application/zukanlist/zkn_data/zukan_data_gira.narc",
    .pokedex_heights = 0,
    .pokedex_weights = 1,
    .species_to_national_dex = 11,

    .text = "/msgdata/pl_msg.narc",
    .pokemon_names = 412,
    .trainer_names = 618,
    .move_names = 647,
    .move_descriptions = 646,
    .ability_names = 610,
    .item_names = 392,
    .item_descriptions = 391,
    .type_names = 624,
};

pub const tm_count = 92;
pub const hm_count = 8;
pub const starters_len = 12;
