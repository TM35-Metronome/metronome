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
        testing.expectEqualStrings(expected_line, actual_line);
        testing.expectEqual(@as(u8, '\n'), actual_line[actual_line.len]);
    }
    testing.expectEqual(@as(?[:'\n']const u8, null), try readLine(fbs.reader(), &fifo));
}

/// For windows, we don't want to use `BufferedWritev`, as the implementaion of
/// `std.fs.File.writev` currently just writes the first `iovec` and returns.
pub const BufferedWriter = switch (std.builtin.os.tag) {
    .linux => BufferedWritev,
    else => std.io.BufferedWriter(bufsize, fs.File.Writer),
};

pub fn bufferedWriter(writer: fs.File.Writer) BufferedWriter {
    switch (std.builtin.os.tag) {
        .linux => return .{ .file = writer.context },
        else => return .{ .unbuffered_writer = writer },
    }
}

/// A stream that works much like `std.io.BufferedWriter`. Bytes written to this stream
/// is buffered and can be flushed at any type with the `flush` function.
/// The difference between this and `std.io.BufferedWriter` is that bytes are flushed
/// using `writev`. This allows `BufferedWritev` to expose the function
/// `writeAssumeValidUntilFlush`, which takes a slice that has to live until the
/// next call to `flush`. This can make `BufferedWritev` more efficient in certain
/// cases, where most of the slices you write to it have long lifetimes.
/// `BufferedWritev` also exposes it's own implementation of `std.io.Writer` which
/// overrides the `print` function with it's own. This print function has the exact
/// same behavior and api as `Writer.print`, but it will call `writeAssumeValidUntilFlush`
/// for all static parts of the format string.
pub const BufferedWritev = struct {
    iovecs_end: usize = 0,
    iovecs: [1024]os.iovec_const = undefined,
    buf_end: usize = 0,
    buf: [1024 * 4]u8 = undefined,
    bytes_buffered: usize = 0,
    file: fs.File,

    pub const Error = fs.File.WriteError;
    pub const Writer = BufferedWritevWriter;

    pub fn flush(bw: *BufferedWritev) Error!void {
        try bw.file.writevAll(bw.iovecs[0..bw.iovecs_end]);
        bw.buf_end = 0;
        bw.iovecs_end = 0;
        bw.bytes_buffered = 0;
    }

    pub fn writer(bw: *BufferedWritev) Writer {
        return .{ .context = bw };
    }

    pub fn write(bw: *BufferedWritev, bytes: []const u8) Error!usize {
        const free_space = bw.buf.len - bw.buf_end;
        const bytes_to_write = math.min(bytes.len, free_space);
        const slice_to_write = bw.buf[bw.buf_end..][0..bytes_to_write];
        mem.copy(u8, slice_to_write, bytes[0..bytes_to_write]);
        bw.buf_end += bytes_to_write;

        // Once we have written `bytes` to `bw.buf`, then we know that `slice_to_write`
        // lives until the next `flush`, so calling this is safe.
        try bw.writeIovec(slice_to_write);

        if (bw.buf_end == bw.buf.len)
            try bw.flush();

        return slice_to_write.len;
    }

    pub fn writeAssumeValidUntilFlush(bw: *BufferedWritev, bytes: []const u8) Error!void {
        // If the buffer is too small, just write it normally. This can, in some cases,
        // allow the writer to merge multiple smaller continues iovecs.
        if (bytes.len < 16) {
            try bw.writer().writeAll(bytes);
        } else {
            try bw.writeIovec(bytes);
        }
    }

    fn writeIovec(bw: *BufferedWritev, bytes: []const u8) Error!void {
        if (bw.iovecs_end != 0) {
            // If buffer we get in is right after the last buffer in memory,
            // we can just extend the last buffer instead of writing a new one.
            const last = &bw.iovecs[bw.iovecs_end - 1];
            if (last.iov_base + last.iov_len == bytes.ptr) {
                last.iov_len += bytes.len;
                bw.bytes_buffered += bytes.len;
                return;
            }
        }

        bw.iovecs[bw.iovecs_end] = .{
            .iov_base = bytes.ptr,
            .iov_len = bytes.len,
        };
        bw.bytes_buffered += bytes.len;
        bw.iovecs_end += 1;

        if (bw.iovecs_end == bw.iovecs.len)
            try bw.flush();
    }
};

