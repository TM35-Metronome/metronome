const std = @import("std");

const mem = std.mem;
const testing = std.testing;

/// A data structure representing an integer set.
/// This data structure has been optimized for best case space
/// efficiency and performance, sacrificing the worst case.
/// The way this is done, is by representing the set as a list of
/// ranges from N..M. So if you have the integer set [1,2,3,5,6,7],
/// then that would be stored as [(1,3),(5,7)]. By storing a set
/// like this you get a best case for space and time of O(1), but
/// a worst case for space to be O(N*2) and for time to be O(N).
/// This data structure is therefor best when working with ranges
/// of integers.
pub fn Managed(comptime Int: type) type {
    return struct {
        allocator: *mem.Allocator,
        inner: Inner = Inner{},

        pub const Inner = Unmanaged(Int);
        pub const Range = Unmanaged(Int);

        pub fn deinit(set: @This()) void {
            return set.inner.deinit(set.allocator);
        }

        pub fn exists(set: *const @This(), i: Int) bool {
            return set.inner.exists(i);
        }

        pub fn count(set: *const @This()) usize {
            return set.inner.count();
        }

        pub fn at(set: *const @This(), i: usize) Int {
            return set.inner.at(i);
        }

        pub fn index(set: *const @This(), i: Int) ?usize {
            return set.inner.index(i);
        }

        pub fn put(set: *@This(), i: Int) !bool {
            return set.inner.put(set.allocator, i);
        }

        pub fn remove(set: *@This(), i: Int) !bool {
            return set.inner.remove(set.allocator, i);
        }

        pub fn span(set: var) mem.Span(@TypeOf(&set.inner.small)) {
            return set.inner.span();
        }
    };
}

pub fn Unmanaged(comptime Int: type) type {
    return struct {
        entries: usize = 0,
        data: union {
            small: [1]Range,
            big: struct {
                ptr: [*]Range,
                cap: usize,
            },
        } = undefined,

        pub const Range = struct {
            start: Int,
            end: Int,
        };

        pub fn deinit(set: @This(), allocator: *mem.Allocator) void {
            if (set.entries > 1)
                allocator.free(set.data.big.ptr[0..set.entries]);
        }

        pub fn exists(set: *const @This(), i: Int) bool {
            return set.lookup(i).found;
        }

        pub fn count(set: *const @This()) usize {
            const items = set.span();
            var res: usize = 0;
            for (items) |range|
                res += (range.end + 1) - range.start;
            return res;
        }

        pub fn at(set: *const @This(), i: usize) Int {
            var tmp: usize = i;
            const items = set.span();
            for (items) |range| {
                const len = (range.end + 1) - range.start;
                if (tmp < len)
                    return range.start + @intCast(Int, tmp);
                tmp -= len;
            }
            unreachable;
        }

        pub fn index(set: *const @This(), i: Int) ?usize {
            var tmp: usize = 0;
            const items = set.span();
            for (items) |range| {
                const len = (range.end + 1) - range.start;
                if (i < range.start)
                    return null;
                if (i <= range.end)
                    return tmp + (i - range.start);
                tmp += len;
            }
            return null;
        }

        pub fn put(set: *@This(), allocator: *mem.Allocator, i: Int) !bool {
            const l = set.lookup(i);
            if (l.found)
                return true;

            const items = set.span();
            if (l.index != 0 and items[l.index - 1].end == i - 1) {
                items[l.index - 1].end += 1;
                set.merge(allocator, l.index - 1);
            } else if (l.index != items.len and items[l.index].start == i + 1) {
                items[l.index].start -= 1;
                if (l.index != 0)
                    set.merge(allocator, l.index - 1);
            } else if (set.entries == 0) {
                set.entries += 1;
                set.data.small = .{Range{ .start = i, .end = i }};
            } else {
                var list = try set.toOwnedList(allocator);
                try list.insert(l.index, Range{ .start = i, .end = i });
                set.* = fromOwnedList(list);
            }
            return false;
        }

        pub fn remove(set: *@This(), allocator: *mem.Allocator, i: Int) !bool {
            const l = set.lookup(i);
            if (!l.found)
                return false;

            const items = set.span();
            const item = &items[l.index];
            if (item.start == item.end) {
                if (set.entries == 1) {
                    set.entries = 0;
                    return true;
                }
                var list = try set.toOwnedList(allocator);
                _ = list.orderedRemove(l.index);
                set.* = fromOwnedList(list);
            } else if (item.start == i) {
                item.start += 1;
            } else if (item.end == i) {
                item.end -= 1;
            } else {
                const end = item.end;
                item.end = i - 1;

                var list = try set.toOwnedList(allocator);
                try list.insert(l.index + 1, Range{ .start = i + 1, .end = end });
                set.* = fromOwnedList(list);
            }

            return true;
        }

        pub fn span(set: var) mem.Span(@TypeOf(&set.data.small)) {
            if (set.entries == 0)
                return &[_]Range{};
            if (set.entries == 1)
                return &set.data.small;
            return set.data.big.ptr[0..set.entries];
        }

        fn merge(set: *@This(), allocator: *mem.Allocator, idx: usize) void {
            const items = set.span();
            if (idx + 1 == items.len)
                return;

            const a = items[idx];
            const b = &items[idx + 1];
            if (a.end != b.start - 1)
                return;

            b.start = a.start;
            var list = set.toOwnedList(allocator) catch unreachable;
            _ = list.orderedRemove(idx);
            set.* = fromOwnedList(list);
        }

        fn lookup(set: *const @This(), i: Int) struct { found: bool, index: usize } {
            const items = set.span();
            for (items) |range, idx| {
                if (i < range.start)
                    return .{ .found = false, .index = idx };
                if (i <= range.end)
                    return .{ .found = true, .index = idx };
            }
            return .{ .found = false, .index = items.len };
        }

        fn toOwnedList(set: *@This(), allocator: *mem.Allocator) !std.ArrayList(Range) {
            return if (set.entries == 1) blk: {
                var list = std.ArrayList(Range).init(allocator);
                errdefer list.deinit();
                try list.ensureCapacity(2);
                list.append(set.data.small[0]) catch unreachable;
                return list;
            } else {
                return std.ArrayList(Range){
                    .items = set.span(),
                    .capacity = set.data.big.cap,
                    .allocator = allocator,
                };
            };
        }

        fn fromOwnedList(list: std.ArrayList(Range)) @This() {
            if (list.items.len == 0) {
                defer list.deinit();
                return @This(){};
            }
            if (list.items.len == 1) {
                defer list.deinit();
                return @This(){
                    .entries = 1,
                    .data = .{ .small = list.items[0..1].* },
                };
            }

            return @This(){
                .entries = list.items.len,
                .data = .{
                    .big = .{
                        .ptr = list.items.ptr,
                        .cap = list.capacity,
                    },
                },
            };
        }
    };
}

