const std = @import("std");

const fmt = std.fmt;
const log = std.log;
const meta = std.meta;

pub fn seed(args: anytype) !u64 {
    return (try int(args, "--seed", u64)) orelse return std.crypto.random.int(u64);
}

pub fn int(args: anytype, comptime name: []const u8, comptime T: type) !?T {
    const arg = args.option(name) orelse return null;
    return fmt.parseInt(T, arg, 10) catch |err| {
        log.err("'{s}' isn't a valid value for {s}: {}", .{ arg, name, err });
        return error.InvalidIntArgument;
    };
}

pub fn float(args: anytype, comptime name: []const u8, comptime T: type) !?T {
    const arg = args.option(name) orelse return null;
    return fmt.parseFloat(T, arg) catch |err| {
        log.err("'{s}' isn't a valid value for {s}: {}", .{ arg, name, err });
        return error.InvalidIntArgument;
    };
}

pub fn enumeration(args: anytype, comptime name: []const u8, comptime T: type) !?T {
    const arg = args.option(name) orelse return null;
    return meta.stringToEnum(T, arg) orelse {
        log.err("'{s}' isn't a valid value for {s}", .{ arg, name });
        return error.InvalidIntArgument;
    };
}
