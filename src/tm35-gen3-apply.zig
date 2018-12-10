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
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const os = std.os;
const path = os.path;

const sscan = fun.scan.sscan;

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu64 = fun.platform.lu64;

const BufInStream = io.BufferedInStream(os.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(os.File.OutStream.Error);
const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = []Param{
    Param.flag(
        "abort execution on the first warning emitted",
        Names.long("abort-on-first-warning"),
    ),
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

pub fn main() !void {
    const unbuf_stdin = &(try std.io.getStdIn()).inStream().stream;
    var buf_stdin = BufInStream.init(unbuf_stdin);

    const stderr = &(try std.io.getStdErr()).outStream().stream;
    const stdout = &(try std.io.getStdOut()).outStream().stream;
    const stdin = &buf_stdin.stream;

    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    var arena = heap.ArenaAllocator.init(&direct_allocator.allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    const iter = &arg_iter.iter;
    _ = iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator.Error, iter) catch |err| {
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
        var file = try os.File.openRead(file_name);
        defer file.close();

        break :blk try gen3.Game.fromFile(file, allocator);
    };

    var line: usize = 1;
    var line_buf = try std.Buffer.initSize(allocator, 0);

    while (stdin.readUntilDelimiterBuffer(&line_buf, '\n', 10000)) : (line += 1) {
        apply(game, line, mem.trimRight(u8, line_buf.toSlice(), "\r\n")) catch |err| {
            warning(line, 1, "{}\n", @errorName(err));
            if (abort_on_first_warning)
                return err;
        };
        line_buf.shrink(0);
    } else |err| switch (err) {
        error.EndOfStream => {
            const str = mem.trim(u8, line_buf.toSlice(), " \t");
            if (str.len != 0)
                warning(line, 1, "none empty last line\n");
        },
        else => return err,
    }

    var out_file = try os.File.openWrite(out);
    defer out_file.close();

    var out_stream = out_file.outStream();
    try game.writeToStream(&out_stream.stream);
}

fn apply(game: gen3.Game, line: usize, str: []const u8) !void {
    var parser = format.StrParser.init(str);

    if (parser.eatStr(".version=")) |_| {
        const version = meta.stringToEnum(common.Version, parser.str) orelse return error.SyntaxError;
        if (version != game.version)
            return error.VersionDontMatch;
    } else |_| if (parser.eatStr(".game_title=")) {
        if (!mem.eql(u8, parser.str, game.header.game_title))
            return error.GameTitleDontMatch;
    } else |_| if (parser.eatStr(".gamecode=")) {
        if (!mem.eql(u8, parser.str, game.header.gamecode))
            return error.GameCodeDontMatch;
    } else |_| if (parser.eatStr(".trainers[")) |_| {
        const trainer_index = try parser.eatUnsignedMax(usize, 10, game.trainers.len);
        const trainer = &game.trainers[trainer_index];
        try parser.eatStr("].");

        if (parser.eatStr("class=")) |_| {
            trainer.class = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("encounter_music=")) |_| {
            trainer.encounter_music = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("trainer_picture=")) |_| {
            trainer.trainer_picture = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("items[")) |_| {
            const item_index = try parser.eatUnsignedMax(usize, 10, trainer.items.len);
            try parser.eatStr("]=");
            trainer.items[item_index] = lu16.init(try parser.eatUnsignedMax(u16, 10, game.items.len));
        } else |_| if (parser.eatStr("is_double=")) |_| {
            trainer.is_double = lu32.init(try parser.eatUnsigned(u32, 10));
        } else |_| if (parser.eatStr("ai=")) |_| {
            trainer.ai = lu32.init(try parser.eatUnsigned(u32, 10));
        } else |_| if (parser.eatStr("party[")) |_| {
            const party_index = try parser.eatUnsignedMax(usize, 10, trainer.partyLen());
            const member = try trainer.partyAt(party_index, game.data);
            try parser.eatStr("].");

            if (parser.eatStr("iv=")) |_| {
                member.iv = lu16.init(try parser.eatUnsigned(u16, 10));
            } else |_| if (parser.eatStr("level=")) |_| {
                member.level = lu16.init(try parser.eatUnsigned(u16, 10));
            } else |_| if (parser.eatStr("species=")) |_| {
                member.species = lu16.init(try parser.eatUnsignedMax(u16, 10, game.pokemons.len));
            } else |_| if (parser.eatStr("item=")) |_| {
                const item = try parser.eatUnsignedMax(u16, 10, game.items.len);
                switch (trainer.party_type) {
                    gen3.PartyType.Item => member.toParent(gen3.PartyMemberItem).item = lu16.init(item),
                    gen3.PartyType.Both => member.toParent(gen3.PartyMemberBoth).item = lu16.init(item),
                    else => return error.NoField,
                }
            } else |_| if (parser.eatStr("moves[")) |_| {
                const mv_ptr = switch (trainer.party_type) {
                    gen3.PartyType.Moves => blk: {
                        const move_member = member.toParent(gen3.PartyMemberMoves);
                        const move_index = try parser.eatUnsignedMax(usize, 10, move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    gen3.PartyType.Both => blk: {
                        const move_member = member.toParent(gen3.PartyMemberBoth);
                        const move_index = try parser.eatUnsignedMax(usize, 10, move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    else => return error.NoField,
                };

                try parser.eatStr("]=");
                mv_ptr.* = lu16.init(try parser.eatUnsignedMax(u16, 10, game.moves.len));
            } else |_| {
                return error.NoField;
            }
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatStr(".moves[")) |_| {
        const move_index = try parser.eatUnsignedMax(usize, 10, game.moves.len);
        const move = &game.moves[move_index];
        try parser.eatStr("].");

        if (parser.eatStr("effect=")) |_| {
            move.effect = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("power=")) |_| {
            move.power = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("type=")) |_| {
            move.@"type" = meta.stringToEnum(gen3.Type, parser.str) orelse return error.SyntaxError;
        } else |_| if (parser.eatStr("accuracy=")) |_| {
            move.accuracy = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("pp=")) |_| {
            move.pp = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("side_effect_chance=")) |_| {
            move.side_effect_chance = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("target=")) |_| {
            move.target = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("priority=")) |_| {
            move.priority = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("flags=")) |_| {
            move.flags = lu32.init(try parser.eatUnsigned(u32, 10));
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatStr(".pokemons[")) {
        const pokemon_index = try parser.eatUnsignedMax(usize, 10, game.pokemons.len);
        const pokemon = &game.pokemons[pokemon_index];
        try parser.eatStr("].");

        if (parser.eatStr("stats.hp=")) |_| {
            pokemon.stats.hp = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats.attack=")) |_| {
            pokemon.stats.attack = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats.defense=")) |_| {
            pokemon.stats.defense = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats.speed=")) |_| {
            pokemon.stats.speed = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats.sp_attack=")) |_| {
            pokemon.stats.sp_attack = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats.sp_defense=")) |_| {
            pokemon.stats.sp_defense = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("types[")) |_| {
            const type_index = try parser.eatUnsignedMax(usize, 10, pokemon.types.len);
            try parser.eatStr("]=");

            pokemon.types[type_index] = meta.stringToEnum(gen3.Type, parser.str) orelse return error.SyntaxError;
        } else |_| if (parser.eatStr("catch_rate=")) |_| {
            pokemon.catch_rate = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("base_exp_yield=")) |_| {
            pokemon.base_exp_yield = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("ev_yield.hp=")) |_| {
            pokemon.ev_yield.hp = try parser.eatUnsigned(u2, 10);
        } else |_| if (parser.eatStr("ev_yield.attack=")) |_| {
            pokemon.ev_yield.attack = try parser.eatUnsigned(u2, 10);
        } else |_| if (parser.eatStr("ev_yield.defense=")) |_| {
            pokemon.ev_yield.defense = try parser.eatUnsigned(u2, 10);
        } else |_| if (parser.eatStr("ev_yield.speed=")) |_| {
            pokemon.ev_yield.speed = try parser.eatUnsigned(u2, 10);
        } else |_| if (parser.eatStr("ev_yield.sp_attack=")) |_| {
            pokemon.ev_yield.sp_attack = try parser.eatUnsigned(u2, 10);
        } else |_| if (parser.eatStr("ev_yield.sp_defense=")) |_| {
            pokemon.ev_yield.sp_defense = try parser.eatUnsigned(u2, 10);
        } else |_| if (parser.eatStr("items[")) |_| {
            const item_index = try parser.eatUnsignedMax(usize, 10, pokemon.items.len);
            try parser.eatStr("]=");

            pokemon.items[item_index] = lu16.init(try parser.eatUnsignedMax(u16, 10, game.items.len));
        } else |_| if (parser.eatStr("gender_ratio=")) |_| {
            pokemon.gender_ratio = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("egg_cycles=")) |_| {
            pokemon.egg_cycles = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("base_friendship=")) |_| {
            pokemon.base_friendship = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("growth_rate=")) |_| {
            pokemon.growth_rate = meta.stringToEnum(common.GrowthRate, parser.str) orelse return error.SyntaxError;
        } else |_| if (parser.eatStr("egg_groups[")) |_| {
            const egg_index = try parser.eatUnsignedMax(usize, 10, 2);
            try parser.eatStr("]=");

            const egg_group = meta.stringToEnum(common.EggGroup, parser.str) orelse return error.SyntaxError;
            switch (egg_index) {
                0 => pokemon.egg_group1 = egg_group,
                1 => pokemon.egg_group2 = egg_group,
                else => return error.OutOfBound,
            }
        } else |_| if (parser.eatStr("abilities[")) |_| {
            const ability_index = try parser.eatUnsignedMax(usize, 10, pokemon.abilities.len);
            try parser.eatStr("]=");

            // TODO: Check on max number of abilities
            pokemon.abilities[ability_index] = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("safari_zone_rate=")) |_| {
            pokemon.safari_zone_rate = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("color=")) |_| {
            pokemon.color = meta.stringToEnum(common.Color, parser.str) orelse return error.SyntaxError;
        } else |_| if (parser.eatStr("flip=")) |_| {
            pokemon.flip = stringToBool(parser.str) orelse return error.SyntaxError;
        } else |_| if (parser.eatStr("tms[")) |_| {
            const tm_index = try parser.eatUnsignedMax(usize, 10, game.tms.len);
            try parser.eatStr("]=");

            const value = stringToBool(parser.str) orelse return error.SyntaxError;
            const learnset = &game.machine_learnsets[pokemon_index];
            const new = switch (value) {
                true => bits.set(u64, learnset.value(), @intCast(u6, tm_index)),
                false => bits.clear(u64, learnset.value(), @intCast(u6, tm_index)),
                else => unreachable,
            };
            learnset.* = lu64.init(new);
        } else |_| if (parser.eatStr("hms[")) |_| {
            const hm_index = try parser.eatUnsignedMax(usize, 10, game.tms.len);
            try parser.eatStr("]=");

            const value = stringToBool(parser.str) orelse return error.SyntaxError;
            const learnset = &game.machine_learnsets[pokemon_index];
            const new = switch (value) {
                true => bits.set(u64, learnset.value(), @intCast(u6, hm_index + game.tms.len)),
                false => bits.clear(u64, learnset.value(), @intCast(u6, hm_index + game.tms.len)),
                else => unreachable,
            };
            learnset.* = lu64.init(new);
        } else |_| if (parser.eatStr("evos[")) |_| {
            const evos = &game.evolutions[pokemon_index];
            const evo_index = try parser.eatUnsignedMax(usize, 10, evos.len);
            const evo = &evos[evo_index];
            try parser.eatStr("].");

            if (parser.eatStr("method=")) |_| {
                evo.method = meta.stringToEnum(common.Evolution.Method, parser.str) orelse return error.SyntaxError;
            } else |_| if (parser.eatStr("param=")) |_| {
                evo.param = lu16.init(try parser.eatUnsigned(u16, 10));
            } else |_| if (parser.eatStr("target=")) |_| {
                evo.target = lu16.init(try parser.eatUnsignedMax(u16, 10, game.pokemons.len));
            } else |_| {
                return error.NoField;
            }
        } else |_| if (parser.eatStr("moves[")) |_| {
            const lvl_up_moves = try game.level_up_learnset_pointers[pokemon_index].toMany(game.data);

            // TODO: Bounds check
            const lvl_up_index = try parser.eatUnsigned(usize, 10);
            const lvl_up_move = &lvl_up_moves[lvl_up_index];
            try parser.eatStr("].");

            if (parser.eatStr("id=")) |_| {
                lvl_up_move.id = try parser.eatUnsigned(u9, 10);
            } else |_| if (parser.eatStr("level=")) |_| {
                lvl_up_move.level = try parser.eatUnsigned(u7, 10);
            } else |_| {
                return error.NoField;
            }
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatStr(".tms[")) {
        const tm_index = try parser.eatUnsignedMax(usize, 10, game.tms.len);
        try parser.eatStr("]=");

        game.tms[tm_index] = lu16.init(try parser.eatUnsignedMax(u16, 10, game.moves.len));
    } else |_| if (parser.eatStr(".hms[")) {
        const tm_index = try parser.eatUnsignedMax(usize, 10, game.hms.len);
        try parser.eatStr("]=");

        game.hms[tm_index] = lu16.init(try parser.eatUnsignedMax(u16, 10, game.moves.len));
    } else |_| if (parser.eatStr(".items[")) {
        const item_index = try parser.eatUnsignedMax(usize, 10, game.items.len);
        const item = &game.items[item_index];
        try parser.eatStr("].");

        if (parser.eatStr("id=")) |_| {
            item.id = lu16.init(try parser.eatUnsigned(u16, 10));
        } else |_| if (parser.eatStr("price=")) |_| {
            item.price = lu16.init(try parser.eatUnsigned(u16, 10));
        } else |_| if (parser.eatStr("hold_effect=")) |_| {
            item.hold_effect = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("hold_effect_param=")) |_| {
            item.hold_effect_param = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("importance=")) |_| {
            item.importance = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("pocked=")) |_| {
            item.pocked = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("type=")) |_| {
            item.@"type" = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("battle_usage=")) |_| {
            item.battle_usage = lu32.init(try parser.eatUnsigned(u32, 10));
        } else |_| if (parser.eatStr("secondary_id=")) |_| {
            item.secondary_id = lu32.init(try parser.eatUnsigned(u32, 10));
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatStr(".zones[")) {
        const zone_index = try parser.eatUnsignedMax(usize, 10, game.wild_pokemon_headers.len);
        const header = &game.wild_pokemon_headers[zone_index];
        try parser.eatStr("].wild.");

        inline for ([][]const u8{
            "land",
            "surf",
            "rock_smash",
            "fishing",
        }) |area_name| {
            if (parser.eatStr(area_name ++ ".")) |_| {
                const area = try @field(header, area_name).toSingle(game.data);

                if (parser.eatStr("encounter_rate=")) |_| {
                    area.encounter_rate = try parser.eatUnsigned(u8, 10);
                } else |_| if (parser.eatStr("pokemons[")) |_| {
                    const wilds = try area.wild_pokemons.toSingle(game.data);
                    const wild_index = try parser.eatUnsignedMax(usize, 10, wilds.len);
                    const wild = &wilds[wild_index];
                    try parser.eatStr("].");

                    if (parser.eatStr("min_level=")) |_| {
                        wild.min_level = try parser.eatUnsigned(u8, 10);
                    } else |_| if (parser.eatStr("max_level=")) |_| {
                        wild.max_level = try parser.eatUnsigned(u8, 10);
                    } else |_| if (parser.eatStr("species=")) |_| {
                        wild.species = lu16.init(try parser.eatUnsignedMax(u16, 10, game.pokemons.len));
                    } else |_| {
                        return error.NoField;
                    }
                } else |_| {
                    return error.NoField;
                }
            } else |_| {}
        }
    } else |_| {
        return error.NoField;
    }
}

fn stringToBool(str: []const u8) ?bool {
    if (mem.eql(u8, "true", str))
        return true;
    if (mem.eql(u8, "false", str))
        return false;

    return null;
}

fn warning(line: usize, col: usize, comptime f: []const u8, a: ...) void {
    debug.warn("(stdin):{}:{}: warning: ", line, col);
    debug.warn(f, a);
}
