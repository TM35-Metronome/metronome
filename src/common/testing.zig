const clap = @import("clap");
const std = @import("std");
const util = @import("util.zig");

const debug = std.debug;
const heap = std.heap;
const mem = std.mem;
const io = std.io;
const testing = std.testing;

pub fn testProgram(
    comptime main: anytype,
    comptime params: []const clap.Param(clap.Help),
    args: []const []const u8,
    in: []const u8,
    out: []const u8,
) void {
    var alloc_buf: [1024 * 50]u8 = undefined;
    var out_buf: [1024 * 10]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&alloc_buf);
    var stdin = io.bufferedReader(io.fixedBufferStream(in).reader());
    var stdout = io.fixedBufferStream(&out_buf);
    var stderr = io.fixedBufferStream(&err_buf);
    var arg_iter = clap.args.SliceIterator{ .args = args };
    const clap_args = clap.parseEx(clap.Help, params, &fba.allocator, &arg_iter, null) catch unreachable;

    const StdIo = util.CustomStdIoStreams(
        io.BufferedReader(4096, std.io.FixedBufferStream([]const u8).Reader).Reader,
        io.FixedBufferStream([]u8).Writer,
    );

    const res = main(
        &fba.allocator,
        StdIo.Reader,
        StdIo.Writer,
        StdIo{
            .in = stdin.reader(),
            .out = stdout.writer(),
            .err = stderr.writer(),
        },
        clap_args,
    );
    testing.expectEqual(@as(u8, 0), res);
    testing.expectEqualStrings("", stderr.getWritten());
    testing.expectEqualStrings(out, stdout.getWritten());
}
