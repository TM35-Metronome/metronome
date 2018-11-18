const format = @import("index.zig");
const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;

const Access = format.Access;
const Pattern = format.Pattern;
const Property = format.Property;
const Token = tokenizer.Token;

const Error = struct {
    expected: []const Token,
    found: Token,
};

pub fn Result(comptime T: type) type {
    return union(enum) {
        Ok: T,
        Error: Error,

        pub fn ok(res: T) @This() {
            return @This(){ .Ok = res };
        }

        pub fn err(found: Token, expected: []const Token) @This() {
            return @This(){
                .Error = Error{
                    .expected = expected,
                    .found = found,
                },
            };
        }
    };
}

pub fn parseProperty(allocator: *mem.Allocator, line: []const u8) !Result(Property) {
    var list = std.ArrayList(Access).init(allocator);
    errdefer list.deinit();

    var res = try parsePropertyList(&list, line);
    switch (res) {
        Result(Property).Ok => |*ok| ok.access = list.toOwnedSlice(),
        Result(Property).Error => list.deinit(),
    }

    return res;
}

pub fn parsePropertyList(list: *std.ArrayList(Access), line: []const u8) !Result(Property) {
    const State = enum {
        Begin,
        Field,
        Index,
        IndexEnd,
    };

    var state = State.Field;
    var rest = line;
    while (true) {
        const token = if (tokenizer.next(rest)) |next| blk: {
            rest = next.rest;
            break :blk next.token;
        } else Token.init(Token.Id.Invalid, rest);

        switch (state) {
            State.Begin => switch (token.id) {
                Token.Id.LBracket => state = State.Index,
                Token.Id.Dot => state = State.Field,
                Token.Id.Equal => return Result(Property).ok(Property{
                    .access = list.toSlice(),
                    .value = rest,
                }),
                else => return Result(Property).err(token, []Token{
                    Token.init(Token.Id.LBracket, "["),
                    Token.init(Token.Id.Dot, "."),
                    Token.init(Token.Id.Equal, "="),
                }),
            },
            State.Field => switch (token.id) {
                Token.Id.Identifier => {
                    state = State.Begin;
                    try list.append(Access{ .Field = token.str });
                },
                else => return Result(Property).err(token, []Token{Token.init(Token.Id.Identifier, "Identifier")}),
            },
            State.Index => switch (token.id) {
                Token.Id.Integer => {
                    state = State.IndexEnd;
                    try list.append(Access{ .Index = try fmt.parseUnsigned(usize, token.str, 10) });
                },
                else => return Result(Property).err(token, []Token{Token.init(Token.Id.Integer, "Integer")}),
            },
            State.IndexEnd => switch (token.id) {
                Token.Id.RBracket => state = State.Begin,
                else => return Result(Property).err(token, []Token{Token.init(Token.Id.RBracket, "]")}),
            },
        }
    }
}

fn testParsePropertyOk(str: []const u8, res: Property) !void {
    var buf: [1024]u8 = undefined;
    var fb_allocator = heap.FixedBufferAllocator.init(buf[0..]);

    const r = try parseProperty(&fb_allocator.allocator, str);
    const prop = r.Ok;

    for (prop.access) |a1, i| {
        const a2 = res.access[i];
        switch (a1) {
            Access.Field => |s| debug.assert(mem.eql(u8, s, a2.Field)),
            Access.Index => |index| debug.assert(index == a2.Index),
        }
    }
    debug.assert(mem.eql(u8, prop.value, res.value));
}

fn testParsePropertyError(str: []const u8, token: Token) !void {
    var buf: [1024]u8 = undefined;
    var fb_allocator = heap.FixedBufferAllocator.init(buf[0..]);
    const r = try parseProperty(&fb_allocator.allocator, str);

    const t1 = r.Error.found;
    debug.assert(token.id == t1.id);
    debug.assert(mem.eql(u8, token.str, t1.str));
}

