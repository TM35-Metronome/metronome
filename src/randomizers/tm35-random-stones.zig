const std = @import("std");
const ston = @import("ston");
const util = @import("util");

const escape = util.escape.default;
const Utf8 = util.unicode.Utf8View;

const Program = @This();

pub fn main() !void {
    var list = std.ArrayList(u8).init(std.heap.page_allocator);
    defer list.deinit();

    const items = Items{};
    for (items.keys(), items.values()) |item_id, item| {
        try ston.serialize(list.writer(), ston.index(item_id, .{
            .name = ston.string(escape.escapeFmt(item.name)),
        }));
    }
}

const Items = std.AutoArrayHashMapUnmanaged(u16, Item);

const Item = struct {
    name: []const u8 = "",
};
