pub const default_escapes = blk: {
    @setEvalBranchQuota(1000000);
    var res: []const Escape = &[_]Escape{};
    var i: u8 = 0;
    while (i <= std.math.maxInt(u7)) : (i += 1) {
        switch (i) {
            '\\' => res = res ++ [_]Escape{.{ .escaped = "\\\\", .unescaped = "\\" }},
            '\n' => res = res ++ [_]Escape{.{ .escaped = "\\n", .unescaped = "\n" }},
            '\r' => res = res ++ [_]Escape{.{ .escaped = "\\r", .unescaped = "\r" }},
            '\t' => res = res ++ [_]Escape{.{ .escaped = "\\t", .unescaped = "\t" }},
            else => {
                if (std.ascii.isPrint(i))
                    continue;

                const escaped = std.fmt.comptimePrint("\\x{x:02}", .{i});
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

        pub fn unescapingReader(child_reader: anytype) UnescapingReader(@TypeOf(child_reader)) {
            return .{ .child_reader = child_reader };
        }

        pub fn escapeWrite(writer: anytype, str: []const u8) !void {
            var esc = escapingWriter(writer);
            try esc.writer().writeAll(str);
            try esc.finish();
        }

        pub fn escapePrint(writer: anytype, comptime format: []const u8, args: anytype) !void {
            var esc = escapingWriter(writer);
            try esc.writer().print(format, args);
            try esc.finish();
        }

        pub fn escapeAlloc(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
            var res = std.ArrayList(u8).init(allocator);
            try escapeWrite(res.writer(), str);
            return res.toOwnedSlice();
        }

        pub fn escapeFmt(value: anytype) Format(@TypeOf(value), .escape) {
            return .{ .value = value };
        }

        pub fn unescapeWrite(writer: anytype, str: []const u8) !void {
            var esc = unescapingWriter(writer);
            try esc.writer().writeAll(str);
            try esc.finish();
        }

        pub fn unescapePrint(writer: anytype, comptime format: []const u8, args: anytype) !void {
            var esc = unescapingWriter(writer);
            try esc.writer().print(format, args);
            try esc.finish();
        }

        pub fn unescapeAlloc(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
            var res = std.ArrayList(u8).init(allocator);
            try unescapeWrite(res.writer(), str);
            return res.toOwnedSlice();
        }

        pub fn unescapeFmt(value: anytype) Format(@TypeOf(value), .unescape) {
            return .{ .value = value };
        }

        pub fn Format(comptime T: type, comptime kind: enum { escape, unescape }) type {
            return struct {
                value: T,

                pub fn format(
                    self: @This(),
                    comptime fmt_str: []const u8,
                    options: std.std.fmt.FormatOptions,
                    writer: anytype,
                ) @TypeOf(writer).Error!void {
                    var esc = switch (kind) {
                        .escape => escapingWriter(writer),
                        .unescape => unescapingWriter(writer),
                    };
                    try std.fmt.formatType(
                        self.value,
                        fmt_str,
                        options,
                        esc.writer(),
                        std.fmt.default_max_depth,
                    );
                    try esc.finish();
                }
            };
        }
    };
}

pub const Replacement = struct {
    find: []const u8,
    replace: []const u8,

    fn lessThan(_: u8, a: Replacement, b: Replacement) bool {
        return std.mem.lessThan(u8, a.find, b.find);
    }
};

fn startsWith(comptime replacements: []const Replacement, buf: []const u8) ?usize {
    inline for (replacements, 0..) |rep, i| {
        if (std.mem.startsWith(u8, buf, rep.find))
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
fn transion(replacements: []const Replacement, byte: u8, state: State) ?State {
    const start = for (replacements[state.start..state.end], state.start..) |rep, i| {
        const rest = rep.find[state.index..];
        if (rest.len != 0 and rest[0] == byte)
            break i;
    } else return null;

    const end = for (replacements[start..state.end], start..) |rep, i| {
        const rest = rep.find[state.index..];
        if (rest.len == 0 or rest[0] != byte)
            break i;
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
    try std.testing.expectEqual(@as(?State, State{ .index = 1, .start = 2, .end = 3 }), transion(&replacements, 'f', .{ .end = 3 }));
    try std.testing.expectEqual(@as(?State, State{ .index = 1, .start = 0, .end = 2 }), transion(&replacements, 'b', .{ .end = 3 }));
    try std.testing.expectEqual(@as(?State, State{ .index = 2, .start = 0, .end = 2 }), transion(&replacements, 'a', .{ .index = 1, .start = 0, .end = 2 }));
    try std.testing.expectEqual(@as(?State, State{ .index = 3, .start = 1, .end = 2 }), transion(&replacements, 'z', .{ .index = 2, .start = 0, .end = 2 }));
}

pub fn ReplacingWriter(comptime replacements: []const Replacement, comptime ChildWriter: type) type {
    @setEvalBranchQuota(1000000);
    comptime var replacements_sorted_var = replacements[0..replacements.len].*;
    std.mem.sort(Replacement, &replacements_sorted_var, @as(u8, 0), Replacement.lessThan);

    const replacements_sorted = replacements_sorted_var;
    return struct {
        child_writer: ChildWriter,
        state: State = .{ .end = replacements.len },

        pub const Error = switch (@typeInfo(ChildWriter)) {
            .pointer => |info| info.child.Error,
            else => ChildWriter.Error,
        };
        pub const Writer = std.io.Writer(*@This(), Error, write);

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
                res = @max(r.find.len, res);
            break :blk res;
        };

        child_reader: ChildReader,
        buf: [std.mem.page_size]u8 = undefined,
        start: usize = 0,
        end: usize = 0,
        leftovers: []const u8 = "",

        pub const Error = ChildReader.Error;
        pub const Reader = std.io.Reader(*@This(), Error, read);

        pub fn reader(self: *@This()) Reader {
            return .{ .context = self };
        }

        pub fn read(self: *@This(), dest: []u8) Error!usize {
            const rest = self.buf[self.start..self.end];
            if (rest.len < longest_find) {
                @memcpy(self.buf[0..rest.len], rest);
                self.end -= self.start;
                self.start = 0;
                self.end += try self.child_reader.read(self.buf[self.start..]);
            }

            var fbs = std.io.fixedBufferStream(dest);

            // We might have leftovers from a replacement that didn't
            // quite finish. We need to make sure that gets written now.
            const l = fbs.write(self.leftovers) catch return 0;
            self.leftovers = self.leftovers[l..];
            if (self.leftovers.len != 0)
                return l;

            var i: usize = self.start;
            while (i < self.end) {
                if (startsWith(replacements, self.buf[i..self.end])) |rep| {
                    self.start += fbs.write(self.buf[self.start..i]) catch 0;
                    if (self.start != i)
                        break;

                    i += replacements[rep].find.len;
                    self.start = i;

                    const replace = replacements[rep].replace;
                    const res = fbs.write(replace) catch 0;
                    if (replace.len != res) {
                        self.leftovers = replace[res..];
                        break;
                    }
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

fn testReplacingStreams(comptime replacements: []const Replacement, input: []const u8, expect: []const u8) !void {
    var buf: [std.mem.page_size]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var replacing_writer = replacingWriter(replacements, fbs.writer());
    replacing_writer.writer().writeAll(input) catch unreachable;
    replacing_writer.finish() catch unreachable;
    try std.testing.expectEqualStrings(expect, fbs.getWritten());

    var fbs2 = std.io.fixedBufferStream(input);
    var replacing_reader = replacingReader(replacements, fbs2.reader());
    const res = replacing_reader.reader().readAll(&buf) catch unreachable;
    try std.testing.expectEqualStrings(expect, buf[0..res]);
}

test "replacingWriter" {
    const replacements = [_]Replacement{
        .{ .find = "baz", .replace = "stuff" },
        .{ .find = "foo", .replace = "bar" },
        .{ .find = "bar", .replace = "baz" },
    };

    try testReplacingStreams(&replacements, "abcd", "abcd");
    try testReplacingStreams(&replacements, "abfoocd", "abbarcd");
    try testReplacingStreams(&replacements, "abbarcd", "abbazcd");
    try testReplacingStreams(&replacements, "abbazcd", "abstuffcd");
    try testReplacingStreams(&replacements, "foobarbaz", "barbazstuff");
    try testReplacingStreams(&replacements, "bazbarfoo", "stuffbazbar");
    try testReplacingStreams(&replacements, "baz bar foo", "stuff baz bar");
}

const std = @import("std");
