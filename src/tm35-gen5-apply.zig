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
    const iter = &arg_iter.iter;
    _ = iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator.Error, iter) catch |err| {
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

    var out_file = os.File.openWrite(out) catch |err| {
        debug.warn("Couldn't open {}\n", out);
        return err;
    };
    defer out_file.close();
    try rom.writeToFile(out_file);
}

fn apply(rom: nds.Rom, game: gen5.Game, line: usize, str: []const u8) !void {
    var parser = format.StrParser.init(str);

    if (parser.eatStr(".version=")) {
        const version = meta.stringToEnum(common.Version, parser.str) orelse return error.SyntaxError;
        if (version != game.version)
            return error.VersionDontMatch;
    } else |_| if (parser.eatStr(".game_title=")) {
        const null_index = mem.indexOfScalar(u8, rom.header.game_title, 0) orelse rom.header.game_title.len;
        if (!mem.eql(u8, parser.str, rom.header.game_title[0..null_index]))
            return error.GameTitleDontMatch;
    } else |_| if (parser.eatStr(".gamecode=")) {
        if (!mem.eql(u8, parser.str, rom.header.gamecode))
            return error.GameCodeDontMatch;
    } else |_| if (parser.eatStr(".starters[")) {
        const starter_index = try parser.eatUnsignedMax(usize, 10, game.starters.len);
        try parser.eatStr("]=");
        const value = lu16.init(try parser.eatUnsigned(u16, 10));
        for (game.starters[starter_index]) |starter|
            starter.* = value;
    } else |_| if (parser.eatStr(".trainers[")) {
        const trainers = game.trainers.nodes.toSlice();
        const trainer_index = try parser.eatUnsignedMax(usize, 10, trainers.len);
        const trainer = try nodeAsType(gen5.Trainer, trainers[trainer_index]);
        try parser.eatStr("].");

        if (parser.eatStr("class=")) {
            trainer.class = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("battle_type=")) {
            trainer.battle_type = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("items[")) {
            const item_index = try parser.eatUnsignedMax(usize, 10, trainer.items.len);
            try parser.eatStr("]=");

            trainer.items[item_index] = lu16.init(try parser.eatUnsigned(u16, 10));
        } else |_| if (parser.eatStr("ai=")) {
            trainer.ai = lu32.init(try parser.eatUnsigned(u32, 10));
        } else |_| if (parser.eatStr("is_healer=")) {
            trainer.healer = stringToBool(parser.str) orelse return error.OutOfBound;
        } else |_| if (parser.eatStr("cash=")) {
            trainer.cash = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("post_battle_item=")) {
            trainer.post_battle_item = lu16.init(try parser.eatUnsigned(u16, 10));
        } else |_| if (parser.eatStr("party[")) {
            const parties = game.parties.nodes.toSlice();
            const party_index = try parser.eatUnsignedMax(usize, 10, trainer.party_size);
            const party_file = try nodeAsFile(parties[trainer_index]);
            const member = getMemberBase(trainer.party_type, party_file.data, party_index) orelse return error.OutOfBound;
            try parser.eatStr("].");

            if (parser.eatStr("iv=")) {
                member.iv = try parser.eatUnsigned(u8, 10);
            } else |_| if (parser.eatStr("gender=")) {
                member.gender = try parser.eatUnsigned(u4, 10);
            } else |_| if (parser.eatStr("ability=")) {
                member.ability = try parser.eatUnsigned(u4, 10);
            } else |_| if (parser.eatStr("level=")) {
                member.level = try parser.eatUnsigned(u8, 10);
            } else |_| if (parser.eatStr("species=")) {
                member.species = lu16.init(try parser.eatUnsignedMax(u16, 10, game.pokemons.nodes.len));
            } else |_| if (parser.eatStr("form=")) {
                member.form = lu16.init(try parser.eatUnsigned(u16, 10));
            } else |_| if (parser.eatStr("item=")) {
                const item = try parser.eatUnsigned(u16, 10);
                switch (trainer.party_type) {
                    gen5.PartyType.Item => member.toParent(gen5.PartyMemberItem).item = lu16.init(item),
                    gen5.PartyType.Both => member.toParent(gen5.PartyMemberBoth).item = lu16.init(item),
                    else => return error.NoField,
                }
            } else |_| if (parser.eatStr("moves[")) {
                const mv_ptr = switch (trainer.party_type) {
                    gen5.PartyType.Moves => blk: {
                        const move_member = member.toParent(gen5.PartyMemberMoves);
                        const move_index = try parser.eatUnsignedMax(usize, 10, move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    gen5.PartyType.Both => blk: {
                        const move_member = member.toParent(gen5.PartyMemberBoth);
                        const move_index = try parser.eatUnsignedMax(usize, 10, move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    else => return error.NoField,
                };

                try parser.eatStr("]=");
                mv_ptr.* = lu16.init(try parser.eatUnsignedMax(u16, 10, game.moves.nodes.len));
            } else |_| {
                return error.NoField;
            }
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatStr(".moves[")) {
        const moves = game.moves.nodes.toSlice();
        const move_index = try parser.eatUnsignedMax(usize, 10, moves.len);
        const move = try nodeAsType(gen5.Move, moves[move_index]);
        try parser.eatStr("].");

        if (parser.eatStr("type=")) {
            move.@"type" = meta.stringToEnum(gen5.Type, parser.str) orelse return error.SyntaxError;
        } else |_| if (parser.eatStr("effect_category=")) {
            move.effect_category = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("category=")) {
            move.category = meta.stringToEnum(common.MoveCategory, parser.str) orelse return error.SyntaxError;
        } else |_| if (parser.eatStr("power=")) {
            move.power = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("accuracy=")) {
            move.accuracy = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("pp=")) {
            move.pp = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("priority=")) {
            move.priority = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("hits=")) {
            move.hits = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("min_hits=")) {
            move.min_hits = try parser.eatUnsigned(u4, 10);
        } else |_| if (parser.eatStr("max_hits=")) {
            move.max_hits = try parser.eatUnsigned(u4, 10);
        } else |_| if (parser.eatStr("crit_chance=")) {
            move.crit_chance = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("flinch=")) {
            move.flinch = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("effect=")) {
            move.effect = lu16.init(try parser.eatUnsigned(u16, 10));
        } else |_| if (parser.eatStr("target_hp=")) {
            move.target_hp = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("user_hp=")) {
            move.user_hp = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("target=")) {
            move.target = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats_affected[")) {
            const status_index = try parser.eatUnsignedMax(usize, 10, move.stats_affected.len);
            try parser.eatStr("]=");

            move.stats_affected[status_index] = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats_affected_magnetude[")) {
            const status_index = try parser.eatUnsignedMax(usize, 10, move.stats_affected_magnetude.len);
            try parser.eatStr("]=");

            move.stats_affected_magnetude[status_index] = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats_affected_chance[")) {
            const status_index = try parser.eatUnsignedMax(usize, 10, move.stats_affected_chance.len);
            try parser.eatStr("]=");

            move.stats_affected_chance[status_index] = try parser.eatUnsigned(u8, 10);
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatStr(".pokemons[")) {
        const pokemons = game.pokemons.nodes.toSlice();
        const pokemon_index = try parser.eatUnsignedMax(usize, 10, pokemons.len);
        const pokemon = try nodeAsType(gen5.BasePokemon, pokemons[pokemon_index]);
        try parser.eatStr("].");

        if (parser.eatStr("stats.hp=")) {
            pokemon.stats.hp = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats.attack=")) {
            pokemon.stats.attack = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats.defense=")) {
            pokemon.stats.defense = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats.speed=")) {
            pokemon.stats.speed = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats.sp_attack=")) {
            pokemon.stats.sp_attack = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("stats.sp_defense=")) {
            pokemon.stats.sp_defense = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("types[")) {
            const type_index = try parser.eatUnsignedMax(usize, 10, pokemon.types.len);
            try parser.eatStr("]=");

            pokemon.types[type_index] = meta.stringToEnum(gen5.Type, parser.str) orelse return error.SyntaxError;
        } else |_| if (parser.eatStr("catch_rate=")) {
            pokemon.catch_rate = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("items[")) {
            const item_index = try parser.eatUnsignedMax(usize, 10, pokemon.items.len);
            try parser.eatStr("]=");

            pokemon.items[item_index] = lu16.init(try parser.eatUnsigned(u16, 10));
        } else |_| if (parser.eatStr("gender_ratio=")) {
            pokemon.gender_ratio = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("egg_cycles=")) {
            pokemon.egg_cycles = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("base_friendship=")) {
            pokemon.base_friendship = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("growth_rate=")) {
            pokemon.growth_rate = meta.stringToEnum(common.GrowthRate, parser.str) orelse return error.SyntaxError;
        } else |_| if (parser.eatStr("egg_groups[")) {
            const egg_index = try parser.eatUnsignedMax(usize, 10, 2);
            try parser.eatStr("]=");

            const egg_group = meta.stringToEnum(common.EggGroup, parser.str) orelse return error.SyntaxError;
            switch (egg_index) {
                0 => pokemon.egg_group1 = egg_group,
                1 => pokemon.egg_group2 = egg_group,
                else => return error.OutOfBound,
            }
        } else |_| if (parser.eatStr("abilities[")) {
            const ability_index = try parser.eatUnsignedMax(usize, 10, pokemon.abilities.len);
            try parser.eatStr("]=");

            // TODO: Check on max number of abilities
            pokemon.abilities[ability_index] = try parser.eatUnsigned(u8, 10);
        } else |_| if (parser.eatStr("color=")) {
            pokemon.color = meta.stringToEnum(common.Color, parser.str) orelse return error.SyntaxError;
        } else |_| if (parser.eatStr("height=")) {
            pokemon.height = lu16.init(try parser.eatUnsigned(u16, 10));
        } else |_| if (parser.eatStr("weight=")) {
            pokemon.weight = lu16.init(try parser.eatUnsigned(u16, 10));
        } else |_| if (parser.eatStr("tms[")) {
            const tm_index = try parser.eatUnsignedMax(usize, 10, game.tms1.len + game.tms2.len);
            try parser.eatStr("]=");

            const real_index = if (tm_index < game.tms1.len) tm_index else tm_index + game.hms.len;

            const value = stringToBool(parser.str) orelse return error.SyntaxError;
            const learnset = &pokemon.machine_learnset;
            const new = switch (value) {
                true => bits.set(u128, learnset.value(), @intCast(u7, real_index)),
                false => bits.clear(u128, learnset.value(), @intCast(u7, real_index)),
                else => unreachable,
            };
            learnset.* = lu128.init(new);
        } else |_| if (parser.eatStr("hms[")) {
            const hm_index = try parser.eatUnsignedMax(usize, 10, game.hms.len);
            try parser.eatStr("]=");

            const value = stringToBool(parser.str) orelse return error.SyntaxError;
            const learnset = &pokemon.machine_learnset;
            const new = switch (value) {
                true => bits.set(u128, learnset.value(), @intCast(u7, hm_index + game.tms1.len)),
                false => bits.clear(u128, learnset.value(), @intCast(u7, hm_index + game.tms1.len)),
                else => unreachable,
            };
            learnset.* = lu128.init(new);
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatStr(".tms[")) {
        const tm_index = try parser.eatUnsignedMax(usize, 10, game.tms1.len + game.tms2.len);
        try parser.eatStr("]=");

        const value = lu16.init(try parser.eatUnsignedMax(u16, 10, game.moves.nodes.len));
        if (tm_index < game.tms1.len) {
            game.tms1[tm_index] = value;
        } else {
            game.tms1[tm_index - game.tms1.len] = value;
        }
    } else |_| if (parser.eatStr(".hms[")) {
        const hm_index = try parser.eatUnsignedMax(usize, 10, game.hms.len);
        try parser.eatStr("]=");

        game.hms[hm_index] = lu16.init(try parser.eatUnsignedMax(u16, 10, game.moves.nodes.len));
    } else |_| if (parser.eatStr(".zones[")) done: {
        const wild_pokemons = game.wild_pokemons.nodes.toSlice();
        const zone_index = try parser.eatUnsignedMax(usize, 10, wild_pokemons.len);
        const wilds = try nodeAsType(gen5.WildPokemons, wild_pokemons[zone_index]);
        try parser.eatStr("].wild.");

        inline for ([][]const u8{
            "grass",
            "dark_grass",
            "rustling_grass",
            "surf",
            "ripple_surf",
            "fishing",
            "ripple_fishing",
        }) |area_name, j| {
            if (parser.eatStr(area_name ++ ".encounter_rate=")) {
                wilds.rates[j] = try parser.eatUnsigned(u8, 10);
                break :done;
            } else |_| if (parser.eatStr(area_name ++ ".pokemons[")) {
                const area = &@field(wilds, area_name);
                const wild_index = try parser.eatUnsignedMax(usize, 10, area.len);
                const wild = &area[wild_index];
                try parser.eatStr("].");

                if (parser.eatStr("min_level=")) {
                    wild.min_level = try parser.eatUnsigned(u8, 10);
                } else |_| if (parser.eatStr("max_level=")) {
                    wild.max_level = try parser.eatUnsigned(u8, 10);
                } else |_| if (parser.eatStr("species=")) {
                    wild.species.setSpecies(try parser.eatUnsignedMax(u10, 10, game.pokemons.nodes.len));
                } else |_| if (parser.eatStr("form=")) {
                    wild.species.setForm(try parser.eatUnsigned(u6, 10));
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

fn warning(line: usize, col: usize, comptime f: []const u8, a: ...) void {
    debug.warn("(stdin):{}:{}: warning: ", line, col);
    debug.warn(f, a);
}

fn stringToBool(str: []const u8) ?bool {
    if (mem.eql(u8, "true", str))
        return true;
    if (mem.eql(u8, "false", str))
        return false;

    return null;
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
