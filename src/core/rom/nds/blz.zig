const std = @import("std");

const debug = std.debug;
const math = std.math;
const mem = std.mem;

const default_mask = 0x80;
const threshold = 2;

// TODO: Tests

// TODO: This file could use some love in the form of a refactor. So far, it is mostly
//       a direct translation of blz.c, but with some minor refactors here and there.
//       Sadly, it's still not clear at all what this code is trying to do other than
//       some kind of encoding. `searchMatch` is an example of my refactor, that actually
//       did help make a little piece of this code clearer.

// TODO: Figure out if it's possible to make these encode and decode functions use readers.
pub fn decode(data: []const u8, allocator: *mem.Allocator) ![]u8 {
    const Lengths = struct {
        enc: u32,
        dec: u32,
        pak: u32,
        raw: u32,
    };

    if (data.len < 8)
        return error.BadHeader;

    const inc_len = mem.readIntLittle(u32, data[data.len - 4 ..][0..4]);
    const lengths = blk: {
        if (inc_len == 0) {
            return error.BadHeaderLength;
        } else {
            const hdr_len = data[data.len - 5];
            if (hdr_len < 8 or hdr_len > 0xB) return error.BadHeaderLength;
            if (data.len <= hdr_len) return error.BadLength;

            const enc_len = mem.readIntLittle(u32, data[data.len - 8 ..][0..4]) & 0x00FFFFFF;
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
    mem.reverse(u8, pak_buffer[lengths.dec .. lengths.dec + lengths.pak]);

    const pak_end = lengths.dec + lengths.pak;
    var pak = lengths.dec;
    var raw = lengths.dec;
    var mask = @as(usize, 0);
    var flags = @as(usize, 0);

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

            const pos = (@as(usize, pak_buffer[pak]) << 8) | pak_buffer[pak + 1];
            pak += 2;

            const len = (pos >> 12) + threshold + 1;
            if (raw + len > lengths.raw) return error.WrongDecodedLength;

            const new_pos = (pos & 0xFFF) + 3;
            var i = @as(usize, 0);
            while (i < len) : (i += 1) {
                result[raw] = result[raw - new_pos];
                raw += 1;
            }
        }
    }

    if (raw != lengths.raw) return error.UnexpectedEnd;

    mem.reverse(u8, result[lengths.dec..lengths.raw]);
    return result[0..raw];
}

pub const Mode = enum {
    normal,
    best,
};

pub fn encode(data: []const u8, mode: Mode, arm9: bool, allocator: *mem.Allocator) ![]u8 {
    var pak_tmp = @as(usize, 0);
    var raw_tmp = data.len;
    var pak_len = data.len + ((data.len + 7) / 8) + 11;
    var pak = @as(usize, 0);
    var raw = @as(usize, 0);
    var mask = @as(usize, 0);
    var flag = @as(usize, 0);
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

    mem.reverse(u8, raw_buffer[0..data.len]);

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
            if (mode == .best) {
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

    mem.reverse(u8, raw_buffer[0..data.len]);
    mem.reverse(u8, result[0..pak_len]);

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
        var hdr_len = @as(usize, 8);

        while ((pak & 3) != 0) : ({
            pak += 1;
            hdr_len += 1;
        }) {
            new_result[pak] = 0xFF;
        }

        mem.writeIntLittle(u32, new_result[pak..][0..4], @intCast(u32, enc_len + hdr_len));
        pak += 3;
        new_result[pak] = @truncate(u8, hdr_len);
        pak += 1;
        mem.writeIntLittle(u32, new_result[pak..][0..4], @intCast(u32, inc_len - hdr_len));
        pak += 4;

        return new_result[0..pak];
    }
}

/// Searches for ::match in ::data, and returns a slice to the best match.
fn searchMatch(data: []const u8, match: []const u8) []const u8 {
    var pos: usize = 0;
    var best = data[pos..pos];
    while (pos < data.len) : (pos += 1) {
        pos = mem.indexOfScalarPos(u8, data, pos, match[0]) orelse break;

        const max = math.min(match.len, data.len - pos);
        var len: usize = 1;
        while (len < max) : (len += 1) {
            if (data[pos + len] != match[len]) break;
        }

        if (best.len < len) {
            best = data[pos..][0..len];
            if (best.len == match.len)
                break;
        }
    }

    return best;
}

/// Finding best match of data[raw..raw+0x12] in data[max(0, raw - 0x1002)..raw]
/// and return the pos and length to that match
fn search(data: []const u8, raw: usize) []const u8 {
    const max = math.min(raw, @as(usize, 0x1002));
    const pattern = data[raw..math.min(@as(usize, 0x12) + raw, data.len)];
    const d = data[raw - max .. raw];

    return searchMatch(d, pattern);
}
