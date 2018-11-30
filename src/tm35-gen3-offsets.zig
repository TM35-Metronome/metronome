const clap = @import("zig-clap");
const common = @import("tm35-common");
const fun = @import("fun-with-zig");
const gba = @import("gba.zig");
const gen3 = @import("gen3-types.zig");
const offsets = @import("gen3-offsets.zig");
const std = @import("std");

const debug = std.debug;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu64 = fun.platform.lu64;

const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);
const Searcher = fun.searcher.Searcher;

const params = []Param{
    Param.flag(
        "display this help text and exit",
        Names.both("help"),
    ),
    Param.positional(""),
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-gen3-offsets [OPTION]... [FILE]...
        \\Finds the offsets to data in generation 3 Pokemon roms.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    const stdout_file = std.io.getStdOut() catch return 1;
    const stderr_file = std.io.getStdErr() catch return 1;
    var stdout_out_stream = stdout_file.outStream();
    var stderr_out_stream = stderr_file.outStream();
    const stdout = &stdout_out_stream.stream;
    const stderr = &stderr_out_stream.stream;

    var direct_allocator_state = std.heap.DirectAllocator.init();
    const direct_allocator = &direct_allocator_state.allocator;
    defer direct_allocator_state.deinit();

    // TODO: Other allocator?
    const allocator = direct_allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    const iter = &arg_iter.iter;
    defer arg_iter.deinit();
    _ = iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator.Error, iter) catch |err| {
        debug.warn("error: {}\n", err);
        usage(stderr) catch {};
        return 1;
    };
    defer args.deinit();

    var buf_out_stream = io.BufferedOutStream(os.File.OutStream.Error).init(stdout);
    main2(allocator, args, stdout) catch |err| {
        debug.warn("error: {}\n", err);
        return 1;
    };
    buf_out_stream.flush() catch |err| {
        debug.warn("error: {}\n", err);
        return 1;
    };

    return 0;
}

pub fn main2(allocator: *mem.Allocator, args: Clap, stream: *io.OutStream(os.File.OutStream.Error)) !void {
    if (args.flag("--help"))
        return try usage(stream);

    for (args.positionals()) |file_name, i| {
        var file = os.File.openRead(file_name) catch |err| {
            debug.warn("Couldn't open {}.\n", file_name);
            return err;
        };
        defer file.close();

        var file_stream = file.inStream();
        const data = try file_stream.stream.readAllAlloc(allocator, 1024 * 1024 * 32);
        defer allocator.free(data);

        const gamecode = getGamecode(data);
        const game_title = getGameTitle(data);
        const version = getVersion(gamecode) catch |err| {
            debug.warn("{} is not a gen3 Pokemon rom.\n", file_name);
            return err;
        };

        const info = try getInfo(data, version, gamecode, game_title);
        try stream.print(".game[{}].game_title={}\n", i, game_title);
        try stream.print(".game[{}].gamecode={}\n", i, gamecode);
        try stream.print(".game[{}].version={}\n", i, @tagName(version));
        try stream.print(".game[{}].trainers.start={}\n", i, info.trainers.start);
        try stream.print(".game[{}].trainers.len={}\n", i, info.trainers.len);
        try stream.print(".game[{}].moves.start={}\n", i, info.moves.start);
        try stream.print(".game[{}].moves.len={}\n", i, info.moves.len);
        try stream.print(".game[{}].machine_learnsets.start={}\n", i, info.machine_learnsets.start);
        try stream.print(".game[{}].machine_learnsets.len={}\n", i, info.machine_learnsets.len);
        try stream.print(".game[{}].base_stats.start={}\n", i, info.machine_learnsets.start);
        try stream.print(".game[{}].base_stats.len={}\n", i, info.machine_learnsets.len);
        try stream.print(".game[{}].evolutions.start={}\n", i, info.evolutions.start);
        try stream.print(".game[{}].evolutions.len={}\n", i, info.evolutions.len);
        try stream.print(".game[{}].level_up_learnset_pointers.start={}\n", i, info.level_up_learnset_pointers.start);
        try stream.print(".game[{}].level_up_learnset_pointers.len={}\n", i, info.level_up_learnset_pointers.len);
        try stream.print(".game[{}].hms.start={}\n", i, info.hms.start);
        try stream.print(".game[{}].hms.len={}\n", i, info.hms.len);
        try stream.print(".game[{}].tms.start={}\n", i, info.tms.start);
        try stream.print(".game[{}].tms.len={}\n", i, info.tms.len);
        try stream.print(".game[{}].items.start={}\n", i, info.items.start);
        try stream.print(".game[{}].items.len={}\n", i, info.items.len);
        try stream.print(".game[{}].wild_pokemon_headers.start={}\n", i, info.wild_pokemon_headers.start);
        try stream.print(".game[{}].wild_pokemon_headers.len={}\n", i, info.wild_pokemon_headers.len);
    }
}

