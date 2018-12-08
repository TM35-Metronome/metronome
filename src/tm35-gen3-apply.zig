const clap = @import("zig-clap");
const common = @import("tm35-common");
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
    const eql_index = mem.indexOfScalar(u8, str, '=') orelse return error.SyntaxError;
    const value = str[eql_index + 1 ..];

    if (sscan(str, ".version=", struct {})) |_| {
        const version = meta.stringToEnum(common.Version, value) orelse return error.SyntaxError;
        if (version != game.version)
            return error.VersionDontMatch;
    } else |_| if (sscan(str, ".game_title=", struct {})) |_| {
        if (!mem.eql(u8, value, game.header.game_title))
            return error.GameTitleDontMatch;
    } else |_| if (sscan(str, ".gamecode=", struct {})) |_| {
        if (!mem.eql(u8, value, game.header.gamecode))
            return error.GameCodeDontMatch;
    } else |_| if (sscan(str, ".trainers[{}].class={}", Index1Value(u8))) |r| {
        if (game.trainers.len <= r.index1)
            return error.OutOfBound;

        game.trainers[r.index1].class = r.value;
    } else |_| if (sscan(str, ".trainers[{}].encounter_music={}", Index1Value(u8))) |r| {
        if (game.trainers.len <= r.index1)
            return error.OutOfBound;

        game.trainers[r.index1].encounter_music = r.value;
    } else |_| if (sscan(str, ".trainers[{}].trainer_picture={}", Index1Value(u8))) |r| {
        if (game.trainers.len <= r.index1)
            return error.OutOfBound;

        game.trainers[r.index1].encounter_music = r.value;
    } else |_| if (sscan(str, ".trainers[{}].items[{}]={}", Index2Value(u16))) |r| {
        if (game.trainers.len <= r.index1)
            return error.OutOfBound;
        if (game.trainers[r.index1].items.len <= r.index2)
            return error.OutOfBound;

        game.trainers[r.index1].items[r.index2] = lu16.init(r.value);
    } else |_| if (sscan(str, ".trainers[{}].is_double={}", Index1Value(u32))) |r| {
        if (game.trainers.len <= r.index1)
            return error.OutOfBound;

        game.trainers[r.index1].is_double = lu32.init(r.value);
    } else |_| if (sscan(str, ".trainers[{}].ai={}", Index1Value(u32))) |r| {
        if (game.trainers.len <= r.index1)
            return error.OutOfBound;

        game.trainers[r.index1].ai = lu32.init(r.value);
    } else |_| if (sscan(str, ".trainers[{}].party[{}].iv={}", Index2Value(u16))) |r| {
        if (game.trainers.len <= r.index1)
            return error.OutOfBound;
        if (game.trainers[r.index1].partyLen() <= r.index2)
            return error.OutOfBound;

        (try game.trainers[r.index1].partyAt(r.index2, game.data)).iv = lu16.init(r.value);
    } else |_| if (sscan(str, ".trainers[{}].party[{}].level={}", Index2Value(u16))) |r| {
        if (game.trainers.len <= r.index1)
            return error.OutOfBound;
        if (game.trainers[r.index1].partyLen() <= r.index2)
            return error.OutOfBound;

        (try game.trainers[r.index1].partyAt(r.index2, game.data)).level = lu16.init(r.value);
    } else |_| if (sscan(str, ".trainers[{}].party[{}].species={}", Index2Value(u16))) |r| {
        if (game.trainers.len <= r.index1)
            return error.OutOfBound;
        if (game.trainers[r.index1].partyLen() <= r.index2)
            return error.OutOfBound;

        (try game.trainers[r.index1].partyAt(r.index2, game.data)).species = lu16.init(r.value);
    } else |_| if (sscan(str, ".trainers[{}].party[{}].item={}", Index2Value(u16))) |r| {
        if (game.trainers.len <= r.index1)
            return error.OutOfBound;
        if (game.trainers[r.index1].partyLen() <= r.index2)
            return error.OutOfBound;

        const trainer = &game.trainers[r.index1];
        const base = try trainer.partyAt(r.index2, game.data);
        switch (trainer.party_type) {
            gen3.PartyType.Item => base.toParent(gen3.PartyMemberItem).item = lu16.init(r.value),
            gen3.PartyType.Both => base.toParent(gen3.PartyMemberBoth).item = lu16.init(r.value),
            else => return error.NoField,
        }
    } else |_| if (sscan(str, ".trainers[{}].party[{}].moves[{}]={}", Index3Value(u16))) |r| {
        if (game.trainers.len <= r.index1)
            return error.OutOfBound;
        if (game.trainers[r.index1].partyLen() <= r.index2)
            return error.OutOfBound;

        const trainer = &game.trainers[r.index1];
        const base = try trainer.partyAt(r.index2, game.data);
        switch (trainer.party_type) {
            gen3.PartyType.Moves => {
                const member = base.toParent(gen3.PartyMemberMoves);
                if (member.moves.len <= r.index3)
                    return error.OutOfBound;

                member.moves[r.index3] = lu16.init(r.value);
            },
            gen3.PartyType.Both => {
                const member = base.toParent(gen3.PartyMemberBoth);
                if (member.moves.len <= r.index3)
                    return error.OutOfBound;

                member.moves[r.index3] = lu16.init(r.value);
            },
            else => return error.NoField,
        }
    } else |_| if (sscan(str, ".moves[{}].effect={}", Index1Value(u8))) |r| {
        if (game.moves.len <= r.index1)
            return error.OutOfBound;

        game.moves[r.index1].effect = r.value;
    } else |_| if (sscan(str, ".moves[{}].power={}", Index1Value(u8))) |r| {
        if (game.moves.len <= r.index1)
            return error.OutOfBound;

        game.moves[r.index1].power = r.value;
    } else |_| if (sscan(str, ".moves[{}].type=", Index1)) |r| {
        if (game.moves.len <= r.index1)
            return error.OutOfBound;

        game.moves[r.index1].@"type" = meta.stringToEnum(gen3.Type, value) orelse return error.SyntaxError;
    } else |_| if (sscan(str, ".moves[{}].accuracy={}", Index1Value(u8))) |r| {
        if (game.moves.len <= r.index1)
            return error.OutOfBound;

        game.moves[r.index1].accuracy = r.value;
    } else |_| if (sscan(str, ".moves[{}].pp={}", Index1Value(u8))) |r| {
        if (game.moves.len <= r.index1)
            return error.OutOfBound;

        game.moves[r.index1].pp = r.value;
    } else |_| if (sscan(str, ".moves[{}].side_effect_chance={}", Index1Value(u8))) |r| {
        if (game.moves.len <= r.index1)
            return error.OutOfBound;

        game.moves[r.index1].side_effect_chance = r.value;
    } else |_| if (sscan(str, ".moves[{}].target={}", Index1Value(u8))) |r| {
        if (game.moves.len <= r.index1)
            return error.OutOfBound;

        game.moves[r.index1].target = r.value;
    } else |_| if (sscan(str, ".moves[{}].priority={}", Index1Value(u8))) |r| {
        if (game.moves.len <= r.index1)
            return error.OutOfBound;

        game.moves[r.index1].priority = r.value;
    } else |_| if (sscan(str, ".moves[{}].flags={}", Index1Value(u32))) |r| {
        if (game.moves.len <= r.index1)
            return error.OutOfBound;

        game.moves[r.index1].flags = lu32.init(r.value);
    } else |_| if (sscan(str, ".pokemons[{}].stats.hp={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].stats.hp = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].stats.attack={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].stats.attack = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].stats.defense={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].stats.defense = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].stats.speed={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].stats.speed = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].stats.sp_attack={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].stats.sp_attack = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].stats.sp_defense={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].stats.sp_defense = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].types[{}]=", Index2)) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;
        if (game.pokemons[r.index1].types.len <= r.index2)
            return error.OutOfBound;

        game.pokemons[r.index1].types[r.index2] = meta.stringToEnum(gen3.Type, value) orelse return error.SyntaxError;
    } else |_| if (sscan(str, ".pokemons[{}].catch_rate={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].catch_rate = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].base_exp_yield={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].base_exp_yield = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].ev_yield.hp={}", Index1Value(u2))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].ev_yield.hp = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].ev_yield.attack={}", Index1Value(u2))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].ev_yield.attack = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].ev_yield.defense={}", Index1Value(u2))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].ev_yield.defense = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].ev_yield.speed={}", Index1Value(u2))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].ev_yield.speed = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].ev_yield.sp_attack={}", Index1Value(u2))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].ev_yield.sp_attack = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].ev_yield.sp_defense={}", Index1Value(u2))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].ev_yield.sp_defense = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].items[{}]={}", Index2Value(u16))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;
        if (game.pokemons[r.index1].items.len <= r.index2)
            return error.OutOfBound;

        game.pokemons[r.index1].items[r.index2] = lu16.init(r.value);
    } else |_| if (sscan(str, ".pokemons[{}].gender_ratio={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].gender_ratio = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].egg_cycles={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].egg_cycles = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].base_friendship={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].base_friendship = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].growth_rate=", Index1)) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].growth_rate = meta.stringToEnum(common.GrowthRate, value) orelse return error.SyntaxError;
    } else |_| if (sscan(str, ".pokemons[{}].egg_groups[{}]=", Index2)) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        const egg_group = meta.stringToEnum(common.EggGroup, value) orelse return error.SyntaxError;
        switch (r.index2) {
            0 => game.pokemons[r.index1].egg_group1 = egg_group,
            1 => game.pokemons[r.index1].egg_group2 = egg_group,
            else => return error.OutOfBound,
        }
    } else |_| if (sscan(str, ".pokemons[{}].abilities[{}]={}", Index2Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;
        if (game.pokemons[r.index1].abilities.len <= r.index2)
            return error.OutOfBound;

        game.pokemons[r.index1].abilities[r.index2] = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].safari_zone_rate={}", Index1Value(u8))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].safari_zone_rate = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].color=", Index1)) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].color = meta.stringToEnum(common.Color, value) orelse return error.SyntaxError;
    } else |_| if (sscan(str, ".pokemons[{}].flip={}", Index1Value(bool))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;

        game.pokemons[r.index1].flip = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].tms[{}]={}", Index2Value(bool))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;
        if (game.tms.len <= r.index2)
            return error.OutOfBound;

        const learnset = &game.machine_learnsets[r.index1];
        const new = switch (r.value) {
            true => bits.set(u64, learnset.value(), @intCast(u6, r.index2)),
            false => bits.clear(u64, learnset.value(), @intCast(u6, r.index2)),
            else => unreachable,
        };
        learnset.* = lu64.init(new);
    } else |_| if (sscan(str, ".pokemons[{}].hms[{}]={}", Index2Value(bool))) |r| {
        if (game.pokemons.len <= r.index1)
            return error.OutOfBound;
        if (game.hms.len <= r.index2)
            return error.OutOfBound;

        const learnset = &game.machine_learnsets[r.index1];
        const new = switch (r.value) {
            true => bits.set(u64, learnset.value(), @intCast(u6, r.index2 + game.tms.len)),
            false => bits.clear(u64, learnset.value(), @intCast(u6, r.index2 + game.tms.len)),
            else => unreachable,
        };
        learnset.* = lu64.init(new);
    } else |_| if (sscan(str, ".pokemons[{}].evos[{}].method=", Index2)) |r| {
        if (game.evolutions.len <= r.index1)
            return error.OutOfBound;
        if (game.evolutions[r.index1].len <= r.index2)
            return error.OutOfBound;

        game.evolutions[r.index1][r.index2].method = meta.stringToEnum(common.Evolution.Method, value) orelse return error.SyntaxError;
    } else |_| if (sscan(str, ".pokemons[{}].evos[{}].param={}", Index2Value(u16))) |r| {
        if (game.evolutions.len <= r.index1)
            return error.OutOfBound;
        if (game.evolutions[r.index1].len <= r.index2)
            return error.OutOfBound;

        game.evolutions[r.index1][r.index2].param = lu16.init(r.value);
    } else |_| if (sscan(str, ".pokemons[{}].evos[{}].target={}", Index2Value(u16))) |r| {
        if (game.evolutions.len <= r.index1)
            return error.OutOfBound;
        if (game.evolutions[r.index1].len <= r.index2)
            return error.OutOfBound;

        game.evolutions[r.index1][r.index2].target = lu16.init(r.value);
    } else |_| if (sscan(str, ".pokemons[{}].moves[{}].id={}", Index2Value(u9))) |r| {
        if (game.level_up_learnset_pointers.len <= r.index1)
            return error.OutOfBound;

        // TODO: Bounds check indexing on lvl up learnset

        const lvl_up_moves = try game.level_up_learnset_pointers[r.index1].toMany(game.data);
        lvl_up_moves[r.index2].id = r.value;
    } else |_| if (sscan(str, ".pokemons[{}].moves[{}].level={}", Index2Value(u7))) |r| {
        if (game.level_up_learnset_pointers.len <= r.index1)
            return error.OutOfBound;

        // TODO: Bounds check indexing on lvl up learnset

        const lvl_up_moves = try game.level_up_learnset_pointers[r.index1].toMany(game.data);
        lvl_up_moves[r.index2].level = r.value;
    } else |_| if (sscan(str, ".tms[{}]={}", Index1Value(u16))) |r| {
        if (game.tms.len <= r.index1)
            return error.OutOfBound;

        game.tms[r.index1] = lu16.init(r.value);
    } else |_| if (sscan(str, ".hms[{}]={}", Index1Value(u16))) |r| {
        if (game.hms.len <= r.index1)
            return error.OutOfBound;

        game.hms[r.index1] = lu16.init(r.value);
    } else |_| if (sscan(str, ".items[{}].id={}", Index1Value(u16))) |r| {
        if (game.items.len <= r.index1)
            return error.OutOfBound;

        game.items[r.index1].id = lu16.init(r.value);
    } else |_| if (sscan(str, ".items[{}].price={}", Index1Value(u16))) |r| {
        if (game.items.len <= r.index1)
            return error.OutOfBound;

        game.items[r.index1].price = lu16.init(r.value);
    } else |_| if (sscan(str, ".items[{}].hold_effect={}", Index1Value(u8))) |r| {
        if (game.items.len <= r.index1)
            return error.OutOfBound;

        game.items[r.index1].hold_effect = r.value;
    } else |_| if (sscan(str, ".items[{}].hold_effect_param={}", Index1Value(u8))) |r| {
        if (game.items.len <= r.index1)
            return error.OutOfBound;

        game.items[r.index1].hold_effect_param = r.value;
    } else |_| if (sscan(str, ".items[{}].importance={}", Index1Value(u8))) |r| {
        if (game.items.len <= r.index1)
            return error.OutOfBound;

        game.items[r.index1].importance = r.value;
    } else |_| if (sscan(str, ".items[{}].pocked={}", Index1Value(u8))) |r| {
        if (game.items.len <= r.index1)
            return error.OutOfBound;

        game.items[r.index1].pocked = r.value;
    } else |_| if (sscan(str, ".items[{}].type={}", Index1Value(u8))) |r| {
        if (game.items.len <= r.index1)
            return error.OutOfBound;

        game.items[r.index1].@"type" = r.value;
    } else |_| if (sscan(str, ".items[{}].battle_usage={}", Index1Value(u32))) |r| {
        if (game.items.len <= r.index1)
            return error.OutOfBound;

        game.items[r.index1].battle_usage = lu32.init(r.value);
    } else |_| if (sscan(str, ".items[{}].secondary_id={}", Index1Value(u32))) |r| {
        if (game.items.len <= r.index1)
            return error.OutOfBound;

        game.items[r.index1].secondary_id = lu32.init(r.value);
    } else |_| success: {
        inline for ([][]const u8{
            "land",
            "surf",
            "rock_smash",
            "fishing",
        }) |area_name| {
            if (sscan(str, ".zones[{}].wild." ++ area_name ++ ".encounter_rate={}", Index1Value(u8))) |r| {
                if (game.wild_pokemon_headers.len <= r.index1)
                    return error.OutOfBound;

                const area = try @field(game.wild_pokemon_headers[r.index1], area_name).toSingle(game.data);
                area.encounter_rate = r.value;
                break :success;
            } else |_| if (sscan(str, ".zones[{}].wild." ++ area_name ++ ".pokemons[{}].min_level={}", Index2Value(u8))) |r| {
                if (game.wild_pokemon_headers.len <= r.index1)
                    return error.OutOfBound;

                const area = try @field(game.wild_pokemon_headers[r.index1], area_name).toSingle(game.data);
                const wilds = try area.wild_pokemons.toSingle(game.data);
                if (wilds.len <= r.index2)
                    return error.OutOfBound;

                wilds[r.index2].min_level = r.value;
                break :success;
            } else |_| if (sscan(str, ".zones[{}].wild." ++ area_name ++ ".pokemons[{}].max_level={}", Index2Value(u8))) |r| {
                if (game.wild_pokemon_headers.len <= r.index1)
                    return error.OutOfBound;

                const area = try @field(game.wild_pokemon_headers[r.index1], area_name).toSingle(game.data);
                const wilds = try area.wild_pokemons.toSingle(game.data);
                if (wilds.len <= r.index2)
                    return error.OutOfBound;

                wilds[r.index2].max_level = r.value;
                break :success;
            } else |_| if (sscan(str, ".zones[{}].wild." ++ area_name ++ ".pokemons[{}].species={}", Index2Value(u16))) |r| {
                if (game.wild_pokemon_headers.len <= r.index1)
                    return error.OutOfBound;

                const area = try @field(game.wild_pokemon_headers[r.index1], area_name).toSingle(game.data);
                const wilds = try area.wild_pokemons.toSingle(game.data);
                if (wilds.len <= r.index2)
                    return error.OutOfBound;

                wilds[r.index2].species = lu16.init(r.value);
                break :success;
            } else |_| {}
        }

        return error.NoField;
    }
}

fn warning(line: usize, col: usize, comptime f: []const u8, a: ...) void {
    debug.warn("(stdin):{}:{}: warning: ", line, col);
    debug.warn(f, a);
}

const Index1 = struct {
    index1: usize,
};

const Index2 = struct {
    index1: usize,
    index2: usize,
};

const Index3 = struct {
    index1: usize,
    index2: usize,
    index3: usize,
};

fn Index1Value(comptime V: type) type {
    return struct {
        index1: usize,
        value: V,
    };
}

fn Index2Value(comptime V: type) type {
    return struct {
        index1: usize,
        index2: usize,
        value: V,
    };
}

fn Index3Value(comptime V: type) type {
    return struct {
        index1: usize,
        index2: usize,
        index3: usize,
        value: V,
    };
}
