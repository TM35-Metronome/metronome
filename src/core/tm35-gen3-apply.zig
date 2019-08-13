const clap = @import("clap");
const common = @import("common.zig");
const fun = @import("fun");
const gba = @import("gba.zig");
const gen3 = @import("gen3-types.zig");
const nds = @import("nds.zig");
const std = @import("std");
const builtin = @import("builtin");
const format = @import("format");

const bits = fun.bits;
const debug = std.debug;
const heap = std.heap;
const io = std.io;
const fs = std.fs;
const math = std.math;
const mem = std.mem;
const fmt = std.fmt;
const os = std.os;
const rand = std.rand;
const slice = fun.generic.slice;
const path = fs.path;

const BufInStream = io.BufferedInStream(fs.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);
const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu64 = fun.platform.lu64;
const lu128 = fun.platform.lu128;

const params = [_]Param{
    Param{
        .id = "abort execution on the first warning emitted",
        .names = Names{ .long = "abort-on-first-warning" },
    },
    Param{
        .id = "display this help text and exit",
        .names = Names{ .short = 'h', .long = "help" },
    },
    Param{
        .id = "override destination path",
        .names = Names{ .short = 'o', .long = "output" },
        .takes_value = true,
    },
    Param{
        .id = "",
        .takes_value = true,
    },
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

pub fn main() !void {
    const unbuf_stdout = &(try io.getStdOut()).outStream().stream;
    var buf_stdout = BufOutStream.init(unbuf_stdout);
    defer buf_stdout.flush() catch {};

    const stderr = &(try io.getStdErr()).outStream().stream;
    const stdin = &BufInStream.init(&(try std.io.getStdIn()).inStream().stream).stream;
    const stdout = &buf_stdout.stream;

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const file_name = if (args.positionals().len > 0) args.positionals()[0] else {
        usage(stderr) catch {};
        return error.NoFileProvided;
    };

    const abort_on_first_warning = args.flag("--abort-on-first-warning");
    const out = args.option("--output") orelse blk: {
        break :blk try fmt.allocPrint(allocator, "{}.modified", path.basename(file_name));
    };

    var game = blk: {
        var file = try fs.File.openRead(file_name);
        defer file.close();

        break :blk try gen3.Game.fromFile(file, allocator);
    };

    var line: usize = 1;
    var line_buf = try std.Buffer.initSize(allocator, 0);

    while (stdin.readUntilDelimiterBuffer(&line_buf, '\n', 10000)) : (line += 1) {
        apply(game, line, mem.trimRight(u8, line_buf.toSlice(), "\r\n")) catch |err| {
            debug.warn("(stdin):{}:1: warning: {}\n", line, @errorName(err));
            if (abort_on_first_warning)
                return err;
        };
        line_buf.shrink(0);
    } else |err| switch (err) {
        error.EndOfStream => {
            const str = mem.trim(u8, line_buf.toSlice(), " \t");
            if (str.len != 0)
                debug.warn("(stdin):{}:1: warning: none empty last line\n", line);
        },
        else => return err,
    }

    var out_file = try fs.File.openWrite(out);
    defer out_file.close();

    var out_stream = out_file.outStream();
    try game.writeToStream(&out_stream.stream);
}

fn apply(game: gen3.Game, line: usize, str: []const u8) !void {
    var parser = format.StrParser.init(str);

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
            const new = switch (value) {
                true => bits.set(u64, learnset.value(), @intCast(u6, tm_index)),
                false => bits.clear(u64, learnset.value(), @intCast(u6, tm_index)),
                else => unreachable,
            };
            learnset.* = lu64.init(new);
        } else |_| if (parser.eatField("hms")) {
            const hm_index = try parser.eatIndexMax(game.tms.len);
            const value = try parser.eatBoolValue();
            const learnset = &game.machine_learnsets[pokemon_index];
            const new = switch (value) {
                true => bits.set(u64, learnset.value(), @intCast(u6, hm_index + game.tms.len)),
                false => bits.clear(u64, learnset.value(), @intCast(u6, hm_index + game.tms.len)),
                else => unreachable,
            };
            learnset.* = lu64.init(new);
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
            fn applyArea(p: *format.StrParser, g: gen3.Game, area: var) !void {
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
