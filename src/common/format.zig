const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const testing = std.testing;

/// Line <- Suffix* '=' .*
///
/// Suffix
///    <- '.' IDENTIFIER
///     / '[' INTEGER ']'
///
/// INTEGER <- [0-9]+
/// IDENTIFIER <- [a-zA-Z][A-Za-z0-9_]*
///
pub const Parser = struct {
    str: []const u8,

    pub fn peek(parser: Parser) !u8 {
        if (parser.str.len == 0)
            return error.EndOfString;

        return parser.str[0];
    }

    pub fn eat(parser: *Parser) !u8 {
        const c = try parser.peek();
        parser.str = parser.str[1..];
        return c;
    }

    pub fn eatChar(parser: *Parser, c: u8) !void {
        const reset = parser.*;
        errdefer parser.* = reset;

        if (c != try parser.eat())
            return error.InvalidCharacter;
    }

    pub fn eatStr(parser: *Parser, str: []const u8) !void {
        if (parser.str.len < str.len)
            return error.EndOfString;
        if (!mem.startsWith(u8, parser.str, str))
            return error.InvalidCharacter;

        parser.str = parser.str[str.len..];
    }

    pub fn eatUnsigned(parser: *Parser, comptime Int: type, base: u8) !Int {
        const reset = parser.*;
        errdefer parser.* = reset;

        var res: Int = try math.cast(Int, try fmt.charToDigit(try parser.eat(), base));
        while (true) {
            const c = parser.peek() catch return res;
            const digit = fmt.charToDigit(c, base) catch return res;
            _ = parser.eat() catch unreachable;

            res = try math.mul(Int, res, try math.cast(Int, base));
            res = try math.add(Int, res, try math.cast(Int, digit));
        }
    }

    pub fn eatUnsignedMax(parser: *Parser, comptime Int: type, base: u8, max: var) !Int {
        const reset = parser.*;
        errdefer parser.* = reset;

        const res = try parser.eatUnsigned(Int, base);
        if (max <= res)
            return error.Overflow;

        return res;
    }

    pub fn eatUntil(parser: *Parser, c: u8) ![]const u8 {
        const reset = parser.*;
        errdefer parser.* = reset;

        var len: usize = 0;
        while (c != try parser.eat()) : (len += 1) {}

        return reset.str[0..len];
    }

    pub fn eatField(parser: *Parser, field: []const u8) !void {
        const reset = parser.*;
        errdefer parser.* = reset;
        const f = try parser.eatAnyField();
        if (!mem.eql(u8, f, field))
            return error.InvalidField;
    }

    pub fn eatAnyField(parser: *Parser) ![]const u8 {
        const reset = parser.*;
        errdefer parser.* = reset;

        try parser.eatChar('.');
        if (parser.str.len == 0)
            return error.EndOfString;

        const end = for (parser.str) |c, i| {
            switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                else => break i,
            }
        } else parser.str.len;

        defer parser.str = parser.str[end..];
        return parser.str[0..end];
    }

    pub fn eatIndex(parser: *Parser) !usize {
        const reset = parser.*;
        errdefer parser.* = reset;

        _ = try parser.eatChar('[');
        const res = try parser.eatUnsigned(usize, 10);
        _ = try parser.eatChar(']');

        return res;
    }

    pub fn eatIndexMax(parser: *Parser, max: var) !usize {
        const reset = parser.*;
        errdefer parser.* = reset;

        const res = try parser.eatIndex();
        if (max <= res)
            return error.Overflow;

        return res;
    }

    pub fn eatValue(parser: *Parser) ![]const u8 {
        const reset = parser.*;
        errdefer parser.* = reset;
        try parser.eatChar('=');

        const res = parser.str;
        parser.str = res[res.len..];
        return res;
    }

    pub fn eatUnsignedValue(parser: *Parser, comptime Int: type, base: u8) !Int {
        const reset = parser.*;
        errdefer parser.* = reset;

        try parser.eatChar('=');
        const res = try parser.eatUnsigned(Int, base);

        if (parser.str.len != 0)
            return error.InvalidCharacter;

        return res;
    }

    pub fn eatUnsignedValueMax(parser: *Parser, comptime Int: type, base: u8, max: var) !Int {
        const reset = parser.*;
        errdefer parser.* = reset;

        const res = try parser.eatUnsignedValue(Int, base);
        if (max <= res)
            return error.Overflow;

        return res;
    }

    pub fn eatEnumValue(parser: *Parser, comptime Enum: type) !Enum {
        const reset = parser.*;
        errdefer parser.* = reset;

        const str = try parser.eatValue();
        const res = std.meta.stringToEnum(Enum, str) orelse return error.InvalidValue;
        return res;
    }

    pub fn eatBoolValue(parser: *Parser) !bool {
        const Bool = enum {
            @"true",
            @"false",
        };
        const res = try parser.eatEnumValue(Bool);
        return res == Bool.@"true";
    }
};

