const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const IntSet = @import("intset.zig").Unmanaged;

pub fn Managed(comptime K: type, comptime V: type) type {
    return struct {
        inner: Inner = Inner{},
        allocator: *mem.Allocator,

        const Inner = Unmanaged(K, V);
        pub const Pair = Inner.Pair;
        pub const GetOrPutResult = Inner.GetOrPutResult;

        pub fn deinit(map: @This()) void {
            map.inner.deinit(map.allocator);
        }

        pub fn exists(map: *const @This(), key: K) bool {
            return map.inner.exists(key);
        }

        pub fn count(map: *const @This()) usize {
            return map.inner.count();
        }

        pub fn at(map: *const @This(), i: usize) Pair {
            return map.inner.at(i);
        }

        pub fn put(map: *@This(), key: K, value: V) !?V {
            return map.inner.put(map.allocator, key, value);
        }

        pub fn get(map: *const @This(), key: K) ?*V {
            return map.inner.get(key);
        }

        pub fn getOrPut(map: *@This(), key: K) !GetOrPutResult {
            return map.inner.getOrPut(map.allocator, key);
        }

        pub fn getOrPutValue(map: *@This(), key: K, value: V) !*V {
            return map.inner.getOrPutValue(map.allocator, key, value);
        }

        pub fn keys(map: *const @This()) []const Inner.Set.Range {
            return map.inner.keys();
        }

        pub fn values(map: *const @This()) []V {
            return map.inner.values();
        }
    };
}

pub fn Unmanaged(comptime K: type, comptime V: type) type {
    return struct {
        set: Set = Set{},
        vals: [*]V = @as([]V, &[_]V{}).ptr,
        cap: usize = 0,

        const Set = IntSet(K);
        pub const Pair = struct {
            key: K,
            value: *V,
        };

        pub fn deinit(map: @This(), allocator: *mem.Allocator) void {
            map.set.deinit(allocator);
            allocator.free(map.vals[0..map.cap]);
        }

        pub fn exists(map: *const @This(), key: K) bool {
            return map.set.exists(key);
        }

        pub fn count(map: *const @This()) usize {
            return map.set.count();
        }

        pub fn at(map: *const @This(), i: usize) Pair {
            return .{
                .key = map.set.at(i),
                .value = &map.values()[i],
            };
        }

        pub fn put(map: *@This(), allocator: *mem.Allocator, key: K, value: V) !?V {
            const found = try map.set.put(allocator, key);
            const index = map.set.index(key).?;
            const vals = map.values();
            if (found) {
                defer vals[index] = value;
                return vals[index];
            }

            var list = std.ArrayList(V){
                .items = vals,
                .capacity = map.cap,
                .allocator = allocator,
            };
            try list.insert(index, value);
            map.vals = list.items.ptr;
            map.cap = list.capacity;
            return null;
        }

        pub fn get(map: *const @This(), key: K) ?*V {
            if (map.set.index(key)) |index|
                return &map.values()[index];
            return null;
        }

        pub const GetOrPutResult = struct {
            value: *V,
            found_existing: bool,
        };

        pub fn getOrPut(map: *@This(), allocator: *mem.Allocator, key: K) !GetOrPutResult {
            if (map.get(key)) |v|
                return GetOrPutResult{ .value = v, .found_existing = true };

            _ = try map.put(allocator, key, undefined);
            const index = map.set.index(key).?;
            return GetOrPutResult{ .value = &map.values()[index], .found_existing = false };
        }

        pub fn getOrPutValue(map: *@This(), allocator: *mem.Allocator, key: K, value: V) !*V {
            const res = try map.getOrPut(allocator, key);
            if (!res.found_existing)
                res.value.* = value;
            return res.value;
        }

        pub fn keys(map: *const @This()) []const Set.Range {
            return map.set.span();
        }

        pub fn values(map: *const @This()) []V {
            return map.vals[0..map.count()];
        }
    };
}

test "" {
    const Map = Managed(u8, u8);
    var map = Map{ .allocator = testing.allocator };
    defer map.deinit();

    testing.expectEqual(@as(u8, 2), (try map.getOrPutValue(1, 2)).*);
    testing.expectEqual(@as(u8, 4), (try map.getOrPutValue(2, 4)).*);
    testing.expectEqual(@as(u8, 8), (try map.getOrPutValue(3, 8)).*);
    testing.expectEqual(@as(?u8, null), try map.put(4, 16));
    testing.expectEqual(@as(?u8, 2), try map.put(1, 4));
    testing.expectEqual(@as(u8, 4), map.get(1).?.*);
    testing.expectEqual(@as(u8, 4), map.get(2).?.*);
    testing.expectEqual(@as(u8, 8), map.get(3).?.*);
    testing.expectEqual(@as(u8, 16), map.get(4).?.*);
    testing.expectEqual(@as(?*u8, null), map.get(5));
    testing.expectEqual(@as(usize, 4), map.count());
    testing.expectEqual(@as(u8, 1), map.at(0).key);
    testing.expectEqual(@as(u8, 4), map.at(0).value.*);
    testing.expectEqual(@as(u8, 2), map.at(1).key);
    testing.expectEqual(@as(u8, 4), map.at(1).value.*);
    testing.expectEqual(@as(u8, 3), map.at(2).key);
    testing.expectEqual(@as(u8, 8), map.at(2).value.*);
    testing.expectEqual(@as(u8, 4), map.at(3).key);
    testing.expectEqual(@as(u8, 16), map.at(3).value.*);
    testing.expectEqualSlices(u8, &[_]u8{ 4, 4, 8, 16 }, map.values());

    var i: u8 = 1;
    for (map.keys()) |range| {
        var k = range.start;
        while (k <= range.end) : ({
            k += 1;
            i += 1;
        }) {
            testing.expectEqual(@as(u8, i), k);
        }
    }
}