test "IntSet" {
    var set = Managed(u8){ .allocator = testing.allocator };
    defer set.deinit();

    testing.expectEqual(false, try set.put(5));
    testing.expectEqual(false, try set.put(4));
    testing.expectEqual(false, try set.put(6));
    testing.expectEqual(true, try set.put(5));
    testing.expectEqual(true, try set.put(4));
    testing.expectEqual(true, try set.put(6));
    testing.expectEqual(true, set.exists(5));
    testing.expectEqual(true, set.exists(4));
    testing.expectEqual(true, set.exists(6));
    testing.expectEqual(false, set.exists(3));
    testing.expectEqual(false, set.exists(7));
    testing.expectEqual(false, set.exists(11));
    testing.expectEqual(@as(usize, 3), set.count());
    testing.expectEqual(@as(usize, 5), set.at(1));
    testing.expectEqual(@as(?usize, 1), set.index(5));
    testing.expectEqual(@as(usize, 1), set.inner.entries);
    testing.expectEqual(@as(u8, 4), set.inner.data.small[0].start);
    testing.expectEqual(@as(u8, 6), set.inner.data.small[0].end);

    testing.expectEqual(false, try set.put(9));
    testing.expectEqual(false, try set.put(8));
    testing.expectEqual(false, try set.put(10));
    testing.expectEqual(true, try set.put(9));
    testing.expectEqual(true, try set.put(8));
    testing.expectEqual(true, try set.put(10));
    testing.expectEqual(true, set.exists(9));
    testing.expectEqual(true, set.exists(8));
    testing.expectEqual(true, set.exists(10));
    testing.expectEqual(false, set.exists(3));
    testing.expectEqual(false, set.exists(7));
    testing.expectEqual(false, set.exists(11));
    testing.expectEqual(@as(usize, 6), set.count());
    testing.expectEqual(@as(usize, 5), set.at(1));
    testing.expectEqual(@as(usize, 9), set.at(4));
    testing.expectEqual(@as(?usize, 1), set.index(5));
    testing.expectEqual(@as(?usize, 4), set.index(9));
    testing.expectEqual(@as(usize, 2), set.inner.entries);
    testing.expectEqual(@as(u8, 4), set.inner.data.big.ptr[0].start);
    testing.expectEqual(@as(u8, 6), set.inner.data.big.ptr[0].end);
    testing.expectEqual(@as(u8, 8), set.inner.data.big.ptr[1].start);
    testing.expectEqual(@as(u8, 10), set.inner.data.big.ptr[1].end);

    testing.expectEqual(false, try set.put(1));
    testing.expectEqual(false, try set.put(0));
    testing.expectEqual(false, try set.put(2));
    testing.expectEqual(true, try set.put(1));
    testing.expectEqual(true, try set.put(0));
    testing.expectEqual(true, try set.put(2));
    testing.expectEqual(true, set.exists(1));
    testing.expectEqual(true, set.exists(0));
    testing.expectEqual(true, set.exists(2));
    testing.expectEqual(false, set.exists(3));
    testing.expectEqual(false, set.exists(7));
    testing.expectEqual(false, set.exists(11));
    testing.expectEqual(@as(usize, 9), set.count());
    testing.expectEqual(@as(usize, 1), set.at(1));
    testing.expectEqual(@as(usize, 5), set.at(4));
    testing.expectEqual(@as(usize, 9), set.at(7));
    testing.expectEqual(@as(?usize, 1), set.index(1));
    testing.expectEqual(@as(?usize, 4), set.index(5));
    testing.expectEqual(@as(?usize, 7), set.index(9));
    testing.expectEqual(@as(usize, 3), set.inner.entries);
    testing.expectEqual(@as(u8, 0), set.inner.data.big.ptr[0].start);
    testing.expectEqual(@as(u8, 2), set.inner.data.big.ptr[0].end);
    testing.expectEqual(@as(u8, 4), set.inner.data.big.ptr[1].start);
    testing.expectEqual(@as(u8, 6), set.inner.data.big.ptr[1].end);
    testing.expectEqual(@as(u8, 8), set.inner.data.big.ptr[2].start);
    testing.expectEqual(@as(u8, 10), set.inner.data.big.ptr[2].end);

    testing.expectEqual(false, try set.put(3));
    testing.expectEqual(true, try set.put(3));
    testing.expectEqual(true, set.exists(3));
    testing.expectEqual(false, set.exists(7));
    testing.expectEqual(false, set.exists(11));
    testing.expectEqual(@as(usize, 10), set.count());
    testing.expectEqual(@as(usize, 1), set.at(1));
    testing.expectEqual(@as(usize, 4), set.at(4));
    testing.expectEqual(@as(usize, 8), set.at(7));
    testing.expectEqual(@as(?usize, 1), set.index(1));
    testing.expectEqual(@as(?usize, 4), set.index(4));
    testing.expectEqual(@as(?usize, 7), set.index(8));
    testing.expectEqual(@as(usize, 2), set.inner.entries);
    testing.expectEqual(@as(u8, 0), set.inner.data.big.ptr[0].start);
    testing.expectEqual(@as(u8, 6), set.inner.data.big.ptr[0].end);
    testing.expectEqual(@as(u8, 8), set.inner.data.big.ptr[1].start);
    testing.expectEqual(@as(u8, 10), set.inner.data.big.ptr[1].end);

    testing.expectEqual(false, try set.put(7));
    testing.expectEqual(true, try set.put(7));
    testing.expectEqual(true, set.exists(7));
    testing.expectEqual(false, set.exists(11));
    testing.expectEqual(@as(usize, 11), set.count());
    testing.expectEqual(@as(usize, 1), set.at(1));
    testing.expectEqual(@as(usize, 4), set.at(4));
    testing.expectEqual(@as(usize, 7), set.at(7));
    testing.expectEqual(@as(?usize, 1), set.index(1));
    testing.expectEqual(@as(?usize, 4), set.index(4));
    testing.expectEqual(@as(?usize, 7), set.index(7));
    testing.expectEqual(@as(usize, 1), set.inner.entries);
    testing.expectEqual(@as(u8, 0), set.inner.data.small[0].start);
    testing.expectEqual(@as(u8, 10), set.inner.data.small[0].end);

    testing.expectEqual(true, try set.remove(7));
    testing.expectEqual(false, try set.remove(7));
    testing.expectEqual(false, set.exists(7));
    testing.expectEqual(@as(usize, 10), set.count());
    testing.expectEqual(@as(usize, 1), set.at(1));
    testing.expectEqual(@as(usize, 4), set.at(4));
    testing.expectEqual(@as(usize, 8), set.at(7));
    testing.expectEqual(@as(?usize, 1), set.index(1));
    testing.expectEqual(@as(?usize, 4), set.index(4));
    testing.expectEqual(@as(?usize, 7), set.index(8));
    testing.expectEqual(@as(usize, 2), set.inner.entries);
    testing.expectEqual(@as(u8, 0), set.inner.data.big.ptr[0].start);
    testing.expectEqual(@as(u8, 6), set.inner.data.big.ptr[0].end);
    testing.expectEqual(@as(u8, 8), set.inner.data.big.ptr[1].start);
    testing.expectEqual(@as(u8, 10), set.inner.data.big.ptr[1].end);

    testing.expectEqual(true, try set.remove(6));
    testing.expectEqual(false, try set.remove(6));
    testing.expectEqual(false, set.exists(6));
    testing.expectEqual(@as(usize, 9), set.count());
    testing.expectEqual(@as(usize, 1), set.at(1));
    testing.expectEqual(@as(usize, 4), set.at(4));
    testing.expectEqual(@as(usize, 9), set.at(7));
    testing.expectEqual(@as(?usize, 1), set.index(1));
    testing.expectEqual(@as(?usize, 4), set.index(4));
    testing.expectEqual(@as(?usize, 7), set.index(9));
    testing.expectEqual(@as(usize, 2), set.inner.entries);
    testing.expectEqual(@as(u8, 0), set.inner.data.big.ptr[0].start);
    testing.expectEqual(@as(u8, 5), set.inner.data.big.ptr[0].end);
    testing.expectEqual(@as(u8, 8), set.inner.data.big.ptr[1].start);
    testing.expectEqual(@as(u8, 10), set.inner.data.big.ptr[1].end);

    testing.expectEqual(true, try set.remove(8));
    testing.expectEqual(false, try set.remove(8));
    testing.expectEqual(false, set.exists(8));
    testing.expectEqual(@as(usize, 8), set.count());
    testing.expectEqual(@as(usize, 1), set.at(1));
    testing.expectEqual(@as(usize, 4), set.at(4));
    testing.expectEqual(@as(usize, 10), set.at(7));
    testing.expectEqual(@as(?usize, 1), set.index(1));
    testing.expectEqual(@as(?usize, 4), set.index(4));
    testing.expectEqual(@as(?usize, 7), set.index(10));
    testing.expectEqual(@as(usize, 2), set.inner.entries);
    testing.expectEqual(@as(u8, 0), set.inner.data.big.ptr[0].start);
    testing.expectEqual(@as(u8, 5), set.inner.data.big.ptr[0].end);
    testing.expectEqual(@as(u8, 9), set.inner.data.big.ptr[1].start);
    testing.expectEqual(@as(u8, 10), set.inner.data.big.ptr[1].end);

    var i: u8 = 0;
    while (i < 6) : (i += 1) {
        testing.expectEqual(@as(usize, 2), set.inner.entries);
        testing.expectEqual(@as(usize, 8 - i), set.count());
        testing.expectEqual(true, try set.remove(i));
        testing.expectEqual(false, try set.remove(i));
        testing.expectEqual(false, set.exists(i));
    }

    testing.expectEqual(@as(usize, 2), set.count());
    testing.expectEqual(@as(usize, 1), set.inner.entries);
    testing.expectEqual(@as(u8, 9), set.inner.data.small[0].start);
    testing.expectEqual(@as(u8, 10), set.inner.data.small[0].end);

    i = 0;
    while (i < 2) : (i += 1) {
        testing.expectEqual(@as(usize, 1), set.inner.entries);
        testing.expectEqual(@as(usize, 2 - i), set.count());
        testing.expectEqual(true, try set.remove(i + 9));
        testing.expectEqual(false, try set.remove(i + 9));
        testing.expectEqual(false, set.exists(i + 9));
    }

    testing.expectEqual(@as(usize, 0), set.count());
    testing.expectEqual(@as(usize, 0), set.inner.entries);
}