fn getGamecode(data: []const u8) [4]u8 {
    const header = &@bytesToSlice(gba.Header, data[0..@sizeOf(gba.Header)])[0];
    return header.gamecode;
}

fn getGameTitle(data: []const u8) [12]u8 {
    const header = &@bytesToSlice(gba.Header, data[0..@sizeOf(gba.Header)])[0];
    return header.game_title;
}

fn getVersion(gamecode: []const u8) !common.Version {
    if (mem.startsWith(u8, gamecode, "BPE"))
        return common.Version.Emerald;
    if (mem.startsWith(u8, gamecode, "BPR"))
        return common.Version.FireRed;
    if (mem.startsWith(u8, gamecode, "BPG"))
        return common.Version.LeafGreen;
    if (mem.startsWith(u8, gamecode, "AXV"))
        return common.Version.Ruby;
    if (mem.startsWith(u8, gamecode, "AXP"))
        return common.Version.Sapphire;

    return error.UnknownPokemonVersion;
}

fn dumpSection(sec: var) void {
    debug.warn("{{\n");
    debug.warn("        .start = 0x{X8},\n", sec.start);
    debug.warn("        .len = {},\n", sec.len);
    debug.warn("    }},\n");
}

pub fn getInfo(data: []const u8, version: common.Version, gamecode: [4]u8, game_title: [12]u8) !offsets.Info {
    const trainer_searcher = Searcher(gen3.Trainer, [][]const []const u8{
        [][]const u8{ "party" },
        [][]const u8{ "name" },
    }).init(data);
    const trainers = switch (version) {
        common.Version.Emerald => trainer_searcher.findSlice3(
            em_first_trainers,
            em_last_trainers,
        ),
        common.Version.Ruby, common.Version.Sapphire => trainer_searcher.findSlice3(
            rs_first_trainers,
            rs_last_trainers,
        ),
        common.Version.FireRed, common.Version.LeafGreen => trainer_searcher.findSlice3(
            frls_first_trainers,
            frls_last_trainers,
        ),
        else => null,
    } orelse return error.UnableToFindTrainerOffset;

    const move_searcher = Searcher(gen3.Move, [][]const []const u8{}).init(data);
    const moves = move_searcher.findSlice3(
        first_moves,
        last_moves,
    ) orelse return error.UnableToFindMoveOffset;

    const machine_searcher = Searcher(lu64, [][]const []const u8{}).init(data);
    const machine_learnset = machine_searcher.findSlice3(
        first_machine_learnsets,
        last_machine_learnsets,
    ) orelse return error.UnableToFindTmHmLearnsetOffset;

    const base_stats_searcher = Searcher(gen3.BasePokemon, [][]const []const u8{
        [][]const u8{ "padding" },
        [][]const u8{ "egg_group1_pad" },
        [][]const u8{ "egg_group2_pad" },
    }).init(data);
    const base_stats = base_stats_searcher.findSlice3(
        first_base_stats,
        last_base_stats,
    ) orelse return error.UnableToFindBaseStatsOffset;

    const evolution_searcher = Searcher([5]common.Evolution, [][]const []const u8{
        [][]const u8{ "padding" },
    }).init(data);
    const evolution_table = evolution_searcher.findSlice3(
        first_evolutions,
        last_evolutions,
    ) orelse return error.UnableToFindEvolutionTableOffset;

    const level_up_learnset_pointers = blk: {
        const LevelUpRef = gen3.Ptr(gen3.LevelUpMove);
        const level_up_searcher = Searcher(u8, [][]const []const u8{}).init(data);

        var first_pointers: [first_levelup_learnsets.len]LevelUpRef = undefined;
        for (first_levelup_learnsets) |learnset, i| {
            const p = level_up_searcher.findSlice(learnset) orelse return error.UnableToFindLevelUpLearnsetOffset;
            const offset = @ptrToInt(p.ptr) - @ptrToInt(data.ptr);
            first_pointers[i] = try LevelUpRef.init(@intCast(u32, offset));
        }

        var last_pointers: [last_levelup_learnsets.len]LevelUpRef = undefined;
        for (last_levelup_learnsets) |learnset, i| {
            const p = level_up_searcher.findSlice(learnset) orelse return error.UnableToFindLevelUpLearnsetOffset;
            const offset = @ptrToInt(p.ptr) - @ptrToInt(data.ptr);
            last_pointers[i] = try LevelUpRef.init(@intCast(u32, offset));
        }

        const pointer_searcher = Searcher(LevelUpRef, [][]const []const u8{}).init(data);
        break :blk pointer_searcher.findSlice3(first_pointers, last_pointers) orelse return error.UnableToFindLevelUpLearnsetOffset;
    };

    const hm_tm_searcher = Searcher(lu16, [][]const []const u8{}).init(data);
    const hms_slice = hm_tm_searcher.findSlice(hms) orelse return error.UnableToFindHmOffset;

    // TODO: Pokemon Emerald have 2 tm tables. I'll figure out some hack for that
    //       if it turns out that both tables are actually used. For now, I'll
    //       assume that the first table is the only one used.
    const tms_slice = hm_tm_searcher.findSlice(tms) orelse return error.UnableToFindTmOffset;

    const items_searcher = Searcher(gen3.Item, [][]const []const u8{
        [][]const u8{ "name" },
        [][]const u8{ "description" },
        [][]const u8{ "field_use_func" },
        [][]const u8{ "battle_use_func" },
    }).init(data);
    const items = switch (version) {
        common.Version.Emerald => items_searcher.findSlice3(
            em_first_items,
            em_last_items,
        ),
        common.Version.Ruby, common.Version.Sapphire => items_searcher.findSlice3(
            rs_first_items,
            rs_last_items,
        ),
        common.Version.FireRed, common.Version.LeafGreen => items_searcher.findSlice3(
            frlg_first_items,
            frlg_last_items,
        ),
        else => null,
    } orelse return error.UnableToFindItemsOffset;

    const wild_pokemon_headers_searcher = Searcher(gen3.WildPokemonHeader, [][]const []const u8{
        [][]const u8{ "pad" },
        [][]const u8{ "land" },
        [][]const u8{ "surf" },
        [][]const u8{ "rock_smash" },
        [][]const u8{ "fishing"},
    }).init(data);
    const maybe_wild_pokemon_headers = switch (version) {
        common.Version.Emerald => wild_pokemon_headers_searcher.findSlice3(
            em_first_wild_mon_headers,
            em_last_wild_mon_headers,
        ),
        common.Version.Ruby, common.Version.Sapphire => wild_pokemon_headers_searcher.findSlice3(
            rs_first_wild_mon_headers,
            rs_last_wild_mon_headers,
        ),
        common.Version.FireRed, common.Version.LeafGreen => wild_pokemon_headers_searcher.findSlice3(
            frlg_first_wild_mon_headers,
            frlg_last_wild_mon_headers,
        ),
        else => null,
    };
    const wild_pokemon_headers = maybe_wild_pokemon_headers orelse return error.UnableToFindWildPokemonHeaders;

    return offsets.Info{
        .game_title = undefined,
        .gamecode = undefined,
        .version = version,
        .trainers = offsets.TrainerSection.init(data, trainers),
        .moves = offsets.MoveSection.init(data, moves),
        .machine_learnsets = offsets.MachineLearnsetSection.init(data, machine_learnset),
        .base_stats = offsets.BaseStatsSection.init(data, base_stats),
        .evolutions = offsets.EvolutionSection.init(data, evolution_table),
        .level_up_learnset_pointers = offsets.LevelUpLearnsetPointerSection.init(data, level_up_learnset_pointers),
        .hms = offsets.HmSection.init(data, hms_slice),
        .tms = offsets.TmSection.init(data, tms_slice),
        .items = offsets.ItemSection.init(data, items),
        .wild_pokemon_headers = offsets.WildPokemonHeaderSection.init(data, wild_pokemon_headers),
    };
}

