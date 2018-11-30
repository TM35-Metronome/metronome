const clap = @import("zig-clap");
const common = @import("tm35-common");
const format = @import("tm35-format");
const fun = @import("fun-with-zig");
const gba = @import("gba.zig");
const gen3 = @import("gen3-types.zig");
const offsets = @import("gen3-offsets.zig");
const std = @import("std");

const bits = fun.bits;
const debug = std.debug;
const fmt = std.fmt;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const path = os.path;

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu64 = fun.platform.lu64;

const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = []Param{
    Param.flag(
        "display this help text and exit",
        Names.both("help"),
    ),
    Param.option(
        "override destination path",
        Names.both("output"),
    ),
    Param.positional(""),
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-gen3-apply [OPTION]... FILE
        \\Reads the tm35 format from stdin and applies it to a generation 3 Pokemon rom.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    const stdin_file = std.io.getStdIn() catch return 1;
    const stderr_file = std.io.getStdErr() catch return 1;
    const stdout_file = std.io.getStdOut() catch return 1;
    var stdin_in_stream = stdin_file.inStream();
    var stderr_out_stream = stderr_file.outStream();
    var stdout_out_stream = stdout_file.outStream();
    var buf_in_stream = io.BufferedInStream(os.File.InStream.Error).init(&stdin_in_stream.stream);

    const stderr = &stderr_out_stream.stream;
    const stdout = &stdout_out_stream.stream;
    const stdin = &buf_in_stream.stream;

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

    main2(allocator, args, stdin, stdout, stderr) catch |err| return 1;

    return 0;
}

pub fn main2(allocator: *mem.Allocator, args: Clap, stdin: var, stdout: var, stderr: var) !void {
    if (args.flag("--help"))
        return try usage(stdout);

    const file_name = if (args.positionals().len > 0) args.positionals()[0] else {
        debug.warn("No file provided.");
        return try usage(stderr);
    };

    var free_out = false;
    const out = args.option("--output") orelse blk: {
        free_out = true;
        break :blk try fmt.allocPrint(allocator, "{}.modified", path.basename(file_name));
    };
    defer if (free_out) allocator.free(out);

    var game = blk: {
        var file = os.File.openRead(file_name) catch |err| {
            debug.warn("Couldn't open {}.\n", file_name);
            return err;
        };
        defer file.close();

        break :blk try gen3.Game.fromFile(file, allocator);
    };
    defer game.deinit();

    var line: usize = 1;
    var line_buf = try std.Buffer.initSize(allocator, 0);
    defer line_buf.deinit();
    while (stdin.readUntilDelimiterBuffer(&line_buf, '\n', 10000)) : (line += 1) {
        apply(game, line, mem.trimRight(u8, line_buf.toSlice(), "\r\n")) catch {};
        line_buf.shrink(0);
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }

    var out_file = os.File.openWrite(out) catch |err| {
        debug.warn("Couldn't open {}.\n", out);
        return err;
    };
    defer out_file.close();
    var out_stream = out_file.outStream();
    try game.writeToStream(&out_stream.stream);
}

