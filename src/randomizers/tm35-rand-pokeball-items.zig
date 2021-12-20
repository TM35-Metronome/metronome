const clap = @import("clap");
const format = @import("format");
const std = @import("std");
const ston = @import("ston");
const util = @import("util");

const ascii = std.ascii;
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

const escape = util.escape;

const Program = @This();

allocator: *mem.Allocator,
options: struct {
    seed: u64,
    include_tms_hms: bool,
    include_key_items: bool,
    excluded_items: []const []const u8,
},
pokeballs: Pokeballs = Pokeballs{},
items: Items = Items{},

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Randomizes items found on the ground in pokeballs..
    \\
;

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam(
        "-h, --help " ++
            "Display this help text and exit.",
    ) catch unreachable,
    clap.parseParam(
        "-t, --include-tms-hms " ++
            "Allow for tms/hms to be randomized (This might make the game impossible to " ++
            "complete).",
    ) catch unreachable,
    clap.parseParam(
        "-k, --include-key-items " ++
            "Allow for key items to be randomized (This might make the game impossible to " ++
            "complete).",
    ) catch unreachable,
    clap.parseParam(
        "-s, --seed <INT> " ++
            "The seed to use for random numbers. A random seed will be picked if this is not " ++
            "specified.",
    ) catch unreachable,
    clap.parseParam(
        "-e, --exclude <STRING>... " ++
            "List of items to never pick. Case insensitive. Supports wildcards like '*mail'.",
    ) catch unreachable,
    clap.parseParam(
        "-v, --version " ++
            "Output version information and exit.",
    ) catch unreachable,
};

pub fn init(allocator: *mem.Allocator, args: anytype) !Program {
    const excluded_items_arg = args.options("--exclude");
    var excluded_items = try std.ArrayList([]const u8).initCapacity(
        allocator,
        excluded_items_arg.len,
    );
    for (excluded_items_arg) |exclude|
        excluded_items.appendAssumeCapacity(try ascii.allocLowerString(allocator, exclude));

    return Program{
        .allocator = allocator,
        .options = .{
            .seed = try util.getSeed(args),
            .include_tms_hms = args.flag("--include-tms-hms"),
            .include_key_items = args.flag("--include-key-items"),
            .excluded_items = excluded_items.toOwnedSlice(),
        },
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) !void {
    try format.io(program.allocator, stdio.in, stdio.out, program, useGame);
    try program.randomize();
    try program.output(stdio.out);
}

pub fn deinit(program: *Program) void {}

fn output(program: *Program, writer: anytype) !void {
    try ston.serialize(writer, .{ .pokeball_items = program.pokeballs });
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .pokeball_items => |items| switch (items.value) {
            .item => |item| {
                _ = try program.pokeballs.put(allocator, items.index, .{ .item = item });
                return;
            },
            .amount => return error.ParserFailed,
        },
        .items => |items| {
            const item = (try program.items.getOrPutValue(allocator, items.index, .{})).value_ptr;
            switch (items.value) {
                .pocket => |pocket| item.pocket = pocket,
                .price => |price| item.price = price,
                .name => |name| {
                    item.name = try escape.default.unescapeAlloc(allocator, name);
                    for (item.name) |*c|
                        c.* = ascii.toLower(c.*);
                },
                .description,
                .battle_effect,
                => return error.ParserFailed,
            }
            return error.ParserFailed;
        },
        .version,
        .game_title,
        .gamecode,
        .instant_text,
        .starters,
        .text_delays,
        .trainers,
        .moves,
        .pokemons,
        .abilities,
        .types,
        .tms,
        .hms,
        .pokedex,
        .maps,
        .wild_pokemons,
        .static_pokemons,
        .given_pokemons,
        .hidden_hollows,
        .text,
        => return error.ParserFailed,
    }
    unreachable;
}

