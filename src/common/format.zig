const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const math = std.math;
const mem = std.mem;

/// Line <- Suffix* '=' .*
///
/// Suffix
///    <- '.' IDENTIFIER
///     / '[' INTEGER ']'
///
/// INTEGER <- [0-9]+
/// IDENTIFIER <- [a-zA-Z][A-Za-z0-9_]*
///
pub const StrParser = struct {
    str: []const u8,

    pub fn init(str: []const u8) StrParser {
        return StrParser{ .str = str };
    }

    pub fn peek(parser: StrParser) !u8 {
        if (parser.str.len == 0)
            return error.EndOfString;

        return parser.str[0];
    }

    pub fn eat(parser: *StrParser) !u8 {
        const c = try parser.peek();
        parser.str = parser.str[1..];
        return c;
    }

    pub fn eatChar(parser: *StrParser, c: u8) !void {
        const reset = parser.*;
        errdefer parser.* = reset;

        if (c != try parser.eat())
            return error.InvalidCharacter;
    }

    pub fn eatStr(parser: *StrParser, str: []const u8) !void {
        if (parser.str.len < str.len)
            return error.EndOfString;
        if (!mem.startsWith(u8, parser.str, str))
            return error.InvalidCharacter;

        parser.str = parser.str[str.len..];
    }

    pub fn eatUnsigned(parser: *StrParser, comptime Int: type, base: u8) !Int {
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

    pub fn eatUnsignedMax(parser: *StrParser, comptime Int: type, base: u8, max: var) !Int {
        const reset = parser.*;
        errdefer parser.* = reset;

        const res = try parser.eatUnsigned(Int, base);
        if (max <= res)
            return error.Overflow;

        return res;
    }

    pub fn eatUntil(parser: *StrParser, c: u8) ![]const u8 {
        const reset = parser.*;
        errdefer parser.* = reset;

        var len: usize = 0;
        while (c != try parser.eat()) : (len += 1) {}

        return reset.str[0..len];
    }

    pub fn eatField(parser: *StrParser, field: []const u8) !void {
        const reset = parser.*;
        errdefer parser.* = reset;
        try parser.eatChar('.');
        const f = try parser.eatAnyField();
        if (!mem.eql(u8, f, field))
            return error.InvalidField;
    }

    pub fn eatAnyField(parser: *StrParser) ![]const u8 {
        for (parser.str) |c, i| {
            switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                else => {
                    defer parser.str = parser.str[i..];
                    return parser.str[0..i];
                },
            }
        }

        return error.EndOfString;
    }

    pub fn eatIndex(parser: *StrParser) !usize {
        const reset = parser.*;
        errdefer parser.* = reset;

        _ = try parser.eatChar('[');
        const res = try parser.eatUnsigned(usize, 10);
        _ = try parser.eatChar(']');

        return res;
    }

    pub fn eatIndexMax(parser: *StrParser, max: var) !usize {
        const reset = parser.*;
        errdefer parser.* = reset;

        const res = try parser.eatIndex();
        if (max <= res)
            return error.Overflow;

        return res;
    }

    pub fn eatValue(parser: *StrParser) ![]const u8 {
        const reset = parser.*;
        errdefer parser.* = reset;
        try parser.eatChar('=');

        const res = parser.str;
        parser.str = res[res.len..];
        return res;
    }

    pub fn eatUnsignedValue(parser: *StrParser, comptime Int: type, base: u8) !Int {
        const reset = parser.*;
        errdefer parser.* = reset;

        try parser.eatChar('=');
        const res = try parser.eatUnsigned(Int, base);

        if (parser.str.len != 0)
            return error.InvalidCharacter;

        return res;
    }

    pub fn eatUnsignedValueMax(parser: *StrParser, comptime Int: type, base: u8, max: var) !Int {
        const reset = parser.*;
        errdefer parser.* = reset;

        const res = parser.eatUnsignedValue(Int, base);
        if (max <= res)
            return error.Overflow;

        return res;
    }

    pub fn eatEnumValue(parser: *StrParser, comptime Enum: type) !Enum {
        const reset = parser.*;
        errdefer parser.* = reset;

        const str = try parser.eatValue();
        const res = std.meta.stringToEnum(Enum, str) orelse return error.InvalidValue;
        return res;
    }

    pub fn eatBoolValue(parser: *StrParser) !bool {
        const Bool = enum {
            @"true",
            @"false",
        };
        const res = try parser.eatEnumValue(Bool);
        return res == Bool.@"true";
    }
};
