const std = @import("std");

const ascii = std.ascii;
const debug = std.debug;
const fmt = std.fmt;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const testing = std.testing;

pub const default_escapes = blk: {
    @setEvalBranchQuota(1000000);
    var res: []const Escape = &[_]Escape{};
    var i: u8 = 0;
    while (i <= math.maxInt(u7)) : (i += 1) {
        switch (i) {
            '\\' => res = res ++ [_]Escape{.{ .escaped = "\\\\", .unescaped = "\\" }},
            '\n' => res = res ++ [_]Escape{.{ .escaped = "\\n", .unescaped = "\n" }},
            '\r' => res = res ++ [_]Escape{.{ .escaped = "\\r", .unescaped = "\r" }},
            '\t' => res = res ++ [_]Escape{.{ .escaped = "\\t", .unescaped = "\t" }},
            else => {
                if (ascii.isPrint(i))
                    continue;

                const escaped = fmt.comptimePrint("\\x{x:02}", .{i});
                res = res ++ [_]Escape{.{ .escaped = escaped, .unescaped = &[_]u8{i} }};
            },
        }
    }
    break :blk res;
};

pub const default = generate(default_escapes);

pub const Escape = struct {
    escaped: []const u8,
    unescaped: []const u8,
};

pub fn generate(comptime escapes: []const Escape) type {
    const find_replace_escaped = blk: {
        var res: []const Replacement = &[_]Replacement{};
        for (escapes) |esc|
            res = res ++ [_]Replacement{.{ .find = esc.escaped, .replace = esc.unescaped }};
        break :blk res;
    };

    const find_replace_unescaped = blk: {
        var res: []const Replacement = &[_]Replacement{};
        for (escapes) |esc|
            res = res ++ [_]Replacement{.{ .find = esc.unescaped, .replace = esc.escaped }};
        break :blk res;
    };

    return struct {
        pub fn EscapingWriter(comptime ChildWriter: type) type {
            return ReplacingWriter(find_replace_unescaped, ChildWriter);
        }

        pub fn escapingWriter(child_writer: anytype) EscapingWriter(@TypeOf(child_writer)) {
            return .{ .child_writer = child_writer };
        }

        pub fn UnescapingWriter(comptime ChildWriter: type) type {
            return ReplacingWriter(find_replace_escaped, ChildWriter);
        }

        pub fn unescapingWriter(child_writer: anytype) UnescapingWriter(@TypeOf(child_writer)) {
            return .{ .child_writer = child_writer };
        }

        pub fn EscapingReader(comptime ChildReader: type) type {
            return ReplacingReader(find_replace_unescaped, ChildReader);
        }

        pub fn escapingReader(child_reader: anytype) EscapingReader(@TypeOf(child_reader)) {
            return .{ .child_reader = child_reader };
        }

        pub fn UnescapingReader(comptime ChildReader: type) type {
            return ReplacingReader(find_replace_escaped, ChildReader);
        }

        pub fn unescapingReader(child_reader: anytype) EscapingReader(@TypeOf(child_reader)) {
            return .{ .child_reader = child_reader };
        }

        pub fn escapeWrite(writer: anytype, str: []const u8) !void {
            var esc = escapingWriter(writer);
            try esc.writer().writeAll(str);
            try esc.finish();
        }

        pub fn escapeAlloc(allocator: *mem.Allocator, str: []const u8) ![]u8 {
            var res = std.ArrayList(u8).init(allocator);
            try escapeWrite(res.writer(), str);
            return res.toOwnedSlice();
        }

        pub fn unescapeWrite(writer: anytype, str: []const u8) !void {
            var esc = unescapingWriter(writer);
            try esc.writer().writeAll(str);
            try esc.finish();
        }

        pub fn unescapeAlloc(allocator: *mem.Allocator, str: []const u8) ![]u8 {
            var res = std.ArrayList(u8).init(allocator);
            try unescapeWrite(res.writer(), str);
            return res.toOwnedSlice();
        }
    };
}

pub const Replacement = struct {
    find: []const u8,
    replace: []const u8,

    fn findLessThan(ctx: void, a: Replacement, b: Replacement) bool {
        return mem.lessThan(u8, a.find, b.find);
    }
};

fn startsWith(comptime replacements: []const Replacement, buf: []const u8) ?usize {
    inline for (replacements) |rep, i| {
        if (mem.startsWith(u8, buf, rep.find))
            return i;
    }
    return null;
}

const State = struct {
    index: usize = 0,
    start: usize = 0,
    end: usize,
};