test "parser.parseProperty" {
    try testParsePropertyOk(
        "a=1",
        Property{
            .access = []Access{Access{ .Field = "a" }},
            .value = "1",
        },
    );
    try testParsePropertyOk(
        "a.b=1",
        Property{
            .access = []Access{
                Access{ .Field = "a" },
                Access{ .Field = "b" },
            },
            .value = "1",
        },
    );
    try testParsePropertyOk(
        "a[1]=1",
        Property{
            .access = []Access{
                Access{ .Field = "a" },
                Access{ .Index = 1 },
            },
            .value = "1",
        },
    );
    try testParsePropertyError(",", Token.init(Token.Id.Invalid, ","));
    try testParsePropertyError("1", Token.init(Token.Id.Integer, "1"));
    try testParsePropertyError("[", Token.init(Token.Id.LBracket, "["));
    try testParsePropertyError("]", Token.init(Token.Id.RBracket, "]"));
    try testParsePropertyError("=", Token.init(Token.Id.Equal, "="));
    try testParsePropertyError(".", Token.init(Token.Id.Dot, "."));
    try testParsePropertyError("a.,", Token.init(Token.Id.Invalid, ","));
    try testParsePropertyError("a.1", Token.init(Token.Id.Integer, "1"));
    try testParsePropertyError("a.[", Token.init(Token.Id.LBracket, "["));
    try testParsePropertyError("a.]", Token.init(Token.Id.RBracket, "]"));
    try testParsePropertyError("a.=", Token.init(Token.Id.Equal, "="));
    try testParsePropertyError("a..", Token.init(Token.Id.Dot, "."));
    try testParsePropertyError("a[,", Token.init(Token.Id.Invalid, ","));
    try testParsePropertyError("a[a", Token.init(Token.Id.Identifier, "a"));
    try testParsePropertyError("a[[", Token.init(Token.Id.LBracket, "["));
    try testParsePropertyError("a[]", Token.init(Token.Id.RBracket, "]"));
    try testParsePropertyError("a[=", Token.init(Token.Id.Equal, "="));
    try testParsePropertyError("a[.", Token.init(Token.Id.Dot, "."));
    try testParsePropertyError("a[1,", Token.init(Token.Id.Invalid, ","));
    try testParsePropertyError("a[1a", Token.init(Token.Id.Identifier, "a"));
    try testParsePropertyError("a[1 1", Token.init(Token.Id.Integer, "1"));
    try testParsePropertyError("a[1=", Token.init(Token.Id.Equal, "="));
    try testParsePropertyError("a[1.", Token.init(Token.Id.Dot, "."));
}

pub fn parsePattern(allocator: *mem.Allocator, line: []const u8) !Result([]const Pattern) {
    var list = std.ArrayList(Pattern).init(allocator);
    errdefer list.deinit();

    var res = try parsePatternList(&list, line);
    switch (res) {
        Result([]const Pattern).Ok => |*ok| ok.* = list.toOwnedSlice(),
        Result([]const Pattern).Error => list.deinit(),
    }

    return res;
}

pub fn parsePatternList(list: *std.ArrayList(Pattern), line: []const u8) !Result([]const Pattern) {
    const State = enum {
        Begin,
        Field,
        FieldPattern,
        FieldPatternEnd,
        Index,
        IndexEnd,
        IndexPattern,
        IndexPatternEnd,
    };

    var state = State.Field;
    var rest = line;
    while (true) {
        const token = if (tokenizer.next(rest)) |next| blk: {
            rest = next.rest;
            break :blk next.token;
        } else if (state == State.Begin) {
            return Result([]const Pattern).ok(list.toSlice());
        } else Token.init(Token.Id.Invalid, rest);

        switch (state) {
            State.Begin => switch (token.id) {
                Token.Id.LBracket => state = State.Index,
                Token.Id.Dot => state = State.Field,
                else => return Result([]const Pattern).err(token, []Token{
                    Token.init(Token.Id.LBracket, "["),
                    Token.init(Token.Id.Dot, "."),
                }),
            },
            State.Field => switch (token.id) {
                Token.Id.Identifier => {
                    state = State.Begin;
                    try list.append(Pattern{ .Field = token.str });
                },
                Token.Id.LBrace => state = State.FieldPattern,
                else => return Result([]const Pattern).err(token, []Token{
                    Token.init(Token.Id.Identifier, "Identifier"),
                    Token.init(Token.Id.LBrace, "{"),
                }),
            },
            State.FieldPattern => switch (token.id) {
                Token.Id.Integer => {
                    state = State.FieldPatternEnd;
                    try list.append(Pattern{ .FieldPattern = try fmt.parseUnsigned(usize, token.str, 10) });
                },
                else => return Result([]const Pattern).err(token, []Token{Token.init(Token.Id.Integer, "Integer")}),
            },
            State.FieldPatternEnd => switch (token.id) {
                Token.Id.RBrace => state = State.Begin,
                else => return Result([]const Pattern).err(token, []Token{Token.init(Token.Id.RBrace, "}")}),
            },
            State.Index => switch (token.id) {
                Token.Id.Integer => {
                    state = State.IndexEnd;
                    try list.append(Pattern{ .Index = try fmt.parseUnsigned(usize, token.str, 10) });
                },
                Token.Id.LBrace => state = State.IndexPattern,
                else => return Result([]const Pattern).err(token, []Token{
                    Token.init(Token.Id.Integer, "Integer"),
                    Token.init(Token.Id.LBrace, "{"),
                }),
            },
            State.IndexEnd => switch (token.id) {
                Token.Id.RBracket => state = State.Begin,
                else => return Result([]const Pattern).err(token, []Token{Token.init(Token.Id.RBracket, "]")}),
            },
            State.IndexPattern => switch (token.id) {
                Token.Id.Integer => {
                    state = State.IndexPatternEnd;
                    try list.append(Pattern{ .IndexPattern = try fmt.parseUnsigned(usize, token.str, 10) });
                },
                else => return Result([]const Pattern).err(token, []Token{Token.init(Token.Id.Integer, "Integer")}),
            },
            State.IndexPatternEnd => switch (token.id) {
                Token.Id.RBrace => state = State.IndexEnd,
                else => return Result([]const Pattern).err(token, []Token{Token.init(Token.Id.RBrace, "}")}),
            },
        }
    }
}

