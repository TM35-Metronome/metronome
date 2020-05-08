const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const errors = util.errors;
const format = util.format;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

// TODO: Have the tm35-randomizer recognize options with it's help message split onto a new line
const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help      Display this help text and exit.") catch unreachable,
        clap.parseParam("-v, --version   Output version information and exit.") catch unreachable,
    };
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-no-trade-evolutions ");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Replace trade evolutions with non trade versions.
        \\
        \\Here is how each trade evolution is replaced:
        \\* Trade -> Level up 36
        \\* Trade holding <item> -> Level up holding <item> during daytime
        \\* Trade with <pokemon> -> Level up with other <pokemon> in party
        \\
        \\Certain level up methods might not exist in some game.
        \\Supported methods are found by looking over all methods used in the game.
        \\If one method doesn't exist, 'Level up 36' is used as a fallback.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

pub fn main() u8 {
    var stdio = util.getStdIo();
    defer stdio.err.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(&arena.allocator) catch
        return errors.allocErr(stdio.err.outStream());
    const res = main2(
        &arena.allocator,
        util.StdIo.In.InStream,
        util.StdIo.Out.OutStream,
        stdio.streams(),
        clap.args.OsIterator,
        &arg_iter,
    );

    stdio.out.flush() catch |err| return errors.writeErr(stdio.err.outStream(), "<stdout>", err);
    return res;
}

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime InStream: type,
    comptime OutStream: type,
    stdio: util.CustomStdIoStreams(InStream, OutStream),
    comptime ArgIterator: type,
    arg_iter: *ArgIterator,
) u8 {
    var stdin = io.bufferedInStream(stdio.in);
    var args = Clap.parse(allocator, ArgIterator, arg_iter) catch |err| {
        stdio.err.print("{}\n", .{err}) catch {};
        usage(stdio.err) catch {};
        return 1;
    };
    defer args.deinit();

    if (args.flag("--help")) {
        usage(stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.print("{}\n", .{program_version}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    var line_buf = std.ArrayList(u8).init(allocator);
    var data = Data{
        .pokemons = Pokemons.init(allocator),
    };

    while (util.readLine(&stdin, &line_buf) catch |err| return errors.readErr(stdio.err, "<stdin>", err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(&data, str) catch |err| switch (err) {
            error.OutOfMemory => return errors.allocErr(stdio.err),
            error.Overflow,
            error.EndOfString,
            error.InvalidCharacter,
            => true,
        };
        if (print_line)
            stdio.out.print("{}\n", .{str}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

        line_buf.resize(0) catch unreachable;
    }

    removeTradeEvolutions(data);

    var p_it = data.pokemons.iterator();
    while (p_it.next()) |p_kv| {
        var e_it = p_kv.value.evos.iterator();
        while (e_it.next()) |e_kv| {
            if (e_kv.value.param) |param|
                stdio.out.print(".pokemons[{}].evos[{}].param={}\n", .{ p_kv.key, e_kv.key, param }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
            if (e_kv.value.method) |method|
                stdio.out.print(".pokemons[{}].evos[{}].method={}\n", .{ p_kv.key, e_kv.key, method }) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        }
    }
    return 0;
}

fn parseLine(data: *Data, str: []const u8) !bool {
    const allocator = data.pokemons.allocator;
    var parser = format.Parser{ .str = str };

    if (parser.eatField("pokemons")) |_| {
        const poke_index = try parser.eatIndex();
        const poke_entry = try data.pokemons.getOrPutValue(poke_index, Pokemon.init(allocator));
        const pokemon = &poke_entry.value;

        if (parser.eatField("evos")) |_| {
            const evo_index = try parser.eatIndex();
            const evo_entry = try pokemon.evos.getOrPutValue(evo_index, Evolution{});
            const evo = &evo_entry.value;

            if (parser.eatField("param")) |_| {
                evo.param = try parser.eatUnsignedValue(usize, 10);
            } else |_| if (parser.eatField("method")) |_| {
                evo.method = try mem.dupe(allocator, u8, try parser.eatValue());
            } else |_| {
                return true;
            }

            return false;
        } else |_| {}
    } else |_| {}

    return true;
}

fn removeTradeEvolutions(data: Data) void {
    // Find methods that exists in the game.
    var has_level_up = false;
    var has_level_up_holding = false;
    var has_level_up_party = false;
    var p_it = data.pokemons.iterator();
    while (p_it.next()) |p_kv| {
        var e_it = p_kv.value.evos.iterator();
        while (e_it.next()) |e_kv| {
            const method = e_kv.value.method orelse continue;
            has_level_up = has_level_up or mem.eql(u8, method, "level_up");
            has_level_up_holding = has_level_up_holding or mem.eql(u8, method, "level_up_holding_item_during_daytime");
            has_level_up_party = has_level_up_party or mem.eql(u8, method, "level_up_with_other_pokemon_in_party");
        }
    }

    const trade_method_replace: ?[]const u8 = if (has_level_up) "level_up" else null;
    const trade_method_holding_replace = if (has_level_up_holding) "level_up_holding_item_during_daytime" else trade_method_replace;
    const trade_method_pokemon_replace = if (has_level_up_party) "level_up_with_other_pokemon_in_party" else trade_method_replace;

    const trade_param_replace: ?usize = if (has_level_up) @as(usize, 36) else null;
    const trade_param_holding_replace: ?usize = if (has_level_up_holding) null else trade_param_replace;
    const trade_param_pokemon_replace: ?usize = if (has_level_up_party) null else trade_param_replace;

    p_it = data.pokemons.iterator();
    while (p_it.next()) |p_kv| {
        var e_it = p_kv.value.evos.iterator();
        while (e_it.next()) |e_kv| {
            const method = e_kv.value.method orelse continue;
            const param = e_kv.value.param;
            if (mem.eql(u8, method, "trade")) {
                e_kv.value.method = trade_method_replace orelse method;
                e_kv.value.param = trade_param_replace orelse param;
            } else if (mem.eql(u8, method, "trade_holding_item")) {
                e_kv.value.method = trade_method_holding_replace orelse method;
                e_kv.value.param = trade_param_holding_replace orelse param;
            } else if (mem.eql(u8, method, "trade_with_pokemon")) {
                e_kv.value.method = trade_method_pokemon_replace orelse method;
                e_kv.value.param = trade_param_pokemon_replace orelse param;
            }
        }
    }
}

const Pokemons = std.AutoHashMap(usize, Pokemon);
const Evolutions = std.AutoHashMap(usize, Evolution);

const Data = struct {
    pokemons: Pokemons,
};

const Pokemon = struct {
    evos: Evolutions,

    fn init(allocator: *mem.Allocator) Pokemon {
        return Pokemon{
            .evos = Evolutions.init(allocator),
        };
    }
};

const Evolution = struct {
    param: ?usize = null,
    method: ?[]const u8 = null,
};

test "tm35-rand-static" {
    const H = struct {
        fn evo(
            comptime id: []const u8,
            comptime method: []const u8,
            comptime param: []const u8,
        ) []const u8 {
            return ".pokemons[0].evos[" ++ id ++ "].param=" ++ param ++ "\n" ++
                ".pokemons[0].evos[" ++ id ++ "].method=" ++ method ++ "\n";
        }
    };

    const test_string = H.evo("0", "level_up", "12") ++
        H.evo("1", "trade", "1") ++
        H.evo("2", "trade_holding_item", "1") ++
        H.evo("3", "trade_with_pokemon", "1");

    util.testing.testProgram(
        main2,
        &[_][]const u8{},
        test_string,
        H.evo("3", "level_up", "36") ++
            H.evo("1", "level_up", "36") ++
            H.evo("2", "level_up", "36") ++
            H.evo("0", "level_up", "12"),
    );
    util.testing.testProgram(
        main2,
        &[_][]const u8{},
        test_string ++
            H.evo("4", "level_up_holding_item_during_daytime", "1"),
        H.evo("4", "level_up_holding_item_during_daytime", "1") ++
            H.evo("3", "level_up", "36") ++
            H.evo("1", "level_up", "36") ++
            H.evo("2", "level_up_holding_item_during_daytime", "1") ++
            H.evo("0", "level_up", "12"),
    );
    util.testing.testProgram(
        main2,
        &[_][]const u8{},
        test_string ++
            H.evo("4", "level_up_with_other_pokemon_in_party", "1"),
        H.evo("4", "level_up_with_other_pokemon_in_party", "1") ++
            H.evo("3", "level_up_with_other_pokemon_in_party", "1") ++
            H.evo("1", "level_up", "36") ++
            H.evo("2", "level_up", "36") ++
            H.evo("0", "level_up", "12"),
    );
}
