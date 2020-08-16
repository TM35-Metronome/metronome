const std = @import("std");

const mem = std.mem;
const testing = std.testing;

/// This is a special case readLine implementation for BufferedInStreams.
/// This function looks directly into the buffer that BufferedInStream manages
/// to find lines. This function returns slices into the BufferedInStream and
/// can therefor only read lines as long as the buffers size. For all programs
/// in this project, this shouldn't really be a problem as lines are relativly
/// small (at least a lot smaller than 4096, which is bufinstreams default).
///
/// NOTE: using `readUntilDelimitorArrayList` over this function results in
///       tm35-rand-parties to be around 2x slower. This function is therefor
///       still better to use until zigs std gets a better `readUntilDelimitor`
///       implementation. Replacement code bellow:
///```
///buf_in_stream.inStream().readUntilDelimiterArrayList(buffer, '\n', std.math.maxInt(usize)) catch |err| switch (err) {
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
pub fn readLine(buf_in_stream: var) !?[]u8 {
    const fifo = &buf_in_stream.fifo;

    while (true) {
        const buf = fifo.readableSliceMut(0);
        if (mem.indexOfScalar(u8, buf, '\n')) |index| {
            defer fifo.head += index + 1;
            defer fifo.count -= index + 1;
            return buf[0..index];
        }

        mem.copyBackwards(u8, fifo.buf[0..], buf);
        fifo.head = 0;

        const num = try buf_in_stream.unbuffered_in_stream.readAll(fifo.writableSlice(0));
        fifo.count += num;

        if (num == 0) {
            if (fifo.count != 0) {
                defer fifo.count = 0;
                return fifo.readableSliceMut(0);
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
    var bis = std.io.bufferedInStream(fbs.inStream());

    for (lines) |expected_line| {
        const actual_line = (try readLine(&bis)).?;
        testing.expectEqualSlices(u8, expected_line, actual_line);
    }
    testing.expectEqual(@as(?[]u8, null), try readLine(&bis));
}