fn apply(game: gen3.Game, line: usize, str: []const u8) !void {
    @setEvalBranchQuota(100000);
    const m = format.Matcher([][]const u8{
        ".version",
        ".game_title",
        ".gamecode",

        ".trainers[*].class",
        ".trainers[*].encounter_music",
        ".trainers[*].trainer_picture",
        ".trainers[*].items[*]",
        ".trainers[*].is_double",
        ".trainers[*].ai",
        ".trainers[*].party[*].iv",
        ".trainers[*].party[*].level",
        ".trainers[*].party[*].species",
        ".trainers[*].party[*].item",
        ".trainers[*].party[*].moves[*]",

        ".moves[*].effect",
        ".moves[*].power",
        ".moves[*].type",
        ".moves[*].accuracy",
        ".moves[*].pp",
        ".moves[*].side_effect_chance",
        ".moves[*].target",
        ".moves[*].priority",
        ".moves[*].flags",

        ".pokemons[*].stats.hp",
        ".pokemons[*].stats.attack",
        ".pokemons[*].stats.defense",
        ".pokemons[*].stats.speed",
        ".pokemons[*].stats.sp_attack",
        ".pokemons[*].stats.sp_defense",
        ".pokemons[*].types[*]",
        ".pokemons[*].catch_rate",
        ".pokemons[*].base_exp_yield",
        ".pokemons[*].ev_yield.hp",
        ".pokemons[*].ev_yield.attack",
        ".pokemons[*].ev_yield.defense",
        ".pokemons[*].ev_yield.speed",
        ".pokemons[*].ev_yield.sp_attack",
        ".pokemons[*].ev_yield.sp_defense",
        ".pokemons[*].items[*]",
        ".pokemons[*].gender_ratio",
        ".pokemons[*].egg_cycles",
        ".pokemons[*].base_friendship",
        ".pokemons[*].growth_rate",
        ".pokemons[*].egg_groups[*]",
        ".pokemons[*].abilities[*]",
        ".pokemons[*].safari_zone_rate",
        ".pokemons[*].color",
        ".pokemons[*].flip",
        ".pokemons[*].tms[*]",
        ".pokemons[*].hms[*]",
        ".pokemons[*].evos[*].method",
        ".pokemons[*].evos[*].param",
        ".pokemons[*].evos[*].target",
        ".pokemons[*].moves[*].id",
        ".pokemons[*].moves[*].level",

        ".tms[*]",
        ".hms[*]",

        ".items[*].id",
        ".items[*].price",
        ".items[*].hold_effect",
        ".items[*].hold_effect_param",
        ".items[*].importance",
        ".items[*].pocked",
        ".items[*].type",
        ".items[*].battle_usage",
        ".items[*].battle_usage",
        ".items[*].secondary_id",

        ".zones[*].wild.land.encounter_rate",
        ".zones[*].wild.land.pokemons[*].min_level",
        ".zones[*].wild.land.pokemons[*].max_level",
        ".zones[*].wild.land.pokemons[*].species",
        ".zones[*].wild.surf.encounter_rate",
        ".zones[*].wild.surf.pokemons[*].min_level",
        ".zones[*].wild.surf.pokemons[*].max_level",
        ".zones[*].wild.surf.pokemons[*].species",
        ".zones[*].wild.rock_smash.encounter_rate",
        ".zones[*].wild.rock_smash.pokemons[*].min_level",
        ".zones[*].wild.rock_smash.pokemons[*].max_level",
        ".zones[*].wild.rock_smash.pokemons[*].species",
        ".zones[*].wild.fishing.encounter_rate",
        ".zones[*].wild.fishing.pokemons[*].min_level",
        ".zones[*].wild.fishing.pokemons[*].max_level",
        ".zones[*].wild.fishing.pokemons[*].species",
    });

    if (m.match(str)) |match| switch (match.case) {
        m.case(".version") => {
            const version = try parseEnum(line, common.Version, match.value);
            if (version != game.version)
                warning(line, 1, "Version '{}' differs from '{}'\n", @tagName(version), @tagName(game.version));
        },
        m.case(".game_title") => {
            const value = match.value;
            const column = value.index(str) + 1;

            if (!mem.eql(u8, value.str, game.header.game_title))
                warning(line, column, "Game title '{}' differs from '{}'\n", value.str, game.header.game_title);
        },
        m.case(".gamecode") => {
            const value = match.value;
            const column = value.index(str) + 1;

            if (!mem.eql(u8, value.str, game.header.gamecode))
                warning(line, column, "Gamecode '{}' differs from '{}'\n", value.str, game.header.gamecode);
        },

        m.case(".trainers[*].class"),
        m.case(".trainers[*].encounter_music"),
        m.case(".trainers[*].trainer_picture"),
        m.case(".trainers[*].items[*]"),
        m.case(".trainers[*].is_double"),
        m.case(".trainers[*].ai"),
        m.case(".trainers[*].party[*].iv"),
        m.case(".trainers[*].party[*].level"),
        m.case(".trainers[*].party[*].species"),
        m.case(".trainers[*].party[*].item"),
        m.case(".trainers[*].party[*].moves[*]"),
        => {
            const trainer_index = try parseIntBound(line, usize, game.trainers.len, match.anys[0]);
            const trainer = &game.trainers[trainer_index];

            switch (match.case) {
                m.case(".trainers[*].class") => trainer.class = try parseInt(line, u8, match.value),
                m.case(".trainers[*].encounter_music") => trainer.encounter_music = try parseInt(line, u8, match.value),
                m.case(".trainers[*].trainer_picture") => trainer.trainer_picture = try parseInt(line, u8, match.value),
                m.case(".trainers[*].is_double") => trainer.is_double = lu32.init(try parseInt(line, u32, match.value)),
                m.case(".trainers[*].ai") => trainer.ai = lu32.init(try parseInt(line, u32, match.value)),
                m.case(".trainers[*].items[*]") => {
                    const index = try parseIntBound(line, usize, trainer.items.len, match.anys[1]);
                    const value = try parseIntBound(line, u16, game.items.len, match.value);
                    trainer.items[index] = lu16.init(value);
                },
                m.case(".trainers[*].party[*].iv"),
                m.case(".trainers[*].party[*].level"),
                m.case(".trainers[*].party[*].species"),
                m.case(".trainers[*].party[*].item"),
                m.case(".trainers[*].party[*].moves[*]"),
                => {
                    const party_index = try parseIntBound(line, usize, trainer.partyLen(), match.anys[1]);
                    const base = try trainer.partyAt(party_index, game.data);
                    switch (match.case) {
                        m.case(".trainers[*].party[*].iv") => base.iv = lu16.init(try parseInt(line, u16, match.value)),
                        m.case(".trainers[*].party[*].level") => base.level = lu16.init(try parseInt(line, u16, match.value)),
                        m.case(".trainers[*].party[*].species") => base.species = lu16.init(try parseIntBound(line, u16, game.base_stats.len, match.value)),
                        m.case(".trainers[*].party[*].item") => success: {
                            inline for ([][]const u8{ "Item", "Both" }) |kind| {
                                if (trainer.party_type == @field(gen3.PartyType, kind)) {
                                    const member = base.toParent(@field(gen3, "PartyMember" ++ kind));
                                    const value = try parseIntBound(line, u16, game.items.len, match.value);
                                    member.item = lu16.init(value);
                                    break :success;
                                }
                            }

                            // TODO: Error message and stuff
                        },
                        m.case(".trainers[*].party[*].moves[*]") => success: {
                            inline for ([][]const u8{ "Moves", "Both" }) |kind| {
                                if (trainer.party_type == @field(gen3.PartyType, kind)) {
                                    const member = base.toParent(@field(gen3, "PartyMember" ++ kind));
                                    const index = try parseIntBound(line, usize, member.moves.len, match.anys[2]);
                                    const value = try parseIntBound(line, u16, game.moves.len, match.value);
                                    member.moves[index] = lu16.init(value);
                                    break :success;
                                }
                            }

                            // TODO: Error message and stuff
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },

        m.case(".moves[*].effect"),
        m.case(".moves[*].power"),
        m.case(".moves[*].type"),
        m.case(".moves[*].accuracy"),
        m.case(".moves[*].pp"),
        m.case(".moves[*].side_effect_chance"),
        m.case(".moves[*].target"),
        m.case(".moves[*].priority"),
        m.case(".moves[*].flags"),
        => {
            const move_index = try parseIntBound(line, usize, game.moves.len, match.anys[0]);
            const move = &game.moves[move_index];
            switch (match.case) {
                m.case(".moves[*].effect") => move.effect = try parseInt(line, u8, match.value),
                m.case(".moves[*].power") => move.power = try parseInt(line, u8, match.value),
                m.case(".moves[*].type") => move.@"type" = try parseEnum(line, gen3.Type, match.value),
                m.case(".moves[*].accuracy") => move.accuracy = try parseInt(line, u8, match.value),
                m.case(".moves[*].pp") => move.pp = try parseInt(line, u8, match.value),
                m.case(".moves[*].side_effect_chance") => move.side_effect_chance = try parseInt(line, u8, match.value),
                m.case(".moves[*].target") => move.target = try parseInt(line, u8, match.value),
                m.case(".moves[*].priority") => move.priority = try parseInt(line, u8, match.value),
                m.case(".moves[*].flags") => move.flags = lu32.init(try parseInt(line, u32, match.value)),
                else => unreachable,
            }
        },

        m.case(".pokemons[*].stats.hp"),
        m.case(".pokemons[*].stats.attack"),
        m.case(".pokemons[*].stats.defense"),
        m.case(".pokemons[*].stats.speed"),
        m.case(".pokemons[*].stats.sp_attack"),
        m.case(".pokemons[*].stats.sp_defense"),
        m.case(".pokemons[*].types[*]"),
        m.case(".pokemons[*].catch_rate"),
        m.case(".pokemons[*].base_exp_yield"),
        m.case(".pokemons[*].ev_yield.hp"),
        m.case(".pokemons[*].ev_yield.attack"),
        m.case(".pokemons[*].ev_yield.defense"),
        m.case(".pokemons[*].ev_yield.speed"),
        m.case(".pokemons[*].ev_yield.sp_attack"),
        m.case(".pokemons[*].ev_yield.sp_defense"),
        m.case(".pokemons[*].items[*]"),
        m.case(".pokemons[*].gender_ratio"),
        m.case(".pokemons[*].egg_cycles"),
        m.case(".pokemons[*].base_friendship"),
        m.case(".pokemons[*].growth_rate"),
        m.case(".pokemons[*].egg_groups[*]"),
        m.case(".pokemons[*].abilities[*]"),
        m.case(".pokemons[*].safari_zone_rate"),
        m.case(".pokemons[*].color"),
        m.case(".pokemons[*].flip"),
        => {
            const pokemon_index = try parseIntBound(line, usize, game.base_stats.len, match.anys[0]);
            const pokemon = &game.base_stats[pokemon_index];
            switch (match.case) {
                m.case(".pokemons[*].stats.hp") => pokemon.stats.hp = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].stats.attack") => pokemon.stats.attack = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].stats.defense") => pokemon.stats.defense = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].stats.speed") => pokemon.stats.speed = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].stats.sp_attack") => pokemon.stats.sp_attack = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].stats.sp_defense") => pokemon.stats.sp_defense = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].types[*]") => {
                    const index = try parseIntBound(line, usize, pokemon.types.len, match.anys[1]);
                    pokemon.types[index] = try parseEnum(line, gen3.Type, match.value);
                },
                m.case(".pokemons[*].catch_rate") => pokemon.catch_rate = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].base_exp_yield") => pokemon.base_exp_yield = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].ev_yield.hp") => pokemon.ev_yield.hp = try parseInt(line, u2, match.value),
                m.case(".pokemons[*].ev_yield.attack") => pokemon.ev_yield.attack = try parseInt(line, u2, match.value),
                m.case(".pokemons[*].ev_yield.defense") => pokemon.ev_yield.defense = try parseInt(line, u2, match.value),
                m.case(".pokemons[*].ev_yield.speed") => pokemon.ev_yield.speed = try parseInt(line, u2, match.value),
                m.case(".pokemons[*].ev_yield.sp_attack") => pokemon.ev_yield.sp_attack = try parseInt(line, u2, match.value),
                m.case(".pokemons[*].ev_yield.sp_defense") => pokemon.ev_yield.sp_defense = try parseInt(line, u2, match.value),
                m.case(".pokemons[*].items[*]") => {
                    const index = try parseIntBound(line, usize, pokemon.items.len, match.anys[1]);
                    pokemon.items[index] = lu16.init(try parseIntBound(line, u16, game.items.len, match.value));
                },
                m.case(".pokemons[*].gender_ratio") => pokemon.gender_ratio = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].egg_cycles") => pokemon.egg_cycles = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].base_friendship") => pokemon.base_friendship = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].growth_rate") => pokemon.growth_rate = try parseEnum(line, common.GrowthRate, match.value),
                m.case(".pokemons[*].egg_groups[*]") => {
                    const index = try parseIntBound(line, usize, 2, match.anys[1]);
                    switch (index) {
                        0 => pokemon.egg_group1 = try parseEnum(line, common.EggGroup, match.value),
                        1 => pokemon.egg_group2 = try parseEnum(line, common.EggGroup, match.value),
                        else => unreachable,
                    }
                },
                m.case(".pokemons[*].abilities[*]") => {
                    const index = try parseIntBound(line, usize, pokemon.abilities.len, match.anys[1]);
                    pokemon.abilities[index] = try parseInt(line, u8, match.value);
                },
                m.case(".pokemons[*].safari_zone_rate") => pokemon.safari_zone_rate = try parseInt(line, u8, match.value),
                m.case(".pokemons[*].color") => pokemon.color = try parseEnum(line, common.Color, match.value),
                m.case(".pokemons[*].flip") => pokemon.flip = try parseBool(line, match.value),
                else => unreachable,
            }
        },
        m.case(".pokemons[*].tms[*]") => {
            const machine_index = try parseIntBound(line, usize, game.machine_learnsets.len, match.anys[0]);
            const tm_index = try parseIntBound(line, usize, game.tms.len, match.anys[1]);
            const value = try parseBool(line, match.value);
            const learnset = &game.machine_learnsets[machine_index];
            const new = switch (value) {
                true => bits.set(u64, learnset.value(), @intCast(u6, tm_index)),
                false => bits.clear(u64, learnset.value(), @intCast(u6, tm_index)),
                else => unreachable,
            };
            learnset.* = lu64.init(new);
        },
        m.case(".pokemons[*].hms[*]") => {
            const machine_index = try parseIntBound(line, usize, game.machine_learnsets.len, match.anys[0]);
            const hm_index = try parseIntBound(line, usize, game.hms.len, match.anys[1]);
            const value = try parseBool(line, match.value);
            const learnset = &game.machine_learnsets[machine_index];
            const new = switch (value) {
                true => bits.set(u64, learnset.value(), @intCast(u6, hm_index + game.tms.len)),
                false => bits.clear(u64, learnset.value(), @intCast(u6, hm_index + game.tms.len)),
                else => unreachable,
            };
            learnset.* = lu64.init(new);
        },
        m.case(".pokemons[*].evos[*].method"),
        m.case(".pokemons[*].evos[*].param"),
        m.case(".pokemons[*].evos[*].target"),
        => {
            const evos_index = try parseIntBound(line, usize, game.evolutions.len, match.anys[0]);
            const evos = &game.evolutions[evos_index];
            const evo_index = try parseIntBound(line, usize, evos.len, match.anys[1]);
            const evo = &evos[evo_index];
            switch (match.case) {
                m.case(".pokemons[*].evos[*].method") => evo.method = try parseEnum(line, common.Evolution.Method, match.value),
                m.case(".pokemons[*].evos[*].param") => evo.param = lu16.init(try parseInt(line, u16, match.value)),
                m.case(".pokemons[*].evos[*].target") => evo.target = lu16.init(try parseInt(line, u16, match.value)),
                else => unreachable,
            }
        },
        m.case(".pokemons[*].moves[*].id"),
        m.case(".pokemons[*].moves[*].level"),
        => {
            const lvl_up_index = try parseIntBound(line, usize, game.level_up_learnset_pointers.len, match.anys[0]);
            const lvl_up_moves = try game.level_up_learnset_pointers[lvl_up_index].toMany(game.data);
            var len: usize = 0;

            // UNSAFE: Bounds check on game data
            while (lvl_up_moves[len].id != math.maxInt(u9) or lvl_up_moves[len].level != math.maxInt(u7)) : (len += 1) {}

            const move_index = try parseIntBound(line, usize, len, match.anys[1]);
            const move = &lvl_up_moves[move_index];
            switch (match.case) {
                m.case(".pokemons[*].moves[*].id") => move.id = try parseInt(line, u9, match.value),
                m.case(".pokemons[*].moves[*].level") => move.level = try parseInt(line, u7, match.value),
                else => unreachable,
            }
        },
        m.case(".tms[*]") => {
            const machine_index = try parseIntBound(line, usize, game.tms.len, match.anys[0]);
            game.tms[machine_index] = lu16.init(try parseInt(line, u16, match.value));
        },
        m.case(".hms[*]") => {
            const machine_index = try parseIntBound(line, usize, game.hms.len, match.anys[0]);
            game.hms[machine_index] = lu16.init(try parseInt(line, u16, match.value));
        },

        m.case(".items[*].id"),
        m.case(".items[*].price"),
        m.case(".items[*].hold_effect"),
        m.case(".items[*].hold_effect_param"),
        m.case(".items[*].importance"),
        m.case(".items[*].pocked"),
        m.case(".items[*].type"),
        m.case(".items[*].battle_usage"),
        m.case(".items[*].secondary_id"),
        => {
            const item_index = try parseIntBound(line, usize, game.items.len, match.anys[0]);
            const item = &game.items[item_index];
            switch (match.case) {
                m.case(".items[*].id") => item.id = lu16.init(try parseInt(line, u16, match.value)),
                m.case(".items[*].price") => item.price = lu16.init(try parseInt(line, u16, match.value)),
                m.case(".items[*].hold_effect") => item.hold_effect = try parseInt(line, u8, match.value),
                m.case(".items[*].hold_effect_param") => item.hold_effect_param = try parseInt(line, u8, match.value),
                m.case(".items[*].importance") => item.importance = try parseInt(line, u8, match.value),
                m.case(".items[*].pocked") => item.pocked = try parseInt(line, u8, match.value),
                m.case(".items[*].type") => item.@"type" = try parseInt(line, u8, match.value),
                m.case(".items[*].battle_usage") => item.battle_usage = lu32.init(try parseInt(line, u8, match.value)),
                m.case(".items[*].secondary_id") => item.secondary_id = lu32.init(try parseInt(line, u32, match.value)),
                else => unreachable,
            }
        },

        m.case(".zones[*].wild.land.encounter_rate"),
        m.case(".zones[*].wild.land.pokemons[*].min_level"),
        m.case(".zones[*].wild.land.pokemons[*].max_level"),
        m.case(".zones[*].wild.land.pokemons[*].species"),
        m.case(".zones[*].wild.surf.encounter_rate"),
        m.case(".zones[*].wild.surf.pokemons[*].min_level"),
        m.case(".zones[*].wild.surf.pokemons[*].max_level"),
        m.case(".zones[*].wild.surf.pokemons[*].species"),
        m.case(".zones[*].wild.rock_smash.encounter_rate"),
        m.case(".zones[*].wild.rock_smash.pokemons[*].min_level"),
        m.case(".zones[*].wild.rock_smash.pokemons[*].max_level"),
        m.case(".zones[*].wild.rock_smash.pokemons[*].species"),
        m.case(".zones[*].wild.fishing.encounter_rate"),
        m.case(".zones[*].wild.fishing.pokemons[*].min_level"),
        m.case(".zones[*].wild.fishing.pokemons[*].max_level"),
        m.case(".zones[*].wild.fishing.pokemons[*].species"),
        => {
            const header_index = try parseIntBound(line, usize, game.wild_pokemon_headers.len, match.anys[0]);
            const header = &game.wild_pokemon_headers[header_index];
            inline for ([][]const u8{
                "land",
                "surf",
                "rock_smash",
                "fishing",
            }) |area_name| {
                const pre = ".zones[*].wild." ++ area_name;
                switch (match.case) {
                    m.case(pre ++ ".encounter_rate") => {
                        const area = try @field(header, area_name).toSingle(game.data);
                        area.encounter_rate = try parseInt(line, u8, match.value);
                    },
                    m.case(pre ++ ".pokemons[*].min_level"),
                    m.case(pre ++ ".pokemons[*].max_level"),
                    m.case(pre ++ ".pokemons[*].species"),
                    => {
                        const area = try @field(header, area_name).toSingle(game.data);
                        const wilds = try area.wild_pokemons.toSingle(game.data);
                        const pokemon_index = try parseIntBound(line, usize, wilds.len, match.anys[1]);
                        const wild = &wilds[pokemon_index];
                        switch (match.case) {
                            m.case(pre ++ ".pokemons[*].min_level") => wild.min_level = try parseInt(line, u8, match.value),
                            m.case(pre ++ ".pokemons[*].max_level") => wild.max_level = try parseInt(line, u8, match.value),
                            m.case(pre ++ ".pokemons[*].species") => wild.species = lu16.init(try parseInt(line, u16, match.value)),
                            else => unreachable,
                        }
                    },
                    else => {},
                }
            }
        },

        else => {
            var tok = format.Tokenizer.init(str);
            warning(line, 1, "unexpected field '");
            while (true) {
                const token = tok.next();
                switch (token.id) {
                    format.Token.Id.Invalid => unreachable,
                    format.Token.Id.Equal => break,
                    else => debug.warn("{}", token.str),
                }
            }
            debug.warn("'\n");
        },
    } else |e| switch (e) {
        error.SyntaxError => {
            var parser = format.Parser.init(format.Tokenizer.init(str));
            const err = done: while (true) {
                switch (parser.next()) {
                    format.Parser.Result.Ok => {},
                    format.Parser.Result.Error => |err| break :done err,
                }
            } else unreachable;

            warning(line, err.found.index(str), "expected ");
            for (err.expected) |id, i| {
                const rev_i = (err.expected.len - 1) - i;
                debug.warn("'{}'", id.str());
                if (rev_i == 1)
                    debug.warn(" or ");
                if (rev_i > 1)
                    debug.warn(", ");
            }

            debug.warn(" found '{}'\n", err.found.str);
        },
    }
}

