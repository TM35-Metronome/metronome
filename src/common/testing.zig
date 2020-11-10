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
    var stdin = io.bufferedInStream(io.fixedBufferStream(in).inStream());
    var stdout = io.fixedBufferStream(&out_buf);
    var stderr = io.fixedBufferStream(&err_buf);
    var arg_iter = clap.args.SliceIterator{ .args = args };
    const clap_args = clap.parseEx(clap.Help, params, &fba.allocator, &arg_iter, null) catch unreachable;

    const StdIo = util.CustomStdIoStreams(
        io.BufferedInStream(4096, std.io.FixedBufferStream([]const u8).InStream).InStream,
        io.FixedBufferStream([]u8).OutStream,
    );

    const res = main(
        &fba.allocator,
        StdIo.InStream,
        StdIo.OutStream,
        StdIo{
            .in = stdin.inStream(),
            .out = stdout.outStream(),
            .err = stderr.outStream(),
        },
        clap_args,
    );
    debug.warn("{}", .{stderr.getWritten()});
    testing.expectEqual(@as(u8, 0), res);
    testing.expectEqualSlices(u8, "", stderr.getWritten());
    if (!mem.eql(u8, out, stdout.getWritten())) {
        debug.warn("\n====== expected this output: =========\n", .{});
        debug.warn("{}", .{out});
        debug.warn("\n======== instead found this: =========\n", .{});
        debug.warn("{}", .{stdout.getWritten()});
        debug.warn("\n======================================\n", .{});
        testing.expect(false);
    }
    testing.expectEqualSlices(u8, out, stdout.getWritten());
}
