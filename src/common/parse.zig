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

fn structure(str: []const u8, ptr: var, comptime converters: var) !void {
    const fields = @typeInfo(@TypeOf(ptr).Child).Struct.fields;
    inline for (fields) |field_info| blk: {
        const Field = field_info.field_type;
        const f = &@field(ptr, field_info.name);
        if (field(field_info.name)(str)) |ff|
            return anyT(ff.rest, f, converters);
    }

    return error.FoundNoField;
}

fn slice(str: []const u8, s: var, comptime converters: var) !void {
    const ii = index(str) orelse return error.FoundNoIndex;
    if (ii.value >= s.len)
        return error.IndexOutOfBound;
    return anyT(ii.rest, &s[ii.value], converters);
}

pub fn anyT(str: []const u8, ptr: var, comptime converters: var) !void {
    const T = @TypeOf(ptr).Child;
    comptime var i = 0;
    inline while (i < converters.len) : (i += 1) {
        const conv = converters[i];
        const Return = @TypeOf(conv).ReturnType.Child;
        if (T == Return) {
            const v = value(T, conv)(str) orelse return error.FoundNoValue;
            ptr.* = v.value;
            return;
        }
    } else switch (@typeInfo(T)) {
        .Struct => return structure(str, ptr, converters),
        .Array => |a| return slice(str, ptr, converters),
        .Pointer => |s| return slice(str, ptr.*, converters),
        else => @compileError("No converter for '" ++ @typeName(T) ++ "'"),
    }
    unreachable;
}

test "anyT" {
    const S = struct {
        a: u8,
        b: u16,
        c: [2]u8,
    };
    var s: S = undefined;
    const converters = comptime .{
        toInt(u8, 10),
        toInt(u16, 10),
    };

    try anyT(".a=2", &s, converters);
    try anyT(".b=4", &s, converters);
    try anyT(".c[0]=6", &s, converters);
    try anyT(".c[1]=8", &s, converters);
    testing.expectError(error.IndexOutOfBound, anyT(".c[2]=8", &s, converters));
    testing.expectError(error.FoundNoField, anyT("d=8", &s, converters));
    testing.expectEqual(@as(u8, 2), s.a);
    testing.expectEqual(@as(u16, 4), s.b);
    testing.expectEqual(@as(u16, 6), s.c[0]);
    testing.expectEqual(@as(u16, 8), s.c[1]);
}

pub const strv = value([]const u8, struct {
    fn func(str: []const u8) ?[]const u8 {
        return str;
    }
}.func);
pub const u4v = value(u4, toInt(u4, 10));
pub const u6v = value(u6, toInt(u6, 10));
pub const u7v = value(u7, toInt(u7, 10));
pub const u8v = value(u8, toInt(u8, 10));
pub const u10v = value(u10, toInt(u10, 10));
pub const u16v = value(u16, toInt(u16, 10));
pub const u32v = value(u32, toInt(u32, 10));
pub const u64v = value(u64, toInt(u64, 10));
pub const usizev = value(usize, toInt(usize, 10));
pub const boolv = value(bool, toBool);

pub fn enumv(comptime Enum: type) Parser(Enum) {
    return comptime value(Enum, toEnum(Enum));
}

pub fn field(comptime str: []const u8) Parser(void) {
    return convert(
        void,
        struct {
            fn match(s: []const u8) ?void {
                return if (mem.eql(u8, s, str)) {} else null;
            }
        }.match,
        comptime combine(.{ char('.'), ident }),
    );
}

pub fn value(comptime T: type, comptime conv: fn ([]const u8) ?T) Parser(T) {
    return comptime convert(T, conv, combine(.{ char('='), any }));
}

pub const index: Parser(usize) = combine(.{ char('['), int(usize, 10), char(']') });
pub const anyField: Parser([]const u8) = combine(.{ char('.'), ident });

pub const ident: Parser([]const u8) = manyRange(1, math.maxInt(usize), oneOf(.{
    range('_', '_'),
    alpha,
    digit(10),
}));

pub const MutParser = struct {
    str: []const u8,

    pub fn parse(p: *MutParser, comptime parser: var) !ParserResult(@TypeOf(parser)) {
        const v = parser(p.str) orelse return error.ParseError;
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
    const Hash = std.meta.IntType(false, (max_bytes + @sizeOf(L)) * 8);

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
            var res: Hash = length;
            for (h) |r|
                res = (res * 256) + r;
            return res;
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
