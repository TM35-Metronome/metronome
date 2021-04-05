const clap = @import("clap");
const format = @import("format");
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

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help               Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-t, --include-tms-hms    Allow for tms/hms to be randomized (This might make the game impossible to complete).     ") catch unreachable,
        clap.parseParam("-k, --include-key-items  Allow for key items to be randomized (This might make the game impossible to complete).   ") catch unreachable,
        clap.parseParam("-s, --seed <INT>         The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-v, --version            Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-rand-pokeball-items ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nRandomizes the items found in pokeballs lying around. " ++
        "Doesn't work for hg and ss yet.\n" ++
        "\n" ++
        "Options:\n");
    try clap.help(writer, &params);
}

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) anyerror!void {
    const seed = try util.getSeed(args);
    const include_tms_hms = args.flag("--include-tms-hms");
    const include_key_items = args.flag("--include-key-items");

    const data = try handleInput(allocator, stdio.in, stdio.out);
    try randomize(
        allocator,
        data,
        seed,
        include_tms_hms,
        include_key_items,
    );
    try outputData(stdio.out, data);
}

fn handleInput(allocator: *mem.Allocator, reader: anytype, writer: anytype) !Data {
    var data = Data{};
    var fifo = util.io.Fifo(.Dynamic).init(allocator);
    while (try util.io.readLine(reader, &fifo)) |line| {
        parseLine(allocator, &data, line) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParserFailed => try writer.print("{}\n", .{line}),
        };
    }
    return data;
}

fn outputData(writer: anytype, data: Data) !void {
    for (data.pokeballs.items()) |ball| {
        try format.write(writer, format.Game.pokeball_item(ball.key, .{ .item = ball.value }));
    }
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !void {
    const parsed = try format.parseNoEscape(str);
    switch (parsed) {
        .pokeball_items => |items| switch (items.value) {
            .item => |item| {
                _ = try data.pokeballs.put(allocator, items.index, item);
                return;
            },
            .amount => return error.ParserFailed,
        },
        .items => |items| {
            const item = try data.items.getOrPutValue(allocator, items.index, Item{});
            switch (items.value) {
                .pocket => |pocket| item.value.pocket = pocket,
                .price => |price| item.value.price = price,
                .name,
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

fn randomize(
    allocator: *mem.Allocator,
    data: Data,
    seed: u64,
    include_tms_hms: bool,
    include_key_items: bool,
) !void {
    var random_adapt = rand.DefaultPrng.init(seed);
    const random = &random_adapt.random;

    var z: usize = 0;
    var pocket_blacklist_buffer: [2]format.Pocket = undefined;
    var pocket_blacklist = std.ArrayListUnmanaged(format.Pocket){
        .items = pocket_blacklist_buffer[z..z],
        .capacity = pocket_blacklist_buffer.len,
    };
    if (!include_tms_hms)
        pocket_blacklist.appendAssumeCapacity(.tms_hms);
    if (!include_key_items)
        pocket_blacklist.appendAssumeCapacity(.key_items);

    const pick_from = try data.getItems(allocator, pocket_blacklist.items);
    const max = pick_from.count();

    outer: for (data.pokeballs.items()) |*ball| {
        const item = data.items.get(ball.key) orelse continue;
        for (pocket_blacklist.items) |blacklisted_pocket| {
            if (item.pocket == blacklisted_pocket)
                continue :outer;
        }

        ball.value = util.random.item(random, pick_from.items()).?.key;
    }
}

const Items = std.AutoArrayHashMapUnmanaged(u16, Item);
const Pokeballs = std.AutoArrayHashMapUnmanaged(u16, u16);
const Set = std.AutoArrayHashMapUnmanaged(u16, void);

const Data = struct {
    pokeballs: Pokeballs = Pokeballs{},
    items: Items = Items{},

    fn getItems(
        d: Data,
        allocator: *mem.Allocator,
        pocket_blacklist: []const format.Pocket,
    ) !Set {
        var res = Set{};
        errdefer res.deinit(allocator);

        outer: for (d.items.items()) |item| {
            // Assume that items in the 'items' pocket with price 0 is
            // none useful or invalid items.
            if (item.value.price == 0 and item.value.pocket == .items)
                continue;

            for (pocket_blacklist) |blacklisted_pocket| {
                if (item.value.pocket == blacklisted_pocket)
                    continue :outer;
            }

            _ = try res.put(allocator, item.key, {});
        }

        return res;
    }
};

const Item = struct {
    pocket: format.Pocket = .none,
    price: usize = 1,
};

test "tm35-rand-pokeball-items" {
    const H = struct {
        fn item(comptime id: []const u8, comptime pocket: []const u8) []const u8 {
            return ".items[" ++ id ++ "].pocket=" ++ pocket ++ "\n";
        }

        fn pokeball(comptime id: []const u8, comptime it: []const u8) []const u8 {
            return ".pokeball_items[" ++ id ++ "].item=" ++ it ++ "\n";
        }
    };

    const items = H.item("0", "key_items") ++
        H.item("1", "items") ++
        H.item("2", "tms_hms") ++
        H.item("3", "berries");

    const result_prefix = items;
    const test_string = comptime result_prefix ++
        H.pokeball("0", "0") ++
        H.pokeball("1", "1") ++
        H.pokeball("2", "2") ++
        H.pokeball("3", "3");

    util.testing.testProgram(main2, &params, &[_][]const u8{"--seed=3"}, test_string, result_prefix ++
        \\.pokeball_items[0].item=0
        \\.pokeball_items[1].item=3
        \\.pokeball_items[2].item=2
        \\.pokeball_items[3].item=1
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=2", "--include-key-items" }, test_string, result_prefix ++
        \\.pokeball_items[0].item=1
        \\.pokeball_items[1].item=3
        \\.pokeball_items[2].item=2
        \\.pokeball_items[3].item=3
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=2", "--include-tms-hms" }, test_string, result_prefix ++
        \\.pokeball_items[0].item=0
        \\.pokeball_items[1].item=2
        \\.pokeball_items[2].item=3
        \\.pokeball_items[3].item=3
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{ "--seed=1", "--include-tms-hms", "--include-key-items" }, test_string, result_prefix ++
        \\.pokeball_items[0].item=1
        \\.pokeball_items[1].item=3
        \\.pokeball_items[2].item=0
        \\.pokeball_items[3].item=1
        \\
    );
}