test "peek/eat" {
    var parser = Parser{ .str = "abcd" };
    testing.expectEqual(@as(u8, 'a'), try parser.peek());
    testing.expectEqual(@as(u8, 'a'), try parser.eat());
    testing.expectEqual(@as(u8, 'b'), try parser.peek());
    testing.expectEqual(@as(u8, 'b'), try parser.eat());
    testing.expectEqual(@as(u8, 'c'), try parser.peek());
    testing.expectEqual(@as(u8, 'c'), try parser.eat());
    testing.expectEqual(@as(u8, 'd'), try parser.peek());
    testing.expectEqual(@as(u8, 'd'), try parser.eat());
    testing.expectError(error.EndOfString, parser.peek());
    testing.expectError(error.EndOfString, parser.eat());
}

test "eatChar" {
    var parser = Parser{ .str = "abcd" };
    try parser.eatChar('a');
    testing.expectError(error.InvalidCharacter, parser.eatChar('a'));
    try parser.eatChar('b');
    testing.expectError(error.InvalidCharacter, parser.eatChar('b'));
    try parser.eatChar('c');
    testing.expectError(error.InvalidCharacter, parser.eatChar('c'));
    try parser.eatChar('d');
    testing.expectError(error.EndOfString, parser.eatChar('d'));
}

test "eatStr" {
    var parser = Parser{ .str = "abcd" };
    try parser.eatStr("ab");
    testing.expectError(error.InvalidCharacter, parser.eatStr("ab"));
    try parser.eatStr("cd");
    testing.expectError(error.EndOfString, parser.eatStr("cd"));
}

test "eatUnsigned" {
    var parser = Parser{ .str = "1234a" };
    testing.expectEqual(@as(usize, 1234), try parser.eatUnsigned(usize, 10));
    testing.expectError(error.InvalidCharacter, parser.eatUnsigned(usize, 10));
}

test "eatUnsigned" {
    var parser = Parser{ .str = "1234a1234" };
    testing.expectEqual(@as(usize, 1234), try parser.eatUnsignedMax(usize, 10, 10000));
    try parser.eatChar('a');
    testing.expectError(error.Overflow, parser.eatUnsignedMax(usize, 10, 1000));
}

test "eatUntil" {
    var parser = Parser{ .str = "aab" };
    testing.expectEqualSlices(u8, "aa", try parser.eatUntil('b'));
    testing.expectError(error.EndOfString, parser.eatUntil('b'));
}

test "eatAnyField" {
    var parser = Parser{ .str = ".a.b*" };
    testing.expectEqualSlices(u8, "a", try parser.eatAnyField());
    testing.expectEqualSlices(u8, "b", try parser.eatAnyField());
    testing.expectError(error.InvalidCharacter, parser.eatAnyField());
}

test "eatField" {
    var parser = Parser{ .str = ".a.b" };
    testing.expectError(error.InvalidField, parser.eatField("b"));
    try parser.eatField("a");
    try parser.eatField("b");
}

test "eatIndex" {
    var parser = Parser{ .str = "[1][2]*" };
    testing.expectEqual(@as(usize, 1), try parser.eatIndex());
    testing.expectEqual(@as(usize, 2), try parser.eatIndex());
    testing.expectError(error.InvalidCharacter, parser.eatIndex());
}

test "eatIndexMax" {
    var parser = Parser{ .str = "[1][2]*" };
    testing.expectError(error.Overflow, parser.eatIndexMax(0));
    testing.expectEqual(@as(usize, 1), try parser.eatIndexMax(2));
    testing.expectEqual(@as(usize, 2), try parser.eatIndexMax(3));
    testing.expectError(error.InvalidCharacter, parser.eatIndexMax(2));
}

test "eatValue" {
    var parser = Parser{ .str = "=test" };
    testing.expectEqualSlices(u8, "test", try parser.eatValue());
    parser = Parser{ .str = "test" };
    testing.expectError(error.InvalidCharacter, parser.eatValue());
}

test "eatUnsignedValue" {
    var parser = Parser{ .str = "=123" };
    testing.expectEqual(@as(usize, 123), try parser.eatUnsignedValue(usize, 10));
    parser = Parser{ .str = "=abc" };
    testing.expectError(error.InvalidCharacter, parser.eatUnsignedValue(usize, 10));
}

test "eatUnsignedValueMax" {
    var parser = Parser{ .str = "=123" };
    testing.expectEqual(@as(usize, 123), try parser.eatUnsignedValueMax(usize, 10, 124));
    parser = Parser{ .str = "=124" };
    testing.expectError(error.Overflow, parser.eatUnsignedValueMax(usize, 10, 124));
}

test "eatEnumValue" {
    const E = enum {
        a,
    };
    var parser = Parser{ .str = "=a" };
    testing.expectEqual(E.a, try parser.eatEnumValue(E));
    parser = Parser{ .str = "=b" };
    testing.expectError(error.InvalidValue, parser.eatEnumValue(E));
}

test "eatBoolValue" {
    const E = enum {
        a,
    };
    var parser = Parser{ .str = "=true" };
    testing.expectEqual(true, try parser.eatBoolValue());
    parser = Parser{ .str = "=false" };
    testing.expectEqual(false, try parser.eatBoolValue());
    parser = Parser{ .str = "=A" };
    testing.expectError(error.InvalidValue, parser.eatBoolValue());
}