pub const em_first_trainers = []gen3.Trainer{
    gen3.Trainer{
        .party_type = gen3.PartyType.None,
        .class = 0,
        .encounter_music = 0,
        .trainer_picture = 0,
        .name = undefined,
        .items = []lu16{ lu16.init(0), lu16.init(0), lu16.init(0), lu16.init(0) },
        .is_double = lu32.init(0),
        .ai = lu32.init(0),
        .party = undefined,
    },
    gen3.Trainer{
        .party_type = gen3.PartyType.None,
        .class = 0x02,
        .encounter_music = 0x0b,
        .trainer_picture = 0,
        .name = undefined,
        .items = []lu16{ lu16.init(0), lu16.init(0), lu16.init(0), lu16.init(0) },
        .is_double = lu32.init(0),
        .ai = lu32.init(7),
        .party = undefined,
    },
};

pub const em_last_trainers = []gen3.Trainer{gen3.Trainer{
    .party_type = gen3.PartyType.None,
    .class = 0x41,
    .encounter_music = 0x80,
    .trainer_picture = 0x5c,
    .name = undefined,
    .items = []lu16{ lu16.init(0), lu16.init(0), lu16.init(0), lu16.init(0) },
    .is_double = lu32.init(0),
    .ai = lu32.init(0),
    .party = undefined,
}};