fn randomize(program: *Program) !void {
    const allocator = program.allocator;
    const random = &rand.DefaultPrng.init(program.options.seed).random;

    var z: usize = 0;
    var excluded_pockets_buffer: [2]format.Pocket = undefined;
    var excluded_pockets = std.ArrayListUnmanaged(format.Pocket){
        .items = excluded_pockets_buffer[z..z],
        .capacity = excluded_pockets_buffer.len,
    };
    if (!program.options.include_tms_hms)
        excluded_pockets.appendAssumeCapacity(.tms_hms);
    if (!program.options.include_key_items)
        excluded_pockets.appendAssumeCapacity(.key_items);

    const pick_from = try getItems(
        allocator,
        program.items,
        excluded_pockets.items,
        program.options.excluded_items,
    );
    const max = pick_from.count();

    outer: for (program.pokeballs.values()) |*ball, i| {
        const ball_key = program.pokeballs.keys()[i];
        const item = program.items.get(ball_key) orelse continue;
        for (excluded_pockets.items) |excluded_pocket| {
            if (item.pocket == excluded_pocket)
                continue :outer;
        }

        ball.item = util.random.item(random, pick_from.keys()).?.*;
    }
}

const Items = std.AutoArrayHashMapUnmanaged(u16, Item);
const Pokeballs = std.AutoArrayHashMapUnmanaged(u16, Pokeball);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);

fn getItems(
    allocator: *mem.Allocator,
    items: Items,
    excluded_pockets: []const format.Pocket,
    excluded_items: []const []const u8,
) !Set {
    var res = Set{};
    errdefer res.deinit(allocator);

    outer: for (items.values()) |item, i| {
        const item_key = items.keys()[i];
        // Assume that items in the 'items' pocket with price 0 are useless or invalid items.
        if (item.price == 0 and item.pocket == .items)
            continue;

        for (excluded_pockets) |pocket| {
            if (item.pocket == pocket)
                continue :outer;
        }

        for (excluded_items) |glob| {
            if (util.glob.match(glob, item.name))
                continue :outer;
        }

        _ = try res.put(allocator, item_key, {});
    }

    return res;
}

const Item = struct {
    pocket: format.Pocket = .none,
    price: usize = 1,
    name: []u8 = "",
};

const Pokeball = struct {
    item: u16,
};

test "tm35-rand-pokeball-items" {
    const H = struct {
        fn item(
            comptime id: []const u8,
            comptime pocket: []const u8,
            comptime name: []const u8,
        ) []const u8 {
            return ".items[" ++ id ++ "].pocket=" ++ pocket ++ "\n" ++
                ".items[" ++ id ++ "].name=" ++ name ++ "\n";
        }

        fn pokeball(comptime id: []const u8, comptime it: []const u8) []const u8 {
            return ".pokeball_items[" ++ id ++ "].item=" ++ it ++ "\n";
        }
    };

    const items = H.item("0", "key_items", "item 0") ++
        H.item("1", "items", "item 1") ++
        H.item("2", "tms_hms", "item 2") ++
        H.item("3", "berries", "item 3");

    const result_prefix = items;
    const test_string = comptime result_prefix ++
        H.pokeball("0", "0") ++
        H.pokeball("1", "1") ++
        H.pokeball("2", "2") ++
        H.pokeball("3", "3");

    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=3",
    }, test_string, result_prefix ++
        \\.pokeball_items[0].item=0
        \\.pokeball_items[1].item=3
        \\.pokeball_items[2].item=2
        \\.pokeball_items[3].item=1
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=2",
        "--include-key-items",
    }, test_string, result_prefix ++
        \\.pokeball_items[0].item=1
        \\.pokeball_items[1].item=3
        \\.pokeball_items[2].item=2
        \\.pokeball_items[3].item=3
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=2",
        "--include-tms-hms",
    }, test_string, result_prefix ++
        \\.pokeball_items[0].item=0
        \\.pokeball_items[1].item=2
        \\.pokeball_items[2].item=3
        \\.pokeball_items[3].item=3
        \\
    );
    try util.testing.testProgram(Program, &[_][]const u8{
        "--seed=1",
        "--include-tms-hms",
        "--include-key-items",
    }, test_string, result_prefix ++
        \\.pokeball_items[0].item=1
        \\.pokeball_items[1].item=3
        \\.pokeball_items[2].item=0
        \\.pokeball_items[3].item=1
        \\
    );

    // Test excluding system by running 100 seeds and checking that none of them pick the
    // excluded pokemons
    var seed: u8 = 0;
    while (seed < 100) : (seed += 1) {
        var buf: [100]u8 = undefined;
        const seed_arg = try fmt.bufPrint(&buf, "--seed={}", .{seed});
        const out = try util.testing.runProgram(Program, &[_][]const u8{
            "--exclude=item 1",
            seed_arg,
        }, test_string);
        defer testing.allocator.free(out);

        try testing.expect(mem.indexOf(u8, out, ".item=1") == null);
    }
}
