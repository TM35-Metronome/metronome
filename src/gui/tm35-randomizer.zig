const build_options = @import("build_options");
const clap = @import("clap");
const nk = @import("nuklear.zig");
const std = @import("std");

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const process = std.process;
const time = std.time;

const c = nk.c;
const path = fs.path;

const fps = 60;
const frame_time = time.second / fps;
const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;

const border_group = nk.WINDOW_BORDER | nk.WINDOW_NO_SCROLLBAR;
const border_title_group = border_group | nk.WINDOW_TITLE;

pub fn main() u8 {
    const allocator = heap.c_allocator;

    var window = nk.Window.create(WINDOW_WIDTH, WINDOW_HEIGHT) catch |err| return errPrint("Could not create window: {}\n", err);
    defer window.destroy();

    const font = window.createFont(c"Arial");
    defer window.destroyFont(font);

    const ctx = nk.create(window, font) catch |err| return errPrint("Could not create nuklear context: {}\n", err);
    defer nk.destroy(ctx, window);

    var timer = time.Timer.start() catch |err| return errPrint("Could not create timer: {}\n", err);

    // TODO: This error should be shown in the GUI
    const exes = Exes.find(allocator) catch |err| return errPrint("Failed to find exes: {}\n", err);
    defer exes.deinit();

    outer: while (true) {
        timer.reset();

        c.nk_input_begin(ctx);
        while (window.nextEvent()) |event| {
            if (nk.isExitEvent(event))
                break :outer;

            nk.handleEvent(ctx, window, event);
        }
        c.nk_input_end(ctx);

        if (nk.begin(ctx, c"", nk.rect(0, 0, @intToFloat(f32, window.width), @intToFloat(f32, window.height)), 0)) {
            c.nk_layout_row_dynamic(ctx, 400, 1);
            var list_view: c.nk_list_view = undefined;
            if (c.nk_list_view_begin(ctx, &list_view, c"filter-list", 0, 20, @intCast(c_int, exes.filters.count())) != 0) {
                var filters = exes.filters.iterator();
                while (filters.next()) |kv| {
                    c.nk_layout_row_dynamic(ctx, 20, 1);
                    c.nk_text(ctx, kv.key.ptr, @intCast(c_int, kv.key.len), nk.NK_TEXT_LEFT);
                }
            }
            c.nk_list_view_end(&list_view);

            //c.nk_layout_row_template_begin(ctx, 400);
            //c.nk_layout_row_template_push_dynamic(ctx);
            //c.nk_layout_row_template_push_static(ctx, 200);
            //c.nk_layout_row_template_end(ctx);
            //
            //if (c.nk_group_begin(ctx, c"help-box", border_group) != 0) {
            //    c.nk_layout_row_dynamic(ctx, 0, 1);
            //    c.nk_group_end(ctx);
            //}
            //if (c.nk_group_begin(ctx, c"General", border_title_group) != 0) {
            //    c.nk_layout_row_dynamic(ctx, 0, 1);
            //    if (c.nk_button_label(ctx, c"Randomize Rom") != 0) {}
            //    c.nk_group_end(ctx);
            //}
        }
        c.nk_end(ctx);

        nk.render(ctx, window);
        time.sleep(math.sub(u64, frame_time, timer.read()) catch 0);
    }

    return 0;
}

fn errPrint(comptime format_str: []const u8, args: ...) u8 {
    debug.warn(format_str, args);
    return 1;
}

fn rowMinHeight(ctx: *const c.struct_nk_context) f32 {
    return ctx.current.*.layout.*.row.min_height + ctx.style.window.spacing.y;
}

fn groupSize(ctx: *const c.struct_nk_context) f32 {
    return headerHeight(ctx) + ctx.style.window.group_padding.y + ctx.style.window.spacing.y;
}

fn headerHeight(ctx: *const c.struct_nk_context) f32 {
    return ctx.style.font.*.height +
        (ctx.style.window.header.padding.y * 2) +
        (ctx.style.window.header.label_padding.y * 2) + 1;
}

