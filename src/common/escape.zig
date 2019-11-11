const std = @import("std");

const debug = std.debug;
const io = std.io;
const mem = std.mem;
const os = std.os;
const testing = std.testing;

const chars = blk: {
    var res: [255]u8 = undefined;
    for (res) |*char, i|
        char.* = @intCast(u8, i);

    break :blk res;
};

pub const default_escapes = blk: {
    var res: [255][]const u8 = undefined;
    for (res) |*slice, i|
        slice.* = (*const [1]u8)(&chars[i]);

    break :blk res;
};

pub fn writeEscaped(out_stream: var, buf: []const u8, escapes: [255][]const u8) !void {
    for (buf) |char| {
        try out_stream.write(escapes[char]);
    }
}

test "writeEscaped" {
    var comma_escape = default_escapes;
    comma_escape[','] = "\\,";

    testWriteEscaped(comma_escape, "abc", "abc");
    testWriteEscaped(comma_escape, "a,bc", "a\\,bc");
    testWriteEscaped(comma_escape, "a,b,c", "a\\,b\\,c");
    testWriteEscaped(comma_escape, "a,,b,,c", "a\\,\\,b\\,\\,c");
    testWriteEscaped(comma_escape, "a\\,,b,,c", "a\\\\,\\,b\\,\\,c");
}

fn testWriteEscaped(escapes: [255][]const u8, str: []const u8, expect: []const u8) void {
    var buf: [1024]u8 = undefined;
    var sos = io.SliceOutStream.init(&buf);
    writeEscaped(&sos.stream, str, escapes) catch unreachable;
    testing.expectEqualSlices(u8, expect, sos.getWritten());
}

pub fn writeUnEscaped(out_stream: var, buf: []const u8, escapes: [255][]const u8) !void {
    var index: usize = 0;
    outer: while (index < buf.len) {
        for (escapes) |escape, c| {
            if (mem.startsWith(u8, buf[index..], escape)) {
                index += escape.len;
                try out_stream.write((*const [1]u8)(&@intCast(u8, c)));
                continue :outer;
            }
        }

        try out_stream.write(buf[index .. index + 1]);
        index += 1;
    }
}

test "writeUnEscaped" {
    var comma_escape = default_escapes;
    comma_escape[','] = "\\,";

    testWriteUnEscaped(comma_escape, "abc", "abc");
    testWriteUnEscaped(comma_escape, "a\\,bc", "a,bc");
    testWriteUnEscaped(comma_escape, "a\\,b\\,c", "a,b,c");
    testWriteUnEscaped(comma_escape, "a\\,,b\\,\\,c", "a,,b,,c");
}

fn testWriteUnEscaped(escapes: [255][]const u8, str: []const u8, expect: []const u8) void {
    var buf: [1024]u8 = undefined;
    var sos = io.SliceOutStream.init(&buf);
    writeUnEscaped(&sos.stream, str, escapes) catch unreachable;
    testing.expectEqualSlices(u8, expect, sos.getWritten());
}

pub fn separateEscaped(buffer: []const u8, escape: []const u8, delimiter: []const u8) EscapedSeparator {
    std.debug.assert(delimiter.len != 0);
    return EscapedSeparator{
        .index = 0,
        .buffer = buffer,
        .escape = escape,
        .delimiter = delimiter,
    };
}

pub const EscapedSeparator = struct {
    buffer: []const u8,
    index: ?usize,
    escape: []const u8,
    delimiter: []const u8,

    /// Returns a slice of the next field, or null if splitting is complete.
    pub fn next(self: *EscapedSeparator) ?[]const u8 {
        const start = self.index orelse return null;
        var start2 = start;

        const end = blk: {
            while (true) {
                if (mem.indexOfPos(u8, self.buffer, start2, self.delimiter)) |delim_start| {
                    if (delim_start >= self.escape.len and
                        mem.eql(u8, self.buffer[delim_start - self.escape.len .. delim_start], self.escape))
                    {
                        start2 = delim_start + self.escape.len;
                        continue;
                    }

                    self.index = delim_start + self.delimiter.len;
                    break :blk delim_start;
                } else {
                    self.index = null;
                    break :blk self.buffer.len;
                }
            }

            unreachable;
        };
        return self.buffer[start..end];
    }

    /// Returns a slice of the remaining bytes. Does not affect iterator state.
    pub fn rest(self: EscapedSeparator) []const u8 {
        const end = self.buffer.len;
        const start = self.index orelse end;
        return self.buffer[start..end];
    }
};

test "separateEscaped" {
    var it = separateEscaped("abc|def||ghi\\|jkl", "\\", "|");
    testing.expectEqualSlices(u8, "abc", it.next().?);
    testing.expectEqualSlices(u8, "def", it.next().?);
    testing.expectEqualSlices(u8, "", it.next().?);
    testing.expectEqualSlices(u8, "ghi\\|jkl", it.next().?);
    testing.expect(it.next() == null);

    it = separateEscaped("", "\\", "|");
    testing.expectEqualSlices(u8, "", it.next().?);
    testing.expect(it.next() == null);

    it = separateEscaped("|", "\\", "|");
    testing.expectEqualSlices(u8, "", it.next().?);
    testing.expectEqualSlices(u8, "", it.next().?);
    testing.expect(it.next() == null);

    it = separateEscaped("hello", "\\", " ");
    testing.expectEqualSlices(u8, it.next().?, "hello");
    testing.expect(it.next() == null);

    it = separateEscaped("\\,\\,,", "\\", ",");
    testing.expectEqualSlices(u8, it.next().?, "\\,\\,");
    testing.expectEqualSlices(u8, it.next().?, "");
    testing.expect(it.next() == null);
}

test "separateEscaped (multibyte)" {
    var it = separateEscaped("a, b ,, c, d, e\\\\, f", "\\\\", ", ");
    testing.expectEqualSlices(u8, it.next().?, "a");
    testing.expectEqualSlices(u8, it.next().?, "b ,");
    testing.expectEqualSlices(u8, it.next().?, "c");
    testing.expectEqualSlices(u8, it.next().?, "d");
    testing.expectEqualSlices(u8, it.next().?, "e\\\\, f");
    testing.expect(it.next() == null);
}
