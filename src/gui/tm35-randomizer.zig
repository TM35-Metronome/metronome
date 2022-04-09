const builtin = @import("builtin");
const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const c = @import("c.zig");

const Executables = @import("Executables.zig");
const Settings = @import("Settings.zig");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const process = std.process;
const time = std.time;

const escape = util.escape;

const path = fs.path;

// TODO: proper versioning
const program_version = "0.0.0";

const bug_message = "Hi user. You have just hit a bug/limitation in the program. " ++
    "If you care about this program, please report this to the issue tracker here: " ++
    "https://github.com/TM35-Metronome/metronome/issues/new";

const platform = switch (builtin.target.os.tag) {
    .windows => struct {
        extern "kernel32" fn GetConsoleWindow() callconv(std.os.windows.WINAPI) std.os.windows.HWND;
    },
    else => struct {},
};

pub fn main() anyerror!void {
    // HACK: I don't want to show a console to the user.
    //       Here is someone explaing what to pass to the C compiler to make that happen:
    //       https://stackoverflow.com/a/9619254
    //       I have no idea how to get the same behavior using the Zig compiler, so instead
    //       I use this solution:
    //       https://stackoverflow.com/a/9618984
    switch (builtin.target.os.tag) {
        .windows => _ = std.os.windows.user32.showWindow(platform.GetConsoleWindow(), 0),
        else => {},
    }

    const w = c.webview_create(1, null);
    c.webview_set_title(w, "Webview Example");
    c.webview_set_size(w, 800, 600, c.WEBVIEW_HINT_NONE);
    c.webview_set_html(w, @embedFile("tm35-randomizer.html"));

    c.webview_bind(w, "tm35GetSettings", tm35GetSettings, w);

    c.webview_run(w);
    c.webview_destroy(w);
}

fn tm35GetSettings(seq: [*c]const u8, req: [*c]const u8, arg: ?*anyopaque) callconv(.C) void {
    const w = @ptrCast(*c.webview_t, @alignCast(@alignOf(c.webview_t), arg));
    _ = req;

    var arena = heap.ArenaAllocator.init(heap.c_allocator);
    defer arena.deinit();

    if (getSettingsJson(arena.allocator())) |settings| {
        c.webview_return(w, seq, 0, settings.ptr);
    } else |_| {
        c.webview_return(w, seq, 1, "\"Error!\"");
    }
}

fn getSettingsJson(allocator: mem.Allocator) ![:0]u8 {
    const settings = try Settings.loadAll(allocator);
    var res = std.ArrayList(u8).init(allocator);

    try res.append('[');
    for (settings.items) |setting, i| {
        try setting.save(res.writer());
        if (i + 1 != settings.items.len)
            try res.append(',');
    }
    try res.append(']');

    return res.toOwnedSliceSentinel(0);
}

fn randomize(exes: Executables, settings: Settings, in: []const u8, out: []const u8) !void {
    var buf: [1024 * 40]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);

    const term = switch (builtin.target.os.tag) {
        .linux => blk: {
            var sh = std.ChildProcess.init(&[_][]const u8{ "sh", "-e" }, fba.allocator());
            sh.stdin_behavior = .Pipe;
            try sh.spawn();

            const writer = sh.stdin.?.writer();
            try outputScript(writer, exes, settings, in, out);

            sh.stdin.?.close();
            sh.stdin = null;

            break :blk try sh.wait();
        },
        .windows => blk: {
            const cache_dir = try util.dir.folder(.cache);
            const program_cache_dir = util.path.join(&[_][]const u8{
                cache_dir.constSlice(),
                Executables.program_name,
            });
            const script_file_name = util.path.join(&[_][]const u8{
                program_cache_dir.constSlice(),
                "tmp_scipt.bat",
            });
            {
                try fs.cwd().makePath(program_cache_dir.constSlice());
                const file = try fs.cwd().createFile(script_file_name.constSlice(), .{});
                defer file.close();
                try outputScript(file.writer(), exes, settings, in, out);
            }

            var cmd = std.ChildProcess.init(
                &[_][]const u8{ "cmd", "/c", "call", script_file_name.constSlice() },
                fba.allocator(),
            );
            break :blk try cmd.spawnAndWait();
        },
        else => @compileError("Unsupported os"),
    };
    switch (term) {
        .Exited => |code| {
            if (code != 0)
                return error.CommandFailed;
        },
        .Signal, .Stopped, .Unknown => |_| {
            return error.CommandFailed;
        },
    }
}