const Exes = struct {
    allocator: *mem.Allocator,
    load: []const u8,
    apply: []const u8,
    filters: Filters,

    const Filters = std.HashMap([]const u8, Filter, mem.hash_slice_u8, mem.eql_slice_u8);

    const Filter = struct {
        call: bool,
        path: []const u8,
        help: []const u8,
        params: []const clap.Param(clap.Help),
    };

    fn deinit(exes: Exes) void {
        exes.allocator.free(exes.load);
        exes.allocator.free(exes.apply);
        freeFilters(exes.allocator, exes.filters);
    }

    fn find(allocator: *mem.Allocator) !Exes {
        var self_exe_dir_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
        const self_exe_path = try fs.selfExePath(&self_exe_dir_buf);
        const self_exe = path.basename(self_exe_path);
        const self_exe_dir = path.dirname(self_exe_path).?;

        var cwd_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
        const cwd = try process.getCwd(&cwd_buf);
        var env_map = try process.getEnvMap(allocator);
        defer env_map.deinit();

        const load_tool = findCore(allocator, self_exe_dir, "tm35-load", cwd, &env_map) catch return error.LoadToolNotFound;
        errdefer allocator.free(load_tool);

        const apply_tool = findCore(allocator, self_exe_dir, "tm35-apply", cwd, &env_map) catch return error.ApplyToolNotFound;
        errdefer allocator.free(apply_tool);

        const filters = try findFilters(allocator, self_exe, self_exe_dir, cwd, &env_map);
        errdefer freeFilters(filters);

        return Exes{
            .allocator = allocator,
            .load = load_tool,
            .apply = apply_tool,
            .filters = filters,
        };
    }

    fn findCore(allocator: *mem.Allocator, self_exe_dir: []const u8, tool: []const u8, cwd: []const u8, env_map: *const std.BufMap) ![]u8 {
        var fs_tmp: [fs.MAX_PATH_BYTES]u8 = undefined;

        if (join(&fs_tmp, [_][]const u8{ self_exe_dir, "core", tool })) |in_core| {
            if (execHelpCheckSuccess(in_core, cwd, env_map)) {
                return mem.dupe(allocator, u8, in_core);
            } else |_| {}
        } else |_| {}

        if (join(&fs_tmp, [_][]const u8{ self_exe_dir, tool })) |in_self_exe_dir| {
            if (execHelpCheckSuccess(in_self_exe_dir, cwd, env_map)) {
                return mem.dupe(allocator, u8, in_self_exe_dir);
            } else |_| {}
        } else |_| {}

        // Try exe as if it was in PATH
        if (execHelpCheckSuccess(tool, cwd, env_map)) {
            return mem.dupe(allocator, u8, tool);
        } else |_| {}

        return error.CoreToolNotFound;
    }

    fn findFilters(allocator: *mem.Allocator, self_exe: []const u8, self_exe_dir: []const u8, cwd: []const u8, env_map: *const std.BufMap) !Filters {
        var res = Filters.init(allocator);
        errdefer freeFilters(allocator, res);

        // HACK: We put our own exe in as a blacklist to avoid running our self infinite times
        try res.putNoClobber(self_exe, undefined);
        errdefer _ = res.remove(self_exe);

        // Try to find filters is "$SELF_EXE_PATH/filter" and "$SELF_EXE_PATH/"
        var fs_tmp: [fs.MAX_PATH_BYTES]u8 = undefined;
        if (join(&fs_tmp, [_][]const u8{ self_exe_dir, "filter" })) |self_filter_dir| {
            findFiltersIn(&res, allocator, self_filter_dir, cwd, env_map) catch {};
        } else |_| {}

        findFiltersIn(&res, allocator, self_exe_dir, cwd, env_map) catch {};

        // Try to find filters from "$PATH"
        const path_split = if (std.os.windows.is_the_target) ";" else ":";
        const path_list = env_map.get("PATH") orelse "";

        var it = mem.separate(path_list, path_split);
        while (it.next()) |dir|
            findFiltersIn(&res, allocator, dir, cwd, env_map) catch {};

        _ = res.remove(self_exe);
        return res;
    }

    fn findFiltersIn(filters: *Filters, allocator: *mem.Allocator, dir: []const u8, cwd: []const u8, env_map: *const std.BufMap) !void {
        var open_dir = try fs.Dir.open(allocator, dir);
        defer open_dir.close();

        var fs_tmp: [fs.MAX_PATH_BYTES]u8 = undefined;
        while (try open_dir.next()) |entry| {
            if (entry.kind != .File)
                continue;
            if (!mem.startsWith(u8, entry.name, "tm35-"))
                continue;
            if (filters.contains(entry.name))
                continue;

            const path_to_exe = join(&fs_tmp, [_][]const u8{ dir, entry.name }) catch continue;
            const filter = pathToFilter(allocator, path_to_exe, cwd, env_map) catch continue;

            const duped_entry = try mem.dupe(allocator, u8, entry.name);
            errdefer allocator.free(duped_entry);

            try filters.putNoClobber(duped_entry, filter);
        }
    }

    fn pathToFilter(allocator: *mem.Allocator, filter_path: []const u8, cwd: []const u8, env_map: *const std.BufMap) !Filter {
        try checkTm35Tool(filter_path, cwd, env_map);
        const help = try execHelp(allocator, filter_path, cwd, env_map);
        errdefer allocator.free(help);

                var params = std.ArrayList(clap.Param(clap.Help)).init(allocator);
                errdefer params.deinit();

                var it = mem.separate(help, "\n");
                while (it.next()) |line| {
                    const param = clap.parseParam(line) catch continue;
                    try params.append(param);
                }

                return Filter{
                    .path = try mem.dupe(allocator, u8, filter_path),
                    .help = help,
                    .params = params.toOwnedSlice(),
                };
    }

    fn freeFilters(allocator: *mem.Allocator, filters: Filters) void {
        var it = filters.iterator();
        while (it.next()) |kv| {
            allocator.free(kv.value.path);
            allocator.free(kv.value.help);
            allocator.free(kv.value.params);
            allocator.free(kv.key);
        }
        filters.deinit();
    }

    fn checkTm35Tool(exe: []const u8, cwd: []const u8, env_map: *const std.BufMap) !void {
        var buf: [1024 * 4]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(&buf);

        var p = try std.ChildProcess.init([_][]const u8{exe}, &fba.allocator);
        defer p.deinit();

        p.stdin_behavior = std.ChildProcess.StdIo.Pipe;
        p.stdout_behavior = std.ChildProcess.StdIo.Pipe;
        p.stderr_behavior = std.ChildProcess.StdIo.Ignore;
        p.cwd = cwd;
        p.env_map = env_map;

        try p.spawn();
        defer _ = p.kill() catch undefined;

        try p.stdin.?.write(".this.is.a[0].dummy=Line\n");
        p.stdin.?.close();
        p.stdin = null;

        var response_buf: [1024]u8 = undefined;
        const response_len = try p.stdout.?.inStream().stream.readFull(&response_buf);
        const response = response_buf[0..response_len];
        if (!mem.startsWith(u8, response, ".this.is.a[0].dummy="))
            return error.NoTm35Filter;
    }

    fn execHelpCheckSuccess(exe: []const u8, cwd: []const u8, env_map: *const std.BufMap) !void {
        var buf: [1024 * 4]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(&buf);

        var p = try std.ChildProcess.init([_][]const u8{ exe, "--help" }, &fba.allocator);
        defer p.deinit();

        p.stdin_behavior = std.ChildProcess.StdIo.Ignore;
        p.stdout_behavior = std.ChildProcess.StdIo.Ignore;
        p.stderr_behavior = std.ChildProcess.StdIo.Ignore;
        p.cwd = cwd;
        p.env_map = env_map;

        const res = try p.spawnAndWait();
        switch (res) {
            .Exited => |status| if (status != 0) return error.ProcessFailed,
            else => return error.ProcessFailed,
        }
    }

    fn execHelp(allocator: *mem.Allocator, exe: []const u8, cwd: []const u8, env_map: *const std.BufMap) ![]u8 {
        var buf: [1024 * 4]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(&buf);

        var p = try std.ChildProcess.init([_][]const u8{ exe, "--help" }, &fba.allocator);
        defer p.deinit();

        p.stdin_behavior = std.ChildProcess.StdIo.Ignore;
        p.stdout_behavior = std.ChildProcess.StdIo.Pipe;
        p.stderr_behavior = std.ChildProcess.StdIo.Ignore;
        p.cwd = cwd;
        p.env_map = env_map;

        try p.spawn();
        errdefer _ = p.kill() catch undefined;

        const help = try p.stdout.?.inStream().stream.readAllAlloc(allocator, 1024 * 1024);

        const res = try p.wait();
        switch (res) {
            .Exited => |status| if (status != 0) return error.ProcessFailed,
            else => return error.ProcessFailed,
        }

        return help;
    }

    fn join(buf: *[fs.MAX_PATH_BYTES]u8, paths: []const []const u8) ![]u8 {
        var fba = heap.FixedBufferAllocator.init(buf);
        return path.join(&fba.allocator, paths);
    }
};
