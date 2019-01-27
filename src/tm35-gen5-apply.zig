const clap = @import("zig-clap");
const common = @import("tm35-common");
const format = @import("tm35-format");
const fun = @import("fun-with-zig");
const gen5 = @import("gen5-types.zig");
const nds = @import("tm35-nds");
const offsets = @import("gen5-offsets.zig");
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
const slice = fun.generic.slice;

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu64 = fun.platform.lu64;
const lu128 = fun.platform.lu128;

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
        \\Usage: tm35-gen5-apply [OPTION]... FILE
        \\Reads the tm35 format from stdin and applies it to a generation 5 Pokemon rom.
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
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const file_name = if (args.positionals().len > 0) args.positionals()[0] else {
        debug.warn("No file provided");
        return try usage(stderr);
    };

    const abort_on_first_warning = args.flag("--abort-on-first-warning");
    const out = args.option("--output") orelse blk: {
        break :blk try fmt.allocPrint(allocator, "{}.modified", path.basename(file_name));
    };

    var rom = blk: {
        var file = os.File.openRead(file_name) catch |err| {
            debug.warn("Couldn't open {}.\n", file_name);
            return err;
        };
        defer file.close();

        break :blk try nds.Rom.fromFile(file, allocator);
    };

    const game = try gen5.Game.fromRom(allocator, rom);

    var line: usize = 1;
    var line_buf = try std.Buffer.initSize(allocator, 0);

    while (stdin.readUntilDelimiterBuffer(&line_buf, '\n', 10000)) : (line += 1) {
        apply(rom, game, line, mem.trimRight(u8, line_buf.toSlice(), "\r\n")) catch |err| {
            debug.warn("(stdin):{}:1: warning: {}\n", line, @errorName(err));
            if (abort_on_first_warning)
                return err;
        };
        line_buf.shrink(0);
    } else |err| switch (err) {
        error.EndOfStream => {
            const str = mem.trim(u8, line_buf.toSlice(), " \t");
            if (str.len != 0)
                debug.warn("(stdin):{}:1: warning: {}\n", line, @errorName(err));
        },
        else => return err,
    }

    var out_file = os.File.openWrite(out) catch |err| {
        debug.warn("Couldn't open {}\n", out);
        return err;
    };
    defer out_file.close();
    try rom.writeToFile(out_file);
}

