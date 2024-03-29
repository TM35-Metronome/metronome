const clap = @import("clap");
const std = @import("std");

const util = @import("../util.zig");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const testing = std.testing;

pub const test_case = @embedFile("test_file.tm35");

pub const TestProgramOptions = struct {
    args: []const []const u8 = &[_][]const u8{},
    in: []const u8 = test_case,
    out: []const u8,
};

pub fn testProgram(
    comptime Program: type,
    args: []const []const u8,
    in: []const u8,
    out: []const u8,
) !void {
    const res = try runProgram(Program, .{ .args = args, .in = in });
    defer testing.allocator.free(res);

    try testing.expectEqualStrings(out, res);
}

pub const RunProgramOptions = struct {
    args: []const []const u8,
    in: []const u8 = test_case,
};

pub fn runProgram(comptime Program: type, opt: RunProgramOptions) ![:0]const u8 {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    var stdout = std.ArrayList(u8).init(testing.allocator);
    var stdin = io.fixedBufferStream(opt.in);
    var arg_iter = clap.args.SliceIterator{ .args = opt.args };
    var clap_args = try clap.parseEx(clap.Help, &Program.params, Program.parsers, &arg_iter, .{});
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
    return stdout.toOwnedSliceSentinel(0);
}

pub const Context = struct {
    handle: *const anyopaque,
    len: usize,

    pub fn fromSlice(slice: anytype) Context {
        return .{
            .handle = @ptrCast(slice.ptr),
            .len = slice.len,
        };
    }

    pub fn toSlice(ctx: Context, comptime T: type) []const T {
        const ptr: [*]const T = @ptrCast(@alignCast(ctx.handle));
        return ptr[0..ctx.len];
    }
};

pub const Pattern = struct {
    min: usize,
    max: usize,
    ctx: Context,
    matches: *const fn (Context, []const u8) bool,
    deinit: *const fn (Context, mem.Allocator) void,

    pub fn string(min: usize, max: usize, str: []const u8) Pattern {
        return .{
            .min = min,
            .max = max,
            .ctx = Context.fromSlice(str),
            .matches = matchesString,
            .deinit = deinitString,
        };
    }

    fn matchesString(ctx: Context, haystack: []const u8) bool {
        const slice = ctx.toSlice(u8);
        return mem.indexOf(u8, haystack, slice) != null;
    }

    fn deinitString(_: Context, _: mem.Allocator) void {}

    pub fn endsWith(min: usize, max: usize, str: []const u8) Pattern {
        return .{
            .min = min,
            .max = max,
            .ctx = Context.fromSlice(str),
            .matches = matchesEndsWith,
            .deinit = deinitEndsWith,
        };
    }

    fn matchesEndsWith(ctx: Context, haystack: []const u8) bool {
        const slice = ctx.toSlice(u8);
        return mem.endsWith(u8, haystack, slice);
    }

    fn deinitEndsWith(_: Context, _: mem.Allocator) void {}

    pub fn glob(min: usize, max: usize, str: []const u8) Pattern {
        const split = util.glob.split(testing.allocator, str) catch unreachable;
        return .{
            .min = min,
            .max = max,
            .ctx = Context.fromSlice(split),
            .matches = matchesGlob,
            .deinit = deinitGlob,
        };
    }

    fn matchesGlob(ctx: Context, haystack: []const u8) bool {
        const glob_split = ctx.toSlice([]const u8);
        return util.glob.matchSplit(glob_split, haystack);
    }

    fn deinitGlob(ctx: Context, allocator: mem.Allocator) void {
        allocator.free(ctx.toSlice([]const u8));
    }
};

pub const FindMatchesOptions = struct {
    args: []const []const u8 = &[_][]const u8{},
    in: []const u8 = test_case,
    patterns: []const Pattern,
};

/// Runs `Program` and checks that the output contains a number of patterns. A pattern is just
/// something that can be found in a string, and a pattern also specifies how many of that
/// pattern is expected to be found in the output.
pub fn runProgramFindPatterns(comptime Program: type, opt: FindMatchesOptions) !void {
    const str = try runProgram(Program, .{ .args = opt.args, .in = opt.in });
    defer testing.allocator.free(str);

    const matches = try testing.allocator.alloc(usize, opt.patterns.len);
    defer testing.allocator.free(matches);
    @memset(matches, 0);

    defer for (opt.patterns) |pattern|
        pattern.deinit(pattern.ctx, testing.allocator);

    var it = mem.split(u8, str, "\n");
    while (it.next()) |line| {
        for (opt.patterns, matches) |pattern, *match|
            match.* += @intFromBool(pattern.matches(pattern.ctx, line));
    }

    var fail = false;
    for (opt.patterns, matches) |pattern, match| {
        if (match < pattern.min or pattern.max < match) {
            std.debug.print("\nexpected between {} and {} matches, found {}", .{
                pattern.min,
                pattern.max,
                match,
            });
            fail = true;
        }
    }

    if (fail) {
        std.debug.print("\n", .{});
        return error.TestExpectedEqual;
    }
}

pub fn filter(in: []const u8, globs: []const []const u8) ![:0]u8 {
    const split = try util.glob.splitAll(testing.allocator, globs);
    defer {
        for (split) |item|
            testing.allocator.free(item);
        testing.allocator.free(split);
    }

    var res = std.ArrayList(u8).init(testing.allocator);
    errdefer res.deinit();

    var it = mem.split(u8, in, "\n");
    while (it.next()) |line| {
        if (util.glob.matchesOneOfSplit(line, split) == null)
            continue;

        try res.appendSlice(line);
        try res.append('\n');
    }

    return res.toOwnedSliceSentinel(0);
}

pub fn boundPrint(
    comptime bound: usize,
    comptime format: []const u8,
    args: anytype,
) !std.BoundedArray(u8, bound) {
    var res: std.BoundedArray(u8, bound) = undefined;
    res.len = @intCast((try fmt.bufPrint(&res.buffer, format, args)).len);
    return res;
}
