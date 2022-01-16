const std = @import("std");
const util = @import("util.zig");

const fs = std.fs;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const testing = std.testing;

pub const bufsize = mem.page_size * 2;

pub fn Fifo(comptime buffer_type: std.fifo.LinearFifoBufferType) type {
    return std.fifo.LinearFifo(u8, buffer_type);
}

/// Reads lines from `reader` using a `Fifo` for buffering.
///
/// NOTE: using `readUntilDelimitorArrayList` over this function results in
///       tm35-rand-trainers to be around 2x slower. This function is therefor
///       still better to use until zigs std gets a better `readUntilDelimitor`
///       implementation. Replacement code bellow:
///```
///buf_reader.reader().readUntilDelimiterArrayList(buffer, '\n', std.math.maxInt(usize)) catch |err| switch (err) {
///    error.StreamTooLong => unreachable,
///    error.EndOfStream => {
///        if (buffer.items.len != 0)
///            return buffer.items;
///        return null;
///    },
///    else => |err2| return err2,
///};
///return buffer.items;
///```
pub fn readUntil(reader: anytype, fifo: anytype, byte: u8) !?[]const u8 {
    while (true) {
        const buf = fifo.readableSlice(0);
        if (mem.indexOfScalar(u8, buf, byte)) |index| {
            defer fifo.head += index + 1;
            defer fifo.count -= index + 1;
            return buf[0..index];
        }

        const new_buf = blk: {
            fifo.realign();
            const slice = fifo.writableSlice(0);
            if (slice.len != 0)
                break :blk slice;
            break :blk try fifo.writableWithSize(math.max(bufsize, fifo.buf.len));
        };

        const num = try reader.read(new_buf);
        fifo.update(num);

        if (num == 0) {
            if (fifo.count != 0) {
                // Ensure that the buffer returned always have `byte` terminating
                // it, so that wrappers can return `[:Z]const u8` if they want to.
                // This is used by `readLine`.
                try fifo.writeItem(byte);
                const res = fifo.readableSlice(0);
                fifo.count = 0;
                return res[0 .. res.len - 1];
            }

            return null;
        }
    }
}

pub fn readLine(reader: anytype, fifo: anytype) !?[:'\n']const u8 {
    const res = (try readUntil(reader, fifo, '\n')) orelse return null;
    if (mem.endsWith(u8, res, "\r")) {
        // Right now, readableSliceMut for fifo is private, so i cannot implement
        // this easily without casting away const, as `readUntil` cannot return
        // a mutable slice.
        const res_mut = util.unsafe.castAwayConst(res);
        res_mut[res.len - 1] = '\n';
        return res[0 .. res.len - 1 :'\n'];
    }
    return res.ptr[0..res.len :'\n'];
}

test "readLine" {
    try testReadLine(
        \\a
        \\b
        \\c
    , &[_][]const u8{
        "a",
        "b",
        "c",
    });
    try testReadLine(
        "a\r\n" ++
            "b\n" ++
            "c",
        &[_][]const u8{
            "a",
            "b",
            "c",
        },
    );
}

fn testReadLine(str: []const u8, lines: []const []const u8) !void {
    var fbs = std.io.fixedBufferStream(str);
    var fifo = Fifo(.{ .Static = 3 }).init();

    for (lines) |expected_line| {
        const actual_line = (try readLine(fbs.reader(), &fifo)).?;
        try testing.expectEqualStrings(expected_line, actual_line);
        try testing.expectEqual(@as(u8, '\n'), actual_line[actual_line.len]);
    }
    try testing.expectEqual(@as(?[:'\n']const u8, null), try readLine(fbs.reader(), &fifo));
}