/// replacements must be sorted.
fn transion(comptime replacements: []const Replacement, byte: u8, state: State) ?State {
    const start = for (replacements[state.start..state.end]) |rep, i| {
        const rest = rep.find[state.index..];
        if (rest.len != 0 and rest[0] == byte)
            break state.start + i;
    } else return null;

    const end = for (replacements[start..state.end]) |rep, i| {
        const rest = rep.find[state.index..];
        if (rest.len == 0 or rest[0] != byte)
            break start + i;
    } else state.end;

    return State{
        .start = start,
        .end = end,
        .index = state.index + 1,
    };
}

test "transion" {
    const replacements = [_]Replacement{
        .{ .find = "bar", .replace = "baz" },
        .{ .find = "baz", .replace = "stuff" },
        .{ .find = "foo", .replace = "bar" },
    };
    testing.expect(isSorted(&replacements));
    testing.expectEqual(@as(?State, State{ .index = 1, .start = 2, .end = 3 }), transion(&replacements, 'f', .{ .end = 3 }));
    testing.expectEqual(@as(?State, State{ .index = 1, .start = 0, .end = 2 }), transion(&replacements, 'b', .{ .end = 3 }));
    testing.expectEqual(@as(?State, State{ .index = 2, .start = 0, .end = 2 }), transion(&replacements, 'a', .{ .index = 1, .start = 0, .end = 2 }));
    testing.expectEqual(@as(?State, State{ .index = 3, .start = 1, .end = 2 }), transion(&replacements, 'z', .{ .index = 2, .start = 0, .end = 2 }));
}

pub fn ReplacingWriter(comptime replacements: []const Replacement, comptime ChildWriter: type) type {
    @setEvalBranchQuota(1000000);
    var replacements_sorted = replacements[0..replacements.len].*;
    std.sort.sort(Replacement, &replacements_sorted, {}, Replacement.findLessThan);

    return struct {
        child_writer: ChildWriter,
        state: State = .{ .end = replacements.len },

        pub const Error = ChildWriter.Error;
        pub const Writer = io.Writer(*@This(), Error, write);

        pub fn writer(self: *@This()) Writer {
            return .{ .context = self };
        }

        pub fn write(self: *@This(), bytes: []const u8) Error!usize {
            var i: usize = 0;
            while (i < bytes.len) {
                if (transion(&replacements_sorted, bytes[i], self.state)) |new| {
                    self.state = new;
                    i += 1;
                } else if (self.state.index == 0) {
                    try self.child_writer.writeByte(bytes[i]);
                    self.state = .{ .end = replacements_sorted.len };
                    i += 1;
                } else {
                    try self.finish();
                }
            }

            return bytes.len;
        }

        pub fn finish(self: *@This()) Error!void {
            defer self.state = .{ .end = replacements_sorted.len };
            if (self.state.index == 0)
                return;

            const curr = replacements_sorted[self.state.start];
            if (curr.find.len == self.state.index) {
                try self.child_writer.writeAll(curr.replace);
            } else {
                try self.child_writer.writeAll(curr.find[0..self.state.index]);
            }
        }
    };
}

pub fn replacingWriter(
    comptime replacements: []const Replacement,
    child_writer: anytype,
) ReplacingWriter(replacements, @TypeOf(child_writer)) {
    return .{ .child_writer = child_writer };
}

pub fn ReplacingReader(comptime replacements: []const Replacement, comptime ChildReader: type) type {
    return struct {
        const longest_find = blk: {
            var res: usize = 0;
            for (replacements) |r|
                res = math.max(r.find.len, res);
            break :blk res;
        };

        child_reader: ChildReader,
        buf: [mem.page_size]u8 = undefined,
        start: usize = 0,
        end: usize = 0,
        leftovers: []const u8 = "",

        pub const Error = ChildReader.Error;
        pub const Reader = io.Reader(*@This(), Error, read);

        pub fn reader(self: *@This()) Reader {
            return .{ .context = self };
        }

        pub fn read(self: *@This(), dest: []u8) Error!usize {
            const rest = self.buf[self.start..self.end];
            if (rest.len < longest_find) {
                mem.copy(u8, &self.buf, rest);
                self.end -= self.start;
                self.start = 0;
                self.end += try self.child_reader.read(self.buf[self.start..]);
            }

            var fbs = io.fixedBufferStream(dest);

            // We might have leftovers from a replacement that didn't
            // quite finish. We need to make sure that gets written now.
            const l = fbs.write(self.leftovers) catch 0;
            self.leftovers = self.leftovers[l..];
            if (self.leftovers.len != 0)
                return l;

            var i: usize = self.start;
            while (i < self.end) {
                if (startsWith(replacements, self.buf[i..self.end])) |rep| {
                    self.start += fbs.write(self.buf[self.start..i]) catch 0;
                    if (self.start != i)
                        break;

                    const replace = replacements[rep].replace;
                    const res = fbs.write(replace) catch 0;
                    if (replace.len != res) {
                        self.leftovers = replace[res..];
                        break;
                    }

                    i += replacements[rep].find.len;
                    self.start = i;
                } else {
                    i += 1;
                }
            }

            self.start += fbs.write(self.buf[self.start..i]) catch 0;
            return fbs.getWritten().len;
        }
    };
}

