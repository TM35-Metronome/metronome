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
) u8 {
    const seed = if (args.option("--seed")) |seed|
        fmt.parseUnsigned(u64, seed, 10) catch |err| {
            stdio.err.print("'{}' could not be parsed as a number to --seed: {}\n", .{ seed, err }) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    else blk: {
        var buf: [8]u8 = undefined;
        os.getrandom(buf[0..]) catch break :blk @as(u64, 0);
        break :blk mem.readInt(u64, &buf, .Little);
    };

    const include_tms_hms = args.flag("--include-tms-hms");
    const include_key_items = args.flag("--include-key-items");

    var fifo = util.read.Fifo(.Dynamic).init(allocator);
    var data = Data{
        .strings = std.StringHashMap(usize).init(allocator),
    };
    while (util.read.line(stdio.in, &fifo) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        const str = mem.trimRight(u8, line, "\r\n");
        const print_line = parseLine(allocator, &data, str) catch |err| switch (err) {
            error.OutOfMemory => return exit.allocErr(stdio.err),
            error.ParseError => true,
        };
        if (print_line)
            stdio.out.print("{}\n", .{str}) catch |err| return exit.stdoutErr(stdio.err, err);
    }

    randomize(allocator, &data, seed, include_tms_hms, include_key_items) catch |err| return exit.randErr(stdio.err, err);

    for (data.pokeballs.values()) |ball, i| {
        const key = data.pokeballs.at(i).key;
        stdio.out.print(".pokeball_items[{}].item={}\n", .{ key, ball }) catch |err| return exit.stdoutErr(stdio.err, err);
    }
    return 0;
}

fn parseLine(allocator: *mem.Allocator, data: *Data, str: []const u8) !bool {
    const sw = parse.Swhash(16);
    const m = sw.match;
    const c = sw.case;
    var p = parse.MutParser{ .str = str };

    switch (m(try p.parse(parse.anyField))) {
        c("pokeball_items") => {
            const ball_index = try p.parse(parse.index);
            _ = try p.parse(comptime parse.field("item"));
            const ball_item = try p.parse(parse.usizev);
            _ = try data.pokeballs.put(allocator, ball_index, ball_item);
            return false;
        },
        c("items") => {
            const index = try p.parse(parse.index);
            const item = try data.items.getOrPutValue(allocator, index, Item{});
            switch (m(try p.parse(parse.anyField))) {
                c("pocket") => item.pocket = try data.string(try p.parse(parse.strv)),
                c("price") => item.price = try p.parse(parse.usizev),
                else => return true,
            }

            return true;
        },
        else => return true,
    }

    return true;
}

fn randomize(
    allocator: *mem.Allocator,
    data: *Data,
    seed: u64,
    include_tms_hms: bool,
    include_key_items: bool,
) !void {
    var random_adapt = rand.DefaultPrng.init(seed);
    const random = &random_adapt.random;

    var pocket_blacklist_buffer: [2]usize = undefined;
    const pocket_blacklist = blk: {
        var list = std.ArrayList(usize).fromOwnedSlice(std.testing.failing_allocator, &pocket_blacklist_buffer);
        list.resize(0) catch unreachable;
        if (!include_tms_hms)
            list.append(try data.string("tms_hms")) catch unreachable;
        if (!include_key_items)
            list.append(try data.string("key_items")) catch unreachable;
        break :blk list.items;
    };

    const pick_from = try data.getItems(allocator, pocket_blacklist);
    const max = pick_from.count();

    outer: for (data.pokeballs.values()) |*ball, i| {
        const key = data.pokeballs.at(i).key;
        const item = data.items.get(key) orelse continue;
        for (pocket_blacklist) |blacklisted_pocket| {
            if (item.pocket == blacklisted_pocket)
                continue :outer;
        }

        ball.* = pick_from.at(random.intRangeLessThan(usize, 0, max));
    }
}

const Set = util.container.IntSet.Unmanaged(usize);
const Pokeballs = util.container.IntMap.Unmanaged(usize, usize);
const Items = util.container.IntMap.Unmanaged(usize, Item);

const Data = struct {
    strings: std.StringHashMap(usize),
    pokeballs: Pokeballs = Pokeballs{},
    items: Items = Items{},

    fn string(d: *Data, str: []const u8) !usize {
        const res = try d.strings.getOrPut(str);
        if (!res.found_existing) {
            res.entry.key = try mem.dupe(d.strings.allocator, u8, str);
            res.entry.value = d.strings.count() - 1;
        }
        return res.entry.value;
    }

    fn getItems(d: *Data, allocator: *mem.Allocator, pocket_blacklist: []const usize) !Set {
        var res = Set{};
        errdefer res.deinit(allocator);

        const items_pocket = try d.string("items");

        outer: for (d.items.values()) |item, i| {
            for (pocket_blacklist) |blacklisted_pocket| {
                if (item.pocket == blacklisted_pocket)
                    continue :outer;
                // Assume that items in the 'items' pocket with price 0 is
                // none useful or invalid items.
                if (item.price == 0 and item.pocket == items_pocket)
                    continue :outer;
            }

            _ = try res.put(allocator, d.items.at(i).key);
        }

        return res;
    }
};

const Item = struct {
    pocket: usize = math.maxInt(usize),
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
