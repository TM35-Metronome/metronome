const int = @import("int.zig");
const std = @import("std");

const builtin = std.builtin;

pub const Error = error{InvalidPointer};

/// A data structure representing a relative pointer in binary data.
/// Useful for decoding binary data using only `packed` structs.
pub fn RelativePointer(
    /// The pointer type that this relative pointer represents
    comptime Ptr: type,
    /// The integer used as the storage for the pointer
    comptime Int: type,
    /// The endian of the backing integer
    comptime endian: builtin.Endian,
    /// An external offset that is subtracted from the inner
    /// integer before it is converted to a real pointer.
    comptime offset: comptime_int,
    /// The value of the null pointer. Only used if `Ptr` is
    /// an optional pointer.
    comptime null_ptr: comptime_int,
) type {
    return extern struct {
        inner: Inner,

        const Inner = int.Int(Int, endian);
        const Slice = @Type(blk: {
            var info = ptr_info;
            info.size = .Slice;
            break :blk builtin.Type{ .Pointer = info };
        });
        const SliceNoSentinel = @Type(blk: {
            var info = ptr_info;
            info.size = .Slice;
            info.sentinel = null;
            break :blk builtin.Type{ .Pointer = info };
        });
        const NonOptionalPtr = switch (@typeInfo(Ptr)) {
            .Optional => |opt| opt.child,
            else => Ptr,
        };
        const ptr_info = @typeInfo(NonOptionalPtr).Pointer;
        const child_size: usize = @sizeOf(ptr_info.child);
        const Data = if (ptr_info.is_const) []const u8 else []u8;
        const is_optional = @typeInfo(Ptr) == .Optional;
        const ptr_sentinel = @ptrCast(*const ptr_info.child, ptr_info.sentinel.?).*;

        /// Given a slice of data, and a pointer that points into this
        /// data, construct a `RelativePointer`.
        pub fn init(ptr: anytype, data: []const u8) Error!@This() {
            const ptr_is_optional = @typeInfo(@TypeOf(ptr)) == .Optional or
                @typeInfo(@TypeOf(ptr)) == .Null;
            if (is_optional and ptr_is_optional and ptr == null)
                return @This(){ .inner = Inner.init(null_ptr) };

            const i = @intCast(Int, @ptrToInt(ptr) - @ptrToInt(data.ptr));
            if (data.len < i + child_size)
                return error.InvalidPointer;

            const res = std.math.add(Int, i, offset) //
            catch return error.InvalidPointer;
            return @This(){ .inner = Inner.init(res) };
        }

        /// Convert a `RelativePointer` to a pointer to within `data`.
        pub fn toPtr(ptr: @This(), data: Data) Error!Ptr {
            if (is_optional and ptr.inner.value() == null_ptr)
                return null;

            const i = try ptr.toInt();
            if (data.len < i + child_size * @boolToInt(ptr_info.size == .One))
                return error.InvalidPointer;

            return @ptrCast(Ptr, @alignCast(ptr_info.alignment, &data[i]));
        }

        /// Converts a `RelativePointer` to an unknown number of
        /// elements to a slice.
        pub fn toSlice(ptr: @This(), data: Data, len: usize) Error!SliceNoSentinel {
            if (is_optional and ptr.inner.value() == null_ptr)
                return @as(NonOptionalPtr, undefined)[0..0];
            if (len == 0)
                return @as(NonOptionalPtr, undefined)[0..0];

            const p = try ptr.toPtr(data);
            const start = @ptrToInt(p) - @ptrToInt(data.ptr);
            const end = start + len * child_size;
            if (data.len < end)
                return error.InvalidPointer;

            return if (is_optional) p.?[0..len] else p[0..len];
        }

        /// Converts a `RelativePointer` to an unknown number of
        /// elements to a slice that contains as many elements as
        /// possible from the pointer to the end of `data`.
        pub fn toSliceEnd(ptr: @This(), data: Data) Error!SliceNoSentinel {
            const rest = std.math.sub(usize, data.len, try ptr.toInt()) catch
                return error.InvalidPointer;
            return ptr.toSlice(data, rest / child_size);
        }

        /// Converts a `RelativePointer` to an unknown number of
        /// elements to a slice that contains all the elements until
        /// the sentinel.
        pub fn toSliceZ(ptr: @This(), data: Data) Error!Slice {
            const res = try ptr.toSliceEnd(data);
            for (res, 0..) |item, len| {
                if (std.meta.eql(item, ptr_sentinel))
                    return res[0..len :ptr_sentinel];
            }

            return error.InvalidPointer;
        }

        /// Converts a `RelativePointer` to an unknown number of
        /// elements to a slice that contains all the elements until
        /// the sentinel.
        pub fn toSliceZ2(ptr: @This(), data: Data, sentinel: ptr_info.child) Error!SliceNoSentinel {
            const res = try ptr.toSliceEnd(data);
            for (res, 0..) |item, len| {
                if (std.meta.eql(item, sentinel))
                    return res[0..len];
            }

            return error.InvalidPointer;
        }

        fn toInt(ptr: @This()) Error!Int {
            return std.math.sub(Int, ptr.inner.value(), offset) //
            catch return error.InvalidPointer;
        }
    };
}

