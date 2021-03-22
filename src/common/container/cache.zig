const std = @import("std");

const math = std.math;
const mem = std.mem;
const testing = std.testing;

// TODO: None of these containers are used in this project anymore. Consider
//       removing/moving them.

pub fn CloneFn(comptime T: type) type {
    return fn (*mem.Allocator, T) mem.Allocator.Error!T;
}

pub fn FreeFn(comptime T: type) type {
    return fn (*mem.Allocator, T) void;
}

pub fn CacheOptions(comptime T: type) type {
    return struct {
        /// The identity that will be returned when storing values into the cache.
        /// A cache will return `OutOfMemory` once it has exausted all unique values
        /// of `Id`.
        Id: type = usize,

        /// The function used to duplicate the value into the cache. Defaults to
        /// noop. Override this + `free` if the cache should take ownership of `T`.
        clone: CloneFn(T) = struct {
            fn clone(a: *mem.Allocator, t: T) mem.Allocator.Error!void {}
        }.clone,

        /// The function used to free `T`. Defaults to noop. Only override this if
        /// you have also overriden `clone`.
        free: FreeFn(T) = struct {
            fn free(a: *mem.Allocator, t: T) void {}
        }.free,
        hash: fn (T) u32 = std.array_hash_map.getAutoHashFn(T),
        eql: fn (T, T) bool = std.array_hash_map.getAutoEqlFn(T),
        store_hash: bool = std.array_hash_map.autoEqlIsCheap(T),

        /// Decide if you want a managed or unmanged api. The managed api stores
        /// an allocator internally, while this unmanaged api requires the caller
        /// to provide the allocator for all allocating functions.
        managed: bool = true,
    };
}

pub fn Cache(comptime T: type, comptime opt: CacheOptions(T)) type {
    return struct {
        allocator: if (opt.managed) *mem.Allocator else void = {},
        map: Map = Map{},

        const This = @This();
        const Map = std.ArrayHashMapUnmanaged(T, opt.Id, opt.hash, opt.eql, opt.store_hash);

        pub const deinit = if (opt.managed)
            struct {
                fn deinit(cache: This) void {
                    return cache._deinit(cache.allocator);
                }
            }.deinit
        else
            _deinit;

        pub const put = if (opt.managed)
            struct {
                fn put(cache: *This, value: T) !opt.Id {
                    return cache._put(cache.allocator, value);
                }
            }.put
        else
            _put;

        pub fn get(cache: @This(), id: opt.Id) T {
            return cache.map.items()[id].key;
        }

        fn _deinit(cache: @This(), allocator: *mem.Allocator) void {
            for (cache.map.items()) |item|
                opt.free(allocator, item.key);

            // std really needs to stop with its mutable deinit functions. This
            // is driving me nuts. Cast away const instead or something
            var map = cache.map;
            map.deinit(allocator);
        }

        fn _put(cache: *@This(), allocator: *mem.Allocator, value: T) !opt.Id {
            const result = try cache.map.getOrPut(allocator, value);
            errdefer _ = cache.map.remove(value);

            if (!result.found_existing) {
                result.entry.key = try opt.clone(allocator, value);
                result.entry.value = math.cast(opt.Id, cache.map.count() - 1) catch return error.OutOfMemory;
            }

            return result.entry.value;
        }
    };
}

pub const StringCacheOptions = struct {
    Id: type = usize,
    managed: bool = true,
};

pub fn StringCache(comptime opt: StringCacheOptions) type {
    return Cache([]const u8, .{
        .Id = opt.Id,
        .clone = struct {
            fn clone(allocator: *mem.Allocator, str: []const u8) mem.Allocator.Error![]const u8 {
                return allocator.dupe(u8, str);
            }
        }.clone,
        .free = struct {
            fn free(allocator: *mem.Allocator, str: []const u8) void {
                return allocator.free(str);
            }
        }.free,
        .hash = std.array_hash_map.hashString,
        .eql = std.array_hash_map.eqlString,
        .store_hash = true,
        .managed = opt.managed,
    });
}

test "cache managed" {
    var strings = StringCache(.{}){ .allocator = testing.allocator };
    defer strings.deinit();

    const a1 = try strings.put("a");
    const b1 = try strings.put("b");
    const a2 = try strings.put("a");
    const b2 = try strings.put("b");
    testing.expectEqual(a1, a2);
    testing.expectEqual(b1, b2);
    testing.expectEqual(strings.get(a1), strings.get(a2));
    testing.expectEqual(strings.get(b1), strings.get(b2));
    testing.expectEqualStrings("a", strings.get(a1));
    testing.expectEqualStrings("a", strings.get(a2));
    testing.expectEqualStrings("b", strings.get(b1));
    testing.expectEqualStrings("b", strings.get(b2));
}

test "cache unmanaged" {
    const a = testing.allocator;
    var strings = StringCache(.{ .managed = false }){};
    defer strings.deinit(a);

    const a1 = try strings.put(a, "a");
    const b1 = try strings.put(a, "b");
    const a2 = try strings.put(a, "a");
    const b2 = try strings.put(a, "b");
    testing.expectEqual(a1, a2);
    testing.expectEqual(b1, b2);
    testing.expectEqual(strings.get(a1), strings.get(a2));
    testing.expectEqual(strings.get(b1), strings.get(b2));
    testing.expectEqualStrings("a", strings.get(a1));
    testing.expectEqualStrings("a", strings.get(a2));
    testing.expectEqualStrings("b", strings.get(b1));
    testing.expectEqualStrings("b", strings.get(b2));
}
