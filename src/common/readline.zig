const std = @import("std");

const mem = std.mem;
const testing = std.testing;

/// This is a special case readLine implementation for BufferedInStreams.
/// This function looks directly into the buffer that BufferedInStream manages
/// to find lines. I'm assuming this is a lot faster as this is directly walking
/// over a buffer instead of indirectly calling readByte one at a time.
///
/// TODO: Ever since zig 0.6.0, the InStream api became static (aka functions
///       are not called using dynamic dispatch). Therefor, readUntilDelimitorArrayList
///       might be a lot faster. Do benchmarks to check that this function is
///       still needed.
pub fn readLine(buf_in_stream: var, buffer: *std.ArrayList(u8)) !?[]u8 {
    const start = buffer.items.len;

    while (true) {
        const buf = buf_in_stream.fifo.readableSlice(0);
        if (mem.indexOfScalar(u8, buf, '\n')) |index| {
            const line = buf[0..index];
            try buffer.appendSlice(line);
            buf_in_stream.fifo.discard(line.len + 1);

            return buffer.items[start..];
        }

        try buffer.appendSlice(buf);
        const num = try buf_in_stream.unbuffered_in_stream.readAll(&buf_in_stream.fifo.buf);
        buf_in_stream.fifo.head = 0;
        buf_in_stream.fifo.count = num;
        if (num == 0) {
            if (start != buffer.items.len)
                return buffer.items[start..];

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
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    for (lines) |expected_line| {
        const actual_line = (try readLine(&bis, &buffer)).?;
        testing.expectEqualSlices(u8, expected_line, actual_line);
    }
    testing.expectEqual(@as(?[]u8, null), try readLine(&bis, &buffer));
}
