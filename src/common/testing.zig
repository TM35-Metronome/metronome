const clap = @import("clap");
const std = @import("std");
const util = @import("util.zig");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const testing = std.testing;

pub const test_case = @embedFile("test_file.tm");

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

pub fn runProgram(comptime Program: type, opt: RunProgramOptions) ![]const u8 {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    var stdout = std.ArrayList(u8).init(testing.allocator);
    var stdin = io.fixedBufferStream(opt.in);
    var arg_iter = clap.args.SliceIterator{ .args = opt.args };
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

pub const Context = struct {
    handle: *const anyopaque,
    len: usize,

    pub fn fromSlice(slice: anytype) Context {
        return .{
            .handle = @ptrCast(*const anyopaque, slice.ptr),
            .len = slice.len,
        };
    }

    pub fn toSlice(ctx: Context, comptime T: type) []const T {
        const ptr = @ptrCast([*]const T, ctx.handle);
        return ptr[0..ctx.len];
    }
};

pub const Pattern = struct {
    min: usize,
    max: usize,
    ctx: Context,
    find: fn (Context, []const u8, usize) ?usize,

    pub fn string(min: usize, max: usize, str: []const u8) Pattern {
        return .{
            .min = min,
            .max = max,
            .ctx = Context.fromSlice(str),
            .find = findString,
        };
    }

    fn findString(ctx: Context, haystack: []const u8, pos: usize) ?usize {
        return mem.indexOfPos(u8, haystack, pos, ctx.toSlice(u8));
    }

    pub fn glob(min: usize, max: usize, str: []const u8) Pattern {
        return .{
            .min = min,
            .max = max,
            .ctx = Context.fromSlice(str),
            .find = findGlob,
        };
    }

    fn findGlob(ctx: Context, haystack: []const u8, pos: usize) ?usize {
        const glob_str = ctx.toSlice(u8);
        var it = mem.split(u8, haystack, "\n");
        it.index = pos;

        var curr = it.index;
        while (it.next()) |line| : (curr = it.index) {
            if (util.glob.match(glob_str, line))
                return curr;
        }

        return null;
    }
};

pub const SeedRange = struct {
    min: usize,
    max: usize,
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
    const res = try runProgram(Program, .{ .args = opt.args, .in = opt.in });
    defer testing.allocator.free(res);

    for (opt.patterns) |pattern| {
        var i: usize = 0;
        var matches: usize = 0;
        while (pattern.find(pattern.ctx, res, i)) |new_i| : (i = new_i + 1)
            matches += 1;

        if (matches < pattern.min or pattern.max < matches) {
            std.debug.print("expected between {} and {} matches, found {}\n", .{
                pattern.min,
                pattern.max,
                matches,
            });
            return error.TestExpectedEqual;
        }
    }
}

pub fn filter(in: []const u8, globs: []const []const u8) ![]u8 {
    var res = std.ArrayList(u8).init(testing.allocator);
    errdefer res.deinit();

    var it = mem.split(u8, in, "\n");
    while (it.next()) |line| {
        for (globs) |glob| {
            if (util.glob.match(glob, line))
                break;
        } else continue;

        try res.appendSlice(line);
        try res.append('\n');
    }

    return res.toOwnedSlice();
}
