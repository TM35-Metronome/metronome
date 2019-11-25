const clap = @import("clap");
const rom = @import("rom.zig");
const std = @import("std");
const util = @import("util");

const common = @import("common.zig");
const gen3 = @import("gen3-types.zig");
const gen4 = @import("gen4-types.zig");
const gen5 = @import("gen5-types.zig");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;

const path = fs.path;

const gba = rom.gba;
const nds = rom.nds;

const bit = util.bit;
const errors = util.errors;
const format = util.format;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu64 = rom.int.lu64;
const lu128 = rom.int.lu128;

const BufInStream = io.BufferedInStream(fs.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);
const Clap = clap.ComptimeClap(clap.Help, params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-a, --abort-on-first-warning  Abort execution on the first warning emitted.") catch unreachable,
        clap.parseParam("-h, --help                    Display this help text and exit.             ") catch unreachable,
        clap.parseParam("-o, --output <FILE>           Override destination path.                   ") catch unreachable,
        clap.parseParam("-r, --replace                 Replace output file if it already exists.    ") catch unreachable,
        clap.parseParam("-v, --version                 Output version information and exit.         ") catch unreachable,
        Param{ .takes_value = true },
    };
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-apply [-ahv] [-o <FILE>] <FILE>
        \\Applies changes to Pokémon roms.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    var stdio_unbuf = util.getStdIo() catch |err| return 1;
    var stdio = stdio_unbuf.getBuffered();
    defer stdio.err.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(&arena.allocator);
    _ = arg_iter.next() catch undefined;

    const res = main2(
        &arena.allocator,
        fs.File.ReadError,
        fs.File.WriteError,
        stdio.getStreams(),
        clap.args.OsIterator,
        &arg_iter,
    );

    stdio.out.flush() catch |err| return errors.writeErr(&stdio.err.stream, "<stdout>", err);
    return res;
}

