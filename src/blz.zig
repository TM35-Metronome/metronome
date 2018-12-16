const std = @import("std");

const mem = std.mem;
const debug = std.debug;
const math = std.math;

const threshold = 2;
const default_mask = 0x80;

// TODO: Tests

// TODO: This file could use some love in the form of a refactor. So far, it is mostly
//       a direct translation of blz.c, but with some minor refactors here and there.
//       Sadly, it's still not clear at all what this code is trying to do other than
//       some kind of encoding. searchMatch is an example of my refactor, that actually
//       did help make a little piece of this code clearer.

// TODO: Figure out if it's possible to make these encode and decode functions use streams.
pub fn decode(data: []const u8, allocator: *mem.Allocator) ![]u8 {
    const Lengths = struct {
        enc: u32,
        dec: u32,
        pak: u32,
        raw: u32,
    };

    if (data.len < 8)
        return error.BadHeader;

    const inc_len = mem.readIntLittle(u32, @ptrCast(*const [4]u8, data[data.len - 4 ..][0..4].ptr));
    const lengths = blk: {
        if (inc_len == 0) {
            return error.BadHeaderLength;
        } else {
            const hdr_len = data[data.len - 5];
            if (hdr_len < 8 or hdr_len > 0xB) return error.BadHeaderLength;
            if (data.len <= hdr_len) return error.BadLength;

            const enc_len =  mem.readIntLittle(u32, @ptrCast(*const [4]u8, data[data.len - 8 ..][0..4].ptr)) & 0x00FFFFFF;
            const dec_len = try math.sub(u32, try math.cast(u32, data.len), enc_len);
            const pak_len = try math.sub(u32, enc_len, hdr_len);
            const raw_len = dec_len + enc_len + inc_len;

            if (raw_len > 0x00FFFFFF)
                return error.BadLength;

            break :blk Lengths{
                .enc = enc_len,
                .dec = dec_len,
                .pak = pak_len,
                .raw = raw_len,
            };
        }
    };

    const result = try allocator.alloc(u8, lengths.raw);
    errdefer allocator.free(result);
    const pak_buffer = try allocator.alloc(u8, data.len + 3);
    defer allocator.free(pak_buffer);

    mem.copy(u8, result, data[0..lengths.dec]);
    mem.copy(u8, pak_buffer, data);
    invert(pak_buffer[lengths.dec .. lengths.dec + lengths.pak]);

    const pak_end = lengths.dec + lengths.pak;
    var pak = lengths.dec;
    var raw = lengths.dec;
    var mask = usize(0);
    var flags = usize(0);

    while (raw < lengths.raw) {
        mask = mask >> 1;
        if (mask == 0) {
            if (pak == pak_end) break;

            flags = pak_buffer[pak];
            mask = default_mask;
            pak += 1;
        }

        if (flags & mask == 0) {
            if (pak == pak_end) break;

            result[raw] = pak_buffer[pak];
            raw += 1;
            pak += 1;
        } else {
            if (pak + 1 >= pak_end) break;

            const pos = (usize(pak_buffer[pak]) << 8) | pak_buffer[pak + 1];
            pak += 2;

            const len = (pos >> 12) + threshold + 1;
            if (raw + len > lengths.raw) return error.WrongDecodedLength;

            const new_pos = (pos & 0xFFF) + 3;
            var i = usize(0);
            while (i < len) : (i += 1) {
                result[raw] = result[raw - new_pos];
                raw += 1;
            }
        }
    }

    if (raw != lengths.raw) return error.UnexpectedEnd;

    invert(result[lengths.dec..lengths.raw]);
    return result[0..raw];
}

pub const Mode = enum {
    Normal,
    Best,
};

