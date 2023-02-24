const std = @import("std");

const mem = std.mem;
const testing = std.testing;

test "glob" {
    try testGlob("test case", "test case", true);
    try testGlob("case", "test case", false);
    try testGlob("test", "test case", false);
    try testGlob("*case", "test case", true);
    try testGlob("*case*", "test case", true);
    try testGlob("*case", "test snail", false);
    try testGlob("case*", "test snail", false);
    try testGlob("test*case", "test case", true);
    try testGlob("test*", "test case", true);
    try testGlob("test**", "test case", true);
    try testGlob("This*is*a*test.",
        \\This will be the coolest test ever. It is an honor to be a test.
    , true);
    try testGlob("This*is*a*test.",
        \\This will be the coolest test ever. It is an honor to be a test
    , false);
}

fn testGlob(comptime glob: []const u8, str: []const u8, res: bool) !void {
    const glob_split = try split(testing.allocator, glob);
    defer testing.allocator.free(glob_split);

    try testing.expect(match(glob, str) == res);
    try testing.expect(matchSplit(glob_split, str) == res);
}

pub fn split(allocator: mem.Allocator, glob: []const u8) ![]const []const u8 {
    var res = std.ArrayList([]const u8).init(allocator);
    errdefer res.deinit();

    var matches = mem.split(u8, glob, "*");
    while (matches.next()) |str|
        try res.append(str);

    return res.toOwnedSlice();
}

pub fn splitAll(allocator: mem.Allocator, globs: []const []const u8) ![]const []const []const u8 {
    var res = std.ArrayList([]const []const u8).init(allocator);
    errdefer {
        for (res.items) |item|
            allocator.free(item);
        res.deinit();
    }

    for (globs) |glob|
        try res.append(try split(allocator, glob));

    return res.toOwnedSlice();
}

pub fn matchSplit(glob: []const []const u8, str: []const u8) bool {
    if (glob.len == 0)
        return true;

    const first = glob[0];
    if (!mem.startsWith(u8, str, first))
        return false;
    if (glob.len == 1)
        return str.len == first.len;

    var pos: usize = first.len;
    for (glob[1 .. glob.len - 1]) |curr| {
        pos = mem.indexOfPos(u8, str, pos, curr) orelse return false;
        pos += curr.len;
    }

    return mem.endsWith(u8, str[pos..], glob[glob.len - 1]);
}

pub fn match(glob: []const u8, str: []const u8) bool {
    var matches = mem.split(u8, glob, "*");
    const first = matches.next().?;

    if (!mem.startsWith(u8, str, first))
        return false;

    var pos: usize = first.len;
    var curr = matches.next() orelse return str.len == first.len;
    while (matches.next()) |next| : (curr = next) {
        pos = mem.indexOfPos(u8, str, pos, curr) orelse return false;
        pos += curr.len;
    }

    return mem.endsWith(u8, str[pos..], curr);
}

pub fn matchesOneOf(str: []const u8, globs: []const []const u8) ?usize {
    for (globs, 0..) |glob, i| {
        if (match(glob, str))
            return i;
    }

    return null;
}

pub fn matchesOneOfSplit(str: []const u8, globs: []const []const []const u8) ?usize {
    for (globs, 0..) |glob, i| {
        if (matchSplit(glob, str))
            return i;
    }

    return null;
}
