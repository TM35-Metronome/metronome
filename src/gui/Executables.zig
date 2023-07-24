const builtin = @import("builtin");
const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const json = std.json;
const math = std.math;
const mem = std.mem;
const process = std.process;

const Executables = @This();

arena: heap.ArenaAllocator,
load: util.Path = util.Path{},
apply: util.Path = util.Path{},
identify: util.Path = util.Path{},
commands: []const Command = &[_]Command{},

pub const Command = struct {
    path: []const u8,
    help: []const u8,

    flags: []const Flag,
    ints: []const Int,
    floats: []const Float,
    enums: []const Enum,
    multi_strings: []const MultiString,
    params: []const clap.Param(clap.Help),

    const Flag = struct {
        i: usize,
    };

    const Int = struct {
        i: usize,
        default: usize,
    };

    const Float = struct {
        i: usize,
        default: f64,
    };

    const Enum = struct {
        i: usize,
        options: []const []const u8,
        default: usize,
    };

    const MultiString = struct {
        i: usize,
    };

    pub fn name(command: Command) []const u8 {
        return util.path.basenameNoExt(command.path);
    }
};

pub const program_name = "tm35-randomizer";
const extension = switch (builtin.target.os.tag) {
    .linux => "",
    .windows => ".exe",
    else => @compileError("Unsupported os"),
};
const command_file_name = "commands.json";
const default_commands = [_][]const u8{
    "tm35-balance-pokemons" ++ extension,
    "tm35-generate-site" ++ extension,
    "tm35-misc" ++ extension,
    "tm35-no-trade-evolutions" ++ extension,
    "tm35-randomize-field-items" ++ extension,
    "tm35-randomize-machines" ++ extension,
    "tm35-randomize-names" ++ extension,
    "tm35-randomize-pokemons" ++ extension,
    "tm35-randomize-starters" ++ extension,
    "tm35-randomize-static-encounters" ++ extension,
    "tm35-randomize-trainers" ++ extension,
    "tm35-randomize-wild-encounters" ++ extension,
    "tm35-random-stones" ++ extension,
};

pub fn deinit(exes: Executables) void {
    exes.arena.deinit();
}

pub fn findByName(exes: Executables, name: []const u8) ?*const Executables.Command {
    for (exes.commands) |*command| {
        if (mem.eql(u8, command.name(), name))
            return command;
    }

    return null;
}

pub fn find(allocator: mem.Allocator) !Executables {
    var arena = heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var tmp_arena = heap.ArenaAllocator.init(allocator);
    defer tmp_arena.deinit();

    var res = Executables{
        .arena = undefined,
        .load = findCore("tm35-load" ++ extension) catch
            return error.LoadToolNotFound,
        .apply = findCore("tm35-apply" ++ extension) catch
            return error.ApplyToolNotFound,
        .identify = findCore("tm35-identify" ++ extension) catch
            return error.IdentifyToolNotFound,
        .commands = try findCommands(&arena, &tmp_arena),
    };
    res.arena = arena;
    return res;
}

fn findCore(tool: []const u8) !util.Path {
    const self_exe_dir = (try util.dir.selfExeDir()).slice();

    return joinAccess(&[_][]const u8{ self_exe_dir, "core", tool }) catch
        joinAccess(&[_][]const u8{ self_exe_dir, tool }) catch
        try findInPath(tool);
}

const path_env_seperator = switch (builtin.target.os.tag) {
    .linux => ":",
    .windows => ";",
    else => @compileError("Unsupported os"),
};
const path_env_name = switch (builtin.target.os.tag) {
    .linux => "PATH",
    .windows => "Path",
    else => @compileError("Unsupported os"),
};

fn findInPath(name: []const u8) !util.Path {
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);
    const path_env = try process.getEnvVarOwned(fba.allocator(), path_env_name);

    var iter = mem.tokenize(u8, path_env, path_env_seperator);
    while (iter.next()) |dir|
        return joinAccess(&[_][]const u8{ dir, name }) catch continue;

    return error.NotInPath;
}

fn joinAccess(paths: []const []const u8) !util.Path {
    const res = util.path.join(paths);
    try fs.cwd().access(res.constSlice(), .{});
    return res;
}

fn findCommands(arena: *heap.ArenaAllocator, tmp_arena: *heap.ArenaAllocator) ![]Command {
    const command_file = try openCommandFile();
    defer command_file.close();

    const content = try command_file.readToEndAlloc(tmp_arena.allocator(), math.maxInt(usize));

    const strings = try json.parseFromSlice([]const []const u8, tmp_arena.allocator(), content, .{});
    var res = std.ArrayList(Command).init(arena.allocator());
    for (strings.value) |string| {
        if (fs.path.isAbsolute(string)) {
            const command = pathToCommand(arena, string) catch continue;
            try res.append(command);
        } else {
            const command_path = findCommand(string) catch continue;
            const command = pathToCommand(arena, command_path.constSlice()) catch continue;
            try res.append(command);
        }
    }

    return res.toOwnedSlice();
}

const Allocators = struct {
    temp: mem.Allocator,
    res: mem.Allocator,
};

fn findCommand(name: []const u8) !util.Path {
    const self_exe_dir = (try util.dir.selfExeDir()).slice();
    const config_dir = (try util.dir.folder(.local_configuration)).slice();
    const cwd = (try util.dir.cwd()).slice();
    return joinAccess(&[_][]const u8{ cwd, name }) catch
        joinAccess(&[_][]const u8{ config_dir, program_name, name }) catch
        joinAccess(&[_][]const u8{ self_exe_dir, "randomizers", name }) catch
        joinAccess(&[_][]const u8{ self_exe_dir, name }) catch
        try findInPath(name);
}

