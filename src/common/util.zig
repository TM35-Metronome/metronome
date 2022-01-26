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

pub const args = @import("args.zig");
pub const bit = @import("bit.zig");
pub const escape = @import("escape.zig");
pub const glob = @import("glob.zig");
pub const io = @import("io.zig");
pub const random = @import("random.zig");
pub const set = @import("set.zig");
pub const testing = @import("testing.zig");
pub const unicode = @import("unicode.zig");
pub const unsafe = @import("unsafe.zig");

test {
    std.testing.refAllDecls(@This());
}

pub fn generateMain(comptime Program: type) fn () anyerror!void {
    return struct {
        fn main() anyerror!void {

            // No need to deinit arena. The program will exit when this function
            // ends and all the memory will be freed by the os. This saves a bit
            // of shutdown time.
            var arena = heap.ArenaAllocator.init(heap.page_allocator);
            var diag = clap.Diagnostic{};
            var arguments = clap.parse(clap.Help, Program.params, .{
                .diagnostic = &diag,
            }) catch |err| {
                var stderr = std.io.bufferedWriter(std.io.getStdErr().writer());
                diag.report(stderr.writer(), err) catch {};
                usage(stderr.writer()) catch {};
                stderr.flush() catch {};
                return error.InvalidArgument;
            };

            if (arguments.flag("--help")) {
                var stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
                try usage(stdout.writer());
                try stdout.flush();
                return;
            }

            if (arguments.flag("--version")) {
                var stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
                try stdout.writer().writeAll(Program.version);
                try stdout.writer().writeAll("\n");
                try stdout.flush();
                return;
            }

            var stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
            var program = try Program.init(arena.allocator(), arguments);
            try program.run(std.fs.File.Reader, @TypeOf(stdout.writer()), .{
                .in = std.io.getStdIn().reader(),
                .out = stdout.writer(),
            });

            try stdout.flush();
        }

        fn usage(writer: anytype) !void {
            try writer.writeAll("Usage: ");
            try writer.writeAll(@typeName(Program));
            try writer.writeAll(" ");
            try clap.usage(writer, Program.params);
            try writer.writeAll("\n");
            try writer.writeAll(Program.description);
            try writer.writeAll("\nOptions:\n");
            try clap.help(writer, Program.params);
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
        try std.testing.expectEqual(i, indexOfPtr(u8, arr, item));
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

pub const Path = std.BoundedArray(u8, fs.MAX_PATH_BYTES);

pub const path = struct {
    pub fn join(paths: []const []const u8) Path {
        var res: Path = undefined;

        // FixedBufferAllocator + FailingAllocator are used here to ensure that a max
        // of MAX_PATH_BYTES is allocated, and that only one allocation occures. This
        // ensures that only a valid path has been allocated into res.
        var fba = heap.FixedBufferAllocator.init(&res.buffer);
        var failing = std.testing.FailingAllocator.init(fba.allocator(), 1);
        const res_slice = fs.path.join(failing.allocator(), paths) catch unreachable;
        res.len = res_slice.len;

        return res;
    }

    pub fn resolve(paths: []const []const u8) !Path {
        var res: Path = undefined;

        // FixedBufferAllocator + FailingAllocator are used here to ensure that a max
        // of MAX_PATH_BYTES is allocated, and that only one allocation occures. This
        // ensures that only a valid path has been allocated into res.
        var fba = heap.FixedBufferAllocator.init(&res.buffer);
        var failing = debug.FailingAllocator.init(&fba.allocator, 1);
        const res_slice = fs.path.resolve(&failing.allocator, paths) catch |err| switch (err) {
            error.OutOfMemory => unreachable,
            else => |e| return e,
        };
        res.len = res_slice.len;

        return res;
    }

    pub fn basenameNoExt(p: []const u8) []const u8 {
        const basename = fs.path.basename(p);
        const ext = fs.path.extension(basename);
        return basename[0 .. basename.len - ext.len];
    }
};

pub const dir = struct {
    pub fn selfExeDir() !Path {
        var res: Path = undefined;
        const res_slice = try fs.selfExeDirPath(&res.buffer);
        res.len = res_slice.len;
        return res;
    }

    pub fn cwd() !Path {
        var res: Path = undefined;
        const res_slice = try os.getcwd(&res.buffer);
        res.len = res_slice.len;
        return res;
    }

    pub fn folder(f: folders.KnownFolder) !Path {
        var buf: [fs.MAX_PATH_BYTES * 2]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(&buf);
        const res = (try folders.getPath(fba.allocator(), f)) orelse
            return error.NotAvailable;
        return Path.fromSlice(res);
    }
};