fn apply(rom: nds.Rom, game: gen5.Game, line: usize, str: []const u8) !void {
    var parser = format.StrParser.init(str);

    if (parser.eatField("version")) {
        const version = try parser.eatEnumValue(common.Version);
        if (version != game.version)
            return error.VersionDontMatch;
    } else |_| if (parser.eatField("game_title")) {
        const value = try parser.eatValue();
        const null_index = mem.indexOfScalar(u8, rom.header.game_title, 0) orelse rom.header.game_title.len;
        if (!mem.eql(u8, value, rom.header.game_title[0..null_index]))
            return error.GameTitleDontMatch;
    } else |_| if (parser.eatField("gamecode")) {
        const value = try parser.eatValue();
        if (!mem.eql(u8, value, rom.header.gamecode))
            return error.GameCodeDontMatch;
    } else |_| if (parser.eatField("starters")) {
        const starter_index = try parser.eatIndexMax(game.starters.len);
        const value = lu16.init(try parser.eatUnsignedValue(u16, 10));
        for (game.starters[starter_index]) |starter|
            starter.* = value;
    } else |_| if (parser.eatField("trainers")) {
        const trainers = game.trainers.nodes.toSlice();
        const trainer_index = try parser.eatIndexMax(trainers.len);
        const trainer = try nodeAsType(gen5.Trainer, trainers[trainer_index]);

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
            const party_file = try nodeAsFile(parties[trainer_index]);
            const member = getMemberBase(trainer.party_type, party_file.data, party_index) orelse return error.OutOfBound;

            if (parser.eatField("iv")) {
                member.iv = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("gender")) {
                member.gender = try parser.eatUnsignedValue(u4, 10);
            } else |_| if (parser.eatField("ability")) {
                member.ability = try parser.eatUnsignedValue(u4, 10);
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
        const move = try nodeAsType(gen5.Move, moves[move_index]);

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
        } else |_| if (parser.eatField("hits")) {
            move.hits = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("min_hits")) {
            move.min_hits = try parser.eatUnsignedValue(u4, 10);
        } else |_| if (parser.eatField("max_hits")) {
            move.max_hits = try parser.eatUnsignedValue(u4, 10);
        } else |_| if (parser.eatField("crit_chance")) {
            move.crit_chance = try parser.eatUnsignedValue(u8, 10);
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
        const pokemon = try nodeAsType(gen5.BasePokemon, pokemons[pokemon_index]);

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
            const new = switch (value) {
                true => bits.set(u128, learnset.value(), @intCast(u7, real_index)),
                false => bits.clear(u128, learnset.value(), @intCast(u7, real_index)),
                else => unreachable,
            };
            learnset.* = lu128.init(new);
        } else |_| if (parser.eatField("hms")) {
            const hm_index = try parser.eatIndexMax(game.hms.len);
            const value = try parser.eatBoolValue();
            const learnset = &pokemon.machine_learnset;
            const new = switch (value) {
                true => bits.set(u128, learnset.value(), @intCast(u7, hm_index + game.tms1.len)),
                false => bits.clear(u128, learnset.value(), @intCast(u7, hm_index + game.tms1.len)),
                else => unreachable,
            };
            learnset.* = lu128.init(new);
        } else |_| if (parser.eatField("evos")) {
            const evos_file = try nodeAsFile(game.evolutions.nodes.toSlice()[pokemon_index]);
            const evos = slice.bytesToSliceTrim(gen5.Evolution, evos_file.data);
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
    } else |_| if (parser.eatField("zones")) done: {
        const wild_pokemons = game.wild_pokemons.nodes.toSlice();
        const zone_index = try parser.eatIndexMax(wild_pokemons.len);
        const wilds = try nodeAsType(gen5.WildPokemons, wild_pokemons[zone_index]);
        try parser.eatField("wild");

        inline for ([][]const u8{
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
                break :done;
            } else |_| if (parser.eatField("pokemons")) {
                const area = &@field(wilds, area_name);
                const wild_index = try parser.eatIndexMax(area.len);
                const wild = &area[wild_index];

                if (parser.eatField("min_level")) {
                    wild.min_level = try parser.eatUnsignedValue(u8, 10);
                } else |_| if (parser.eatField("max_level")) {
                    wild.max_level = try parser.eatUnsignedValue(u8, 10);
                } else |_| if (parser.eatField("species")) {
                    wild.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
                } else |_| if (parser.eatField("form")) {
                    wild.species.setForm(try parser.eatUnsignedValue(u6, 10));
                } else |_| {
                    return error.NoField;
                }
                break :done;
            } else |_| {}
        }

        return error.NoField;
    } else |_| {
        return error.NoField;
    }
}

fn nodeAsFile(node: nds.fs.Narc.Node) !*nds.fs.Narc.File {
    switch (node.kind) {
        nds.fs.Narc.Node.Kind.File => |file| return file,
        nds.fs.Narc.Node.Kind.Folder => return error.NotFile,
    }
}

fn nodeAsType(comptime T: type, node: nds.fs.Narc.Node) !*T {
    const file = try nodeAsFile(node);
    const data = slice.bytesToSliceTrim(T, file.data);
    return slice.at(data, 0) catch error.FileToSmall;
}

fn getMemberBase(party_type: gen5.PartyType, data: []u8, i: usize) ?*gen5.PartyMemberBase {
    return switch (party_type) {
        gen5.PartyType.None => &(getMember(gen5.PartyMemberNone, data, i) orelse return null).base,
        gen5.PartyType.Item => &(getMember(gen5.PartyMemberItem, data, i) orelse return null).base,
        gen5.PartyType.Moves => &(getMember(gen5.PartyMemberMoves, data, i) orelse return null).base,
        gen5.PartyType.Both => &(getMember(gen5.PartyMemberBoth, data, i) orelse return null).base,
    };
}

fn getMember(comptime T: type, data: []u8, i: usize) ?*T {
    const party = slice.bytesToSliceTrim(T, data);
    if (party.len <= i)
        return null;

    return &party[i];
}
