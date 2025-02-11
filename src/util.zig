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

test {
    _ = bit;
    _ = glob;
    _ = set;
}

pub const bit = @import("util/bit.zig");
pub const glob = @import("util/glob.zig");
pub const set = @import("util/set.zig");

const std = @import("std");