pub fn main2(
    allocator: *mem.Allocator,
    comptime ReadError: type,
    comptime WriteError: type,
    stdio: util.CustomStdIoStreams(ReadError, WriteError),
    comptime ArgIterator: type,
    arg_iter: *ArgIterator,
) u8 {
    var stdin = io.BufferedInStream(ReadError).init(stdio.in);
    var args = Clap.parse(allocator, ArgIterator, arg_iter) catch |err| {
        stdio.err.print("{}\n", err) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    if (args.flag("--help")) {
        usage(stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.print("{}\n", program_version) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else {
        stdio.err.write("No file provided\n") catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const abort_on_first_warning = args.flag("--abort-on-first-warning");
    const replace = args.flag("--replace");
    const out = args.option("--output") orelse blk: {
        const res = fmt.allocPrint(allocator, "{}.modified", path.basename(file_name));
        break :blk res catch |err| return errors.allocErr(stdio.err);
    };

    const file = fs.File.openRead(file_name) catch |err| return errors.openErr(stdio.err, file_name, err);
    defer file.close();

    var out_file = if (replace)
        fs.File.openWrite(out) catch |err| return errors.openErr(stdio.err, out, err)
    else
        fs.File.openWriteNoClobber(out, fs.File.default_mode) catch |err| return errors.createErr(stdio.err, out, err);
    defer out_file.close();

    var line_num: usize = 1;
    var line_buf = std.Buffer.initSize(allocator, 0) catch |err| return errors.allocErr(stdio.err);

    var nds_rom: nds.Rom = undefined;
    const game: Game = blk: {
        const gen3_error = if (gen3.Game.fromFile(file, allocator)) |game| {
            break :blk Game{ .Gen3 = game };
        } else |err| err;

        file.seekTo(0) catch |err| return errors.readErr(stdio.err, file_name, err);
        nds_rom = nds.Rom.fromFile(file, allocator) catch |nds_error| {
            stdio.err.print("Failed to load '{}' as a gen3 game: {}\n", file_name, gen3_error) catch {};
            stdio.err.print("Failed to load '{}' as a gen4/gen5 game: {}\n", file_name, nds_error) catch {};
            return 1;
        };

        const gen4_error = if (gen4.Game.fromRom(nds_rom)) |game| {
            break :blk Game{ .Gen4 = game };
        } else |err| err;

        const gen5_error = if (gen5.Game.fromRom(allocator, nds_rom)) |game| {
            break :blk Game{ .Gen5 = game };
        } else |err| err;

        stdio.err.print("Successfully loaded '{}' as a nds rom.\n", file_name) catch {};
        stdio.err.print("Failed to load '{}' as a gen4 game: {}\n", file_name, gen4_error) catch {};
        stdio.err.print("Failed to load '{}' as a gen5 game: {}\n", file_name, gen5_error) catch {};
        return 1;
    };

    while (util.readLine(&stdin, &line_buf) catch |err| return errors.readErr(stdio.err, "<stdin>", err)) |line| : (line_num += 1) {
        const trimmed = mem.trimRight(u8, line, "\r\n");
        _ = switch (game) {
            .Gen3 => |gen3_game| applyGen3(gen3_game, line_num, trimmed),
            .Gen4 => |gen4_game| applyGen4(nds_rom, gen4_game, line_num, trimmed),
            .Gen5 => |gen5_game| applyGen5(nds_rom, gen5_game, line_num, trimmed),
        } catch |err| {
            stdio.err.print("(stdin):{}:1: warning: {}\n", line_num, @errorName(err)) catch {};
            if (abort_on_first_warning) {
                stdio.err.print("{}\n", line) catch {};
                return 1;
            }
        };
        line_buf.shrink(0);
    }

    var out_stream = &out_file.outStream().stream;
    switch (game) {
        .Gen3 => |gen3_game| gen3_game.writeToStream(out_stream) catch |err| return errors.writeErr(stdio.err, out, err),
        .Gen4, .Gen5 => nds_rom.writeToFile(out_file) catch |err| return errors.writeErr(stdio.err, out, err),
    }

    return 0;
}

const Game = union(enum) {
    Gen3: gen3.Game,
    Gen4: gen4.Game,
    Gen5: gen5.Game,
};

fn applyGen3(game: gen3.Game, line: usize, str: []const u8) !void {
    var parser = format.Parser{ .str = str };

    if (parser.eatField("version")) {
        const version = try parser.eatEnumValue(common.Version);
        if (version != game.version)
            return error.VersionDontMatch;
    } else |_| if (parser.eatField("game_title")) {
        const value = try parser.eatValue();
        if (!mem.eql(u8, value, game.header.game_title))
            return error.GameTitleDontMatch;
    } else |_| if (parser.eatField("gamecode")) {
        const value = try parser.eatValue();
        if (!mem.eql(u8, value, game.header.gamecode))
            return error.GameCodeDontMatch;
    } else |_| if (parser.eatField("starters")) {
        const starter_index = try parser.eatIndexMax(game.starters.len);
        const value = lu16.init(try parser.eatUnsignedValue(u16, 10));
        game.starters[starter_index].* = value;
        game.starters_repeat[starter_index].* = value;
    } else |_| if (parser.eatField("trainers")) {
        const trainer_index = try parser.eatIndexMax(game.trainers.len);
        const trainer = &game.trainers[trainer_index];

        if (parser.eatField("class")) {
            trainer.class = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("encounter_music")) {
            trainer.encounter_music = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("trainer_picture")) {
            trainer.trainer_picture = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("items")) {
            const item_index = try parser.eatIndexMax(trainer.items.len);
            trainer.items[item_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("is_double")) {
            trainer.is_double = lu32.init(try parser.eatUnsignedValue(u32, 10));
        } else |_| if (parser.eatField("ai")) {
            trainer.ai = lu32.init(try parser.eatUnsignedValue(u32, 10));
        } else |_| if (parser.eatField("party")) {
            const party_index = try parser.eatIndexMax(trainer.partyLen());
            const member = try trainer.partyAt(party_index, game.data);

            if (parser.eatField("iv")) {
                member.iv = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| if (parser.eatField("level")) {
                member.level = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| if (parser.eatField("species")) {
                member.species = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| if (parser.eatField("item")) {
                const item = try parser.eatUnsignedValue(u16, 10);
                switch (trainer.party_type) {
                    gen3.PartyType.Item => member.toParent(gen3.PartyMemberItem).item = lu16.init(item),
                    gen3.PartyType.Both => member.toParent(gen3.PartyMemberBoth).item = lu16.init(item),
                    else => return error.NoField,
                }
            } else |_| if (parser.eatField("moves")) {
                const mv_ptr = switch (trainer.party_type) {
                    gen3.PartyType.Moves => blk: {
                        const move_member = member.toParent(gen3.PartyMemberMoves);
                        const move_index = try parser.eatIndexMax(move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    gen3.PartyType.Both => blk: {
                        const move_member = member.toParent(gen3.PartyMemberBoth);
                        const move_index = try parser.eatIndexMax(move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    else => return error.NoField,
                };

                mv_ptr.* = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| {
                return error.NoField;
            }
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("moves")) {
        const move_index = try parser.eatIndexMax(game.moves.len);
        const move = &game.moves[move_index];

        if (parser.eatField("effect")) {
            move.effect = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("power")) {
            move.power = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("type")) {
            move.@"type" = try parser.eatEnumValue(gen3.Type);
        } else |_| if (parser.eatField("accuracy")) {
            move.accuracy = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("pp")) {
            move.pp = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("side_effect_chance")) {
            move.side_effect_chance = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("target")) {
            move.target = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("priority")) {
            move.priority = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("flags")) {
            move.flags = lu32.init(try parser.eatUnsignedValue(u32, 10));
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("pokemons")) {
        const pokemon_index = try parser.eatIndexMax(game.pokemons.len);
        const pokemon = &game.pokemons[pokemon_index];

        if (parser.eatField("stats")) {
            if (parser.eatField("hp")) {
                pokemon.stats.hp = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("attack")) {
                pokemon.stats.attack = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("defense")) {
                pokemon.stats.defense = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("speed")) {
                pokemon.stats.speed = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_attack")) {
                pokemon.stats.sp_attack = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_defense")) {
                pokemon.stats.sp_defense = try parser.eatUnsignedValue(u8, 10);
            } else |_| {
                return error.NoField;
            }
        } else |_| if (parser.eatField("types")) {
            const type_index = try parser.eatIndexMax(pokemon.types.len);
            pokemon.types[type_index] = try parser.eatEnumValue(gen3.Type);
        } else |_| if (parser.eatField("catch_rate")) {
            pokemon.catch_rate = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("base_exp_yield")) {
            pokemon.base_exp_yield = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("ev_yield")) {
            if (parser.eatField("hp")) {
                pokemon.ev_yield.hp = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("attack")) {
                pokemon.ev_yield.attack = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("defense")) {
                pokemon.ev_yield.defense = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("speed")) {
                pokemon.ev_yield.speed = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("sp_attack")) {
                pokemon.ev_yield.sp_attack = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("sp_defense")) {
                pokemon.ev_yield.sp_defense = try parser.eatUnsignedValue(u2, 10);
            } else |_| {
                return error.NoField;
            }
        } else |_| if (parser.eatField("items")) {
            const item_index = try parser.eatIndexMax(pokemon.items.len);
            pokemon.items[item_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("gender_ratio")) {
            pokemon.gender_ratio = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("egg_cycles")) {
            pokemon.egg_cycles = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("base_friendship")) {
            pokemon.base_friendship = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("growth_rate")) {
            pokemon.growth_rate = try parser.eatEnumValue(common.GrowthRate);
        } else |_| if (parser.eatField("egg_groups")) {
            const egg_index = try parser.eatIndexMax(2);
            const egg_group = try parser.eatEnumValue(common.EggGroup);
            switch (egg_index) {
                0 => pokemon.egg_group1 = egg_group,
                1 => pokemon.egg_group2 = egg_group,
                else => unreachable,
            }
        } else |_| if (parser.eatField("abilities")) {
            const ability_index = try parser.eatIndexMax(pokemon.abilities.len);
            pokemon.abilities[ability_index] = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("safari_zone_rate")) {
            pokemon.safari_zone_rate = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("color")) {
            pokemon.color_flip.color = try parser.eatEnumValue(common.Color);
        } else |_| if (parser.eatField("flip")) {
            pokemon.color_flip.flip = try parser.eatBoolValue();
        } else |_| if (parser.eatField("tms")) {
            const tm_index = try parser.eatIndexMax(game.tms.len);
            const value = try parser.eatBoolValue();
            const learnset = &game.machine_learnsets[pokemon_index];
            learnset.* = lu64.init(bit.setTo(u64, learnset.value(), @intCast(u6, tm_index), value));
        } else |_| if (parser.eatField("hms")) {
            const hm_index = try parser.eatIndexMax(game.tms.len);
            const value = try parser.eatBoolValue();
            const learnset = &game.machine_learnsets[pokemon_index];
            learnset.* = lu64.init(bit.setTo(u64, learnset.value(), @intCast(u6, hm_index + game.tms.len), value));
        } else |_| if (parser.eatField("evos")) {
            const evos = &game.evolutions[pokemon_index];
            const evo_index = try parser.eatIndexMax(evos.len);
            const evo = &evos[evo_index];

            if (parser.eatField("method")) {
                evo.method = try parser.eatEnumValue(common.Evolution.Method);
            } else |_| if (parser.eatField("param")) {
                evo.param = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| if (parser.eatField("target")) {
                evo.target = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| {
                return error.NoField;
            }
        } else |_| if (parser.eatField("moves")) {
            const lvl_up_moves = try game.level_up_learnset_pointers[pokemon_index].toSliceTerminated(game.data, struct {
                fn isTerm(move: gen3.LevelUpMove) bool {
                    return move.id == math.maxInt(u9) and move.level == math.maxInt(u7);
                }
            }.isTerm);

            const lvl_up_index = try parser.eatIndexMax(lvl_up_moves.len);
            const lvl_up_move = &lvl_up_moves[lvl_up_index];
            if (parser.eatField("id")) {
                lvl_up_move.id = try parser.eatUnsignedValue(u9, 10);
            } else |_| if (parser.eatField("level")) {
                lvl_up_move.level = try parser.eatUnsignedValue(u7, 10);
            } else |_| {
                return error.NoField;
            }
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("tms")) {
        const tm_index = try parser.eatIndexMax(game.tms.len);
        game.tms[tm_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
    } else |_| if (parser.eatField("hms")) {
        const tm_index = try parser.eatIndexMax(game.hms.len);
        game.hms[tm_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
    } else |_| if (parser.eatField("items")) {
        const item_index = try parser.eatIndexMax(game.items.len);
        const item = &game.items[item_index];

        if (parser.eatField("id")) {
            item.id = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("price")) {
            item.price = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("hold_effect")) {
            item.hold_effect = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("hold_effect_param")) {
            item.hold_effect_param = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("importance")) {
            item.importance = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("pocked")) {
            item.pocked = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("type")) {
            item.@"type" = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("battle_usage")) {
            item.battle_usage = lu32.init(try parser.eatUnsignedValue(u32, 10));
        } else |_| if (parser.eatField("secondary_id")) {
            item.secondary_id = lu32.init(try parser.eatUnsignedValue(u32, 10));
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("zones")) {
        const zone_index = try parser.eatIndexMax(game.wild_pokemon_headers.len);
        const header = &game.wild_pokemon_headers[zone_index];
        try parser.eatField("wild");

        const Fn = struct {
            fn applyArea(p: *format.Parser, g: gen3.Game, area: var) !void {
                if (p.eatField("encounter_rate")) {
                    area.encounter_rate = try p.eatUnsignedValue(u8, 10);
                } else |_| if (p.eatField("pokemons")) {
                    const wilds = try area.wild_pokemons.toSingle(g.data);
                    const wild_index = try p.eatIndexMax(wilds.len);
                    const wild = &wilds[wild_index];

                    if (p.eatField("min_level")) {
                        wild.min_level = try p.eatUnsignedValue(u8, 10);
                    } else |_| if (p.eatField("max_level")) {
                        wild.max_level = try p.eatUnsignedValue(u8, 10);
                    } else |_| if (p.eatField("species")) {
                        wild.species = lu16.init(try p.eatUnsignedValue(u16, 10));
                    } else |_| {
                        return error.NoField;
                    }
                } else |_| {
                    return error.NoField;
                }
            }
        };

        if (parser.eatField("land")) {
            try Fn.applyArea(&parser, game, try header.land.toSingle(game.data));
        } else |_| if (parser.eatField("surf")) {
            try Fn.applyArea(&parser, game, try header.surf.toSingle(game.data));
        } else |_| if (parser.eatField("rock_smash")) {
            try Fn.applyArea(&parser, game, try header.rock_smash.toSingle(game.data));
        } else |_| if (parser.eatField("fishing")) {
            try Fn.applyArea(&parser, game, try header.fishing.toSingle(game.data));
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("static_pokemons")) {
        const static_mon_index = try parser.eatIndexMax(game.static_pokemons.len);
        var static_mon = game.static_pokemons[static_mon_index].data;

        if (parser.eatField("species")) {
            static_mon.setwildbattle.species = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("level")) {
            static_mon.setwildbattle.level = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("item")) {
            static_mon.setwildbattle.item = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| {
            return error.NoField;
        }

        game.static_pokemons[static_mon_index].data = static_mon;
    } else |_| if (parser.eatField("given_items")) {
        const given_index = try parser.eatIndexMax(game.given_items.len);
        var given_item = game.given_items[given_index].data;

        if (parser.eatField("item")) {
            given_item.giveitem.index = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("quantity")) {
            given_item.giveitem.quantity = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| {
            return error.NoField;
        }

        game.given_items[given_index].data = given_item;
    } else |_| {
        return error.NoField;
    }
}

fn applyGen4(nds_rom: nds.Rom, game: gen4.Game, line: usize, str: []const u8) !void {
    var parser = format.Parser{ .str = str };

    if (parser.eatField("version")) {
        const version = try parser.eatEnumValue(common.Version);
        if (version != game.version)
            return error.VersionDontMatch;
    } else |_| if (parser.eatField("game_title")) {
        const value = try parser.eatValue();
        const null_index = mem.indexOfScalar(u8, nds_rom.header.game_title, 0) orelse nds_rom.header.game_title.len;
        if (!mem.eql(u8, value, nds_rom.header.game_title[0..null_index]))
            return error.GameTitleDontMatch;
    } else |_| if (parser.eatField("gamecode")) {
        const value = try parser.eatValue();
        if (!mem.eql(u8, value, nds_rom.header.gamecode))
            return error.GameCodeDontMatch;
    } else |_| if (parser.eatField("starters")) {
        const starter_index = try parser.eatIndexMax(game.starters.len);
        const value = lu16.init(try parser.eatUnsignedValue(u16, 10));
        game.starters[starter_index].* = value;
    } else |_| if (parser.eatField("trainers")) {
        const trainers = game.trainers.nodes.toSlice();
        const trainer_index = try parser.eatIndexMax(trainers.len);
        const trainer = try trainers[trainer_index].asDataFile(gen4.Trainer);

        if (parser.eatField("class")) {
            trainer.class = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("battle_type")) {
            trainer.battle_type = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("battle_type2")) {
            trainer.battle_type2 = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("items")) {
            const item_index = try parser.eatIndexMax(trainer.items.len);
            trainer.items[item_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("ai")) {
            trainer.ai = lu32.init(try parser.eatUnsignedValue(u32, 10));
        } else |_| if (parser.eatField("party")) {
            const parties = game.parties.nodes.toSlice();
            const party_index = try parser.eatIndexMax(trainer.party_size);
            const party_file = try parties[trainer_index].asFile();
            const member = trainer.partyMember(game.version, party_file.data, party_index) orelse return error.OutOfBound;

            if (parser.eatField("iv")) {
                member.iv = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("gender")) {
                member.gender_ability.gender = try parser.eatUnsignedValue(u4, 10);
            } else |_| if (parser.eatField("ability")) {
                member.gender_ability.ability = try parser.eatUnsignedValue(u4, 10);
            } else |_| if (parser.eatField("level")) {
                member.level = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| if (parser.eatField("species")) {
                member.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
            } else |_| if (parser.eatField("form")) {
                member.species.setForm(try parser.eatUnsignedValue(u6, 10));
            } else |_| if (parser.eatField("item")) {
                const item = try parser.eatUnsignedValue(u16, 10);
                switch (trainer.party_type) {
                    gen4.PartyType.Item => member.toParent(gen4.PartyMemberItem).item = lu16.init(item),
                    gen4.PartyType.Both => member.toParent(gen4.PartyMemberBoth).item = lu16.init(item),
                    else => return error.NoField,
                }
            } else |_| if (parser.eatField("moves")) {
                const mv_ptr = switch (trainer.party_type) {
                    gen4.PartyType.Moves => blk: {
                        const move_member = member.toParent(gen4.PartyMemberMoves);
                        const move_index = try parser.eatIndexMax(move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    gen4.PartyType.Both => blk: {
                        const move_member = member.toParent(gen4.PartyMemberBoth);
                        const move_index = try parser.eatIndexMax(move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    else => return error.NoField,
                };

                mv_ptr.* = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| {
                return error.NoField;
            }
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("moves")) {
        const moves = game.moves.nodes.toSlice();
        const move_index = try parser.eatIndexMax(moves.len);
        const move = try moves[move_index].asDataFile(gen4.Move);

        if (parser.eatField("category")) {
            move.category = try parser.eatEnumValue(common.MoveCategory);
        } else |_| if (parser.eatField("power")) {
            move.power = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("type")) {
            move.@"type" = try parser.eatEnumValue(gen4.Type);
        } else |_| if (parser.eatField("accuracy")) {
            move.accuracy = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("pp")) {
            move.pp = try parser.eatUnsignedValue(u8, 10);
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("pokemons")) {
        const pokemons = game.pokemons.nodes.toSlice();
        const pokemon_index = try parser.eatIndexMax(pokemons.len);
        const pokemon = try pokemons[pokemon_index].asDataFile(gen4.BasePokemon);

        if (parser.eatField("stats")) {
            if (parser.eatField("hp")) {
                pokemon.stats.hp = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("attack")) {
                pokemon.stats.attack = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("defense")) {
                pokemon.stats.defense = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("speed")) {
                pokemon.stats.speed = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_attack")) {
                pokemon.stats.sp_attack = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_defense")) {
                pokemon.stats.sp_defense = try parser.eatUnsignedValue(u8, 10);
            } else |_| {
                return error.NoField;
            }
        } else |_| if (parser.eatField("types")) {
            const type_index = try parser.eatIndexMax(pokemon.types.len);
            pokemon.types[type_index] = try parser.eatEnumValue(gen4.Type);
        } else |_| if (parser.eatField("catch_rate")) {
            pokemon.catch_rate = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("base_exp_yield")) {
            pokemon.base_exp_yield = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("ev_yield")) {
            if (parser.eatField("hp")) {
                pokemon.ev_yield.hp = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("attack")) {
                pokemon.ev_yield.attack = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("defense")) {
                pokemon.ev_yield.defense = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("speed")) {
                pokemon.ev_yield.speed = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("sp_attack")) {
                pokemon.ev_yield.sp_attack = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("sp_defense")) {
                pokemon.ev_yield.sp_defense = try parser.eatUnsignedValue(u2, 10);
            } else |_| {
                return error.NoField;
            }
        } else |_| if (parser.eatField("items")) {
            const item_index = try parser.eatIndexMax(pokemon.items.len);
            pokemon.items[item_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("gender_ratio")) {
            pokemon.gender_ratio = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("egg_cycles")) {
            pokemon.egg_cycles = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("base_friendship")) {
            pokemon.base_friendship = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("growth_rate")) {
            pokemon.growth_rate = try parser.eatEnumValue(common.GrowthRate);
        } else |_| if (parser.eatField("egg_groups")) {
            const egg_index = try parser.eatIndexMax(2);
            const egg_group = try parser.eatEnumValue(common.EggGroup);
            switch (egg_index) {
                0 => pokemon.egg_group1 = egg_group,
                1 => pokemon.egg_group2 = egg_group,
                else => return error.OutOfBound,
            }
        } else |_| if (parser.eatField("abilities")) {
            const ability_index = try parser.eatIndexMax(pokemon.abilities.len);
            pokemon.abilities[ability_index] = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("flee_rate")) {
            pokemon.flee_rate = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("color")) {
            pokemon.color = try parser.eatEnumValue(common.Color);
        } else |_| if (parser.eatField("tms")) {
            const tm_index = try parser.eatIndexMax(game.tms.len);
            const value = try parser.eatBoolValue();
            const learnset = &pokemon.machine_learnset;
            learnset.* = lu128.init(bit.setTo(u128, learnset.value(), @intCast(u7, tm_index), value));
        } else |_| if (parser.eatField("hms")) {
            const hm_index = try parser.eatIndexMax(game.hms.len);
            const value = try parser.eatBoolValue();
            const learnset = &pokemon.machine_learnset;
            learnset.* = lu128.init(bit.setTo(u128, learnset.value(), @intCast(u7, hm_index + game.tms.len), value));
        } else |_| if (parser.eatField("evos")) {
            const evos_file = try game.evolutions.nodes.toSlice()[pokemon_index].asFile();
            const bytes = evos_file.data;
            const rem = bytes.len % @sizeOf(gen4.Evolution);
            const evos = @bytesToSlice(gen4.Evolution, bytes[0 .. bytes.len - rem]);
            const evo_index = try parser.eatIndexMax(evos.len);
            const evo = &evos[evo_index];

            if (parser.eatField("method")) {
                evo.method = try parser.eatEnumValue(gen4.Evolution.Method);
            } else |_| if (parser.eatField("param")) {
                evo.param = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| if (parser.eatField("target")) {
                evo.target = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| {
                return error.NoField;
            }
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("tms")) {
        const tm_index = try parser.eatIndexMax(game.tms.len);
        game.tms[tm_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
    } else |_| if (parser.eatField("hms")) {
        const hm_index = try parser.eatIndexMax(game.hms.len);
        game.hms[hm_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
    } else |_| if (parser.eatField("zones")) {
        const wild_pokemons = game.wild_pokemons.nodes.toSlice();
        const zone_index = try parser.eatIndexMax(wild_pokemons.len);
        try parser.eatField("wild");

        switch (game.version) {
            common.Version.Diamond,
            common.Version.Pearl,
            common.Version.Platinum,
            => {
                const wilds = try wild_pokemons[zone_index].asDataFile(gen4.DpptWildPokemons);
                if (parser.eatField("grass")) {
                    if (parser.eatField("encounter_rate")) {
                        wilds.grass_rate = lu32.init(try parser.eatUnsignedValue(u32, 10));
                        return;
                    } else |_| if (parser.eatField("pokemons")) {
                        const wild_index = try parser.eatIndexMax(wilds.grass.len);
                        const wild = &wilds.grass[wild_index];

                        if (parser.eatField("min_level")) {
                            wild.level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("max_level")) {
                            wild.level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("species")) {
                            wild.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
                            return;
                        } else |_| if (parser.eatField("form")) {
                            wild.species.setForm(try parser.eatUnsignedValue(u6, 10));
                            return;
                        } else |_| {
                            return error.NoField;
                        }
                    } else |_| {
                        return error.NoField;
                    }
                } else |_| {}

                inline for ([_][]const u8{
                    "swarm_replacements",
                    "day_replacements",
                    "night_replacements",
                    "radar_replacements",
                    "unknown_replacements",
                    "gba_replacements",
                }) |area_name| skip: {
                    parser.eatField(area_name) catch break :skip;
                    parser.eatField("pokemons") catch break :skip;

                    const area = &@field(wilds, area_name);
                    const wild_index = try parser.eatIndexMax(area.len);
                    const wild = &area[wild_index];

                    if (parser.eatField("species")) {
                        wild.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
                        return;
                    } else |_| if (parser.eatField("form")) {
                        wild.species.setForm(try parser.eatUnsignedValue(u6, 10));
                        return;
                    } else |_| {
                        return error.NoField;
                    }
                }

                inline for ([_][]const u8{
                    "surf",
                    "sea_unknown",
                    "old_rod",
                    "good_rod",
                    "super_rod",
                }) |area_name| skip: {
                    parser.eatField(area_name) catch break :skip;
                    if (parser.eatField("encounter_rate")) {
                        @field(wilds, area_name ++ "_rate") = lu32.init(try parser.eatUnsignedValue(u32, 10));
                        return;
                    } else |_| if (parser.eatField("pokemons")) {
                        const area = &@field(wilds, area_name);
                        const wild_index = try parser.eatIndexMax(area.len);
                        const wild = &area[wild_index];

                        if (parser.eatField("min_level")) {
                            wild.min_level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("max_level")) {
                            wild.max_level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("species")) {
                            wild.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
                            return;
                        } else |_| if (parser.eatField("form")) {
                            wild.species.setForm(try parser.eatUnsignedValue(u6, 10));
                            return;
                        } else |_| {
                            return error.NoField;
                        }
                    } else |_| {}
                }

                return error.NoField;
            },

            common.Version.HeartGold,
            common.Version.SoulSilver,
            => {
                const wilds = try wild_pokemons[zone_index].asDataFile(gen4.HgssWildPokemons);
                inline for ([_][]const u8{
                    "grass_morning",
                    "grass_day",
                    "grass_night",
                }) |area_name| skip: {
                    parser.eatField(area_name) catch break :skip;
                    if (parser.eatField("encounter_rate")) {
                        wilds.grass_rate = try parser.eatUnsignedValue(u8, 10);
                        return;
                    } else |_| if (parser.eatField("pokemons")) {
                        const area = &@field(wilds, area_name);
                        const wild_index = try parser.eatIndexMax(area.len);
                        const wild = &area[wild_index];

                        if (parser.eatField("min_level")) {
                            wilds.grass_levels[wild_index] = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("max_level")) {
                            wilds.grass_levels[wild_index] = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("species")) {
                            wild.setSpecies(try parser.eatUnsignedValue(u10, 10));
                            return;
                        } else |_| if (parser.eatField("form")) {
                            wild.setForm(try parser.eatUnsignedValue(u6, 10));
                            return;
                        } else |_| {
                            return error.NoField;
                        }
                    } else |_| {}
                }

                inline for ([_][]const u8{
                    "surf",
                    "sea_unknown",
                    "old_rod",
                    "good_rod",
                    "super_rod",
                }) |area_name, j| skip: {
                    parser.eatField(area_name) catch break :skip;
                    if (parser.eatField("encounter_rate")) {
                        wilds.sea_rates[j] = try parser.eatUnsignedValue(u8, 10);
                        return;
                    } else |_| if (parser.eatField("pokemons")) {
                        const area = &@field(wilds, area_name);
                        const wild_index = try parser.eatIndexMax(area.len);
                        const wild = &area[wild_index];

                        if (parser.eatField("min_level")) {
                            wild.min_level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("max_level")) {
                            wild.max_level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("species")) {
                            wild.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
                            return;
                        } else |_| if (parser.eatField("form")) {
                            wild.species.setForm(try parser.eatUnsignedValue(u6, 10));
                            return;
                        } else |_| {
                            return error.NoField;
                        }
                    } else |_| {}
                }

                // TODO: radio, swarm
                return error.NoField;
            },
            else => unreachable,
        }
    } else |err| {
        return error.NoField;
    }
}

fn applyGen5(nds_rom: nds.Rom, game: gen5.Game, line: usize, str: []const u8) !void {
    var parser = format.Parser{ .str = str };

    if (parser.eatField("version")) {
        const version = try parser.eatEnumValue(common.Version);
        if (version != game.version)
            return error.VersionDontMatch;
    } else |_| if (parser.eatField("game_title")) {
        const value = try parser.eatValue();
        const null_index = mem.indexOfScalar(u8, nds_rom.header.game_title, 0) orelse nds_rom.header.game_title.len;
        if (!mem.eql(u8, value, nds_rom.header.game_title[0..null_index]))
            return error.GameTitleDontMatch;
    } else |_| if (parser.eatField("gamecode")) {
        const value = try parser.eatValue();
        if (!mem.eql(u8, value, nds_rom.header.gamecode))
            return error.GameCodeDontMatch;
    } else |_| if (parser.eatField("starters")) {
        const starter_index = try parser.eatIndexMax(game.starters.len);
        const value = lu16.init(try parser.eatUnsignedValue(u16, 10));
        for (game.starters[starter_index]) |starter|
            starter.* = value;
    } else |_| if (parser.eatField("trainers")) {
        const trainers = game.trainers.nodes.toSlice();
        const trainer_index = try parser.eatIndexMax(trainers.len);
        const trainer = try trainers[trainer_index].asDataFile(gen5.Trainer);

        if (parser.eatField("class")) {
            trainer.class = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("battle_type")) {
            trainer.battle_type = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("items")) {
            const item_index = try parser.eatIndexMax(trainer.items.len);
            trainer.items[item_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("ai")) {
            trainer.ai = lu32.init(try parser.eatUnsignedValue(u32, 10));
        } else |_| if (parser.eatField("is_healer")) {
            trainer.healer = try parser.eatBoolValue();
        } else |_| if (parser.eatField("cash")) {
            trainer.cash = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("post_battle_item")) {
            trainer.post_battle_item = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("party")) {
            const parties = game.parties.nodes.toSlice();
            const party_index = try parser.eatIndexMax(trainer.party_size);
            const party_file = try parties[trainer_index].asFile();
            const member = trainer.partyMember(party_file.data, party_index) orelse return error.OutOfBound;

            if (parser.eatField("iv")) {
                member.iv = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("gender")) {
                member.gender_ability.gender = try parser.eatUnsignedValue(u4, 10);
            } else |_| if (parser.eatField("ability")) {
                member.gender_ability.ability = try parser.eatUnsignedValue(u4, 10);
            } else |_| if (parser.eatField("level")) {
                member.level = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("species")) {
                member.species = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| if (parser.eatField("form")) {
                member.form = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| if (parser.eatField("item")) {
                const item = try parser.eatUnsignedValue(u16, 10);
                switch (trainer.party_type) {
                    gen5.PartyType.Item => member.toParent(gen5.PartyMemberItem).item = lu16.init(item),
                    gen5.PartyType.Both => member.toParent(gen5.PartyMemberBoth).item = lu16.init(item),
                    else => return error.NoField,
                }
            } else |_| if (parser.eatField("moves")) {
                const mv_ptr = switch (trainer.party_type) {
                    gen5.PartyType.Moves => blk: {
                        const move_member = member.toParent(gen5.PartyMemberMoves);
                        const move_index = try parser.eatIndexMax(move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    gen5.PartyType.Both => blk: {
                        const move_member = member.toParent(gen5.PartyMemberBoth);
                        const move_index = try parser.eatIndexMax(move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    else => return error.NoField,
                };

                mv_ptr.* = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| {
                return error.NoField;
            }
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("moves")) {
        const moves = game.moves.nodes.toSlice();
        const move_index = try parser.eatIndexMax(moves.len);
        const move = try moves[move_index].asDataFile(gen5.Move);

        if (parser.eatField("type")) {
            move.@"type" = try parser.eatEnumValue(gen5.Type);
        } else |_| if (parser.eatField("effect_category")) {
            move.effect_category = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("category")) {
            move.category = try parser.eatEnumValue(common.MoveCategory);
        } else |_| if (parser.eatField("power")) {
            move.power = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("accuracy")) {
            move.accuracy = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("pp")) {
            move.pp = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("priority")) {
            move.priority = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("min_hits")) {
            move.min_max_hits.min = try parser.eatUnsignedValue(u4, 10);
        } else |_| if (parser.eatField("max_hits")) {
            move.min_max_hits.max = try parser.eatUnsignedValue(u4, 10);
        } else |_| if (parser.eatField("result_effect")) {
            move.result_effect = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("effect_chance")) {
            move.effect_chance = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("status")) {
            move.status = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("min_turns")) {
            move.min_turns = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("max_turns")) {
            move.max_turns = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("crit")) {
            move.crit = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("flinch")) {
            move.flinch = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("effect")) {
            move.effect = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("target_hp")) {
            move.target_hp = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("user_hp")) {
            move.user_hp = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("target")) {
            move.target = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("stats_affected")) {
            const status_index = try parser.eatIndexMax(move.stats_affected.len);
            move.stats_affected[status_index] = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("stats_affected_magnetude")) {
            const status_index = try parser.eatIndexMax(move.stats_affected_magnetude.len);
            move.stats_affected_magnetude[status_index] = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("stats_affected_chance")) {
            const status_index = try parser.eatIndexMax(move.stats_affected_chance.len);
            move.stats_affected_chance[status_index] = try parser.eatUnsignedValue(u8, 10);
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("pokemons")) {
        const pokemons = game.pokemons.nodes.toSlice();
        const pokemon_index = try parser.eatIndexMax(pokemons.len);
        const pokemon = try pokemons[pokemon_index].asDataFile(gen5.BasePokemon);

        if (parser.eatField("stats")) {
            if (parser.eatField("hp")) {
                pokemon.stats.hp = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("attack")) {
                pokemon.stats.attack = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("defense")) {
                pokemon.stats.defense = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("speed")) {
                pokemon.stats.speed = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_attack")) {
                pokemon.stats.sp_attack = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_defense")) {
                pokemon.stats.sp_defense = try parser.eatUnsignedValue(u8, 10);
            } else |_| {
                return error.NoField;
            }
        } else |_| if (parser.eatField("types")) {
            const type_index = try parser.eatIndexMax(pokemon.types.len);
            pokemon.types[type_index] = try parser.eatEnumValue(gen5.Type);
        } else |_| if (parser.eatField("catch_rate")) {
            pokemon.catch_rate = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("items")) {
            const item_index = try parser.eatIndexMax(pokemon.items.len);
            pokemon.items[item_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("gender_ratio")) {
            pokemon.gender_ratio = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("egg_cycles")) {
            pokemon.egg_cycles = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("base_friendship")) {
            pokemon.base_friendship = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("growth_rate")) {
            pokemon.growth_rate = try parser.eatEnumValue(common.GrowthRate);
        } else |_| if (parser.eatField("egg_groups")) {
            const egg_index = try parser.eatIndexMax(2);
            const egg_group = try parser.eatEnumValue(common.EggGroup);
            switch (egg_index) {
                0 => pokemon.egg_group1 = egg_group,
                1 => pokemon.egg_group2 = egg_group,
                else => unreachable,
            }
        } else |_| if (parser.eatField("abilities")) {
            const ability_index = try parser.eatIndexMax(pokemon.abilities.len);
            pokemon.abilities[ability_index] = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("color")) {
            pokemon.color = try parser.eatEnumValue(common.Color);
        } else |_| if (parser.eatField("height")) {
            pokemon.height = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("weight")) {
            pokemon.weight = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("tms")) {
            const tm_index = try parser.eatIndexMax(game.tms1.len + game.tms2.len);
            const real_index = if (tm_index < game.tms1.len) tm_index else tm_index + game.hms.len;
            const value = try parser.eatBoolValue();
            const learnset = &pokemon.machine_learnset;
            learnset.* = lu128.init(bit.setTo(u128, learnset.value(), @intCast(u7, real_index), value));
        } else |_| if (parser.eatField("hms")) {
            const hm_index = try parser.eatIndexMax(game.hms.len);
            const value = try parser.eatBoolValue();
            const learnset = &pokemon.machine_learnset;
            learnset.* = lu128.init(bit.setTo(u128, learnset.value(), @intCast(u7, hm_index + game.tms1.len), value));
        } else |_| if (parser.eatField("evos")) {
            const evos_file = try game.evolutions.nodes.toSlice()[pokemon_index].asFile();
            const bytes = evos_file.data;
            const rem = bytes.len % @sizeOf(gen5.Evolution);
            const evos = @bytesToSlice(gen5.Evolution, bytes[0 .. bytes.len - rem]);
            const evo_index = try parser.eatIndexMax(evos.len);
            const evo = &evos[evo_index];

            if (parser.eatField("method")) {
                evo.method = try parser.eatEnumValue(gen5.Evolution.Method);
            } else |_| if (parser.eatField("param")) {
                evo.param = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| if (parser.eatField("target")) {
                evo.target = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| {
                return error.NoField;
            }
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("tms")) {
        const tm_index = try parser.eatIndexMax(game.tms1.len + game.tms2.len);
        const value = lu16.init(try parser.eatUnsignedValue(u16, 10));
        if (tm_index < game.tms1.len) {
            game.tms1[tm_index] = value;
        } else {
            game.tms1[tm_index - game.tms1.len] = value;
        }
    } else |_| if (parser.eatField("hms")) {
        const hm_index = try parser.eatIndexMax(game.hms.len);
        game.hms[hm_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
    } else |_| if (parser.eatField("zones")) {
        const wild_pokemons = game.wild_pokemons.nodes.toSlice();
        const zone_index = try parser.eatIndexMax(wild_pokemons.len);
        const wilds = try wild_pokemons[zone_index].asDataFile(gen5.WildPokemons);
        try parser.eatField("wild");

        inline for ([_][]const u8{
            "grass",
            "dark_grass",
            "rustling_grass",
            "surf",
            "ripple_surf",
            "fishing",
            "ripple_fishing",
        }) |area_name, j| skip: {
            parser.eatField(area_name) catch break :skip;
            if (parser.eatField("encounter_rate")) {
                wilds.rates[j] = try parser.eatUnsignedValue(u8, 10);
                return;
            } else |_| if (parser.eatField("pokemons")) {
                const area = &@field(wilds, area_name);
                const wild_index = try parser.eatIndexMax(area.len);
                const wild = &area[wild_index];

                if (parser.eatField("min_level")) {
                    wild.min_level = try parser.eatUnsignedValue(u8, 10);
                    return;
                } else |_| if (parser.eatField("max_level")) {
                    wild.max_level = try parser.eatUnsignedValue(u8, 10);
                    return;
                } else |_| if (parser.eatField("species")) {
                    wild.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
                    return;
                } else |_| if (parser.eatField("form")) {
                    wild.species.setForm(try parser.eatUnsignedValue(u6, 10));
                    return;
                } else |_| {
                    return error.NoField;
                }
            } else |_| {}
        }

        return error.NoField;
    } else |_| {
        return error.NoField;
    }
}

test "" {
    // tm35-load imports the "load-apply-test.zig" file, which
    // tests both tm35-load and tm35-apply
}
