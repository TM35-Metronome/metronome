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

path: std.ArrayListUnmanaged(u8),
name: std.ArrayListUnmanaged(u8),
description: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
commands: Commands = Commands{},

pub const Commands = std.ArrayListUnmanaged(Command);

pub const Command = struct {
    name: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
    args: std.ArrayListUnmanaged(Arg) = std.ArrayListUnmanaged(Arg){},

    pub fn init(allocator: mem.Allocator, name: []const u8) !Command {
        var name_list = try toArrayList(u8, allocator, name);
        errdefer name_list.deinit(allocator);

        return Command{ .name = name_list };
    }

    pub fn deinit(command: *Command, allocator: mem.Allocator) void {
        for (command.args.items) |*arg|
            arg.deinit(allocator);
        command.name.deinit(allocator);
        command.args.deinit(allocator);
    }

    pub fn get(command: Command, param: clap.Param(clap.Help)) ?*Arg {
        const name = param.names.longest().name;
        for (command.args.items) |*arg| {
            if (mem.eql(u8, arg.name.items, name))
                return arg;
        }

        return null;
    }

    pub const GetOrPutResult = struct {
        found_existing: bool,
        arg: *Arg,
    };

    pub fn getOrPut(command: *Command, allocator: mem.Allocator, param: clap.Param(clap.Help)) !GetOrPutResult {
        if (command.get(param)) |arg|
            return GetOrPutResult{ .found_existing = true, .arg = arg };

        const arg = try command.args.addOne(allocator);
        errdefer _ = command.args.pop();

        var name = try toArrayList(u8, allocator, param.names.longest().name);
        errdefer name.deinit(allocator);

        arg.* = .{ .name = name };
        return GetOrPutResult{ .found_existing = false, .arg = arg };
    }
};

pub const Arg = struct {
    name: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
    value: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},

    pub fn init(allocator: mem.Allocator, name: []const u8, value: []const u8) !Arg {
        var name_list = try toArrayList(u8, allocator, name);
        errdefer name_list.deinit(allocator);

        var value_list = try toArrayList(u8, allocator, value);
        errdefer value_list.deinit(allocator);

        return Arg{
            .name = name_list,
            .value = value_list,
        };
    }

    pub fn deinit(arg: *Arg, allocator: mem.Allocator) void {
        arg.name.deinit(allocator);
        arg.value.deinit(allocator);
    }
};

pub fn deinit(settings: *Settings, allocator: mem.Allocator) void {
    for (settings.commands.items) |*command|
        command.deinit(allocator);
    settings.path.deinit(allocator);
    settings.name.deinit(allocator);
    settings.description.deinit(allocator);
    settings.commands.deinit(allocator);
}

const SettingsJson = struct {
    name: []const u8,
    description: []const u8,
    commands: []const CommandJson,
};

const CommandJson = struct {
    name: []const u8,
    args: []const ArgJson,
};

const ArgJson = struct {
    name: []const u8,
    value: []const u8,
};

pub fn new(allocator: mem.Allocator, name: []const u8) !Settings {
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;

    const self_exe_dir_path = (try util.dir.selfExeDir()).slice();
    var self_exe_dir = try fs.openDirAbsolute(self_exe_dir_path, .{});
    defer self_exe_dir.close();

    const dirs_to_try = [_]fs.Dir{ fs.cwd(), self_exe_dir };
    for (dirs_to_try) |dir| {
        var settings_dir = dir.makeOpenPath("settings", .{}) catch continue;
        defer settings_dir.close();

        var i: usize = 0;
        while (true) : (i += 1) {
            const file_name = fmt.bufPrint(&buf, "{s}{}.json", .{ name, i }) catch unreachable;
            const file = settings_dir.createFile(file_name, .{
                .exclusive = true,
            }) catch |err| switch (err) {
                error.PathAlreadyExists => continue,
                else => |e| return e,
            };
            file.close();

            var path_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
            const path = try settings_dir.realpath(file_name, &path_buf);

            var name_list = try toArrayList(u8, allocator, name);
            errdefer name_list.deinit(allocator);

            var path_list = try toArrayList(u8, allocator, path);
            errdefer path_list.deinit(allocator);

            return Settings{
                .path = path_list,
                .name = name_list,
            };
        }
    }

    return error.CouldNotCreateSettings;
}

pub fn save(settings: Settings) !void {
    var needs_to_be_closed = false;
    var dir = if (fs.path.dirname(settings.path.items)) |dir| blk: {
        needs_to_be_closed = true;
        break :blk try fs.cwd().makeOpenPath(dir, .{});
    } else fs.cwd();
    defer if (needs_to_be_closed) dir.close();

    const file = try dir.createFile(fs.path.basename(settings.path.items), .{});
    defer file.close();

    var buffered = io.bufferedWriter(file.writer());
    try settings.saveTo(buffered.writer());
    try buffered.flush();
}

