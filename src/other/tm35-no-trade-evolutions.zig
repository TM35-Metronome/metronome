const clap = @import("clap");
const format = @import("format");
const std = @import("std");
const ston = @import("ston");
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

const Program = @This();

allocator: mem.Allocator,
pokemons: Pokemons = Pokemons{},

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
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
;

pub const parsers = .{};

pub const params = clap.parseParamsComptime(
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\-v, --version
    \\        Output version information and exit.
    \\
);

pub fn init(allocator: mem.Allocator, args: anytype) error{}!Program {
    _ = args;
    return Program{ .allocator = allocator };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) !void {
    try format.io(program.allocator, stdio.in, stdio.out, program, useGame);
    program.removeTradeEvolutions();
    try program.output(stdio.out);
}

fn output(program: *Program, writer: anytype) !void {
    try ston.serialize(writer, .{ .pokemons = program.pokemons });
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .pokemons => |pokemons| {
            const pokemon = (try program.pokemons.getOrPutValue(allocator, pokemons.index, .{}))
                .value_ptr;
            switch (pokemons.value) {
                .evos => |evos| {
                    const evo = (try pokemon.evos.getOrPutValue(allocator, evos.index, .{}))
                        .value_ptr;
                    switch (evos.value) {
                        .param => |param| evo.param = param,
                        .method => |method| evo.method = method,
                        .target => return error.DidNotConsumeData,
                    }
                },
                .stats,
                .types,
                .catch_rate,
                .base_exp_yield,
                .items,
                .gender_ratio,
                .egg_cycles,
                .base_friendship,
                .growth_rate,
                .egg_groups,
                .abilities,
                .moves,
                .tms,
                .hms,
                .name,
                .pokedex_entry,
                => return error.DidNotConsumeData,
            }
        },
        .version,
        .game_title,
        .gamecode,
        .instant_text,
        .starters,
        .text_delays,
        .trainers,
        .moves,
        .abilities,
        .types,
        .tms,
        .hms,
        .items,
        .pokedex,
        .maps,
        .wild_pokemons,
        .static_pokemons,
        .given_pokemons,
        .pokeball_items,
        .hidden_hollows,
        .text,
        => return error.DidNotConsumeData,
    }
}

fn removeTradeEvolutions(program: *Program) void {
    // Find methods that exists in the game.
    var has_level_up = false;
    var has_level_up_holding = false;
    var has_level_up_party = false;
    for (program.pokemons.values()) |pokemon| {
        for (pokemon.evos.values()) |evo| {
            if (evo.method == .unused)
                continue;
            has_level_up = has_level_up or evo.method == .level_up;
            has_level_up_holding = has_level_up_holding or
                evo.method == .level_up_holding_item_during_daytime;
            has_level_up_party = has_level_up_party or
                evo.method == .level_up_with_other_pokemon_in_party;
        }
    }

    const M = format.Evolution.Method;
    const trade_method_replace: ?M = if (has_level_up) .level_up else null;
    const trade_method_holding_replace: ?M = if (has_level_up_holding)
        .level_up_holding_item_during_daytime
    else
        trade_method_replace;

    const trade_param_replace: ?u16 = if (has_level_up) @as(usize, 36) else null;
    const trade_param_holding_replace: ?u16 = if (has_level_up_holding)
        null
    else
        trade_param_replace;

    for (program.pokemons.values()) |pokemon| {
        for (pokemon.evos.values()) |*evo| {
            if (evo.method == .unused)
                continue;
            const method = evo.method;
            const param = evo.param;
            switch (evo.method) {
                .trade, .trade_with_pokemon => {
                    evo.method = trade_method_replace orelse method;
                    evo.param = trade_param_replace orelse param;
                },
                .trade_holding_item => {
                    evo.method = trade_method_holding_replace orelse method;
                    evo.param = trade_param_holding_replace orelse param;
                },
                .attack_eql_defense,
                .attack_gth_defense,
                .attack_lth_defense,
                .beauty,
                .friend_ship,
                .friend_ship_during_day,
                .friend_ship_during_night,
                .level_up,
                .level_up_female,
                .level_up_holding_item_during_daytime,
                .level_up_holding_item_during_the_night,
                .level_up_in_special_magnetic_field,
                .level_up_knowning_move,
                .level_up_male,
                .level_up_may_spawn_pokemon,
                .level_up_near_ice_rock,
                .level_up_near_moss_rock,
                .level_up_spawn_if_cond,
                .level_up_with_other_pokemon_in_party,
                .personality_value1,
                .personality_value2,
                .unknown_0x02,
                .unknown_0x03,
                .unused,
                .use_item,
                .use_item_on_female,
                .use_item_on_male,
                => {},
            }
        }
    }
}

const Evolutions = std.AutoArrayHashMapUnmanaged(u8, Evolution);
const Pokemons = std.AutoArrayHashMapUnmanaged(u16, Pokemon);

const Pokemon = struct {
    evos: Evolutions = Evolutions{},
};

const Evolution = struct {
    param: ?u16 = null,
    method: format.Evolution.Method = .unused,
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

    const test_string = comptime H.evo("0", "level_up", "12") ++
        H.evo("1", "trade", "1") ++
        H.evo("2", "trade_holding_item", "1") ++
        H.evo("3", "trade_with_pokemon", "1");

    try util.testing.testProgram(
        Program,
        &[_][]const u8{},
        test_string,
        comptime H.evo("0", "level_up", "12") ++
            H.evo("1", "level_up", "36") ++
            H.evo("2", "level_up", "36") ++
            H.evo("3", "level_up", "36"),
    );
    try util.testing.testProgram(
        Program,
        &[_][]const u8{},
        comptime test_string ++
            H.evo("4", "level_up_holding_item_during_daytime", "1"),
        comptime H.evo("0", "level_up", "12") ++
            H.evo("1", "level_up", "36") ++
            H.evo("2", "level_up_holding_item_during_daytime", "1") ++
            H.evo("3", "level_up", "36") ++
            H.evo("4", "level_up_holding_item_during_daytime", "1"),
    );
    try util.testing.testProgram(
        Program,
        &[_][]const u8{},
        comptime test_string ++
            H.evo("4", "level_up_with_other_pokemon_in_party", "1"),
        comptime H.evo("0", "level_up", "12") ++
            H.evo("1", "level_up", "36") ++
            H.evo("2", "level_up", "36") ++
            H.evo("3", "level_up", "36") ++
            H.evo("4", "level_up_with_other_pokemon_in_party", "1"),
    );
}