// zig fmt: off
test "RelativePointer" {
    @setEvalBranchQuota(100000000);
    inline for ([_]bool{true, false}) |is_optional|
    inline for ([_]builtin.Endian{.Little,.Big}) |endian|
    inline for ([_]usize{25,50,75}) |offset|
    inline for ([_]usize{0,4,100}) |null_ptr|
    inline for ([_]type{u8, u16, u32}) |Child|
    inline for ([_]type{u8, u16, u32}) |Int| {
        const Ptr = if (is_optional) ?*Child else *Child;
        const RPtr = RelativePointer(
            Ptr,
            Int,
            endian,
            offset,
            null_ptr,
        );
        const RPtr2 = RelativePointer(
            [*]Child,
            Int,
            endian,
            offset,
            null_ptr,
        );
        var data = [_]Child{2, 4, 6, 8, 10};
        const bytes = if (Child != u8) std.mem.sliceAsBytes(&data) else &data;
        for (data) |*expect| {
            const p = try RPtr.init(expect, bytes);
            const actual = if (is_optional) (try p.toPtr(bytes)).?
                else try p.toPtr(bytes);
            try std.testing.expectEqual(expect, actual);
        }
        if (is_optional) {
            const p = try RPtr.init(null, bytes);
            try std.testing.expectEqual(@as(Ptr, null), try p.toPtr(bytes));
        }
        for (0..4) |i| {
            const expect = data[i..i+1];
            const p = try RPtr2.init(expect.ptr, bytes);
            const actual = try p.toSlice(bytes, 1);
            try std.testing.expectEqualSlices(Child, expect, actual);
        }
    };
}
// zig fmt: on

pub const Layout = enum {
    pointer_first,
    len_first,
};

pub fn RelativeSlice(
    /// The slice type that this relative slice represents
    comptime Slice: type,
    /// The integer used as the storage for both pointer and length
    comptime Int: type,
    /// The endian of the backing integer
    comptime endian: builtin.Endian,
    /// The layout of the slice
    comptime layout: Layout,
    /// An external offset that is subtracted from the inner
    /// integer before it is converted to a real slice.
    comptime offset: comptime_int,
) type {
    return extern struct {
        inner: Inner,

        const Ptr = @Type(builtin.Type{
            .Pointer = .{
                .size = .Many,
                .is_const = @typeInfo(Slice).Pointer.is_const,
                .is_volatile = @typeInfo(Slice).Pointer.is_volatile,
                .alignment = @typeInfo(Slice).Pointer.alignment,
                .child = @typeInfo(Slice).Pointer.child,
                .is_allowzero = @typeInfo(Slice).Pointer.is_allowzero,
                .address_space = @typeInfo(Slice).Pointer.address_space,
                .sentinel = @typeInfo(Slice).Pointer.sentinel,
            },
        });
        const RPtr = RelativePointer(Ptr, Int, endian, offset, 0);
        const Inner = switch (layout) {
            .pointer_first => extern struct {
                ptr: RPtr,
                len: RPtr.Inner,
            },
            .len_first => extern struct {
                len: RPtr.Inner,
                ptr: RPtr,
            },
        };

        pub fn init(slice: Slice, data: []const u8) Error!@This() {
            const data_end = @ptrToInt(data.ptr) + data.len;
            const start = @ptrToInt(slice.ptr) - @ptrToInt(data.ptr);
            const end = start + (slice.len * @sizeOf(RPtr.ptr_info.child));
            if (data_end < end)
                return error.InvalidPointer;

            return @This(){
                .inner = .{
                    .ptr = try RPtr.init(slice.ptr, data),
                    .len = RPtr.Inner.init(@intCast(Int, slice.len)),
                },
            };
        }

        pub fn toSlice(slice: @This(), data: RPtr.Data) Error!Slice {
            return slice.inner.ptr.toSlice(data, slice.len());
        }

        pub fn len(slice: @This()) Int {
            return slice.inner.len.value();
        }
    };
}

// zig fmt: off
test "RelativeSlice" {
    @setEvalBranchQuota(100000000);
    inline for ([_]builtin.Endian{.Little,.Big}) |endian|
    inline for ([_]usize{25,50,75}) |offset|
    inline for ([_]type{u8, u16, u32}) |Child|
    inline for ([_]type{u8, u16, u32}) |Int| {
        const Slice1 = RelativeSlice(
            []Child,
            Int,
            endian,
            .pointer_first,
            offset,
        );
        const Slice2 = RelativeSlice(
            []Child,
            Int,
            endian,
            .len_first,
            offset,
        );
        var data = [_]Child{2, 4, 6, 8, 10};
        const bytes = if (Child != u8) std.mem.sliceAsBytes(&data) else &data;
        for (0..4) |i| {
            const expect = data[i..i+1];
            const slice1 = try (try Slice1.init(expect, bytes)).toSlice(bytes);
            const slice2 = try (try Slice2.init(expect, bytes)).toSlice(bytes);
            try std.testing.expectEqualSlices(Child, expect, slice1);
            try std.testing.expectEqualSlices(Child, expect, slice2);
        }
    };
}
// zig fmt: on
