const builtin = @import("builtin");
const clap = @import("clap");
const folders = @import("folders");
const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const log = std.log;
const math = std.math;
const mem = std.mem;
const os = std.os;

pub const algorithm = @import("algorithm.zig");
pub const bit = @import("bit.zig");
pub const escape = @import("escape.zig");
pub const io = @import("io.zig");
pub const random = @import("random.zig");
pub const set = @import("set.zig");
pub const testing = @import("testing.zig");
pub const unicode = @import("unicode.zig");
pub const unsafe = @import("unsafe.zig");

test "" {
    _ = algorithm;
    _ = bit;
    _ = escape;
    _ = io;
    _ = random;
    _ = set;
    _ = testing;
    _ = unicode;
    _ = unsafe;
}

pub fn getSeed(args: anytype) !u64 {
    if (args.option("--seed")) |seed| {
        return fmt.parseUnsigned(u64, seed, 10) catch |err| {
            log.err("'{}' could not be parsed as a number to --seed: {}\n", .{ seed, err });
            return error.InvalidSeed;
        };
    } else {
        var buf: [8]u8 = undefined;
        os.getrandom(buf[0..]) catch return @as(u64, 0);
        return mem.readInt(u64, &buf, .Little);
    }
}

pub fn generateMain(
    version: []const u8,
    comptime main2: anytype,
    comptime params: []const clap.Param(clap.Help),
    comptime usage: anytype,
) fn () anyerror!void {
    return struct {
        fn main() anyerror!void {

            // No need to deinit arena. The program will exit when this function
            // ends and all the memory will be freed by the os. This saves a bit
            // of shutdown time.
            var arena = heap.ArenaAllocator.init(heap.page_allocator);
            var diag = clap.Diagnostic{};
            var args = clap.parse(clap.Help, params, &arena.allocator, &diag) catch |err| {
                var stderr = io.bufferedWriter(std.io.getStdErr().writer());
                diag.report(stderr.writer(), err) catch {};
                usage(stderr.writer()) catch {};
                stderr.flush() catch {};
                return error.InvalidArgument;
            };

            if (args.flag("--help")) {
                var stdout = io.bufferedWriter(std.io.getStdOut().writer());
                try usage(stdout.writer());
                try stdout.flush();
                return;
            }

            if (args.flag("--version")) {
                var stdout = io.bufferedWriter(std.io.getStdOut().writer());
                try stdout.writer().print("{}\n", .{version});
                try stdout.flush();
                return;
            }

            var stdout = io.bufferedWriter(std.io.getStdOut().writer());
            const res = main2(&arena.allocator, std.fs.File.Reader, @TypeOf(stdout.writer()), .{
                .in = std.io.getStdIn().reader(),
                .out = stdout.writer(),
            }, args);

            try stdout.flush();
            return res;
        }
    }.main;
}

pub fn CustomStdIoStreams(comptime _Reader: type, comptime _Writer: type) type {
    return struct {
        pub const Reader = _Reader;
        pub const Writer = _Writer;

        in: Reader,
        out: Writer,
    };
}

/// Given a slice and a pointer, returns the pointers index into the slice.
/// ptr has to point into slice.
pub fn indexOfPtr(comptime T: type, slice: []const T, ptr: *const T) usize {
    const start = @ptrToInt(slice.ptr);
    const item = @ptrToInt(ptr);
    const dist_from_start = item - start;
    const res = @divExact(dist_from_start, @sizeOf(T));
    debug.assert(res < slice.len);
    return res;
}

test "indexOfPtr" {
    const arr = "abcde";
    for (arr) |*item, i| {
        std.testing.expectEqual(i, indexOfPtr(u8, arr, item));
    }
}

/// A datastructure representing an array that is either terminated at
/// `sentinel` or at `n`.
pub fn TerminatedArray(comptime n: usize, comptime T: type, comptime sentinel: T) type {
    return extern struct {
        data: [n]T,

        pub fn span(array: anytype) mem.Span(@TypeOf(&array.data)) {
            const i = mem.indexOfScalar(T, &array.data, sentinel) orelse return &array.data;
            return array.data[0..i];
        }
    };
}

pub fn StackArrayList(comptime size: usize, comptime T: type) type {
    return struct {
        items: [size]T = undefined,
        len: usize = 0,

        pub fn fromSlice(items: []const T) !@This() {
            if (size < items.len)
                return error.SliceToBig;

            var res: @This() = undefined;
            mem.copy(T, &res.items, items);
            res.len = items.len;
            return res;
        }

        pub fn toSlice(list: *@This()) []T {
            return list.items[0..list.len];
        }

        pub fn toSliceConst(list: *const @This()) []const T {
            return list.items[0..list.len];
        }
    };
}

pub const Path = StackArrayList(fs.MAX_PATH_BYTES, u8);

pub const path = struct {
    pub fn join(paths: []const []const u8) Path {
        var res: Path = undefined;

        // FixedBufferAllocator + FailingAllocator are used here to ensure that a max
        // of MAX_PATH_BYTES is allocated, and that only one allocation occures. This
        // ensures that only a valid path has been allocated into res.
        var fba = heap.FixedBufferAllocator.init(&res.items);
        var failing = std.testing.FailingAllocator.init(&fba.allocator, 1);
        const res_slice = fs.path.join(&failing.allocator, paths) catch unreachable;
        res.len = res_slice.len;

        return res;
    }

    pub fn resolve(paths: []const []const u8) !Path {
        var res: Path = undefined;

        // FixedBufferAllocator + FailingAllocator are used here to ensure that a max
        // of MAX_PATH_BYTES is allocated, and that only one allocation occures. This
        // ensures that only a valid path has been allocated into res.
        var fba = heap.FixedBufferAllocator.init(&res.items);
        var failing = debug.FailingAllocator.init(&fba.allocator, math.maxInt(usize));
        const res_slice = try fs.path.resolve(&failing.allocator, paths);
        res.len = res_slice.len;
        debug.assert(failing.allocations == 1);

        return res;
    }
};

pub const dir = struct {
    pub fn selfExeDir() !Path {
        var res: Path = undefined;
        const res_slice = try fs.selfExeDirPath(&res.items);
        res.len = res_slice.len;
        return res;
    }

    pub fn cwd() !Path {
        var res: Path = undefined;
        const res_slice = try os.getcwd(&res.items);
        res.len = res_slice.len;
        return res;
    }

    pub fn folder(f: folders.KnownFolder) !Path {
        var buf: [fs.MAX_PATH_BYTES * 2]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(&buf);
        const res = (try folders.getPath(&fba.allocator, f)) //
            orelse return error.NotAvailable;
        return Path.fromSlice(res);
    }
};
