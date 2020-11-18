const std = @import("std");

const math = std.math;
const mem = std.mem;
const testing = std.testing;

pub fn Fifo(comptime buffer_type: std.fifo.LinearFifoBufferType) type {
    return std.fifo.LinearFifo(u8, buffer_type);
}

/// Reads lines from `reader` using a `Fifo` for buffering.
///
/// NOTE: using `readUntilDelimitorArrayList` over this function results in
///       tm35-rand-parties to be around 2x slower. This function is therefor
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
pub fn line(reader: anytype, fifo: anytype) !?[]const u8 {
    while (true) {
        const buf = fifo.readableSlice(0);
        if (mem.indexOfScalar(u8, buf, '\n')) |index| {
            defer fifo.head += index + 1;
            defer fifo.count -= index + 1;
            return buf[0..index];
        }

        const new_buf = blk: {
            fifo.realign();
            const slice = fifo.writableSlice(0);
            if (slice.len != 0)
                break :blk slice;
            break :blk try fifo.writableWithSize(math.max(1024, fifo.buf.len));
        };

        const num = try reader.read(new_buf);
        fifo.update(num);

        if (num == 0) {
            if (fifo.count != 0) {
                defer fifo.count = 0;
                return fifo.readableSlice(0);
            }

            return null;
        }
    }
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
}

fn testReadLine(str: []const u8, lines: []const []const u8) !void {
    var fbs = std.io.fixedBufferStream(str);
    var fifo = std.fifo.LinearFifo(u8, .{ .Static = 3 }).init();

    for (lines) |expected_line| {
        const actual_line = (try line(fbs.reader(), &fifo)).?;
        testing.expectEqualSlices(u8, expected_line, actual_line);
    }
    testing.expectEqual(@as(?[]const u8, null), try line(fbs.reader(), &fifo));
}