pub const rs_first_trainers = []gen3.Trainer{
    gen3.Trainer{
        .party_type = gen3.PartyType.None,
        .class = 0,
        .encounter_music = 0,
        .trainer_picture = 0,
        .name = undefined,
        .items = []lu16{ lu16.init(0), lu16.init(0), lu16.init(0), lu16.init(0) },
        .is_double = lu32.init(0),
        .ai = lu32.init(0),
        .party = undefined,
    },
    gen3.Trainer{
        .party_type = gen3.PartyType.None,
        .class = 0x02,
        .encounter_music = 0x06,
        .trainer_picture = 0x46,
        .name = undefined,
        .items = []lu16{ lu16.init(0x16), lu16.init(0x16), lu16.init(0), lu16.init(0) },
        .is_double = lu32.init(0),
        .ai = lu32.init(7),
        .party = undefined,
    },
};

pub const rs_last_trainers = []gen3.Trainer{gen3.Trainer{
    .party_type = gen3.PartyType.None,
    .class = 0x21,
    .encounter_music = 0x0B,
    .trainer_picture = 0x06,
    .name = undefined,
    .items = []lu16{ lu16.init(0), lu16.init(0), lu16.init(0), lu16.init(0) },
    .is_double = lu32.init(0),
    .ai = lu32.init(1),
    .party = undefined,
}};

pub const frls_first_trainers = []gen3.Trainer{
    gen3.Trainer{
        .party_type = gen3.PartyType.None,
        .class = 0,
        .encounter_music = 0,
        .trainer_picture = 0,
        .name = undefined,
        .items = []lu16{
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
        },
        .is_double = lu32.init(0),
        .ai = lu32.init(0),
        .party = undefined,
    },
    gen3.Trainer{
        .party_type = gen3.PartyType.None,
        .class = 2,
        .encounter_music = 6,
        .trainer_picture = 0,
        .name = undefined,
        .items = []lu16{
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
        },
        .is_double = lu32.init(0),
        .ai = lu32.init(1),
        .party = undefined,
    },
};