fn outputScript(
    writer: anytype,
    exes: Executables,
    settings: Settings,
    in: []const u8,
    out: []const u8,
) !void {
    const escapes = switch (builtin.target.os.tag) {
        .linux => [_]escape.Escape{
            .{ .escaped = "'\\''", .unescaped = "\'" },
        },
        .windows => [_]escape.Escape{
            .{ .escaped = "\\\"", .unescaped = "\"" },
        },
        else => @compileError("Unsupported os"),
    };
    const quotes = switch (builtin.target.os.tag) {
        .linux => "'",
        .windows => "\"",
        else => @compileError("Unsupported os"),
    };

    const esc = escape.generate(&escapes);
    try writer.writeAll(quotes);
    try esc.escapeWrite(writer, exes.load.constSlice());
    try writer.writeAll(quotes ++ " " ++ quotes);
    try esc.escapeWrite(writer, in);
    try writer.writeAll(quotes ++ " | ");

    for (settings.commands.items) |setting| {
        const command = exes.commands[setting.executable];

        try writer.writeAll(quotes);
        try esc.escapeWrite(writer, command.path);
        try writer.writeAll(quotes);

        for (command.flags) |flag_param, i| {
            const param = command.params[flag_param.i];
            const prefix = if (param.names.long) |_| "--" else "-";
            const name = param.names.long orelse @as(*const [1]u8, &param.names.short.?)[0..];
            const flag = setting.flags[i];
            if (!flag)
                continue;

            try writer.writeAll(" " ++ quotes);
            try esc.escapePrint(writer, "{s}{s}", .{ prefix, name });
            try writer.writeAll(quotes);
        }
        for (command.ints) |int_param, i| {
            const param = command.params[int_param.i];
            try writer.writeAll(" " ++ quotes);
            try outputArgument(writer, esc, param, setting.ints[i], "");
            try writer.writeAll(quotes);
        }
        for (command.floats) |float_param, i| {
            const param = command.params[float_param.i];
            try writer.writeAll(" " ++ quotes);
            try outputArgument(writer, esc, param, setting.floats[i], "d");
            try writer.writeAll(quotes);
        }
        for (command.enums) |enum_param, i| {
            const param = command.params[enum_param.i];
            const value = enum_param.options[setting.enums[i]];
            try writer.writeAll(" " ++ quotes);
            try outputArgument(writer, esc, param, value, "s");
            try writer.writeAll(quotes);
        }
        for (command.strings) |string_param, i| {
            const param = command.params[string_param.i];
            try writer.writeAll(" " ++ quotes);
            try outputArgument(writer, esc, param, setting.strings[i].items, "s");
            try writer.writeAll(quotes);
        }
        for (command.files) |file_param, i| {
            const param = command.params[file_param.i];
            try writer.writeAll(" " ++ quotes);
            try outputArgument(writer, esc, param, setting.files[i].items, "s");
            try writer.writeAll(quotes);
        }
        for (command.multi_strings) |multi_param, i| {
            const param = command.params[multi_param.i];

            var it = mem.tokenize(u8, setting.multi_strings[i].items, "\r\n");
            while (it.next()) |string| {
                try writer.writeAll(" " ++ quotes);
                try outputArgument(writer, esc, param, string, "s");
                try writer.writeAll(quotes);
            }
        }

        try writer.writeAll(" | ");
    }

    try writer.writeAll(quotes);
    try esc.escapeWrite(writer, exes.apply.constSlice());
    try writer.writeAll(quotes ++ " --replace --output " ++ quotes);
    try esc.escapeWrite(writer, out);
    try writer.writeAll(quotes ++ " " ++ quotes);
    try esc.escapeWrite(writer, in);
    try writer.writeAll(quotes);
    try writer.writeAll("\n");
}

fn outputArgument(
    writer: anytype,
    escapes: anytype,
    param: clap.Param(clap.Help),
    value: anytype,
    comptime value_fmt: []const u8,
) !void {
    const prefix = if (param.names.long) |_| "--" else "-";
    const name = param.names.long orelse @as(*const [1]u8, &param.names.short.?)[0..];
    try escapes.escapePrint(writer, "{s}{s}={" ++ value_fmt ++ "}", .{
        prefix,
        name,
        value,
    });
}

fn toUserfriendly(human_out: []u8, programmer_in: []const u8) []u8 {
    debug.assert(programmer_in.len <= human_out.len);

    const suffixes = [_][]const u8{};
    const prefixes = [_][]const u8{"tm35-"};

    var trimmed = programmer_in;
    for (prefixes) |prefix| {
        if (mem.startsWith(u8, trimmed, prefix)) {
            trimmed = trimmed[prefix.len..];
            break;
        }
    }
    for (suffixes) |suffix| {
        if (mem.endsWith(u8, trimmed, suffix)) {
            trimmed = trimmed[0 .. trimmed.len - suffix.len];
            break;
        }
    }

    trimmed = mem.trim(u8, trimmed[0..trimmed.len], " \t");
    const result = human_out[0..trimmed.len];
    mem.copy(u8, result, trimmed);
    for (result) |*char| switch (char.*) {
        '-', '_' => char.* = ' ',
        else => {},
    };
    if (result.len != 0)
        result[0] = std.ascii.toUpper(result[0]);

    human_out[result.len] = 0;
    return result;
}
