const std = @import("std");

const mem = std.mem;

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