pub const frls_last_trainers = []gen3.Trainer{
    gen3.Trainer{
        .party_type = gen3.PartyType.Both,
        .class = 90,
        .encounter_music = 0,
        .trainer_picture = 125,
        .name = undefined,
        .items = []lu16{
            lu16.init(19),
            lu16.init(19),
            lu16.init(19),
            lu16.init(19),
        },
        .is_double = lu32.init(0),
        .ai = lu32.init(7),
        .party = undefined,
    },
    gen3.Trainer{
        .party_type = gen3.PartyType.None,
        .class = 0x47,
        .encounter_music = 0,
        .trainer_picture = 0x60,
        .name = undefined,
        .items = []lu16{
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
        },
        .is_double = lu32.init(0),
        .ai = lu32.init(1),
        .party = undefined,
    },
};

pub const first_moves = []gen3.Move{
    // Dummy
    gen3.Move{
        .effect = 0,
        .power = 0,
        .@"type" = gen3.Type.Normal,
        .accuracy = 0,
        .pp = 0,
        .side_effect_chance = 0,
        .target = 0,
        .priority = 0,
        .flags = lu32.init(0),
    },
    // Pound
    gen3.Move{
        .effect = 0,
        .power = 40,
        .@"type" = gen3.Type.Normal,
        .accuracy = 100,
        .pp = 35,
        .side_effect_chance = 0,
        .target = 0,
        .priority = 0,
        .flags = lu32.init(0x33),
    },
};

pub const last_moves = []gen3.Move{
// Psycho Boost
gen3.Move{
    .effect = 204,
    .power = 140,
    .@"type" = gen3.Type.Psychic,
    .accuracy = 90,
    .pp = 5,
    .side_effect_chance = 100,
    .target = 0,
    .priority = 0,
    .flags = lu32.init(0x32),
}};

pub const first_machine_learnsets = []lu64{
    lu64.init(0x0000000000000000), // Dummy Pokemon
    lu64.init(0x00e41e0884350720), // Bulbasaur
    lu64.init(0x00e41e0884350720), // Ivysaur
    lu64.init(0x00e41e0886354730), // Venusaur
};

pub const last_machine_learnsets = []lu64{
    lu64.init(0x035c5e93b7bbd63e), // Latios
    lu64.init(0x00408e93b59bc62c), // Jirachi
    lu64.init(0x00e58fc3f5bbde2d), // Deoxys
    lu64.init(0x00419f03b41b8e28), // Chimecho
};

pub const first_base_stats = []gen3.BasePokemon{
    // Dummy
    gen3.BasePokemon{
        .stats = common.Stats{
            .hp = 0,
            .attack = 0,
            .defense = 0,
            .speed = 0,
            .sp_attack = 0,
            .sp_defense = 0,
        },

        .types = []gen3.Type{ gen3.Type.Normal, gen3.Type.Normal },

        .catch_rate = 0,
        .base_exp_yield = 0,

        .ev_yield = common.EvYield{
            .hp = 0,
            .attack = 0,
            .defense = 0,
            .speed = 0,
            .sp_attack = 0,
            .sp_defense = 0,
            .padding = 0,
        },

        .items = []lu16{ lu16.init(0), lu16.init(0) },

        .gender_ratio = 0,
        .egg_cycles = 0,
        .base_friendship = 0,

        .growth_rate = common.GrowthRate.MediumFast,

        .egg_group1 = common.EggGroup.Invalid,
        .egg_group1_pad = undefined,
        .egg_group2 = common.EggGroup.Invalid,
        .egg_group2_pad = undefined,

        .abilities = []u8{ 0, 0 },
        .safari_zone_rate = 0,

        .color = common.Color.Red,
        .flip = false,

        .padding = undefined,
    },
    // Bulbasaur
    gen3.BasePokemon{
        .stats = common.Stats{
            .hp = 45,
            .attack = 49,
            .defense = 49,
            .speed = 45,
            .sp_attack = 65,
            .sp_defense = 65,
        },

        .types = []gen3.Type{ gen3.Type.Grass, gen3.Type.Poison },

        .catch_rate = 45,
        .base_exp_yield = 64,

        .ev_yield = common.EvYield{
            .hp = 0,
            .attack = 0,
            .defense = 0,
            .speed = 0,
            .sp_attack = 1,
            .sp_defense = 0,
            .padding = 0,
        },

        .items = []lu16{ lu16.init(0), lu16.init(0) },

        .gender_ratio = comptime percentFemale(12.5),
        .egg_cycles = 20,
        .base_friendship = 70,

        .growth_rate = common.GrowthRate.MediumSlow,

        .egg_group1 = common.EggGroup.Monster,
        .egg_group1_pad = undefined,
        .egg_group2 = common.EggGroup.Grass,
        .egg_group2_pad = undefined,

        .abilities = []u8{ 65, 0 },
        .safari_zone_rate = 0,

        .color = common.Color.Green,
        .flip = false,

        .padding = undefined,
    },
};

