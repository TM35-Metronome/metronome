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

const BufInStream = io.BufferedInStream(fs.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);

const Clap = clap.ComptimeClap(clap.Help, params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help        Display this help text and exit.                                                          ") catch unreachable,
        clap.parseParam("-s, --seed <NUM>  The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
        clap.parseParam("-v, --version     Output version information and exit.                                                      ") catch unreachable,
    };
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-pokeball-items [-hv] [-s <NUM>]
        \\Randomizes static Pokémons.
        \\Only works properly for dppt and b2w2.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    var stdio_unbuf = util.getStdIo() catch |err| return 1;
    var stdio = stdio_unbuf.getBuffered();
    defer stdio.err.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(&arena.allocator) catch
        return errors.allocErr(&stdio.err.stream);
    const res = main2(
        &arena.allocator,
        fs.File.ReadError,
        fs.File.WriteError,
        stdio.getStreams(),
        clap.args.OsIterator,
        &arg_iter,
    );

    stdio.out.flush() catch |err| return errors.writeErr(&stdio.err.stream, "<stdout>", err);
    return res;
}

pub fn main2(
    allocator: *mem.Allocator,
    comptime ReadError: type,
    comptime WriteError: type,
    stdio: util.CustomStdIoStreams(ReadError, WriteError),
    comptime ArgIterator: type,
    arg_iter: *ArgIterator,
) u8 {
    var stdin = io.BufferedInStream(ReadError).init(stdio.in);
    var args = Clap.parse(allocator, ArgIterator, arg_iter) catch |err| {
        stdio.err.print("{}\n", err) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    if (args.flag("--help")) {
        usage(stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.print("{}\n", program_version) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    const seed = if (args.option("--seed")) |seed|
        fmt.parseUnsigned(u64, seed, 10) catch |err| {
            stdio.err.print("'{}' could not be parsed as a number to --seed: {}\n", seed, err) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    else blk: {
        var buf: [8]u8 = undefined;
        os.getrandom(buf[0..]) catch break :blk u64(0);
        break :blk mem.readInt(u64, &buf, .Little);
    };

    var line_buf = std.Buffer.initSize(allocator, 0) catch |err| return errors.allocErr(stdio.err);
    var data = Data{
        .items = Items.init(allocator),
        .pokeballs = Pokeballs.init(allocator),
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
            stdio.out.print("{}\n", str) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);

        line_buf.shrink(0);
    }

    randomize(data, seed) catch |err| return errors.randErr(stdio.err, err);

    var it = data.pokeballs.iterator();
    while (it.next()) |kv| {
        stdio.out.print(".pokeball_items[{}]={}\n", kv.key, kv.value) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
    }
    return 0;
}

fn parseLine(data: *Data, str: []const u8) !bool {
    const allocator = data.pokeballs.allocator;
    var parser = format.Parser{ .str = str };

    if (parser.eatField("pokeball_items")) |_| {
        const ball_index = try parser.eatIndex();
        const ball_item = try parser.eatUnsignedValue(usize, 10);
        _ = try data.pokeballs.put(ball_index, ball_item);
        return false;
    } else |_| if (parser.eatField("items")) |_| {
        const index = try parser.eatIndex();
        const item_entry = try data.items.getOrPutValue(index, Item{ .pocket = null });

        if (parser.eatField("pocket")) |_| {
            item_entry.value.pocket = try mem.dupe(allocator, u8, try parser.eatValue());
        } else |_| {}
    } else |_| {}

    return true;
}

fn randomize(data: Data, seed: u64) !void {
    var random_adapt = rand.DefaultPrng.init(seed);
    const random = &random_adapt.random;

    const pick_from = try data.nonKeyItems();

    var it = data.pokeballs.iterator();
    while (it.next()) |kv| {
        const item = (data.items.get(kv.value) orelse continue).value;
        const pocket = item.pocket orelse continue;
        if (mem.eql(u8, pocket, "KeyItems"))
            continue; // Don't randomize items that are key items (they are probably needed for progression)

        kv.value = pick_from[random.range(usize, 0, pick_from.len)];
    }
}

const Pokeballs = std.AutoHashMap(usize, usize);
const Items = std.AutoHashMap(usize, Item);

const Data = struct {
    pokeballs: Pokeballs,
    items: Items,

    fn nonKeyItems(d: Data) ![]usize {
        var res = std.ArrayList(usize).init(d.pokeballs.allocator);
        errdefer res.deinit();

        var it = d.items.iterator();
        while (it.next()) |item_kv| {
            const item = item_kv.value;
            const pocket = item.pocket orelse continue;
            if (mem.eql(u8, pocket, "KeyItems"))
                continue;

            try res.append(item_kv.key);
        }

        return res.toOwnedSlice();
    }
};

const Item = struct {
    pocket: ?[]const u8,
};

test "tm35-rand-pokeball-items" {
    const H = struct {
        fn item(comptime id: []const u8, comptime pocket: []const u8) []const u8 {
            return ".items[" ++ id ++ "].pocket=" ++ pocket ++ "\n";
        }

        fn pokeball(comptime id: []const u8, comptime it: []const u8) []const u8 {
            return ".pokeball_items[" ++ id ++ "]=" ++ it ++ "\n";
        }
    };

    const items = H.item("0", "KeyItems") ++
        H.item("1", "Items") ++
        H.item("2", "HmTms") ++
        H.item("3", "Berries");

    const result_prefix = items;
    const test_string = comptime result_prefix ++
        H.pokeball("0", "0") ++
        H.pokeball("1", "1") ++
        H.pokeball("2", "2") ++
        H.pokeball("3", "3");

    testProgram([_][]const u8{"--seed=0"}, test_string, result_prefix ++
        \\.pokeball_items[3]=3
        \\.pokeball_items[1]=3
        \\.pokeball_items[2]=3
        \\.pokeball_items[0]=0
        \\
    );

    testProgram([_][]const u8{"--seed=1"}, test_string, result_prefix ++
        \\.pokeball_items[3]=3
        \\.pokeball_items[1]=2
        \\.pokeball_items[2]=3
        \\.pokeball_items[0]=0
        \\
    );

    testProgram([_][]const u8{"--seed=2"}, test_string, result_prefix ++
        \\.pokeball_items[3]=1
        \\.pokeball_items[1]=2
        \\.pokeball_items[2]=2
        \\.pokeball_items[0]=0
        \\
    );
}

fn testProgram(
    args: []const []const u8,
    in: []const u8,
    out: []const u8,
) void {
    var alloc_buf: [1024 * 50]u8 = undefined;
    var out_buf: [1024 * 10]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&alloc_buf);
    var stdin = io.SliceInStream.init(in);
    var stdout = io.SliceOutStream.init(&out_buf);
    var stderr = io.SliceOutStream.init(&err_buf);
    var arg_iter = clap.args.SliceIterator{ .args = args };

    const StdIo = util.CustomStdIoStreams(anyerror, anyerror);

    const res = main2(
        &fba.allocator,
        anyerror,
        anyerror,
        StdIo{
            .in = @ptrCast(*io.InStream(anyerror), &stdin.stream),
            .out = @ptrCast(*io.OutStream(anyerror), &stdout.stream),
            .err = @ptrCast(*io.OutStream(anyerror), &stderr.stream),
        },
        clap.args.SliceIterator,
        &arg_iter,
    );
    debug.warn("{}", stderr.getWritten());
    testing.expectEqual(u8(0), res);
    testing.expectEqualSlices(u8, "", stderr.getWritten());
    if (!mem.eql(u8, out, stdout.getWritten())) {
        debug.warn("\n====== expected this output: =========\n");
        debug.warn("{}", out);
        debug.warn("\n======== instead found this: =========\n");
        debug.warn("{}", stdout.getWritten());
        debug.warn("\n======================================\n");
        testing.expect(false);
    }
    testing.expectEqualSlices(u8, out, stdout.getWritten());
}