pub fn saveTo(settings: Settings, raw_writer: anytype) !void {
    var writer = json.writeStream(raw_writer, 16);
    writer.whitespace = .{
        .indent_level = 0,
        .indent = .{ .Space = 4 },
    };

    try writer.beginObject();
    try writer.objectField("name");
    try writer.emitString(settings.name.items);
    try writer.objectField("description");
    try writer.emitString(settings.description.items);

    try writer.objectField("commands");
    try writer.beginArray();

    for (settings.commands.items) |command| {
        try writer.arrayElem();
        try writer.beginObject();
        try writer.objectField("name");
        try writer.emitString(command.name.items);
        try writer.objectField("args");
        try writer.beginArray();

        for (command.args.items) |arg| {
            try writer.arrayElem();
            try writer.beginObject();
            try writer.objectField("name");
            try writer.emitString(arg.name.items);
            try writer.objectField("value");
            try writer.emitString(arg.value.items);
            try writer.endObject();
        }

        try writer.endArray();
        try writer.endObject();
    }

    try writer.endArray();
    try writer.endObject();
}

pub fn parse(allocator: mem.Allocator, path: []const u8, str: []const u8) !Settings {
    var tmp_arena = heap.ArenaAllocator.init(allocator);
    defer tmp_arena.deinit();

    var stream = json.TokenStream.init(str);
    const res = json.parse(SettingsJson, &stream, .{
        .allocator = tmp_arena.allocator(),
    }) catch |err| switch (err) {
        error.AllocatorRequired => unreachable,
        else => |e| return e,
    };

    var commands = Commands{};
    errdefer {
        for (commands.items) |*command| command.deinit(allocator);
        commands.deinit(allocator);
    }

    for (res.commands) |command| {
        var cmd = try Command.init(allocator, command.name);
        errdefer cmd.deinit(allocator);

        for (command.args) |arg| {
            var argument = try Arg.init(allocator, arg.name, arg.value);
            errdefer argument.deinit(allocator);

            try cmd.args.append(allocator, argument);
        }

        try commands.append(allocator, cmd);
    }

    var path_list = try toArrayList(u8, allocator, path);
    errdefer path_list.deinit(allocator);

    var name = try toArrayList(u8, allocator, res.name);
    errdefer name.deinit(allocator);

    var description = try toArrayList(u8, allocator, res.description);
    errdefer description.deinit(allocator);

    return Settings{
        .path = path_list,
        .name = name,
        .description = description,
        .commands = commands,
    };
}

fn toArrayList(
    comptime T: type,
    allocator: mem.Allocator,
    str: []const u8,
) !std.ArrayListUnmanaged(T) {
    var res = std.ArrayListUnmanaged(T){};
    try res.appendSlice(allocator, str);
    return res;
}

pub fn load(allocator: mem.Allocator, path: []const u8, reader: anytype) !Settings {
    const str = try reader.readAllAlloc(allocator, math.maxInt(usize));
    defer allocator.free(str);
    return parse(allocator, path, str);
}

pub fn loadAllFrom(allocator: mem.Allocator, path: []const u8) !std.ArrayListUnmanaged(Settings) {
    var res = std.ArrayListUnmanaged(Settings){};
    errdefer {
        for (res.items) |*item|
            item.deinit(allocator);
        res.deinit(allocator);
    }

    var dir = try fs.cwd().openIterableDir(path, .{});
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| switch (entry.kind) {
        .File => {
            try res.ensureUnusedCapacity(allocator, 1);

            const file = try dir.dir.openFile(entry.name, .{});
            defer file.close();

            const full_path = util.path.join(&.{
                path,
                entry.name,
            });

            if (load(allocator, full_path.slice(), file.reader())) |settings| {
                res.appendAssumeCapacity(settings);
            } else |err| switch (err) {
                // Ignore all json parsing errors
                error.DuplicateJSONField,
                error.UnexpectedEndOfJson,
                error.UnexpectedToken,
                error.UnexpectedValue,
                error.UnknownField,
                error.MissingField,
                error.UnexpectedJsonDepth,
                error.InvalidTopLevel,
                error.TooManyNestedItems,
                error.TooManyClosingItems,
                error.InvalidValueBegin,
                error.InvalidValueEnd,
                error.UnbalancedBrackets,
                error.UnbalancedBraces,
                error.UnexpectedClosingBracket,
                error.UnexpectedClosingBrace,
                error.InvalidNumber,
                error.InvalidSeparator,
                error.InvalidLiteral,
                error.InvalidEscapeCharacter,
                error.InvalidUnicodeHexSymbol,
                error.InvalidUtf8Byte,
                error.InvalidTopLevelTrailing,
                error.InvalidControlCharacter,
                error.InvalidCharacter,
                => {},

                error.AccessDenied,
                error.BrokenPipe,
                error.ConnectionResetByPeer,
                error.ConnectionTimedOut,
                error.InputOutput,
                error.IsDir,
                error.NetNameDeleted,
                error.NotOpenForReading,
                error.OperationAborted,
                error.OutOfMemory,
                error.Overflow,
                error.StreamTooLong,
                error.SystemResources,
                error.Unexpected,
                error.WouldBlock,
                => |e| return e,
            }
        },
        else => {},
    };

    return res;
}

pub fn loadAll(allocator: mem.Allocator) !std.ArrayListUnmanaged(Settings) {
    const self_exe_dir_path = try util.dir.selfExeDir();

    const dirs_to_try = [_][]const u8{ ".", self_exe_dir_path.slice() };
    for (dirs_to_try) |dir| {
        const dir_path = util.path.join(&.{
            dir, "settings",
        });
        return loadAllFrom(allocator, dir_path.slice());
    }

    return std.ArrayListUnmanaged(Settings){};
}

comptime {
    _ = loadAll;
}