pub const last_base_stats = []gen3.BasePokemon{
// Chimecho
gen3.BasePokemon{
    .stats = common.Stats{
        .hp = 65,
        .attack = 50,
        .defense = 70,
        .speed = 65,
        .sp_attack = 95,
        .sp_defense = 80,
    },

    .types = []gen3.Type{ gen3.Type.Psychic, gen3.Type.Psychic },

    .catch_rate = 45,
    .base_exp_yield = 147,

    .ev_yield = common.EvYield{
        .hp = 0,
        .attack = 0,
        .defense = 0,
        .speed = 0,
        .sp_attack = 1,
        .sp_defense = 1,
        .padding = 0,
    },

    .items = []lu16{ lu16.init(0), lu16.init(0) },

    .gender_ratio = comptime percentFemale(50),
    .egg_cycles = 25,
    .base_friendship = 70,

    .growth_rate = common.GrowthRate.Fast,

    .egg_group1 = common.EggGroup.Amorphous,
    .egg_group1_pad = undefined,
    .egg_group2 = common.EggGroup.Amorphous,
    .egg_group2_pad = undefined,

    .abilities = []u8{ 26, 0 },
    .safari_zone_rate = 0,

    .color = common.Color.Blue,
    .flip = false,

    .padding = undefined,
}};

fn percentFemale(percent: f64) u8 {
    return @floatToInt(u8, math.min(f64(254), (percent * 255) / 100));
}

const unused_evo = common.Evolution{
    .method = common.Evolution.Method.Unused,
    .param = lu16.init(0),
    .target = lu16.init(0),
    .padding = undefined,
};
const unused_evo5 = []common.Evolution{unused_evo} ** 5;

pub const first_evolutions = [][5]common.Evolution{
    // Dummy
    unused_evo5,

    // Bulbasaur
    []common.Evolution{
        common.Evolution{
            .method = common.Evolution.Method.LevelUp,
            .param = lu16.init(16),
            .target = lu16.init(2),
            .padding = undefined,
        },
        unused_evo,
        unused_evo,
        unused_evo,
        unused_evo,
    },

    // Ivysaur
    []common.Evolution{
        common.Evolution{
            .method = common.Evolution.Method.LevelUp,
            .param = lu16.init(32),
            .target = lu16.init(3),
            .padding = undefined,
        },
        unused_evo,
        unused_evo,
        unused_evo,
        unused_evo,
    },
};