fn testParsePatternOk(str: []const u8, res: []const Pattern) !void {
    var buf: [1024]u8 = undefined;
    var fb_allocator = heap.FixedBufferAllocator.init(buf[0..]);

    const r = try parsePattern(&fb_allocator.allocator, str);
    const patterns = r.Ok;

    for (patterns) |p1, i| {
        const p2 = res[i];
        switch (p1) {
            Pattern.Field => |s| debug.assert(mem.eql(u8, s, p2.Field)),
            Pattern.FieldPattern => |index| debug.assert(index == p2.FieldPattern),
            Pattern.Index => |index| debug.assert(index == p2.Index),
            Pattern.IndexPattern => |index| debug.assert(index == p2.IndexPattern),
        }
    }
}

fn testParsePatternError(str: []const u8, token: Token) !void {
    var buf: [1024]u8 = undefined;
    var fb_allocator = heap.FixedBufferAllocator.init(buf[0..]);
    const r = try parseProperty(&fb_allocator.allocator, str);

    const t1 = r.Error.found;
    debug.assert(token.id == t1.id);
    debug.assert(mem.eql(u8, token.str, t1.str));
}

test "parser.parsePattern" {
    try testParsePatternOk(
        "a",
        []Pattern{Pattern{ .Field = "a" }},
    );
    try testParsePatternOk(
        "a.b",
        []Pattern{
            Pattern{ .Field = "a" },
            Pattern{ .Field = "b" },
        },
    );
    try testParsePatternOk(
        "a.{0}",
        []Pattern{
            Pattern{ .Field = "a" },
            Pattern{ .FieldPattern = 0 },
        },
    );
    try testParsePatternOk(
        "a[1]",
        []Pattern{
            Pattern{ .Field = "a" },
            Pattern{ .Index = 1 },
        },
    );
    try testParsePatternOk(
        "a[{0}]",
        []Pattern{
            Pattern{ .Field = "a" },
            Pattern{ .IndexPattern = 0 },
        },
    );
    try testParsePatternError(",", Token.init(Token.Id.Invalid, ","));
    try testParsePatternError("1", Token.init(Token.Id.Integer, "1"));
    try testParsePatternError("[", Token.init(Token.Id.LBracket, "["));
    try testParsePatternError("]", Token.init(Token.Id.RBracket, "]"));
    try testParsePatternError("=", Token.init(Token.Id.Equal, "="));
    try testParsePatternError(".", Token.init(Token.Id.Dot, "."));
    try testParsePatternError("a.,", Token.init(Token.Id.Invalid, ","));
    try testParsePatternError("a.1", Token.init(Token.Id.Integer, "1"));
    try testParsePatternError("a.[", Token.init(Token.Id.LBracket, "["));
    try testParsePatternError("a.]", Token.init(Token.Id.RBracket, "]"));
    try testParsePatternError("a.=", Token.init(Token.Id.Equal, "="));
    try testParsePatternError("a..", Token.init(Token.Id.Dot, "."));
    try testParsePatternError("a[,", Token.init(Token.Id.Invalid, ","));
    try testParsePatternError("a[a", Token.init(Token.Id.Identifier, "a"));
    try testParsePatternError("a[[", Token.init(Token.Id.LBracket, "["));
    try testParsePatternError("a[]", Token.init(Token.Id.RBracket, "]"));
    try testParsePatternError("a[=", Token.init(Token.Id.Equal, "="));
    try testParsePatternError("a[.", Token.init(Token.Id.Dot, "."));
    try testParsePatternError("a[1,", Token.init(Token.Id.Invalid, ","));
    try testParsePatternError("a[1a", Token.init(Token.Id.Identifier, "a"));
    try testParsePatternError("a[1 1", Token.init(Token.Id.Integer, "1"));
    try testParsePatternError("a[1=", Token.init(Token.Id.Equal, "="));
    try testParsePatternError("a[1.", Token.init(Token.Id.Dot, "."));
}
