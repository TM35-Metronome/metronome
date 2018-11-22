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
    const str =
        \\Usage: tm35-gen3-apply [OPTION]... FILE
        \\Reads rom data from stdin and applies it to a generation 3 Pokemon rom.
        \\
        \\Options:
        \\
    ;

    try stream.write(str);
    try clap.help(stream, params);
}

var args: Clap = undefined;
var stderr: *io.OutStream(os.File.OutStream.Error) = undefined;
var stdout: *io.OutStream(os.File.OutStream.Error) = undefined;
var stdin: *io.InStream(os.File.InStream.Error) = undefined;
var allocator: *mem.Allocator = undefined;

pub fn main() u8 {
    const stdin_file = std.io.getStdIn() catch return 1;
    const stderr_file = std.io.getStdErr() catch return 1;
    const stdout_file = std.io.getStdOut() catch return 1;
    var stdin_in_stream = stdin_file.inStream();
    var stderr_out_stream = stderr_file.outStream();
    var stdout_out_stream = stdout_file.outStream();
    var buf_in_stream = io.BufferedInStream(os.File.InStream.Error).init(&stdin_in_stream.stream);

    stderr = &stderr_out_stream.stream;
    stdout = &stdout_out_stream.stream;
    stdin = &buf_in_stream.stream;

    var direct_allocator_state = std.heap.DirectAllocator.init();
    const direct_allocator = &direct_allocator_state.allocator;
    defer direct_allocator_state.deinit();

    // TODO: Other allocator?
    allocator = direct_allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    const iter = &arg_iter.iter;
    defer arg_iter.deinit();
    _ = iter.next() catch undefined;

    args = Clap.parse(allocator, clap.args.OsIterator.Error, iter) catch |err| {
        debug.warn("error: {}\n", err);
        usage(stderr) catch {};
        return 1;
    };
    defer args.deinit();

    main2() catch |err| {
        debug.warn("error: {}\n", err);
        return 1;
    };

    return 0;
}

