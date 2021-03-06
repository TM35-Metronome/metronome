const std = @import("std");

const math = std.math;
const mem = std.mem;
const testing = std.testing;

pub usingnamespace @import("mecha");

//! The tm35 format in 8 lines of cfg:
//! Line <- Suffix* '=' .*
//!
//! Suffix
//!    <- '.' IDENTIFIER
//!     / '[' INTEGER ']'
//!
//! INTEGER <- [0-9]+
//! IDENTIFIER <- [A-Za-z0-9_]+
//!

pub const strv = value([]const u8, struct {
    fn func(_: *mem.Allocator, str: []const u8) Error![]const u8 {
        return str;
    }
}.func);
pub const boolv = value(bool, toBool);
pub const u10v = value(u10, toInt(u10, 10));
pub const u16v = value(u16, toInt(u16, 10));
pub const u32v = value(u32, toInt(u32, 10));
pub const u4v = value(u4, toInt(u4, 10));
pub const u64v = value(u64, toInt(u64, 10));
pub const u6v = value(u6, toInt(u6, 10));
pub const u7v = value(u7, toInt(u7, 10));
pub const u8v = value(u8, toInt(u8, 10));
pub const usizev = value(usize, toInt(usize, 10));

pub fn enumv(comptime Enum: type) Parser(Enum) {
    return comptime value(Enum, toEnum(Enum));
}

pub fn field(comptime str: []const u8) Parser(void) {
    return string("." ++ str);
}

pub fn value(comptime T: type, comptime conv: fn (*mem.Allocator, []const u8) Error!T) Parser(T) {
    return comptime convert(T, conv, combine(.{ ascii.char('='), rest }));
}

pub const anyField: Parser([]const u8) = combine(.{ ascii.char('.'), ident });
pub const index: Parser(usize) = combine(.{ ascii.char('['), int(usize, 10), ascii.char(']') });

pub const ident: Parser([]const u8) = many(oneOf(.{
    ascii.range('_', '_'),
    ascii.alpha,
    ascii.digit(10),
}), .{ .collect = false, .min = 1 });

pub const MutParser = struct {
    str: []const u8,

    pub fn parse(p: *MutParser, comptime parser: anytype) !blk: {
        @setEvalBranchQuota(100000);
        break :blk ParserResult(@TypeOf(parser));
    } {
        const v = parser(undefined, p.str) catch return error.ParseError;
        p.str = v.rest;
        return v.value;
    }
};

/// Swhash copied from fengbs fundude project:
/// https://github.com/fengb/fundude/blob/5caa8f46f8d27b9259d74be113407ea0230c2408/src/util.zig#L108-L127
///
/// Copyright (c) 2020 Benjamin Feng
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in all
/// copies or substantial portions of the Software.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
/// SOFTWARE.
///
/// This is a corrected version of Swhash. The original had a few issues with correctness:
/// * "abc" and "abc\x00" would match the same hash.
/// * for Swhash(4) an "\xff\xff\xff\xff" case will match any string larger than 4 bytes.
pub fn Swhash(comptime max_bytes: comptime_int) type {
    const L = std.math.IntFittingRange(0, max_bytes + 1);
    const Hash = std.meta.IntType(.unsigned, (max_bytes + @sizeOf(L)) * 8);

    return struct {
        pub fn match(str: []const u8) Hash {
            return hash(str) orelse result(max_bytes + 1, "");
        }

        pub fn case(comptime str: []const u8) Hash {
            return comptime hash(str) orelse @compileError("Cannot hash '" ++ str ++ "'");
        }

        fn hash(str: []const u8) ?Hash {
            if (str.len > max_bytes) return null;
            return result(@intCast(L, str.len), str);
        }

        fn result(length: L, h: []const u8) Hash {
            var res = [_]u8{0} ** @sizeOf(Hash);
            mem.copy(u8, &res, h);
            mem.copy(u8, res[h.len..], mem.asBytes(&length));
            return @ptrCast(*align(1) Hash, &res).*;
        }
    };
}

test "Swhash" {
    const sw = Swhash(15);
    inline for ([_][]const u8{
        "EqO8Asds",
        "77WmE2bzo",
        "Q96oTxDiKY",
        "rgRIc2jEFu",
        "bssHOVhQMXF",
        "k4GWfgQJY",
        "WY1F5RMj",
        "hICKcKI",
        "3Xh12ag5",
        "NCH6LrS",
        "tXPOk2u1ur",
        "OWo4hmbeMCm",
        "mzHyzU2ETog",
        "fromSF6rzT",
        "5dDlTmSwY0hx",
        "0d1dCGpTzRf",
        "PqZe0A7UPLUzA",
        "HX1SuW2vA",
        "hSUwTBgIptkRuV",
        "typedguRB85VsU",
        "YxnhFMqqajVgTN",
        "SAqF09YXpvO0oo",
        "ScvpzsaEWwWmrK",
        "vhwUblIcVZLtoqj",
        "9ByMKBa",
    }) |str| {
        testing.expectEqual(sw.case(str), sw.match(str));
    }
}
