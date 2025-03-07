pub fn sortedGroupBy(
    comptime K: type,
    comptime V: type,
    gpa: std.mem.Allocator,
    items: []const V,
    context: anytype,
) !SortedGroupBy(K, V) {
    const duped_items = try gpa.dupe(V, items);
    errdefer gpa.free(duped_items);

    var res = try sortedGroupByInline(K, V, gpa, duped_items, context);
    res.items_owned = true;
    return res;
}

pub fn sortedGroupByInline(
    comptime K: type,
    comptime V: type,
    gpa: std.mem.Allocator,
    items: []V,
    context: anytype,
) !SortedGroupBy(K, V) {
    if (items.len == 0) {
        return .{
            .items_owned = false,
            .items = items,
            .groups = .{},
        };
    }

    const Context = struct {
        inner: @TypeOf(context),

        fn lessThan(ctx: @This(), a: V, b: V) bool {
            const a_key = ctx.inner.key(a);
            const b_key = ctx.inner.key(b);
            return ctx.inner.lessThan(a_key, b_key);
        }
    };

    std.mem.sort(V, items, Context{ .inner = context }, Context.lessThan);

    var groups = std.AutoArrayHashMapUnmanaged(K, Span){};
    errdefer groups.deinit(gpa);

    var entry = try groups.getOrPut(gpa, context.key(items[0]));
    entry.value_ptr.off = 0;

    for (items[1..], 1..) |item, i| {
        const key = context.key(item);
        if (!context.lessThan(entry.key_ptr.*, key))
            continue;

        entry.value_ptr.len = @intCast(i - entry.value_ptr.off);

        entry = try groups.getOrPut(gpa, key);
        entry.value_ptr.off = @intCast(i);
    }

    entry.value_ptr.len = @intCast(items.len - entry.value_ptr.off);
    return .{
        .items_owned = false,
        .items = items,
        .groups = groups,
    };
}

pub fn SortedGroupBy(comptime K: type, comptime V: type) type {
    return struct {
        items_owned: bool,
        items: []V,
        groups: std.AutoArrayHashMapUnmanaged(K, Span),

        pub fn deinit(group_by: *@This(), gpa: std.mem.Allocator) void {
            if (group_by.items_owned)
                gpa.free(group_by.items);
            group_by.groups.deinit(gpa);
        }

        pub fn get(group_by: @This(), key: K) ?[]const V {
            const span = group_by.groups.get(key) orelse return null;
            return group_by.items[span.off..][0..span.len];
        }
    };
}

fn testSortedGroupBy(options: struct {
    input: []const u8,
    expected_groups_keys: []const u8,
    expected_groups_values: []const Span,
}) !void {
    const Context = struct {
        fn key(_: @This(), v: u8) u8 {
            return v;
        }
        fn lessThan(_: @This(), a: u8, b: u8) bool {
            return a < b;
        }
    };

    var grouped_by = try sortedGroupBy(u8, u8, std.testing.allocator, options.input, Context{});
    defer grouped_by.deinit(std.testing.allocator);

    try std.testing.expect(std.sort.isSorted(u8, grouped_by.items, Context{}, Context.lessThan));
    try std.testing.expectEqualSlices(u8, options.expected_groups_keys, grouped_by.groups.keys());
    try std.testing.expectEqualSlices(Span, options.expected_groups_values, grouped_by.groups.values());

    for (options.expected_groups_keys) |key| {
        const items = grouped_by.get(key).?;
        for (items) |item|
            try std.testing.expectEqual(key, item);
    }
}

test sortedGroupBy {
    try testSortedGroupBy(.{
        .input = &.{ 5, 3, 4, 5, 3, 8, 9, 6, 3, 3, 5, 2, 6, 7, 6, 2, 8, 9, 2 },
        .expected_groups_keys = &.{ 2, 3, 4, 5, 6, 7, 8, 9 },
        .expected_groups_values = &.{
            .{ .off = 0, .len = 3 },
            .{ .off = 3, .len = 4 },
            .{ .off = 7, .len = 1 },
            .{ .off = 8, .len = 3 },
            .{ .off = 11, .len = 3 },
            .{ .off = 14, .len = 1 },
            .{ .off = 15, .len = 2 },
            .{ .off = 17, .len = 2 },
        },
    });
}

pub const Span = struct {
    off: u32,
    len: u32,
};

const std = @import("std");