fn parseBool(line: usize, token: format.Token) !bool {
    const Bool = enum {
        @"true",
        @"false",
    };
    const res = try parseEnum(line, Bool, token);
    return res == Bool.@"true";
}

fn parseEnum(line: usize, comptime Enum: type, token: format.Token) !Enum {
    const value = mem.trim(u8, token.str, "\t ");

    return std.meta.stringToEnum(Enum, value) orelse {
        const fields = @typeInfo(Enum).Enum.fields;
        const column = 1;
        warning(line, column, "expected ");

        inline for (fields) |field, i| {
            const rev_i = (fields.len - 1) - i;
            debug.warn("'{}'", field.name);
            if (rev_i == 1)
                debug.warn(" or ");
            if (rev_i > 1)
                debug.warn(", ");
        }

        debug.warn(" found '{}'\n", value);
        return error.NotEnum;
    };
}

fn parseInt(line: usize, comptime Int: type, token: format.Token) !Int {
    return parseIntBound(line, Int, math.maxInt(Int), token);
}

fn parseIntBound(line: usize, comptime Int: type, bound: var, token: format.Token) !Int {
    const column = 1;
    const str = mem.trim(u8, token.str, "\t ");
    overflow: {
        const value = fmt.parseUnsigned(Int, str, 10) catch |err| {
            switch (err) {
                error.Overflow => break :overflow,
                error.InvalidCharacter => {
                    warning(line, column, "{} is not an number", str);
                    return err;
                },
            }
        };
        if (bound < value)
            break :overflow;

        return value;
    }

    warning(line, column, "{} is not within the bound {}\n", str, u128(bound));
    return error.Overflow;
}

fn warning(line: usize, col: usize, comptime f: []const u8, a: ...) void {
    debug.warn("(stdin):{}:{}: warning: ", line, col);
    debug.warn(f, a);
}