/// The `Writer` for `BufferedWritev`. This is basically a copy paste from `std.io.Writer`,
/// except the `print` function, which will call `writeAssumeValidUntilFlush` on the static
/// parts of the format string.
/// See `std.io.Writer` for documentation for each of the functions.
const BufferedWritevWriter = struct {
    context: *BufferedWritev,

    pub const Error = BufferedWritev.Error;

    pub fn write(bw: BufferedWritevWriter, bytes: []const u8) Error!usize {
        return bw.context.write(bytes);
    }

    pub fn writeAll(bw: BufferedWritevWriter, bytes: []const u8) Error!void {
        var index: usize = 0;
        while (index != bytes.len)
            index += try bw.context.write(bytes[index..]);
    }

    pub fn writeByte(bw: BufferedWritevWriter, byte: u8) Error!void {
        const array = [1]u8{byte};
        return bw.writeAll(&array);
    }

    pub fn writeByteNTimes(bw: BufferedWritevWriter, byte: u8, n: usize) Error!void {
        var bytes: [256]u8 = undefined;
        mem.set(u8, bytes[0..], byte);

        var remaining: usize = n;
        while (remaining > 0) {
            const to_write = std.math.min(remaining, bytes.len);
            try bw.writeAll(bytes[0..to_write]);
            remaining -= to_write;
        }
    }

    pub fn writeIntNative(bw: BufferedWritevWriter, comptime T: type, value: T) Error!void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        mem.writeIntNative(T, &bytes, value);
        return bw.writeAll(&bytes);
    }

    pub fn writeIntForeign(bw: BufferedWritevWriter, comptime T: type, value: T) Error!void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        mem.writeIntForeign(T, &bytes, value);
        return bw.writeAll(&bytes);
    }

    pub fn writeIntLittle(bw: BufferedWritevWriter, comptime T: type, value: T) Error!void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        mem.writeIntLittle(T, &bytes, value);
        return bw.writeAll(&bytes);
    }

    pub fn writeIntBig(bw: BufferedWritevWriter, comptime T: type, value: T) Error!void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        mem.writeIntBig(T, &bytes, value);
        return bw.writeAll(&bytes);
    }

    pub fn writeInt(bw: BufferedWritevWriter, comptime T: type, value: T, endian: builtin.Endian) Error!void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        mem.writeInt(T, &bytes, value, endian);
        return bw.writeAll(&bytes);
    }

    pub fn print(bw: BufferedWritevWriter, comptime fmt: []const u8, args: anytype) !void {
        const ArgSetType = u32;
        if (@typeInfo(@TypeOf(args)) != .Struct) {
            @compileError("Expected tuple or struct argument, found " ++ @typeName(@TypeOf(args)));
        }
        if (args.len > @typeInfo(ArgSetType).Int.bits) {
            @compileError("32 arguments max are supported per format call");
        }

        const State = enum {
            Start,
            Positional,
            CloseBrace,
            Specifier,
            FormatFillAndAlign,
            FormatWidth,
            FormatPrecision,
        };

        comptime var start_index = 0;
        comptime var state = State.Start;
        comptime var maybe_pos_arg: ?comptime_int = null;
        comptime var specifier_start = 0;
        comptime var specifier_end = 0;
        comptime var options = std.fmt.FormatOptions{};
        comptime var arg_state: struct {
            next_arg: usize = 0,
            used_args: ArgSetType = 0,
            args_len: usize = args.len,

            fn hasUnusedArgs(comptime self: *@This()) bool {
                return (@popCount(ArgSetType, self.used_args) != self.args_len);
            }

            fn nextArg(comptime self: *@This(), comptime pos_arg: ?comptime_int) comptime_int {
                const next_idx = pos_arg orelse blk: {
                    const arg = self.next_arg;
                    self.next_arg += 1;
                    break :blk arg;
                };

                if (next_idx >= self.args_len) {
                    @compileError("Too few arguments");
                }

                // Mark this argument as used
                self.used_args |= 1 << next_idx;

                return next_idx;
            }
        } = .{};

        inline for (fmt) |c, i| {
            switch (state) {
                .Start => switch (c) {
                    '{' => {
                        if (start_index < i) {
                            try bw.context.writeAssumeValidUntilFlush(fmt[start_index..i]);
                        }

                        start_index = i;
                        specifier_start = i + 1;
                        specifier_end = i + 1;
                        maybe_pos_arg = null;
                        state = .Positional;
                        options = std.fmt.FormatOptions{};
                    },
                    '}' => {
                        if (start_index < i) {
                            try bw.context.writeAssumeValidUntilFlush(fmt[start_index..i]);
                        }
                        state = .CloseBrace;
                    },
                    else => {},
                },
                .Positional => switch (c) {
                    '{' => {
                        state = .Start;
                        start_index = i;
                    },
                    ':' => {
                        state = if (comptime peekIsAlign(fmt[i..])) State.FormatFillAndAlign else State.FormatWidth;
                        specifier_end = i;
                    },
                    '0'...'9' => {
                        if (maybe_pos_arg == null) {
                            maybe_pos_arg = 0;
                        }

                        maybe_pos_arg.? *= 10;
                        maybe_pos_arg.? += c - '0';
                        specifier_start = i + 1;

                        if (maybe_pos_arg.? >= args.len) {
                            @compileError("Positional value refers to non-existent argument");
                        }
                    },
                    '}' => {
                        const arg_to_print = comptime arg_state.nextArg(maybe_pos_arg);

                        try std.fmt.formatType(
                            args[arg_to_print],
                            fmt[0..0],
                            options,
                            bw,
                            std.fmt.default_max_depth,
                        );

                        state = .Start;
                        start_index = i + 1;
                    },
                    else => {
                        state = .Specifier;
                        specifier_start = i;
                    },
                },
                .CloseBrace => switch (c) {
                    '}' => {
                        state = .Start;
                        start_index = i;
                    },
                    else => @compileError("Single '}' encountered in format string"),
                },
                .Specifier => switch (c) {
                    ':' => {
                        specifier_end = i;
                        state = if (comptime peekIsAlign(fmt[i..])) State.FormatFillAndAlign else State.FormatWidth;
                    },
                    '}' => {
                        const arg_to_print = comptime arg_state.nextArg(maybe_pos_arg);

                        try std.fmt.formatType(
                            args[arg_to_print],
                            fmt[specifier_start..i],
                            options,
                            bw,
                            std.fmt.default_max_depth,
                        );
                        state = .Start;
                        start_index = i + 1;
                    },
                    else => {},
                },
                // Only entered if the format string contains a fill/align segment.
                .FormatFillAndAlign => switch (c) {
                    '<' => {
                        options.alignment = Alignment.Left;
                        state = .FormatWidth;
                    },
                    '^' => {
                        options.alignment = Alignment.Center;
                        state = .FormatWidth;
                    },
                    '>' => {
                        options.alignment = Alignment.Right;
                        state = .FormatWidth;
                    },
                    else => {
                        options.fill = c;
                    },
                },
                .FormatWidth => switch (c) {
                    '0'...'9' => {
                        if (options.width == null) {
                            options.width = 0;
                        }

                        options.width.? *= 10;
                        options.width.? += c - '0';
                    },
                    '.' => {
                        state = .FormatPrecision;
                    },
                    '}' => {
                        const arg_to_print = comptime arg_state.nextArg(maybe_pos_arg);

                        try std.fmt.formatType(
                            args[arg_to_print],
                            fmt[specifier_start..specifier_end],
                            options,
                            bw,
                            default_max_depth,
                        );
                        state = .Start;
                        start_index = i + 1;
                    },
                    else => {
                        @compileError("Unexpected character in width value: " ++ [_]u8{c});
                    },
                },
                .FormatPrecision => switch (c) {
                    '0'...'9' => {
                        if (options.precision == null) {
                            options.precision = 0;
                        }

                        options.precision.? *= 10;
                        options.precision.? += c - '0';
                    },
                    '}' => {
                        const arg_to_print = comptime arg_state.nextArg(maybe_pos_arg);

                        try std.fmt.formatType(
                            args[arg_to_print],
                            fmt[specifier_start..specifier_end],
                            options,
                            bw,
                            default_max_depth,
                        );
                        state = .Start;
                        start_index = i + 1;
                    },
                    else => {
                        @compileError("Unexpected character in precision value: " ++ [_]u8{c});
                    },
                },
            }
        }
        comptime {
            if (comptime arg_state.hasUnusedArgs()) {
                @compileError("Unused arguments");
            }
            if (state != State.Start) {
                @compileError("Incomplete format string: " ++ fmt);
            }
        }
        if (start_index < fmt.len) {
            try bw.context.writeAssumeValidUntilFlush(fmt[start_index..]);
        }
    }
};
