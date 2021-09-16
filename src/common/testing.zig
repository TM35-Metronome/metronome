const clap = @import("clap");
const std = @import("std");
const util = @import("util.zig");

const debug = std.debug;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const testing = std.testing;

pub fn testProgram(
    comptime Program: type,
    args: []const []const u8,
    in: []const u8,
    out: []const u8,
) !void {
    var alloc_buf: [1024 * 50]u8 = undefined;
    var out_buf: [1024 * 10]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&alloc_buf);
    var stdin = io.fixedBufferStream(in);
    var stdout = io.fixedBufferStream(&out_buf);
    var arg_iter = clap.args.SliceIterator{ .args = args };
    const clap_args = try clap.parseEx(clap.Help, Program.params, &arg_iter, .{});
    defer clap_args.deinit();

    const StdIo = util.CustomStdIoStreams(
        std.io.FixedBufferStream([]const u8).Reader,
        io.FixedBufferStream([]u8).Writer,
    );

    var program = try Program.init(&fba.allocator, clap_args);
    try program.run(
        StdIo.Reader,
        StdIo.Writer,
        StdIo{
            .in = stdin.reader(),
            .out = stdout.writer(),
        },
    );
    try testing.expectEqualStrings(out, stdout.getWritten());
}
