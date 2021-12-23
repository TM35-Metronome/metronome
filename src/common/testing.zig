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
    const res = try runProgram(Program, args, in);
    defer testing.allocator.free(res);

    try testing.expectEqualStrings(out, res);
}

pub fn runProgram(
    comptime Program: type,
    args: []const []const u8,
    in: []const u8,
) ![]const u8 {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    var stdout = std.ArrayList(u8).init(testing.allocator);
    var stdin = io.fixedBufferStream(in);
    var arg_iter = clap.args.SliceIterator{ .args = args };
    const clap_args = try clap.parseEx(clap.Help, Program.params, &arg_iter, .{});
    defer clap_args.deinit();

    const StdIo = util.CustomStdIoStreams(
        std.io.FixedBufferStream([]const u8).Reader,
        std.ArrayList(u8).Writer,
    );

    var program = try Program.init(arena_state.allocator(), clap_args);
    try program.run(
        StdIo.Reader,
        StdIo.Writer,
        .{ .in = stdin.reader(), .out = stdout.writer() },
    );
    return stdout.toOwnedSlice();
}
