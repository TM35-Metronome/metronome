const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const json = std.json;
const math = std.math;
const mem = std.mem;

const escape = util.escape;

const Executables = @import("Executables.zig");

const Settings = @This();

arena: heap.ArenaAllocator,
path: []const u8,
name: []const u8,
description: []const u8,
commands: []const []const []const u8,

pub fn deinit(settings: Settings) void {
    settings.arena.deinit();
}

const SettingsJson = struct {
    name: []const u8,
    description: []const u8,
    commands: []const []const []const u8,
};

const SettingsJsonWithPath = struct {
    path: []const u8,
    name: []const u8,
    description: []const u8,
    commands: []const []const []const u8,
};

pub fn save(settings: Settings, writer: anytype) !void {
    return json.stringify(
        SettingsJson{
            .name = settings.name,
            .description = settings.description,
            .commands = settings.commands,
        },
        .{},
        writer,
    );
}

pub fn saveWithPath(settings: Settings, writer: anytype) !void {
    return json.stringify(
        SettingsJsonWithPath{
            .path = settings.path,
            .name = settings.name,
            .description = settings.description,
            .commands = settings.commands,
        },
        .{},
        writer,
    );
}

pub fn parse(allocator: mem.Allocator, path: []const u8, str: []const u8) !Settings {
    var arena = heap.ArenaAllocator.init(allocator);
    var stream = json.TokenStream.init(str);

    const res = json.parse(SettingsJson, &stream, .{
        .allocator = arena.allocator(),
    }) catch |err| switch (err) {
        error.AllocatorRequired => unreachable,
        else => |e| return e,
    };

    return Settings{
        .arena = arena,
        .path = try arena.allocator().dupe(u8, path),
        .name = res.name,
        .description = res.description,
        .commands = res.commands,
    };
}

pub fn parseWithPath(allocator: mem.Allocator, str: []const u8) !Settings {
    var arena = heap.ArenaAllocator.init(allocator);
    var stream = json.TokenStream.init(str);

    const res = json.parse(SettingsJsonWithPath, &stream, .{
        .allocator = arena.allocator(),
    }) catch |err| switch (err) {
        error.AllocatorRequired => unreachable,
        else => |e| return e,
    };

    return Settings{
        .arena = arena,
        .path = res.path,
        .name = res.name,
        .description = res.description,
        .commands = res.commands,
    };
}

pub fn load(allocator: mem.Allocator, path: []const u8, reader: anytype) !Settings {
    const str = try reader.readAllAlloc(allocator, math.maxInt(usize));
    defer allocator.free(str);
    return parse(allocator, path, str);
}

pub fn loadAllFrom(allocator: mem.Allocator, dir: fs.IterableDir) !std.ArrayList(Settings) {
    var res = std.ArrayList(Settings).init(allocator);
    errdefer {
        for (res.items) |item|
            item.deinit();
        res.deinit();
    }

    var it = dir.iterate();
    while (try it.next()) |entry| switch (entry.kind) {
        .File => {
            try res.ensureUnusedCapacity(1);

            var path_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
            const path = try dir.dir.realpath(entry.name, &path_buf);

            const file = try dir.dir.openFile(entry.name, .{});
            defer file.close();

            if (load(allocator, path, file.reader())) |settings| {
                res.appendAssumeCapacity(settings);
            } else |err| switch (err) {
                // Ignore all json parsing errors
                error.DuplicateJSONField => {},
                error.UnexpectedEndOfJson => {},
                error.UnexpectedToken => {},
                error.UnexpectedValue => {},
                error.UnknownField => {},
                error.MissingField => {},
                error.UnexpectedJsonDepth => {},
                error.InvalidTopLevel => {},
                error.TooManyNestedItems => {},
                error.TooManyClosingItems => {},
                error.InvalidValueBegin => {},
                error.InvalidValueEnd => {},
                error.UnbalancedBrackets => {},
                error.UnbalancedBraces => {},
                error.UnexpectedClosingBracket => {},
                error.UnexpectedClosingBrace => {},
                error.InvalidNumber => {},
                error.InvalidSeparator => {},
                error.InvalidLiteral => {},
                error.InvalidEscapeCharacter => {},
                error.InvalidUnicodeHexSymbol => {},
                error.InvalidUtf8Byte => {},
                error.InvalidTopLevelTrailing => {},
                error.InvalidControlCharacter => {},
                error.InvalidCharacter => {},

                error.OutOfMemory,
                error.Overflow,
                error.StreamTooLong,
                error.InputOutput,
                error.SystemResources,
                error.IsDir,
                error.OperationAborted,
                error.BrokenPipe,
                error.ConnectionResetByPeer,
                error.ConnectionTimedOut,
                error.NotOpenForReading,
                error.WouldBlock,
                error.AccessDenied,
                error.Unexpected,
                => |e| return e,
            }
        },
        else => {},
    };

    return res;
}

pub fn loadAll(allocator: mem.Allocator) !std.ArrayList(Settings) {
    const self_exe_dir_path = (try util.dir.selfExeDir()).slice();
    var self_exe_dir = try fs.openDirAbsolute(self_exe_dir_path, .{});
    defer self_exe_dir.close();

    const dirs_to_try = [_]fs.Dir{ self_exe_dir, fs.cwd() };
    for (dirs_to_try) |dir| {
        var settings_dir = dir.openIterableDir("settings", .{}) catch |err| switch (err) {
            // Settings not found here. Try another dir
            error.FileNotFound => continue,
            else => |e| return e,
        };
        defer settings_dir.close();

        return loadAllFrom(allocator, settings_dir);
    }

    return std.ArrayList(Settings).init(allocator);
}

comptime {
    _ = loadAll;
}
