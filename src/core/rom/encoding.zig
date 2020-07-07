const std = @import("std");

const debug = std.debug;
const io = std.io;
const mem = std.mem;
const testing = std.testing;

/// An array of string<->string that models how to encode and decode
/// from any decoding to any other encoding.
pub const CharMap = []const Char;
pub const Char = [2][]const u8;

/// Encode from one encoding to another using `CharMap` as the specification
/// of how to do transform between the encodings.
/// `curr` specifies what the encoding the `in_stream` is in and is an index
/// into entries in `map`. `out_stream` will always be the opposite encoding
/// of `in_stream`.
pub fn encodeEx(map: CharMap, curr: u1, in_stream: var, out_stream: var) !void {
    const in: usize = @boolToInt(curr == 1);
    const out: usize = @boolToInt(curr != 1);
    var buf: [16]u8 = undefined;
    var len: usize = 0;

    while (true) {
        len += try in_stream.readAll(buf[len..]);
        const chars = buf[0..len];
        if (chars.len == 0)
            break;

        var best_match: ?Char = null;
        for (map) |char| {
            debug.assert(char[in].len <= buf.len);
            if (!mem.startsWith(u8, chars, char[in]))
                continue;
            best_match = if (best_match) |best| blk: {
                break :blk if (best[in].len < char[in].len) char else best;
            } else char;
        }

        const best = best_match orelse
            return error.DecodeError;
        try out_stream.writeAll(best[out]);
        mem.copy(u8, chars, chars[best[in].len..]);
        len -= best[in].len;
    }
}

pub fn encode(map: CharMap, curr: u1, in: []const u8, out_stream: var) !void {
    var fis = io.fixedBufferStream(in);
    try encodeEx(map, curr, fis.inStream(), out_stream);
}

fn testHelper(map: CharMap, curr: u1, in: []const u8, out: []const u8) !void {
    var res: [1024]u8 = undefined;
    var fos = io.fixedBufferStream(&res);
    try encode(map, curr, in, fos.outStream());
    testing.expectEqualSlices(u8, out, fos.getWritten());
}

pub fn testCharMap(map: CharMap, a: []const u8, b: []const u8) !void {
    try testHelper(map, 0, a, b);
    try testHelper(map, 1, b, a);
}