fn openCommandFile() !fs.File {
    const cwd = fs.cwd();
    const config_dir = (try util.dir.folder(.local_configuration)).slice();
    const command_path = util.path.join(&[_][]const u8{
        config_dir,
        program_name,
        command_file_name,
    }).slice();

    // TODO: When we want to enable plugin support, re-add this
    //if (cwd.openFile(command_path, .{})) |file| {
    //    return file;
    //} else |_|
    {
        const dirname = fs.path.dirname(command_path) orelse ".";
        try cwd.makePath(dirname);

        {
            const file = try cwd.createFile(command_path, .{});
            defer file.close();

            var buffered = std.io.bufferedWriter(file.writer());
            try std.json.stringify(&default_commands, .{ .whitespace = .indent_4 }, buffered.writer());
            try buffered.flush();
        }

        return cwd.openFile(command_path, .{});
    }
}

fn pathToCommand(arena: *heap.ArenaAllocator, command_path: []const u8) !Command {
    const help = try execHelp(arena.allocator(), command_path);
    var flags = std.ArrayList(Command.Flag).init(arena.allocator());
    var ints = std.ArrayList(Command.Int).init(arena.allocator());
    var floats = std.ArrayList(Command.Float).init(arena.allocator());
    var enums = std.ArrayList(Command.Enum).init(arena.allocator());
    var multi_strings = std.ArrayList(Command.MultiString).init(arena.allocator());
    var params = std.ArrayList(clap.Param(clap.Help)).init(arena.allocator());

    const options_start_str = "Options:\n";
    var help_index = if (mem.indexOf(u8, help, options_start_str)) |i|
        i + options_start_str.len
    else
        0;

    while (help_index != help.len) {
        var end_of_this: usize = undefined;
        defer help_index += end_of_this;
        const param = clap.parseParamEx(help[help_index..], &end_of_this) catch continue;

        if (param.names.long == null and param.names.short == null)
            continue;
        if (mem.eql(u8, param.names.long orelse "", "help"))
            continue;
        if (mem.eql(u8, param.names.long orelse "", "version"))
            continue;
        if (mem.eql(u8, param.names.long orelse "", "seed"))
            continue;

        const i = params.items.len;
        try params.append(param);
        switch (param.takes_value) {
            .none => try flags.append(.{ .i = i }),
            .one => if (mem.eql(u8, param.id.value(), "BOOL")) {
                try flags.append(.{ .i = i });
            } else if (mem.eql(u8, param.id.value(), "INT")) {
                const default = if (findDefaultValue(param.id.description())) |v|
                    fmt.parseInt(usize, v, 10) catch 0
                else
                    0;

                try ints.append(.{ .i = i, .default = default });
            } else if (mem.eql(u8, param.id.value(), "FLOAT")) {
                const default = if (findDefaultValue(param.id.description())) |v|
                    fmt.parseFloat(f64, v) catch 0
                else
                    0;

                try floats.append(.{ .i = i, .default = default });
            } else if (mem.indexOfScalar(u8, param.id.value(), '|') != null) {
                var options = std.ArrayList([]const u8).init(arena.allocator());
                var options_it = mem.split(u8, param.id.value(), "|");
                while (options_it.next()) |option|
                    try options.append(option);

                const default = if (findDefaultValue(param.id.description())) |v| blk: {
                    for (options.items, 0..) |option, option_i| {
                        if (mem.eql(u8, option, v))
                            break :blk option_i;
                    }
                    break :blk 0;
                } else 0;

                try enums.append(.{
                    .i = i,
                    .options = try options.toOwnedSlice(),
                    .default = default,
                });
            },
            .many => {
                try multi_strings.append(.{ .i = i });
            },
        }
    }

    const lists = .{ flags, ints, floats, enums, multi_strings };
    comptime var i = 0;
    inline while (i < lists.len) : (i += 1) {
        const Item = @TypeOf(lists[i].items[0]);
        mem.sort(Item, lists[i].items, params.items, comptime lessThanByName(Item));
    }

    return Command{
        .path = try arena.allocator().dupe(u8, command_path),
        .help = help,
        .flags = try flags.toOwnedSlice(),
        .ints = try ints.toOwnedSlice(),
        .floats = try floats.toOwnedSlice(),
        .enums = try enums.toOwnedSlice(),
        .multi_strings = try multi_strings.toOwnedSlice(),
        .params = try params.toOwnedSlice(),
    };
}

fn lessThanByName(comptime T: type) fn ([]const clap.Param(clap.Help), T, T) bool {
    return struct {
        fn lessThan(params: []const clap.Param(clap.Help), a: T, b: T) bool {
            const a_names = params[a.i].names;
            const b_names = params[b.i].names;
            const a_text = a_names.long orelse @as(*const [1]u8, &a_names.short.?)[0..];
            const b_text = b_names.long orelse @as(*const [1]u8, &b_names.short.?)[0..];
            return mem.lessThan(u8, a_text, b_text);
        }
    }.lessThan;
}

fn findDefaultValue(str: []const u8) ?[]const u8 {
    const prefix = "(default:";
    const start_with_prefix = mem.indexOf(u8, str, "(default:") orelse return null;
    const start = start_with_prefix + prefix.len;
    const len = mem.indexOf(u8, str[start..], ")") orelse return null;
    return mem.trim(u8, str[start..][0..len], " ");
}

fn execHelp(allocator: mem.Allocator, exe: []const u8) ![]u8 {
    var buf: [1024 * 40]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);

    const res = try std.ChildProcess.exec(.{
        .allocator = fba.allocator(),
        .argv = &[_][]const u8{ exe, "--help" },
    });
    switch (res.term) {
        .Exited => |status| if (status != 0) return error.ProcessFailed,
        else => return error.ProcessFailed,
    }

    return allocator.dupe(u8, res.stdout);
}
