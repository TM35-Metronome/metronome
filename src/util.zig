/// Given a slice and a pointer, returns the pointers index into the slice.
/// ptr has to point into slice.
pub fn indexOfPtr(comptime T: type, slice: []const T, ptr: *const T) usize {
    const start = @intFromPtr(slice.ptr);
    const item = @intFromPtr(ptr);
    const dist_from_start = item - start;
    const res = @divExact(dist_from_start, @sizeOf(T));
    std.debug.assert(res < slice.len);
    return res;
}

test "indexOfPtr" {
    const arr = "abcde";
    for (arr, 0..) |*item, i| {
        try std.testing.expectEqual(i, indexOfPtr(u8, arr, item));
    }
}

/// A datastructure representing an array that is either terminated at
/// `sentinel` or at `n`.
pub fn TerminatedArray(comptime n: usize, comptime T: type, comptime sentinel: T) type {
    return extern struct {
        data: [n]T,

        pub fn slice(array: anytype) Slice(@TypeOf(array)) {
            const i = std.mem.indexOfScalar(T, &array.data, sentinel) orelse return &array.data;
            return array.data[0..i];
        }

        fn Slice(comptime Ptr: type) type {
            var info = @typeInfo(Ptr);
            info.pointer.size = .slice;
            info.pointer.child = T;
            return @Type(info);
        }
    };
}

pub const Path = std.BoundedArray(u8, std.fs.MAX_PATH_BYTES);

pub const path = struct {
    pub fn join(paths: []const []const u8) Path {
        var res: Path = undefined;

        // FixedBufferAllocator + FailingAllocator are used here to ensure that a max
        // of MAX_PATH_BYTES is allocated, and that only one allocation occurs. This
        // ensures that only a valid path has been allocated into res.
        var fba = std.heap.FixedBufferAllocator.init(&res.buffer);
        var failing = std.testing.FailingAllocator.init(fba.allocator(), .{
            .fail_index = 1,
            .resize_fail_index = 0,
        });
        const res_slice = std.fs.path.join(failing.allocator(), paths) catch unreachable;
        res.len = @intCast(res_slice.len);

        return res;
    }

    pub fn basenameNoExt(p: []const u8) []const u8 {
        const basename = std.fs.path.basename(p);
        const ext = std.fs.path.extension(basename);
        return basename[0 .. basename.len - ext.len];
    }
};

pub const dir = struct {
    pub fn selfExeDir() !Path {
        var res: Path = undefined;
        const res_slice = try std.fs.selfExeDirPath(&res.buffer);
        res.len = @intCast(res_slice.len);
        return res;
    }

    pub fn cwd() !Path {
        var res: Path = undefined;
        const res_slice = try std.os.getcwd(&res.buffer);
        res.len = @intCast(res_slice.len);
        return res;
    }

    pub fn folder(f: folders.KnownFolder) !Path {
        var buf: [std.fs.MAX_PATH_BYTES * 2]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const res = (try folders.getPath(fba.allocator(), f)) orelse
            return error.NotAvailable;
        return Path.fromSlice(res);
    }
};

test {
    _ = bit;
    _ = escape;
    _ = glob;
    _ = io;
    _ = set;
    _ = unicode;
}

pub const bit = @import("util/bit.zig");
pub const escape = @import("util/escape.zig");
pub const glob = @import("util/glob.zig");
pub const io = @import("util/io.zig");
pub const set = @import("util/set.zig");
pub const unicode = @import("util/unicode.zig");

const folders = @import("folders");
const std = @import("std");