pub fn encode(data: []const u8, mode: Mode, arm9: bool, allocator: *mem.Allocator) ![]u8 {
    var pak_tmp = usize(0);
    var raw_tmp = data.len;
    var pak_len = data.len + ((data.len + 7) / 8) + 11;
    var pak = usize(0);
    var raw = usize(0);
    var mask = usize(0);
    var flag = usize(0);
    var raw_end = blk: {
        var res = data.len;
        if (arm9) {
            res -= 0x4000;
        }

        break :blk res;
    };

    const result = try allocator.alloc(u8, pak_len);
    const raw_buffer = try allocator.alloc(u8, data.len + 3);
    defer allocator.free(raw_buffer);
    mem.copy(u8, raw_buffer, data);

    invert(raw_buffer[0..data.len]);

    while (raw < raw_end) {
        mask = mask >> 1;
        if (mask == 0) {
            result[pak] = 0;
            mask = default_mask;
            flag = pak;
            pak += 1;
        }

        const best = search(raw_buffer[0..raw_end], raw);
        const pos_best = @ptrToInt(raw_buffer[raw..].ptr) - @ptrToInt(best.ptr);
        const len_best = blk: {
            if (mode == Mode.Best) {
                if (best.len > threshold) {
                    if (raw + best.len < raw_end) {
                        raw += best.len;

                        const next = search(raw_buffer[0..raw_end], raw);
                        raw -= best.len - 1;
                        const post = search(raw_buffer[0..raw_end], raw);
                        raw -= 1;

                        const len_next = if (next.len <= threshold) 1 else next.len;
                        const len_post = if (post.len <= threshold) 1 else post.len;

                        if (best.len + len_next <= 1 + len_post)
                            break :blk 1;
                    }
                }
            }

            break :blk best.len;
        };

        result[flag] = result[flag] << 1;
        if (len_best > threshold) {
            raw += len_best;
            result[flag] |= 1;
            result[pak] = @truncate(u8, ((len_best - (threshold + 1)) << 4) | ((pos_best - 3) >> 8));
            result[pak + 1] = @truncate(u8, (pos_best - 3));
            pak += 2;
        } else {
            result[pak] = raw_buffer[raw];
            pak += 1;
            raw += 1;
        }

        if (pak + data.len - raw < pak_tmp + raw_tmp) {
            pak_tmp = pak;
            raw_tmp = data.len - raw;
        }
    }

    while (mask > 0) {
        mask = mask >> 1;
        result[flag] = result[flag] << 1;
    }

    pak_len = pak;

    invert(raw_buffer[0..data.len]);
    invert(result[0..pak_len]);

    if (pak_tmp == 0 or data.len + 4 < ((pak_tmp + raw_tmp + 3) & 0xFFFFFFFC) + 8) {
        mem.copy(u8, result[0..data.len], raw_buffer[0..data.len]);
        pak = data.len;

        while ((pak & 3) > 0) : (pak += 1) {
            result[pak] = 0;
        }

        result[pak] = 0;
        result[pak + 1] = 0;
        result[pak + 2] = 0;
        result[pak + 3] = 0;
        pak += 4;

        return result[0..pak];
    } else {
        defer allocator.free(result);
        const new_result = try allocator.alloc(u8, raw_tmp + pak_tmp + 11);

        mem.copy(u8, new_result[0..raw_tmp], raw_buffer[0..raw_tmp]);
        mem.copy(u8, new_result[raw_tmp..][0..pak_tmp], result[pak_len - pak_tmp ..][0..pak_tmp]);

        pak = raw_tmp + pak_tmp;

        const enc_len = pak_tmp;
        const inc_len = data.len - pak_tmp - raw_tmp;
        var hdr_len = usize(8);

        while ((pak & 3) != 0) : ({
            pak += 1;
            hdr_len += 1;
        }) {
            new_result[pak] = 0xFF;
        }

        mem.writeInt(new_result[pak..], @intCast(u32, enc_len + hdr_len), @import("builtin").Endian.Little);
        pak += 3;
        new_result[pak] = @truncate(u8, hdr_len);
        pak += 1;
        mem.writeInt(new_result[pak..], @intCast(u32, inc_len - hdr_len), @import("builtin").Endian.Little);
        pak += 4;

        return new_result[0..pak];
    }
}

/// Searches for ::match in ::data, and returns a slice to the best match.
/// TODO: This function finds the last best match, aka if two matches are
///       the same len, the last in ::data will be returned.
///       We only do this so that we are binary equivalent with blz.c.
///       When we don't need blz.c anymore, change this behavior.
fn searchMatch(data: []const u8, match: []const u8) []const u8 {
    var best = data[0..0];

    var pos = usize(0);
    while (pos < data.len) : (pos += 1) {
        const max = math.min(match.len, data.len - pos);

        var len = usize(0);
        while (len < max) : (len += 1) {
            if (data[pos + len] != match[len]) break;
        }

        if (best.len <= len) {
            best = data[pos..][0..len];
        }
    }

    return best;
}

/// Finding best match of data[raw..raw+0x12] in data[max(0, raw - 0x1002)..raw]
/// and return the pos and lenght to that match
fn search(data: []const u8, raw: usize) []const u8 {
    const max = math.min(raw, usize(0x1002));
    const pattern = data[raw..math.min(usize(0x12) + raw, data.len)];
    const d = data[raw - max .. raw];

    return searchMatch(d, pattern);
}

fn invert(data: []u8) void {
    var bottom = data.len - 1;
    var i = usize(0);
    while (i < bottom) : ({
        i += 1;
        bottom -= 1;
    }) {
        const tmp = data[i];
        data[i] = data[bottom];
        data[bottom] = tmp;
    }
}
