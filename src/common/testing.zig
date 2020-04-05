const std = @import("std");
const util = @import("util.zig");

const debug = std.debug;
const heap = std.heap;
const mem = std.mem;
const io = std.io;
const testing = std.testing;

// I've copied SliceIterator from "clap" to this file to avoid depending on "clap".
const SliceIterator = struct {
    const Error = error{};

    args: []const []const u8,
    index: usize = 0,

    pub fn next(iter: *SliceIterator) Error!?[]const u8 {
        if (iter.args.len <= iter.index)
            return null;

        defer iter.index += 1;
        return iter.args[iter.index];
    }
};

pub fn testProgram(
    comptime main: var,
    args: []const []const u8,
    in: []const u8,
    out: []const u8,
) void {
    var alloc_buf: [1024 * 50]u8 = undefined;
    var out_buf: [1024 * 10]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&alloc_buf);
    var stdin = io.SliceInStream.init(in);
    var stdout = io.SliceOutStream.init(&out_buf);
    var stderr = io.SliceOutStream.init(&err_buf);
    var arg_iter = SliceIterator{ .args = args };

    const StdIo = util.CustomStdIoStreams(anyerror, anyerror);

    const res = main(
        &fba.allocator,
        anyerror,
        anyerror,
        StdIo{
            .in = @ptrCast(*io.InStream(anyerror), &stdin.stream),
            .out = @ptrCast(*io.OutStream(anyerror), &stdout.stream),
            .err = @ptrCast(*io.OutStream(anyerror), &stderr.stream),
        },
        SliceIterator,
        &arg_iter,
    );
    debug.warn("{}", stderr.getWritten());
    testing.expectEqual(u8(0), res);
    testing.expectEqualSlices(u8, "", stderr.getWritten());
    if (!mem.eql(u8, out, stdout.getWritten())) {
        debug.warn("\n====== expected this output: =========\n");
        debug.warn("{}", out);
        debug.warn("\n======== instead found this: =========\n");
        debug.warn("{}", stdout.getWritten());
        debug.warn("\n======================================\n");
        debug.warn("\n====== expected this output: =========\n");
        debug.warn("{x}", out);
        debug.warn("\n======== instead found this: =========\n");
        debug.warn("{x}", stdout.getWritten());
        debug.warn("\n======================================\n");
        testing.expect(false);
    }
    testing.expectEqualSlices(u8, out, stdout.getWritten());
}