pub fn replacingReader(
    comptime replacements: []const Replacement,
    child_reader: anytype,
) ReplacingReader(replacements, @TypeOf(child_reader)) {
    return .{ .child_reader = child_reader };
}

fn testReplacingStreams(comptime replacements: []const Replacement, input: []const u8, expect: []const u8) void {
    var buf: [mem.page_size]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    var replacing_writer = replacingWriter(replacements, fbs.writer());
    replacing_writer.writer().writeAll(input) catch unreachable;
    replacing_writer.finish() catch unreachable;
    testing.expectEqualStrings(expect, fbs.getWritten());

    var fbs2 = io.fixedBufferStream(input);
    var replacing_reader = replacingReader(replacements, fbs2.reader());
    const res = replacing_reader.reader().readAll(&buf) catch unreachable;
    testing.expectEqualStrings(expect, buf[0..res]);
}

test "replacingWriter" {
    const replacements = [_]Replacement{
        .{ .find = "baz", .replace = "stuff" },
        .{ .find = "foo", .replace = "bar" },
        .{ .find = "bar", .replace = "baz" },
    };

    testReplacingStreams(&replacements, "abcd", "abcd");
    testReplacingStreams(&replacements, "abfoocd", "abbarcd");
    testReplacingStreams(&replacements, "abbarcd", "abbazcd");
    testReplacingStreams(&replacements, "abbazcd", "abstuffcd");
    testReplacingStreams(&replacements, "foobarbaz", "barbazstuff");
    testReplacingStreams(&replacements, "bazbarfoo", "stuffbazbar");
    testReplacingStreams(&replacements, "baz bar foo", "stuff baz bar");
}

pub fn splitEscaped(buffer: []const u8, esc: []const u8, delimiter: []const u8) EscapedSplitter {
    std.debug.assert(delimiter.len != 0);
    return EscapedSplitter{
        .index = 0,
        .buffer = buffer,
        .escape = esc,
        .delimiter = delimiter,
    };
}

pub const EscapedSplitter = struct {
    buffer: []const u8,
    index: ?usize,
    escape: []const u8,
    delimiter: []const u8,

    /// Returns a slice of the next field, or null if splitting is complete.
    pub fn next(self: *EscapedSplitter) ?[]const u8 {
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
    pub fn rest(self: EscapedSplitter) []const u8 {
        const end = self.buffer.len;
        const start = self.index orelse end;
        return self.buffer[start..end];
    }
};

test "splitEscaped" {
    var it = splitEscaped("abc|def||ghi\\|jkl", "\\", "|");
    testing.expectEqualStrings("abc", it.next().?);
    testing.expectEqualStrings("def", it.next().?);
    testing.expectEqualStrings("", it.next().?);
    testing.expectEqualStrings("ghi\\|jkl", it.next().?);
    testing.expect(it.next() == null);

    it = splitEscaped("", "\\", "|");
    testing.expectEqualStrings("", it.next().?);
    testing.expect(it.next() == null);

    it = splitEscaped("|", "\\", "|");
    testing.expectEqualStrings("", it.next().?);
    testing.expectEqualStrings("", it.next().?);
    testing.expect(it.next() == null);

    it = splitEscaped("hello", "\\", " ");
    testing.expectEqualStrings(it.next().?, "hello");
    testing.expect(it.next() == null);

    it = splitEscaped("\\,\\,,", "\\", ",");
    testing.expectEqualStrings(it.next().?, "\\,\\,");
    testing.expectEqualStrings(it.next().?, "");
    testing.expect(it.next() == null);
}

test "splitEscaped (multibyte)" {
    var it = splitEscaped("a, b ,, c, d, e\\\\, f", "\\\\", ", ");
    testing.expectEqualStrings(it.next().?, "a");
    testing.expectEqualStrings(it.next().?, "b ,");
    testing.expectEqualStrings(it.next().?, "c");
    testing.expectEqualStrings(it.next().?, "d");
    testing.expectEqualStrings(it.next().?, "e\\\\, f");
    testing.expect(it.next() == null);
}