pub const last_evolutions = [][5]common.Evolution{
    // Beldum
    []common.Evolution{
        common.Evolution{
            .method = common.Evolution.Method.LevelUp,
            .param = lu16.init(20),
            .target = lu16.init(399),
            .padding = undefined,
        },
        unused_evo,
        unused_evo,
        unused_evo,
        unused_evo,
    },

    // Metang
    []common.Evolution{
        common.Evolution{
            .method = common.Evolution.Method.LevelUp,
            .param = lu16.init(45),
            .target = lu16.init(400),
            .padding = undefined,
        },
        unused_evo,
        unused_evo,
        unused_evo,
        unused_evo,
    },

    // Metagross, Regirock, Regice, Registeel, Kyogre, Groudon, Rayquaza
    // Latias, Latios, Jirachi, Deoxys, Chimecho
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
};

pub const first_levelup_learnsets = [][]const u8{
    // Dummy mon have same moves as Bulbasaur
    []u8{
        0x21, 0x02, 0x2D, 0x08, 0x49, 0x0E, 0x16, 0x14, 0x4D, 0x1E, 0x4F, 0x1E,
        0x4B, 0x28, 0xE6, 0x32, 0x4A, 0x40, 0xEB, 0x4E, 0x4C, 0x5C, 0xFF, 0xFF,
    },
    // Bulbasaur
    []u8{
        0x21, 0x02, 0x2D, 0x08, 0x49, 0x0E, 0x16, 0x14, 0x4D, 0x1E, 0x4F, 0x1E,
        0x4B, 0x28, 0xE6, 0x32, 0x4A, 0x40, 0xEB, 0x4E, 0x4C, 0x5C, 0xFF, 0xFF,
    },
    // Ivysaur
    []u8{
        0x21, 0x02, 0x2D, 0x02, 0x49, 0x02, 0x2D, 0x08, 0x49, 0x0E, 0x16, 0x14,
        0x4D, 0x1E, 0x4F, 0x1E, 0x4B, 0x2C, 0xE6, 0x3A, 0x4A, 0x4C, 0xEB, 0x5E,
        0x4C, 0x70, 0xFF, 0xFF,
    },
    // Venusaur
    []u8{
        0x21, 0x02, 0x2D, 0x02, 0x49, 0x02, 0x16, 0x02, 0x2D, 0x08, 0x49, 0x0E,
        0x16, 0x14, 0x4D, 0x1E, 0x4F, 0x1E, 0x4B, 0x2C, 0xE6, 0x3A, 0x4A, 0x52,
        0xEB, 0x6A, 0x4C, 0x82, 0xFF, 0xFF,
    },
};

pub const last_levelup_learnsets = [][]const u8{
    // TODO: Figure out if only having Chimechos level up learnset is enough.
    // Chimecho
    []u8{
        0x23, 0x02, 0x2D, 0x0C, 0x36, 0x13, 0x5D, 0x1C, 0x24, 0x22, 0xFD, 0x2C, 0x19,
        0x33, 0x95, 0x3C, 0x26, 0x42, 0xD7, 0x4C, 0xDB, 0x52, 0x5E, 0x5C, 0xFF, 0xFF,
    },
};

pub const hms = []lu16{
    lu16.init(0x000f),
    lu16.init(0x0013),
    lu16.init(0x0039),
    lu16.init(0x0046),
    lu16.init(0x0094),
    lu16.init(0x00f9),
    lu16.init(0x007f),
    lu16.init(0x0123),
};

pub const tms = []lu16{
    lu16.init(0x0108),
    lu16.init(0x0151),
    lu16.init(0x0160),
    lu16.init(0x015b),
    lu16.init(0x002e),
    lu16.init(0x005c),
    lu16.init(0x0102),
    lu16.init(0x0153),
    lu16.init(0x014b),
    lu16.init(0x00ed),
    lu16.init(0x00f1),
    lu16.init(0x010d),
    lu16.init(0x003a),
    lu16.init(0x003b),
    lu16.init(0x003f),
    lu16.init(0x0071),
    lu16.init(0x00b6),
    lu16.init(0x00f0),
    lu16.init(0x00ca),
    lu16.init(0x00db),
    lu16.init(0x00da),
    lu16.init(0x004c),
    lu16.init(0x00e7),
    lu16.init(0x0055),
    lu16.init(0x0057),
    lu16.init(0x0059),
    lu16.init(0x00d8),
    lu16.init(0x005b),
    lu16.init(0x005e),
    lu16.init(0x00f7),
    lu16.init(0x0118),
    lu16.init(0x0068),
    lu16.init(0x0073),
    lu16.init(0x015f),
    lu16.init(0x0035),
    lu16.init(0x00bc),
    lu16.init(0x00c9),
    lu16.init(0x007e),
    lu16.init(0x013d),
    lu16.init(0x014c),
    lu16.init(0x0103),
    lu16.init(0x0107),
    lu16.init(0x0122),
    lu16.init(0x009c),
    lu16.init(0x00d5),
    lu16.init(0x00a8),
    lu16.init(0x00d3),
    lu16.init(0x011d),
    lu16.init(0x0121),
    lu16.init(0x013b),
};

