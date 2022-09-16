const std = @import("std");

const mem = std.mem;
const testing = std.testing;

test {
    try testing.expect(match("test case", "test case"));
    try testing.expect(!match("case", "test case"));
    try testing.expect(!match("test", "test case"));
    try testing.expect(match("*case", "test case"));
    try testing.expect(match("*case*", "test case"));
    try testing.expect(!match("*case", "test snail"));
    try testing.expect(!match("case*", "test snail"));
    try testing.expect(match("test*case", "test case"));
    try testing.expect(match("test*", "test case"));
    try testing.expect(match("test**", "test case"));
    try testing.expect(match("This*is*a*test.",
        \\This will be the coolest test ever. It is an honor to be a test.
    ));
    try testing.expect(!match("This*is*a*test.",
        \\This will be the coolest test ever. It is an honor to be a test
    ));
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
    for (globs) |glob, i| {
        if (match(glob, str))
            return i;
    }

    return null;
}
