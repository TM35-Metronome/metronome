const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;

const Token = tokenizer.Token;

pub const Property = struct {
    invalid_token: ?Token,
    access: []const Access,
    value: []const u8,
};

pub const Access = union(enum) {
    Field: []const u8,
    Index: usize,
};

pub fn parseLine(allocator: *mem.Allocator, line: []const u8) !Property {
    var list = std.ArrayList(Access).init(allocator);
    errdefer list.deinit();

    var res = try parseLineList(&list, line);
    res.access = list.toOwnedSlice();

    return res;
}

pub fn parseLineList(list: *std.ArrayList(Access), line: []const u8) !Property {
    const State = enum {
        Begin,
        Field,
        ArrayIndex,
        ArrayEnd,
    };

    var state = State.Field;
    var rest = line;
    while (tokenizer.next(rest)) |res| {
        rest = res.rest;
        const token = res.token;
        switch (state) {
            State.Begin => switch (token.id) {
                Token.Id.LBracket => state = State.ArrayIndex,
                Token.Id.Dot => state = State.Field,
                Token.Id.Equal => break,
                else => return Property{
                    .invalid_token = token,
                    .access = []Access{},
                    .value = "",
                },
            },
            State.Field => switch (token.id) {
                Token.Id.Identifier => {
                    state = State.Begin;
                    try list.append(Access{.Field = token.str});
                },
                else => return Property{
                    .invalid_token = token,
                    .access = []Access{},
                    .value = "",
                },
            },
            State.ArrayIndex => switch (token.id) {
                Token.Id.Integer => {
                    state = State.ArrayEnd;
                    try list.append(Access{.Index = try fmt.parseUnsigned(usize, token.str, 10) });
                },
                else => return Property{
                    .invalid_token = token,
                    .access = []Access{},
                    .value = "",
                },
            },
            State.ArrayEnd => switch (token.id) {
                Token.Id.RBracket => state = State.Begin,
                else => return Property{
                    .invalid_token = token,
                    .access = []Access{},
                    .value = "",
                },
            },
        }
    }

    return Property{
        .invalid_token = null,
        .access = list.toSlice(),
        .value = rest,
    };
}

fn testParseLine(str: []const u8, res: Property) !void {
    var buf: [1024]u8 = undefined;
    var fb_allocator = heap.FixedBufferAllocator.init(buf[0..]);
    const prop = try parseLine(&fb_allocator.allocator, str);

    if (prop.invalid_token) |t1| {
        const t2 = res.invalid_token.?;
        debug.assert(t1.id == t2.id);
        debug.assert(mem.eql(u8, t1.str, t2.str));
    }
    for (prop.access) |a1, i| {
        const a2 = res.access[i];
        switch (a1) {
            Access.Field => |s| debug.assert(mem.eql(u8, s, a2.Field)),
            Access.Index => |index| debug.assert(index == a2.Index),
        }
    }
    debug.assert(mem.eql(u8, prop.value, res.value));
}

fn testParseLineInvalid(str: []const u8, token: Token) !void {
    var buf: [1024]u8 = undefined;
    var fb_allocator = heap.FixedBufferAllocator.init(buf[0..]);
    const prop = try parseLine(&fb_allocator.allocator, str);

    const t1 = prop.invalid_token.?;
    debug.assert(token.id == t1.id);
    debug.assert(mem.eql(u8, token.str, t1.str));
}

test "parser.parseLine" {
    try testParseLine(
        "a=1",
        Property{
            .invalid_token = null,
            .access = []Access{ Access{.Field = "a"} },
            .value = "1",
        },
    );
    try testParseLine(
        "a.b=1",
        Property{
            .invalid_token = null,
            .access = []Access{
                Access{.Field = "a"},
                Access{.Field = "b"},
            },
            .value = "1",
        },
    );
    try testParseLine(
        "a[1]=1",
        Property{
            .invalid_token = null,
            .access = []Access{
                Access{.Field = "a"},
                Access{.Index = 1},
            },
            .value = "1",
        },
    );
    try testParseLineInvalid(",", Token.init(Token.Id.Invalid, ","));
    try testParseLineInvalid("1", Token.init(Token.Id.Integer, "1"));
    try testParseLineInvalid("[", Token.init(Token.Id.LBracket, "["));
    try testParseLineInvalid("]", Token.init(Token.Id.RBracket, "]"));
    try testParseLineInvalid("=", Token.init(Token.Id.Equal, "="));
    try testParseLineInvalid(".", Token.init(Token.Id.Dot, "."));
    try testParseLineInvalid("a.,", Token.init(Token.Id.Invalid, ","));
    try testParseLineInvalid("a.1", Token.init(Token.Id.Integer, "1"));
    try testParseLineInvalid("a.[", Token.init(Token.Id.LBracket, "["));
    try testParseLineInvalid("a.]", Token.init(Token.Id.RBracket, "]"));
    try testParseLineInvalid("a.=", Token.init(Token.Id.Equal, "="));
    try testParseLineInvalid("a..", Token.init(Token.Id.Dot, "."));
    try testParseLineInvalid("a[,", Token.init(Token.Id.Invalid, ","));
    try testParseLineInvalid("a[a", Token.init(Token.Id.Identifier, "a"));
    try testParseLineInvalid("a[[", Token.init(Token.Id.LBracket, "["));
    try testParseLineInvalid("a[]", Token.init(Token.Id.RBracket, "]"));
    try testParseLineInvalid("a[=", Token.init(Token.Id.Equal, "="));
    try testParseLineInvalid("a[.", Token.init(Token.Id.Dot, "."));
    try testParseLineInvalid("a[1,", Token.init(Token.Id.Invalid, ","));
    try testParseLineInvalid("a[1a", Token.init(Token.Id.Identifier, "a"));
    try testParseLineInvalid("a[1 1", Token.init(Token.Id.Integer, "1"));
    try testParseLineInvalid("a[1=", Token.init(Token.Id.Equal, "="));
    try testParseLineInvalid("a[1.", Token.init(Token.Id.Dot, "."));
}
