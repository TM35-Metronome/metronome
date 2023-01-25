const std = @import("std");

const fmt = std.fmt;
const mem = std.mem;
const unicode = std.unicode;

/// Improved Utf8View which also keeps track of the length in codepoints
pub const Utf8View = struct {
    bytes: []const u8,
    len: usize,

    pub fn init(str: []const u8) !Utf8View {
        return Utf8View{
            .bytes = str,
            .len = try utf8Len(str),
        };
    }

    pub fn slice(view: Utf8View, start: usize, end: usize) Utf8View {
        var len: usize = 0;
        var i: usize = 0;
        var it = view.iterator();
        while (i < start) : (i += 1)
            len += @boolToInt(it.nextCodepointSlice() != null);

        const start_i = it.i;
        while (i < end) : (i += 1)
            len += @boolToInt(it.nextCodepointSlice() != null);

        return .{
            .bytes = view.bytes[start_i..it.i],
            .len = len,
        };
    }

    pub fn iterator(view: Utf8View) unicode.Utf8Iterator {
        return unicode.Utf8View.initUnchecked(view.bytes).iterator();
    }

    pub fn format(
        self: @This(),
        comptime fmt_str: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try fmt.formatType(
            self.bytes,
            fmt_str,
            options,
            writer,
            fmt.default_max_depth,
        );
    }
};

/// Given a string of words, this function will split the string into lines where
/// a maximum of `max_line_len` characters can occur on each line.
pub fn splitIntoLines(allocator: mem.Allocator, max_line_len: usize, string: Utf8View) !Utf8View {
    var res = std.ArrayList(u8).init(allocator);
    errdefer res.deinit();

    var curr_line_len: usize = 0;
    var it = mem.tokenize(u8, string.bytes, " \n");
    while (it.next()) |word_bytes| {
        const word = Utf8View.init(word_bytes) catch unreachable;
        const next_line_len = word.len + curr_line_len + (1 * @boolToInt(curr_line_len != 0));
        if (next_line_len > max_line_len) {
            try res.appendSlice("\n");
            try res.appendSlice(word_bytes);
            curr_line_len = word.len;
        } else {
            if (curr_line_len != 0)
                try res.appendSlice(" ");
            try res.appendSlice(word_bytes);
            curr_line_len = next_line_len;
        }
    }

    return Utf8View.init(try res.toOwnedSlice()) catch unreachable;
}

fn utf8Len(s: []const u8) !usize {
    var res: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (res += 1) {
        const cp_len = try unicode.utf8ByteSequenceLength(s[i]);
        if (i + cp_len > s.len) {
            return error.InvalidUtf8;
        }

        if (unicode.utf8Decode(s[i .. i + cp_len])) |_| {} else |_| {
            return error.InvalidUtf8;
        }
        i += cp_len;
    }
    return res;
}
