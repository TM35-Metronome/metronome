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

const exit = util.exit;
const parse = util.parse;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

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
    try stream.writeAll("\nReplace trade evolutions with non trade versions.\n" ++
        "\n" ++
        "Here is how each trade evolution is replaced:\n" ++
        "* Trade -> Level up 36\n" ++
        "* Trade holding <item> -> Level up holding <item> during daytime\n" ++
        "* Trade with <pokemon> -> Level up with other <pokemon> in party\n" ++
        "\n" ++
        "Certain level up methods might not exist in some game. " ++
        "Supported methods are found by looking over all methods used in the game. " ++
        "If one method doesn't exist, 'Level up 36' is used as a fallback.\n" ++
        "\n" ++
        "Options:\n");
    try clap.help(stream, &params);
}

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime InStream: type,
    comptime OutStream: type,
    stdio: util.CustomStdIoStreams(InStream, OutStream),
    args: var,
) u8 {
    var fifo = util.read.Fifo(.Dynamic).init(allocator);
    var data = Data{};
    while (util.read.line(stdio.in, &fifo) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(allocator, &data, str) catch |err| switch (err) {
            error.OutOfMemory => return exit.allocErr(stdio.err),
            error.ParseError => true,
        };
        if (print_line)
            stdio.out.print("{}\n", .{str}) catch |err| return exit.stdoutErr(stdio.err, err);
    }

    removeTradeEvolutions(data);

    for (data.pokemons.values()) |pokemon, i| {
        const pokemon_i = data.pokemons.at(i).key;
        for (pokemon.evos.values()) |evo, j| {
            const evo_i = pokemon.evos.at(j).key;
            if (evo.param) |param|
                stdio.out.print(".pokemons[{}].evos[{}].param={}\n", .{ pokemon_i, evo_i, param }) catch |err| return exit.stdoutErr(stdio.err, err);
            if (evo.method) |method|
                stdio.out.print(".pokemons[{}].evos[{}].method={}\n", .{ pokemon_i, evo_i, method }) catch |err| return exit.stdoutErr(stdio.err, err);
        }
    }
    return 0;
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !bool {
    const sw = parse.Swhash(16);
    const m = sw.match;
    const c = sw.case;
    var p = parse.MutParser{ .str = str };

    try p.parse(comptime parse.field("pokemons"));
    const poke_index = try p.parse(parse.index);
    const pokemon = try data.pokemons.getOrPutValue(allocator, poke_index, Pokemon{});

    try p.parse(comptime parse.field("evos"));
    const evo_index = try p.parse(parse.index);
    const evo = try pokemon.evos.getOrPutValue(allocator, evo_index, Evolution{});

    switch (m(try p.parse(parse.anyField))) {
        c("param") => evo.param = try p.parse(parse.usizev),
        c("method") => evo.method = try mem.dupe(allocator, u8, try p.parse(parse.strv)),
        else => return true,
    }

    return false;
}

fn removeTradeEvolutions(data: Data) void {
    // Find methods that exists in the game.
    var has_level_up = false;
    var has_level_up_holding = false;
    var has_level_up_party = false;
    for (data.pokemons.values()) |pokemon| {
        for (pokemon.evos.values()) |evo| {
            const method = evo.method orelse continue;
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

    for (data.pokemons.values()) |pokemon| {
        for (pokemon.evos.values()) |*evo| {
            const method = evo.method orelse continue;
            const param = evo.param;
            if (mem.eql(u8, method, "trade")) {
                evo.method = trade_method_replace orelse method;
                evo.param = trade_param_replace orelse param;
            } else if (mem.eql(u8, method, "trade_holding_item")) {
                evo.method = trade_method_holding_replace orelse method;
                evo.param = trade_param_holding_replace orelse param;
            } else if (mem.eql(u8, method, "trade_with_pokemon")) {
                evo.method = trade_method_pokemon_replace orelse method;
                evo.param = trade_param_pokemon_replace orelse param;
            }
        }
    }
}

const Pokemons = util.container.IntMap.Unmanaged(usize, Pokemon);
const Evolutions = util.container.IntMap.Unmanaged(usize, Evolution);

const Data = struct {
    pokemons: Pokemons = Pokemons{},
};

const Pokemon = struct {
    evos: Evolutions = Evolutions{},
};

const Evolution = struct {
    param: ?usize = null,
    method: ?[]const u8 = null,
};

test "tm35-no-trade-evolutions" {
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
        &params,
        &[_][]const u8{},
        test_string,
        H.evo("0", "level_up", "12") ++
            H.evo("1", "level_up", "36") ++
            H.evo("2", "level_up", "36") ++
            H.evo("3", "level_up", "36"),
    );
    util.testing.testProgram(
        main2,
        &params,
        &[_][]const u8{},
        test_string ++
            H.evo("4", "level_up_holding_item_during_daytime", "1"),
        H.evo("0", "level_up", "12") ++
            H.evo("1", "level_up", "36") ++
            H.evo("2", "level_up_holding_item_during_daytime", "1") ++
            H.evo("3", "level_up", "36") ++
            H.evo("4", "level_up_holding_item_during_daytime", "1"),
    );
    util.testing.testProgram(
        main2,
        &params,
        &[_][]const u8{},
        test_string ++
            H.evo("4", "level_up_with_other_pokemon_in_party", "1"),
        H.evo("0", "level_up", "12") ++
            H.evo("1", "level_up", "36") ++
            H.evo("2", "level_up", "36") ++
            H.evo("3", "level_up_with_other_pokemon_in_party", "1") ++
            H.evo("4", "level_up_with_other_pokemon_in_party", "1"),
    );
}