pub const em_first_items = []gen3.Item{
    // ????????
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocked = 1,
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    // MASTER BALL
    gen3.Item{
        .name = undefined,
        .id = lu16.init(1),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocked = 2,
        .@"type" = 0,
        .field_use_func = undefined,
        .battle_usage = lu32.init(2),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

pub const em_last_items = []gen3.Item{
    // MAGMA EMBLEM
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0x177),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 1,
        .unknown = 1,
        .pocked = 5,
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    // OLD SEA MAP
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0x178),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 1,
        .unknown = 1,
        .pocked = 5,
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

pub const rs_first_items = []gen3.Item{
    // ????????
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocked = 1,
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    // MASTER BALL
    gen3.Item{
        .name = undefined,
        .id = lu16.init(1),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocked = 2,
        .@"type" = 0,
        .field_use_func = undefined,
        .battle_usage = lu32.init(2),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

pub const rs_last_items = []gen3.Item{
    // HM08
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0x15A),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 1,
        .unknown = 0,
        .pocked = 3,
        .@"type" = 1,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    // ????????
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocked = 1,
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    // ????????
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocked = 1,
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

pub const frlg_first_items = []gen3.Item{
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocked = 1,
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    gen3.Item{
        .name = undefined,
        .id = lu16.init(1),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocked = 3,
        .@"type" = 0,
        .field_use_func = undefined,
        .battle_usage = lu32.init(2),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

pub const frlg_last_items = []gen3.Item{
    gen3.Item{
        .name = undefined,
        .id = lu16.init(372),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 1,
        .unknown = 1,
        .pocked = 2,
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    gen3.Item{
        .name = undefined,
        .id = lu16.init(373),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 1,
        .unknown = 1,
        .pocked = 2,
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

fn wildHeader(map_group: u8, map_num: u8) gen3.WildPokemonHeader {
    return gen3.WildPokemonHeader{
        .map_group = map_group,
        .map_num = map_num,
        .pad = undefined,
        .land = undefined,
        .surf = undefined,
        .rock_smash = undefined,
        .fishing = undefined,
    };
}

pub const em_first_wild_mon_headers = []gen3.WildPokemonHeader{
    wildHeader(0, 16),
    wildHeader(0, 17),
    wildHeader(0, 18),
};

pub const em_last_wild_mon_headers = []gen3.WildPokemonHeader{
    wildHeader(24, 106),
    wildHeader(24, 106),
    wildHeader(24, 107),
};

pub const rs_first_wild_mon_headers = []gen3.WildPokemonHeader{
    wildHeader(0, 0),
    wildHeader(0, 1),
    wildHeader(0, 5),
    wildHeader(0, 6),
};

pub const rs_last_wild_mon_headers = []gen3.WildPokemonHeader{
    wildHeader(0, 15),
    wildHeader(0, 50),
    wildHeader(0, 51),
};

pub const frlg_first_wild_mon_headers = []gen3.WildPokemonHeader{
    wildHeader(2, 27),
    wildHeader(2, 28),
    wildHeader(2, 29),
};

pub const frlg_last_wild_mon_headers = []gen3.WildPokemonHeader{
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
};