pub fn main2() !void {
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
    while (readLine(stdin, &line_buf)) |str| : (line += 1) {
        var parser = Parser{
            .parser = format.Parser.init(format.Tokenizer.init(str)),
            .line = line,
        };
        parser.parse(game, str) catch {};
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

fn readLine(stream: var, buf: *std.Buffer) ![]u8 {
    while (true) {
        const byte = try stream.readByte();
        switch (byte) {
            '\n' => return buf.toSlice(),
            else => try buf.appendByte(byte),
        }
    }
}

const Parser = struct {
    parser: format.Parser,
    line: usize,

    fn parse(parser: *Parser, game: gen3.Game, str: []const u8) !void {
        @setEvalBranchQuota(100000);

        const tf = fun.match.StringSwitch([][]const u8{
            "version",
            "game_title",
            "gamecode",
            "trainers",
            "moves",
            "pokemons",
            "tms",
            "hms",
            "items",
            "zones",
        });

        const top_field_node = switch (parser.parser.next() orelse return) {
            format.Parser.Result.Ok => |node| node.Field,
            format.Parser.Result.Error => |err| return parser.reportSyntaxError(err),
        };

        switch (tf.match(top_field_node.ident.str)) {
            tf.case("version") => {
                const version = try parser.expectEnumValue(common.Version);

                if (version != game.version)
                    parser.warning(1, "Version '{}' differs from '{}'\n", @tagName(version), @tagName(game.version));
            },
            tf.case("game_title") => {
                const value = try parser.expect(format.Node.Kind.Value);
                const column = value.equal.index(str) + 1;

                if (!mem.eql(u8, value.value.str, game.header.game_title))
                    parser.warning(1, "Game title '{}' differs from '{}'\n", value.value.str, game.header.game_title);
            },
            tf.case("gamecode") => {
                const value = try parser.expect(format.Node.Kind.Value);
                const column = value.equal.index(str) + 1;

                if (!mem.eql(u8, value.value.str, game.header.gamecode))
                    parser.warning(column, "Gamecode '{}' differs from '{}'\n", value.value.str, game.header.gamecode);
            },
            tf.case("trainers") => {
                const trainer_index = try parser.expectIndex(usize, game.trainers.len);
                const trainer = &game.trainers[trainer_index];

                const trainer_field_node = try parser.expect(format.Node.Kind.Field);
                const trf = fun.match.StringSwitch([][]const u8{
                    "class",
                    "encounter_music",
                    "trainer_picture",
                    "items",
                    "is_double",
                    "ai",
                    "party",
                });

                switch (trf.match(trainer_field_node.ident.str)) {
                    trf.case("class") => trainer.class = try parser.expectIntValue(u8),
                    trf.case("encounter_music") => trainer.encounter_music = try parser.expectIntValue(u8),
                    trf.case("trainer_picture") => trainer.trainer_picture = try parser.expectIntValue(u8),
                    trf.case("items") => {
                        const item_index = try parser.expectIndex(usize, game.trainers[trainer_index].items.len);
                        const value = try parser.expectIntValue(u16);
                        trainer.items[item_index] = lu16.init(value);
                    },
                    trf.case("is_double") => trainer.is_double = lu32.init(try parser.expectIntValue(u32)),
                    trf.case("ai") => trainer.ai = lu32.init(try parser.expectIntValue(u32)),
                    trf.case("party") => {
                        const party_index = try parser.expectIndex(usize, trainer.party.Base.len());
                        const party_field_node = try parser.expect(format.Node.Kind.Field);
                        const pf = fun.match.StringSwitch([][]const u8{
                            "iv",
                            "level",
                            "species",
                            "items",
                            "item",
                            "moves",
                        });

                        switch (trainer.party_type) {
                            gen3.PartyType.Base => {
                                // TODO: Handle                                           VVVVVVVVVVV
                                const party = trainer.party.Base.toSlice(game.data) catch unreachable;
                                const member = &party[party_index];
                                switch (pf.match(party_field_node.ident.str)) {
                                    pf.case("iv") => member.iv = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("level") => member.level = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("species") => member.species = lu16.init(try parser.expectIntValue(u16)),
                                    else => return parser.reportNodeError(format.Node{.Field = party_field_node}),
                                }
                            },
                            gen3.PartyType.Item => {
                                // TODO: Handle                                           VVVVVVVVVVV
                                const party = trainer.party.Item.toSlice(game.data) catch unreachable;
                                const member = &party[party_index];
                                switch (pf.match(party_field_node.ident.str)) {
                                    pf.case("iv") => member.base.iv = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("level") => member.base.level = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("species") => member.base.species = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("item") => member.item = lu16.init(try parser.expectIntValue(u16)),
                                    else => return parser.reportNodeError(format.Node{.Field = party_field_node}),
                                }
                            },
                            gen3.PartyType.Moves => {
                                // TODO: Handle                                            VVVVVVVVVVV
                                const party = trainer.party.Moves.toSlice(game.data) catch unreachable;
                                const member = &party[party_index];
                                switch (pf.match(party_field_node.ident.str)) {
                                    pf.case("iv") => member.base.iv = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("level") => member.base.level = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("species") => member.base.species = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("moves") => {
                                        const move_index = try parser.expectIndex(usize, member.moves.len);
                                        member.moves[move_index] = lu16.init(try parser.expectIntValue(u16));
                                    },
                                    else => return parser.reportNodeError(format.Node{.Field = party_field_node}),
                                }
                            },
                            gen3.PartyType.Both => {
                                // TODO: Handle                                           VVVVVVVVVVV
                                const party = trainer.party.Both.toSlice(game.data) catch unreachable;
                                const member = &party[party_index];
                                switch (pf.match(party_field_node.ident.str)) {
                                    pf.case("iv") => member.base.iv = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("level") => member.base.level = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("species") => member.base.species = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("item") => member.item = lu16.init(try parser.expectIntValue(u16)),
                                    pf.case("moves") => {
                                        const move_index = try parser.expectIndex(usize, member.moves.len);
                                        member.moves[move_index] = lu16.init(try parser.expectIntValue(u16));
                                    },
                                    else => return parser.reportNodeError(format.Node{.Field = party_field_node}),
                                }
                            },
                        }
                    },
                    else => return parser.reportNodeError(format.Node{.Field = trainer_field_node}),
                }
            },
            tf.case("moves") => {
                const move_index = try parser.expectIndex(usize, game.moves.len);
                const move = &game.moves[move_index];

                const move_field_node = try parser.expect(format.Node.Kind.Field);
                const mf = fun.match.StringSwitch([][]const u8{
                    "effect",
                    "power",
                    "type",
                    "accuracy",
                    "pp",
                    "side_effect_chance",
                    "target",
                    "priority",
                    "flags",
                });

                switch (mf.match(move_field_node.ident.str)) {
                    mf.case("effect") => move.effect = try parser.expectIntValue(u8),
                    mf.case("power") => move.power = try parser.expectIntValue(u8),
                    mf.case("type") => move.@"type" = try parser.expectEnumValue(gen3.Type),
                    mf.case("accuracy") => move.accuracy = try parser.expectIntValue(u8),
                    mf.case("pp") => move.pp = try parser.expectIntValue(u8),
                    mf.case("side_effect_chance") => move.side_effect_chance = try parser.expectIntValue(u8),
                    mf.case("target") => move.target = try parser.expectIntValue(u8),
                    mf.case("priority") => move.priority = try parser.expectIntValue(u8),
                    mf.case("flags") => move.flags = lu32.init(try parser.expectIntValue(u32)),
                    else => return parser.reportNodeError(format.Node{.Field = move_field_node}),
                }
            },
            tf.case("pokemons") => {
                const pokemon_index = try parser.expectIndex(usize, game.base_stats.len);
                const pokemon = &game.base_stats[pokemon_index];

                const pokemon_field_node = try parser.expect(format.Node.Kind.Field);
                const pf = fun.match.StringSwitch([][]const u8{
                    "stats",
                    "types",
                    "catch_rate",
                    "base_exp_yield",
                    "ev_yield",
                    "items",
                    "gender_ratio",
                    "egg_cycles",
                    "base_friendship",
                    "growth_rate",
                    "egg_groups",
                    "abilities",
                    "safari_zone_rate",
                    "color",
                    "flip",
                    "tms",
                    "hms",
                    "evos",
                    "moves",
                });

                switch (pf.match(pokemon_field_node.ident.str)) {
                    pf.case("stats") => {
                        const stats_field_node = try parser.expect(format.Node.Kind.Field);
                        const sf = fun.match.StringSwitch([][]const u8{
                            "hp",
                            "attack",
                            "defense",
                            "speed",
                            "sp_attack",
                            "sp_defense",
                            "HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "1HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                        });

                        switch (sf.match(stats_field_node.ident.str)) {
                            sf.case("hp") => pokemon.stats.hp = try parser.expectIntValue(u8),
                            sf.case("attack") => pokemon.stats.attack = try parser.expectIntValue(u8),
                            sf.case("defense") => pokemon.stats.defense = try parser.expectIntValue(u8),
                            sf.case("speed") => pokemon.stats.speed = try parser.expectIntValue(u8),
                            sf.case("sp_attack") => pokemon.stats.sp_attack = try parser.expectIntValue(u8),
                            sf.case("sp_defense") => pokemon.stats.sp_defense = try parser.expectIntValue(u8),
                            else => return parser.reportNodeError(format.Node{.Field = stats_field_node}),
                        }
                    },
                    pf.case("types") => {
                        const type_index = try parser.expectIndex(usize, pokemon.types.len);
                        pokemon.types[type_index] = try parser.expectEnumValue(gen3.Type);
                    },
                    pf.case("catch_rate") => pokemon.catch_rate = try parser.expectIntValue(u8),
                    pf.case("base_exp_yield") => pokemon.base_exp_yield = try parser.expectIntValue(u8),
                    pf.case("ev_yield") => {
                        const ev_yield_node = try parser.expect(format.Node.Kind.Field);
                        const ef = fun.match.StringSwitch([][]const u8{
                            "hp",
                            "attack",
                            "defense",
                            "speed",
                            "sp_attack",
                            "sp_defense",
                            "HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "1HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "2HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "3HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "4HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                        });

                        switch (ef.match(ev_yield_node.ident.str)) {
                            // TODO: std.fmt.parseUnsigned can't parse u2
                            ef.case("hp") => pokemon.ev_yield.hp = @intCast(u2, try parser.expectIntValue(u8)),
                            ef.case("attack") => pokemon.ev_yield.attack = @intCast(u2, try parser.expectIntValue(u8)),
                            ef.case("defense") => pokemon.ev_yield.defense = @intCast(u2, try parser.expectIntValue(u8)),
                            ef.case("speed") => pokemon.ev_yield.speed = @intCast(u2, try parser.expectIntValue(u8)),
                            ef.case("sp_attack") => pokemon.ev_yield.sp_attack = @intCast(u2, try parser.expectIntValue(u8)),
                            ef.case("sp_defense") => pokemon.ev_yield.sp_defense = @intCast(u2, try parser.expectIntValue(u8)),
                            else => return parser.reportNodeError(format.Node{.Field = ev_yield_node}),
                        }
                    },
                    pf.case("items") => {
                        const item_index = try parser.expectIndex(usize, pokemon.items.len);
                        pokemon.items[item_index] = lu16.init(try parser.expectIntValue(u16));
                    },
                    pf.case("gender_ratio") => pokemon.gender_ratio = try parser.expectIntValue(u8),
                    pf.case("egg_cycles") => pokemon.egg_cycles = try parser.expectIntValue(u8),
                    pf.case("base_friendship") => pokemon.base_friendship = try parser.expectIntValue(u8),
                    pf.case("growth_rate") => pokemon.growth_rate = try parser.expectEnumValue(common.GrowthRate),
                    pf.case("egg_groups") => {
                        const egg_group_index = try parser.expectIndex(usize, 2);
                        switch (egg_group_index) {
                            0 => pokemon.egg_group1 = try parser.expectEnumValue(common.EggGroup),
                            1 => pokemon.egg_group2 = try parser.expectEnumValue(common.EggGroup),
                            else => unreachable,
                        }
                    },
                    pf.case("abilities") => {
                        const ability_index = try parser.expectIndex(usize, pokemon.abilities.len);
                        pokemon.abilities[ability_index] = try parser.expectIntValue(u8);
                    },
                    pf.case("safari_zone_rate") => pokemon.safari_zone_rate = try parser.expectIntValue(u8),
                    pf.case("color") => pokemon.color = try parser.expectEnumValue(common.Color),
                    pf.case("flip") => pokemon.flip = try parser.expectBoolValue(),
                    pf.case("tms") => {
                        const learnset = &game.machine_learnsets[pokemon_index];
                        const tm_index = try parser.expectIndex(usize, game.tms.len);
                        const value = try parser.expectBoolValue();
                        const new = switch (value) {
                            true => bits.set(u64, learnset.value(), @intCast(u6, tm_index)),
                            false => bits.clear(u64, learnset.value(), @intCast(u6, tm_index)),
                            else => unreachable,
                        };
                        learnset.* = lu64.init(new);
                    },
                    pf.case("hms") => {
                        const learnset = &game.machine_learnsets[pokemon_index];
                        const hm_index = try parser.expectIndex(usize, game.hms.len);
                        const value = try parser.expectBoolValue();
                        const new = switch (value) {
                            true => bits.set(u64, learnset.value(), @intCast(u6, hm_index + game.tms.len)),
                            false => bits.clear(u64, learnset.value(), @intCast(u6, hm_index + game.tms.len)),
                            else => unreachable,
                        };
                        learnset.* = lu64.init(new);
                    },
                    pf.case("evos") => {
                        const evos = &game.evolutions[pokemon_index];
                        const evo_index = try parser.expectIndex(usize, evos.len);

                        const evo_field_node = try parser.expect(format.Node.Kind.Field);
                        const ef = fun.match.StringSwitch([][]const u8{
                            "method",
                            "param",
                            "target",
                        });

                        switch (ef.match(evo_field_node.ident.str)) {
                            ef.case("method") => evos[evo_index].method = try parser.expectEnumValue(common.Evolution.Method),
                            ef.case("param") => evos[evo_index].param = lu16.init(try parser.expectIntValue(u16)),
                            ef.case("target") => evos[evo_index].target = lu16.init(try parser.expectIntValue(u16)),
                            else => return parser.reportNodeError(format.Node{.Field = evo_field_node}),
                        }
                    },
                    pf.case("moves") => {
                        // TODO: Handle                                                                         VVVVVVVVVVV
                        const learnset = game.level_up_learnset_pointers[pokemon_index].toMany(game.data) catch unreachable;
                        var len: usize = 0;

                        // UNSAFE: Bounds check on game data
                        while (learnset[len].id != math.maxInt(u9) or learnset[len].level != math.maxInt(u7)) : (len += 1) { }

                        const move_index = try parser.expectIndex(usize, len);

                        const move_field_node = try parser.expect(format.Node.Kind.Field);
                        const mf = fun.match.StringSwitch([][]const u8{
                            "id",
                            "level",
                            "HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "1HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "2HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "3HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "4HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "5HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "6HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "7HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "8HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "9HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                        });

                        switch (mf.match(move_field_node.ident.str)) {
                            mf.case("id") => learnset[move_index].id = try parser.expectIntValue(u9),
                            // TODO: std.fmt.parseUnsigned can't parse u7
                            mf.case("level") => learnset[move_index].level = @intCast(u7, try parser.expectIntValue(u8)),
                            else => return parser.reportNodeError(format.Node{.Field = move_field_node}),
                        }
                    },
                    else => return parser.reportNodeError(format.Node{.Field = pokemon_field_node}),
                }
            },
            tf.case("tms") => {
                const tm_index = try parser.expectIndex(usize, game.tms.len);
                game.tms[tm_index] = lu16.init(try parser.expectIntValue(u16));
            },
            tf.case("hms") => {
                const hm_index = try parser.expectIndex(usize, game.hms.len);
                game.hms[hm_index] = lu16.init(try parser.expectIntValue(u16));
            },
            tf.case("items") => {
                const item_index = try parser.expectIndex(usize, game.items.len);
                const item = &game.items[item_index];

                const item_field_node = try parser.expect(format.Node.Kind.Field);
                const itf = fun.match.StringSwitch([][]const u8{
                    "id",
                    "price",
                    "hold_effect",
                    "hold_effect_param",
                    "importance",
                    "pocked",
                    "type",
                    "battle_usage",
                    "secondary_id",
                    "HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                    "1HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                    "2HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                    "3HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                    "4HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                    "5HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                    "6HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                    "7HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                    "8HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                    "9HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                    "10HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                });

                switch (itf.match(item_field_node.ident.str)) {
                    itf.case("id") => item.id = lu16.init(try parser.expectIntValue(u16)),
                    itf.case("price") => item.price = lu16.init(try parser.expectIntValue(u16)),
                    itf.case("hold_effect") => item.hold_effect = try parser.expectIntValue(u8),
                    itf.case("hold_effect_param") => item.hold_effect_param = try parser.expectIntValue(u8),
                    itf.case("importance") => item.importance = try parser.expectIntValue(u8),
                    itf.case("pocked") => item.pocked = try parser.expectIntValue(u8),
                    itf.case("type") => item.@"type" = try parser.expectIntValue(u8),
                    itf.case("battle_usage") => item.battle_usage = lu32.init(try parser.expectIntValue(u32)),
                    itf.case("secondary_id") => item.secondary_id = lu32.init(try parser.expectIntValue(u32)),
                    else => return parser.reportNodeError(format.Node{.Field = item_field_node}),
                }
            },
            tf.case("zones") => {
                const zone_index = try parser.expectIndex(usize, game.wild_pokemon_headers.len);
                const header = game.wild_pokemon_headers[zone_index];

                const zone_field_node = try parser.expect(format.Node.Kind.Field);
                const zf = fun.match.StringSwitch([][]const u8{
                    "wild",
                });

                // TODO: This nesting is pretty deep. Maybe we should refactor some of this parse
                //       func into smaller funcs
                switch (zf.match(zone_field_node.ident.str)) {
                    zf.case("wild") => {
                        const wild_field_node = try parser.expect(format.Node.Kind.Field);
                        const areas = [][]const u8{
                            "land",
                            "surf",
                            "rock_smash",
                            "fishing",
                        };

                        const wf = fun.match.StringSwitch(areas);
                        const match = wf.match(wild_field_node.ident.str);
                        done: {
                            inline for (areas) |area_name| {
                                skip: {
                                    if (wf.case(area_name) != match)
                                        break :skip;

                                    const area = @field(header, area_name).toSingle(game.data) catch break :skip;
                                    const area_field_node = try parser.expect(format.Node.Kind.Field);
                                    const af = fun.match.StringSwitch([][]const u8{
                                        "encounter_rate",
                                        "pokemons",
                                        "HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                        "1HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                        "2HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                        "3HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                        "4HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                        "5HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                        "6HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                        "7HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                        "8HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                        "9HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                        "10HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                    });

                                    switch (af.match(area_field_node.ident.str)) {
                                        af.case("encounter_rate") => area.encounter_rate = try parser.expectIntValue(u8),
                                        af.case("pokemons") => {
                                            // TODO: Handle                                               VVVVVVVVVVV
                                            const pokemons = area.wild_pokemons.toSingle(game.data) catch unreachable;
                                            const pokemon_index = try parser.expectIndex(usize, pokemons.len);
                                            const pokemon = &pokemons[pokemon_index];

                                            const pokemon_field_node = try parser.expect(format.Node.Kind.Field);
                                            const pf = fun.match.StringSwitch([][]const u8{
                                                "min_level",
                                                "max_level",
                                                "species",
                                                "HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                                "1HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                                "2HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                                "3HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                                "4HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                                "5HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                                "6HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                                "7HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                                "8HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                                "9HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                                "10HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                                            });

                                            switch (pf.match(pokemon_field_node.ident.str)) {
                                                pf.case("min_level") => pokemon.min_level = try parser.expectIntValue(u8),
                                                pf.case("max_level") => pokemon.max_level = try parser.expectIntValue(u8),
                                                pf.case("species") => pokemon.species = lu16.init(try parser.expectIntValue(u16)),
                                                else => return parser.reportNodeError(format.Node{.Field = pokemon_field_node}),
                                            }
                                        },
                                        else => return parser.reportNodeError(format.Node{.Field = area_field_node}),
                                    }

                                    break :done;
                                }
                            }

                            return parser.reportNodeError(format.Node{.Field = wild_field_node});
                        }
                    },
                    else => return parser.reportNodeError(format.Node{.Field = zone_field_node}),
                }
            },
            else => return parser.reportNodeError(format.Node{.Field = top_field_node})
        }
    }

    fn expect(parser: *Parser, comptime kind: format.Node.Kind) !@field(format.Node, @tagName(kind)) {
        switch (parser.parser.next().?) {
            format.Parser.Result.Ok => |node| switch (node) {
                kind => |res| return res,
                else => {
                    parser.reportNodeError(node);
                    return error.InvalidNode;
                },
            },
            format.Parser.Result.Error => |err| {
                parser.reportSyntaxError(err);
                return error.SyntaxError;
            }
        }
    }

    fn expectIndex(parser: *Parser, comptime Int: type, bound: Int) !Int {
        const index_node = try parser.expect(format.Node.Kind.Index);
        return try parser.parseInt(Int, bound, index_node.int);
    }

    fn expectIntValue(parser: *Parser, comptime Int: type) !Int {
        const value_node = try parser.expect(format.Node.Kind.Value);
        return try parser.parseInt(Int, math.maxInt(Int), value_node.value);
    }

    fn expectEnumValue(parser: *Parser, comptime Enum: type) !Enum {
        const value_node = try parser.expect(format.Node.Kind.Value);
        const token = value_node.value;
        const value = mem.trim(u8, token.str, "\t ");

        return stringToEnum(Enum, value) orelse {
            const fields = @typeInfo(Enum).Enum.fields;
            const column = token.index(parser.parser.tok.str) + 1;
            parser.warning(column, "expected ");

            inline for (fields) |field, i| {
                const rev_i = (fields.len - 1) - i;
                debug.warn("'{}'", field.name);
                if (rev_i == 1)
                    debug.warn(" or ");
                if (rev_i > 1)
                    debug.warn(", ");
            }

            debug.warn(" found '{}'\n", value);
            return error.NotInEnum;
        };
    }

    fn expectBoolValue(parser: *Parser) !bool {
        const value_node = try parser.expect(format.Node.Kind.Value);
        const bs = fun.match.StringSwitch([][]const u8{
            "true",
            "false",
        });

        return switch (bs.match(value_node.value.str)) {
            bs.case("true") => true,
            bs.case("false") => false,
            else => {
                const column = value_node.value.index(parser.parser.tok.str) + 1;
                parser.warning(column, "expected 'true' or 'false' found {}", value_node.value.str);
                return error.NotBool;
            }
        };
    }

    fn parseInt(parser: *const Parser, comptime Int: type, bound: Int, token: format.Token) !Int {
        const column = token.index(parser.parser.tok.str) + 1;
        const str = mem.trim(u8, token.str, "\t ");
        overflow: {
            return fmt.parseUnsigned(Int, str, 10) catch |err| {
                switch (err) {
                    error.Overflow => break :overflow,
                    error.InvalidCharacter => {
                        parser.warning(column, "{} is not an number", str);
                        return err;
                    },
                }
            };
        }

        parser.warning(column, "{} is not within the bound {}", str, bound);
        return error.Overflow;
    }

    fn reportNodeError(parser: *const Parser, node: format.Node) void {
        const first = node.first();
        const i = first.index(parser.parser.tok.str);
        var tok = format.Tokenizer.init(parser.parser.tok.str[0..i]);

        parser.warning(i + 1, "'");
        while (tok.next()) |token|
            debug.warn("{}", token.str);

        debug.warn("' ");
        switch (node) {
            format.Node.Kind.Field => |field| debug.warn("does not have field '{}'\n", field.ident.str),
            format.Node.Kind.Index => |index| debug.warn("cannot be indexed at '{}'\n", index.int.str),
            format.Node.Kind.Value => |value| debug.warn("cannot be set to '{}'\n", value.value.str),
        }
    }

    fn reportSyntaxError(parser: *const Parser, err: format.Parser.Error) void {
        parser.warning(err.found.index(parser.parser.tok.str), "expected ");
        for (err.expected) |id, i| {
            const rev_i = (err.expected.len - 1) - i;
            debug.warn("{}", id.str());
            if (rev_i == 1)
                debug.warn(" or ");
            if (rev_i > 1)
                debug.warn(", ");
        }

        debug.warn(" found {}", err.found.str);
    }

    fn warning(parser: *const Parser, col: usize, comptime f: []const u8, a: ...) void {
        debug.warn("(stdin):{}:{}: warning: ", parser.line, col);
        debug.warn(f, a);
    }
};

fn stringToEnum(comptime Enum: type, str: []const u8) ?Enum {
    inline for (@typeInfo(Enum).Enum.fields) |field| {
        if (mem.eql(u8, field.name, str))
            return @field(Enum, field.name);
    }

    return null;
}
