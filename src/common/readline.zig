const std = @import("std");

const mem = std.mem;
const testing = std.testing;

pub fn readLine(buf_in_stream: var, buffer: *std.Buffer) !?[]u8 {
    const start = buffer.len();

    while (true) {
        const buf = buf_in_stream.buffer[buf_in_stream.start_index..buf_in_stream.end_index];
        if (mem.indexOfScalar(u8, buf, '\n')) |index| {
            const line = buf[0..index];
            try buffer.append(line);
            buf_in_stream.start_index += line.len + 1;

            return buffer.toSlice()[start..];
        }

        try buffer.append(buf);
        const num = try buf_in_stream.unbuffered_in_stream.readFull(&buf_in_stream.buffer);
        buf_in_stream.start_index = 0;
        buf_in_stream.end_index = num;
        if (num == 0) {
            if (start != buffer.len())
                return buffer.toSlice()[start..];

            return null;
        }
    }
}

test "readLine" {
    try testReadLine(
        \\a
        \\b
        \\c
    ,
        [_][]const u8{
            "a",
            "b",
            "c",
        },
    );
}

fn testReadLine(str: []const u8, lines: []const []const u8) !void {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const Error = error{Hack};
    var sis = std.io.SliceInStream.init(str);
    var bis = std.io.BufferedInStream(Error).init(
        @ptrCast(*std.io.InStream(Error), &sis.stream),
    );
    var buffer = try std.Buffer.initSize(&fba.allocator, 0);
    defer buffer.deinit();

    for (lines) |expected_line| {
        const actual_line = (try readLine(&bis, &buffer)).?;
        testing.expectEqualSlices(u8, expected_line, actual_line);
    }
    testing.expectEqual((?[]u8)(null), try readLine(&bis, &buffer));
}
