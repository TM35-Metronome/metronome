const build_options = @import("build_options");
const builtin = @import("builtin");
const clap = @import("clap");
const nk = @import("nuklear.zig");
const std = @import("std");
const util = @import("util");

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

const readLine = @import("readline").readLine;

const fps = 60;
const frame_time = time.second / fps;
const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;

const border_group = nk.WINDOW_BORDER | nk.WINDOW_NO_SCROLLBAR;
const border_title_group = border_group | nk.WINDOW_TITLE;

pub fn main() u8 {
    const font_name = c"Arial";
    const allocator = heap.c_allocator;

    // Set up essetial state for the program to run. If any of these
    // fail, the only thing we can do is exit.
    const stderr = std.io.getStdErr() catch |err| return errPrint("Unable to get stderr: {}\n", err);
    var timer = time.Timer.start() catch |err| return errPrint("Could not create timer: {}\n", err);

    var window = nk.Window.create(WINDOW_WIDTH, WINDOW_HEIGHT) catch |err| return errPrint("Could not create window: {}\n", err);
    defer window.destroy();

    const font = window.createFont(font_name);
    defer window.destroyFont(font);

    const ctx = nk.create(window, font) catch |err| return errPrint("Could not create nuklear context: {}\n", err);
    defer nk.destroy(ctx, window);

    // From this point on, we can report errors to the user. This is done
    // with this 'Errors' struct. If an error occures, it should be appended
    // with 'errors.append("error str {}", arg1, arg2...)'.
    // It is also possible to report a fatal error with
    // 'errors.fatal("error str {}", arg1, arg2...)'. A fatal error means, that
    // the only way to recover is to exit. This error is reported to the user,
    // after which the only option they have is to quit the program.
    var errors = Errors{ .list = std.ArrayList([]const u8).init(allocator) };
    defer errors.deinit();

    const exes = Exes.find(allocator) catch |err| blk: {
        errors.append("Failed to find exes: {}", err);
        break :blk Exes{ .allocator = allocator };
    };
    defer exes.deinit();

    const settings = Settings.init(allocator, exes) catch |err| blk: {
        errors.append("Failed to create settings: {}", err);
        break :blk Settings{ .allocator = allocator };
    };
    defer settings.deinit();

    const FileBrowserKind = enum {
        LoadRom,
        Randomize,
        LoadSettings,
        SaveSettings,
    };

    var in: ?util.Path = null;
    var out: ?util.Path = null;
    var file_browser_kind: FileBrowserKind = undefined; // This should always be written to before read from
    var file_browser_dir = util.dir.cwd() catch
        util.dir.home() catch
        util.dir.selfExeDir() catch blk: {
        errors.fatal("Could not find a directory to start the file browser in.");
        break :blk util.Path{};
    };
    var file_browser: ?nk.FileBrowser = null;
    defer if (file_browser) |fb| fb.close();

    var selected: usize = 0;
    while (true) {
        timer.reset();

        {
            c.nk_input_begin(ctx);
            defer c.nk_input_end(ctx);
            while (window.nextEvent()) |event| {
                if (nk.isExitEvent(event))
                    return 0;

                nk.handleEvent(ctx, window, event);
            }
        }

        const window_rect = nk.rect(0, 0, @intToFloat(f32, window.width), @intToFloat(f32, window.height));

        if (nk.begin(ctx, c"", window_rect, nk.WINDOW_NO_SCROLLBAR)) ui_end: {
            const layout = ctx.current.*.layout;
            const min_height = layout.*.row.min_height;

            var total_space: c.struct_nk_rect = undefined;
            c.nkWindowGetContentRegion(ctx, &total_space);

            // If file_browser isn't null, then we are promting the user for a file,
            // so we just draw the file browser instead of our normal UI.
            if (file_browser) |*fb| {
                if (nk.fileBrowser(ctx, fb, total_space.h)) |pressed| {
                    switch (pressed) {
                        .Confirm => err_blk: {
                            const selected_path = util.path.join([_][]const u8{
                                fb.curr_dir.toSliceConst(),
                                fb.selected_file.toSliceConst(),
                            }) catch {
                                errors.append("Path '{}/{}' is to long", fb.curr_dir.toSliceConst(), fb.selected_file.toSliceConst());
                                break :err_blk;
                            };
                            switch (file_browser_kind) {
                                .LoadRom => in = selected_path,
                                .Randomize => {
                                    // in should never be null here, because "Randomize"
                                    const in_path = in.?.toSliceConst();
                                    const out_path = selected_path.toSliceConst();
                                    outputScript(&stderr.outStream().stream, exes, settings, in_path, out_path) catch {};
                                    stderr.write("\n") catch {};
                                    randomize(exes, settings, in_path, out_path) catch |err| {
                                        // TODO: Maybe print the stderr from the command we run in the randomizer function
                                        errors.append("Failed to randomize '{}': {}", in_path, err);
                                        break :err_blk;
                                    };
                                    // TODO: Print a done message?
                                },
                                .LoadSettings => {
                                    const file = fs.File.openRead(selected_path.toSliceConst()) catch |err| {
                                        errors.append("Could not open '{}': {}", selected_path.toSliceConst(), err);
                                        break :err_blk;
                                    };
                                    defer file.close();
                                    settings.load(exes, &file.inStream().stream) catch |err| {
                                        errors.append("Failed to load from '{}': {}", selected_path.toSliceConst(), err);
                                        break :err_blk;
                                    };
                                },
                                .SaveSettings => {
                                    // TODO: Warn if the user tries to overwrite existing file.
                                    const file = fs.File.openWrite(selected_path.toSliceConst()) catch |err| {
                                        errors.append("Could not open '{}': {}", selected_path.toSliceConst(), err);
                                        break :err_blk;
                                    };
                                    defer file.close();
                                    settings.save(exes, &file.outStream().stream) catch |err| {
                                        errors.append("Failed to write to '{}': {}", selected_path.toSliceConst(), err);
                                        break :err_blk;
                                    };
                                },
                            }
                        },
                        .Cancel => {},
                    }

                    file_browser_dir = fb.curr_dir;
                    fb.close();
                    file_browser = null;
                }
            } else {
                const group_height = total_space.h - ctx.style.window.padding.y * 2;
                const inner_height = group_height - groupOuterHeight(ctx);
                c.nk_layout_row_template_begin(ctx, group_height);
                c.nk_layout_row_template_push_static(ctx, 300);
                c.nk_layout_row_template_push_dynamic(ctx);
                c.nk_layout_row_template_push_static(ctx, 180);
                c.nk_layout_row_template_end(ctx);

                // +---------------------------+
                // | Filters                   |
                // +---------------------------+
                // | +-+ +-------------------+ |
                // | |^| | # tm35-rand-stats | |
                // | +-+ | # tm35-rand-wild  | |
                // | +-+ |                   | |
                // | |V| |                   | |
                // | +-+ |                   | |
                // |     +-------------------+ |
                // +---------------------------+
                if (c.nk_group_begin(ctx, c"Filters", border_title_group) != 0) {
                    defer c.nk_group_end(ctx);
                    c.nk_layout_row_template_begin(ctx, inner_height);
                    c.nk_layout_row_template_push_static(ctx, min_height);
                    c.nk_layout_row_template_push_dynamic(ctx);
                    c.nk_layout_row_template_end(ctx);

                    if (nk.nonPaddedGroupBegin(ctx, c"filter-buttons", nk.WINDOW_NO_SCROLLBAR)) {
                        defer nk.nonPaddedGroupEnd(ctx);
                        c.nk_layout_row_dynamic(ctx, 0, 1);
                        if (c.nk_button_symbol(ctx, c.NK_SYMBOL_TRIANGLE_UP) != 0) {
                            const before = math.sub(usize, selected, 1) catch 0;
                            mem.swap(usize, &settings.order[before], &settings.order[selected]);
                            selected = before;
                        }
                        if (c.nk_button_symbol(ctx, c.NK_SYMBOL_TRIANGLE_DOWN) != 0) {
                            const after = math.min(selected + 1, math.sub(usize, settings.order.len, 1) catch 0);
                            mem.swap(usize, &settings.order[selected], &settings.order[after]);
                            selected = after;
                        }
                    }

                    var list_view: c.nk_list_view = undefined;
                    if (c.nk_list_view_begin(ctx, &list_view, c"filter-list", nk.WINDOW_BORDER, 0, @intCast(c_int, exes.filters.len)) != 0) {
                        defer c.nk_list_view_end(&list_view);
                        for (settings.order) |filter_i, i| {
                            const filter = exes.filters[filter_i];
                            if (i < @intCast(usize, list_view.begin))
                                continue;
                            if (@intCast(usize, list_view.end) <= i)
                                break;

                            c.nk_layout_row_template_begin(ctx, 0);
                            c.nk_layout_row_template_push_static(ctx, ctx.style.font.*.height);
                            c.nk_layout_row_template_push_dynamic(ctx);
                            c.nk_layout_row_template_end(ctx);

                            const name = path.basename(filter.path)[5..];
                            settings.checks[filter_i] = c.nk_check_label(ctx, c"", @boolToInt(settings.checks[filter_i])) != 0;
                            if (c.nk_select_text(ctx, name.ptr, @intCast(c_int, name.len), nk.TEXT_LEFT, @boolToInt(i == selected)) != 0)
                                selected = i;
                        }
                    }
                }

                // +---------------------------+
                // | Options                   |
                // +---------------------------+
                // | This is the help message  |
                // | # flag-a                  |
                // | # flag-b                  |
                // | drop-down |            V| |
                // | field-a   |             | |
                // | field-b   |             | |
                // |                           |
                // +---------------------------+
                if (c.nk_group_begin(ctx, c"Options", border_title_group) != 0) blk: {
                    defer c.nk_group_end(ctx);
                    if (exes.filters.len == 0)
                        break :blk;

                    const filter = exes.filters[settings.order[selected]];
                    var it = mem.separate(filter.help, "\n");
                    while (it.next()) |line_notrim| {
                        const line = mem.trimRight(u8, line_notrim, " ");
                        if (line.len == 0)
                            continue;
                        if (mem.startsWith(u8, line, "Usage:"))
                            continue;
                        if (mem.startsWith(u8, line, "Options:"))
                            continue;
                        if (mem.startsWith(u8, line, " "))
                            continue;
                        if (mem.startsWith(u8, line, "\t"))
                            continue;

                        c.nk_layout_row_dynamic(ctx, 0, 1);
                        c.nk_text(ctx, line.ptr, @intCast(c_int, line.len), nk.TEXT_LEFT);
                    }

                    var biggest_len: f32 = 0;
                    for (filter.params) |param, i| {
                        const text = param.names.long orelse (*const [1]u8)(&param.names.short.?)[0..];
                        if (!param.takes_value)
                            continue;
                        if (mem.eql(u8, text, "help"))
                            continue;
                        if (mem.eql(u8, text, "version"))
                            continue;

                        const style_font = ctx.style.font;
                        const text_len = style_font.*.width.?(style_font.*.userdata, 0, text.ptr, @intCast(c_int, text.len));
                        if (biggest_len < text_len)
                            biggest_len = text_len;
                    }

                    for (filter.params) |param, i| {
                        const buf = &settings.filters_bufs[settings.order[selected]][i];
                        const arg = &settings.filters_args[settings.order[selected]][i];
                        const help = param.id.msg;
                        const value = param.id.value;
                        const text = param.names.long orelse (*const [1]u8)(&param.names.short.?)[0..];
                        var bounds: c.struct_nk_rect = undefined;
                        if (mem.eql(u8, text, "help"))
                            continue;
                        if (mem.eql(u8, text, "version"))
                            continue;

                        if (!param.takes_value) {
                            c.nk_layout_row_dynamic(ctx, 0, 1);

                            c.nkWidgetBounds(ctx, &bounds);
                            if (c.nkInputIsMouseHoveringRect(&ctx.input, &bounds) != 0)
                                c.nk_tooltip_text(ctx, help.ptr, @intCast(c_int, help.len));

                            // For flags, we only care about whether it's checked or not. We indicate this
                            // by having a slice of len 1 instead of 0.
                            const checked = c.nk_check_text(ctx, text.ptr, @intCast(c_int, text.len), @boolToInt(arg.len != 0)) != 0;
                            arg.* = buf[0..@boolToInt(checked)];
                            continue;
                        }

                        const style_font = ctx.style.font;
                        const prompt_len = style_font.*.width.?(style_font.*.userdata, 0, &("a" ** 30), 30);
                        c.nk_layout_row_template_begin(ctx, 0);
                        c.nk_layout_row_template_push_static(ctx, biggest_len);
                        c.nk_layout_row_template_push_static(ctx, prompt_len);
                        c.nk_layout_row_template_push_dynamic(ctx);
                        c.nk_layout_row_template_end(ctx);

                        c.nkWidgetBounds(ctx, &bounds);
                        if (c.nkInputIsMouseHoveringRect(&ctx.input, &bounds) != 0)
                            c.nk_tooltip_text(ctx, help.ptr, @intCast(c_int, help.len));

                        c.nk_text(ctx, text.ptr, @intCast(c_int, text.len), nk.TEXT_LEFT);

                        if (mem.eql(u8, value, "NUM")) {
                            // It is only safe to pass arg.ptr to nk_edit_string if it is actually pointing into buf.
                            debug.assert(@ptrToInt(arg.ptr) == @ptrToInt(buf));
                            _ = c.nk_edit_string(ctx, nk.EDIT_SIMPLE, buf, @ptrCast(*c_int, &arg.len), buf.len, c.nk_filter_decimal);
                            continue;
                        }
                        if (mem.indexOfScalar(u8, value, '|')) |_| {
                            if (c.nkComboBeginText(ctx, arg.ptr, @intCast(c_int, arg.len), &nk.vec2(prompt_len, 500)) != 0) {
                                c.nk_layout_row_dynamic(ctx, 0, 1);
                                if (c.nk_combo_item_label(ctx, c"", nk.TEXT_LEFT) != 0)
                                    arg.* = buf[0..0];

                                var item_it = mem.separate(value, "|");
                                while (item_it.next()) |item| {
                                    if (c.nk_combo_item_text(ctx, item.ptr, @intCast(c_int, item.len), nk.TEXT_LEFT) != 0)
                                        arg.* = item;
                                }
                                c.nk_combo_end(ctx);
                            }
                            continue;
                        }

                        // It is only safe to pass arg.ptr to nk_edit_string if it is actually pointing into buf.
                        debug.assert(@ptrToInt(arg.ptr) == @ptrToInt(buf));
                        _ = c.nk_edit_string(ctx, nk.EDIT_SIMPLE, buf, @ptrCast(*c_int, &arg.len), buf.len, c.nk_filter_default);
                    }
                }

                // +-------------------+
                // | Actions           |
                // +-------------------+
                // | +---+ +---------+ |
                // | | f | | in.nds  | |
                // | +---+ +---------+ |
                // | +---------------+ |
                // | |   Randomize   | |
                // | +---------------+ |
                // | +---------------+ |
                // | | Load Settings | |
                // | +---------------+ |
                // | +---------------+ |
                // | | Save Settings | |
                // | +---------------+ |
                // +-------------------+
                if (c.nk_group_begin(ctx, c"Actions", border_title_group) != 0) {
                    defer c.nk_group_end(ctx);
                    c.nk_layout_row_template_begin(ctx, 0);
                    c.nk_layout_row_template_push_static(ctx, min_height);
                    c.nk_layout_row_template_push_dynamic(ctx);
                    c.nk_layout_row_template_end(ctx);

                    var open_file_browser: bool = false;

                    // TODO: Draw folder icon
                    if (c.nk_button_symbol(ctx, c.NK_SYMBOL_PLUS) != 0) {
                        open_file_browser = true;
                        file_browser_kind = .LoadRom;
                    }

                    const in_slice = if (in) |*i| i.toSliceConst() else " ";
                    var basename = path.basename(in_slice);
                    _ = c.nk_edit_string(
                        ctx,
                        nk.EDIT_READ_ONLY,
                        // with edit_string being READ_ONLY always, it should be safe to cast away const
                        @intToPtr([*]u8, @ptrToInt(basename.ptr)),
                        @ptrCast(*c_int, &basename.len),
                        @intCast(c_int, basename.len + 1),
                        c.nk_filter_default,
                    );

                    c.nk_layout_row_dynamic(ctx, 0, 1);
                    if (in != null) {
                        if (c.nk_button_label(ctx, c"Randomize") != 0) {
                            open_file_browser = true;
                            file_browser_kind = .Randomize;
                        }
                    } else {
                        _ = nk.inactiveButton(ctx, "Randomize");
                    }
                    if (c.nk_button_label(ctx, c"Load settings") != 0) {
                        open_file_browser = true;
                        file_browser_kind = .LoadSettings;
                    }
                    if (c.nk_button_label(ctx, c"Save settings") != 0) {
                        open_file_browser = true;
                        file_browser_kind = .SaveSettings;
                    }

                    if (open_file_browser) {
                        const mode = switch (file_browser_kind) {
                            .Randomize, .SaveSettings => nk.FileBrowser.Mode.Save,
                            .LoadSettings, .LoadRom => nk.FileBrowser.Mode.OpenOne,
                        };
                        if (nk.FileBrowser.open(allocator, mode, file_browser_dir.toSliceConst())) |fb| {
                            file_browser = fb;
                        } else |err| {
                            errors.append("Could not open file browser: {}", err);
                        }
                    }
                }
            }

            // +-------------------+
            // | Error             |
            // +-------------------+
            // | This is an error  |
            // |          +------+ |
            // |          |  Ok  | |
            // |          +------+ |
            // +-------------------+
            const w: f32 = 350;
            const h: f32 = 150;
            const x = (@intToFloat(f32, window.width) / 2) - (w / 2);
            const y = (@intToFloat(f32, window.height) / 2) - (h / 2);
            const popup_rect = nk.rect(x, y, w, h);
            const fatal = errors.fatalError();
            if (fatal != null or errors.list.len != 0) {
                const title = if (fatal) |_| c"Fatal error!" else c"Error";
                if (c.nkPopupBegin(ctx, c.NK_POPUP_STATIC, title, border_title_group, &popup_rect) != 0) {
                    defer c.nk_popup_end(ctx);
                    const err = fatal orelse errors.list.at(errors.list.len - 1);

                    const padding_height = groupOuterHeight(ctx);
                    const buttons_height = ctx.style.window.spacing.y +
                        min_height;
                    const err_height = h - (padding_height + buttons_height);

                    c.nk_layout_row_dynamic(ctx, err_height, 1);
                    c.nk_text_wrap(ctx, err.ptr, @intCast(c_int, err.len));

                    const button_label = if (fatal) |_| c"Quit" else c"Ok";
                    const button_label_len = mem.len(u8, button_label);
                    const style_font = ctx.style.font;
                    const style_button = ctx.style.button;
                    const label_width = style_font.*.width.?(style_font.*.userdata, 0, button_label, @intCast(c_int, button_label_len));
                    const button_width = label_width + style_button.border +
                        (style_button.padding.x + style_button.rounding) * 6;

                    c.nk_layout_row_template_begin(ctx, 0);
                    c.nk_layout_row_template_push_dynamic(ctx);
                    c.nk_layout_row_template_push_static(ctx, button_width);
                    c.nk_layout_row_template_end(ctx);

                    c.nk_label(ctx, c"", nk.TEXT_LEFT);
                    if (c.nk_button_label(ctx, button_label) != 0) {
                        if (fatal) |_|
                            return 1;
                        errors.list.allocator.free(errors.list.pop());
                        c.nk_popup_close(ctx);
                    }
                }
            }
        }
        c.nk_end(ctx);

        nk.render(ctx, window);
        time.sleep(math.sub(u64, frame_time, timer.read()) catch 0);
    }

    return 0;
}

const Errors = struct {
    fatal_error: [128]u8 = "\x00" ** 128,
    list: std.ArrayList([]const u8),

    fn append(errors: *Errors, comptime fmt: []const u8, args: ...) void {
        const err_msg = std.fmt.allocPrint(errors.list.allocator, fmt, args) catch {
            return errors.fatal("Allocation failed");
        };
        errors.list.append(err_msg) catch {
            errors.list.allocator.free(err_msg);
            return errors.fatal("Allocation failed");
        };
    }

    fn fatal(errors: *Errors, comptime fmt: []const u8, args: ...) void {
        _ = std.fmt.bufPrint(&errors.fatal_error, fmt ++ "\x00", args) catch return;
    }

    fn fatalError(errors: *const Errors) ?[]const u8 {
        const res = mem.toSliceConst(u8, &errors.fatal_error);
        if (res.len == 0)
            return null;
        return res;
    }

    fn deinit(errors: Errors) void {
        for (errors.list.toSlice()) |err|
            errors.list.allocator.free(err);
        errors.list.deinit();
    }
};

fn errPrint(comptime format_str: []const u8, args: ...) u8 {
    debug.warn(format_str, args);
    return 1;
}

fn groupOuterHeight(ctx: *const nk.Context) f32 {
    return headerHeight(ctx) + (ctx.style.window.group_padding.y * 2) + ctx.style.window.spacing.y;
}

fn headerHeight(ctx: *const nk.Context) f32 {
    return ctx.style.font.*.height +
        (ctx.style.window.header.padding.y * 2) +
        (ctx.style.window.header.label_padding.y * 2) + 1;
}

fn randomize(exes: Exes, settings: Settings, in: []const u8, out: []const u8) !void {
    switch (builtin.os) {
        .linux => {
            const sh = try std.ChildProcess.init([_][]const u8{"sh"}, std.heap.direct_allocator);
            sh.stdin_behavior = .Pipe;
            try sh.spawn();

            const stream = &sh.stdin.?.outStream().stream;
            try outputScript(stream, exes, settings, in, out);

            sh.stdin.?.close();
            sh.stdin = null;
            const term = try sh.wait();
            switch (term) {
                .Exited => |code| {
                    if (code != 0)
                        return error.CommandFailed;
                },
                .Signal, .Stopped, .Unknown => |code| {
                    return error.CommandFailed;
                },
            }
        },
        else => @compileError("Unsupported os"),
    }
}

fn outputScript(stream: var, exes: Exes, settings: Settings, in: []const u8, out: []const u8) !void {
    switch (builtin.os) {
        .linux => {
            const escapes = blk: {
                var res = util.default_escapes;
                res['\''] = "'\\''";
                break :blk res;
            };

            try stream.write("'");
            try util.writeEscaped(stream, exes.load, escapes);
            try stream.write("' '");
            try util.writeEscaped(stream, in, escapes);
            try stream.write("' | ");

            for (settings.order) |order| {
                const filter = exes.filters[order];
                const filter_args = settings.filters_args[order];
                if (!settings.checks[order])
                    continue;

                try stream.write("'");
                try util.writeEscaped(stream, filter.path, escapes);
                try stream.write("'");

                for (filter.params) |param, i| {
                    const param_pre = if (param.names.long) |_| "--" else "-";
                    const param_name = if (param.names.long) |long| long else (*const [1]u8)(&param.names.short.?)[0..];
                    const arg = filter_args[i];
                    if (arg.len == 0)
                        continue;

                    try stream.write(" '");
                    try stream.write(param_pre);
                    try util.writeEscaped(stream, param_name, escapes);
                    try stream.write("'");
                    if (param.takes_value) {
                        try stream.write(" '");
                        try util.writeEscaped(stream, arg, escapes);
                        try stream.write("'");
                    }
                }

                try stream.write(" | ");
            }

            try stream.write("'");
            try util.writeEscaped(stream, exes.apply, escapes);
            try stream.write("' --replace --output '");
            try util.writeEscaped(stream, out, escapes);
            try stream.write("' '");
            try util.writeEscaped(stream, in, escapes);
            try stream.write("'");
        },
        else => @compileError("Unsupported os"),
    }
}

const Settings = struct {
    allocator: *mem.Allocator,

    // The order in which we call the filters. This is an array of indexes into
    // exes.filters
    order: []usize = ([*]usize)(undefined)[0..0],

    // The filters to call
    checks: []bool = ([*]bool)(undefined)[0..0],

    // Allocate all the memory for the values passed to the commands the user wants to execute.
    // filters_args will be the slices we pass. filters_bufs are the backend buffers that all
    // the filters_args will point into. I believe that 64 bytes max for each arg is more than
    // enough. If this is proven to be false, we can increase that number (or rethink how this
    // is done).
    filters_args: [][][]const u8 = ([*][][]const u8)(undefined)[0..0],
    filters_bufs: [][][64]u8 = ([*][][64]u8)(undefined)[0..0],

    fn init(allocator: *mem.Allocator, exes: Exes) !Settings {
        const order = try allocator.alloc(usize, exes.filters.len);
        errdefer allocator.free(order);

        const checks = try allocator.alloc(bool, exes.filters.len);
        errdefer allocator.free(checks);

        const filters_args = try allocator.alloc([][]const u8, exes.filters.len);
        errdefer allocator.free(filters_args);

        const filters_bufs = try allocator.alloc([][64]u8, exes.filters.len);
        errdefer allocator.free(filters_bufs);

        for (filters_args) |*filter_args, i| {
            errdefer {
                for (filters_args[0..i]) |f|
                    allocator.free(f);
                for (filters_bufs[0..i]) |f|
                    allocator.free(f);
            }

            const params = exes.filters[i].params;
            filter_args.* = try allocator.alloc([]const u8, params.len);
            errdefer allocator.free(filter_args.*);

            filters_bufs[i] = try allocator.alloc([64]u8, params.len);
            errdefer allocator.free(filters_bufs[i]);

            for (filter_args.*) |*arg, j|
                arg.* = filters_bufs[i][j][0..0];
        }

        const settings = Settings{
            .allocator = allocator,
            .order = order,
            .checks = checks,
            .filters_args = filters_args,
            .filters_bufs = filters_bufs,
        };

        settings.reset();
        return settings;
    }

    fn deinit(settings: Settings) void {
        const allocator = settings.allocator;

        for (settings.filters_args) |filter_args|
            allocator.free(filter_args);
        for (settings.filters_bufs) |filter_bufs|
            allocator.free(filter_bufs);

        allocator.free(settings.order);
        allocator.free(settings.checks);
    }

    fn reset(settings: Settings) void {
        mem.set(bool, settings.checks, false);
        for (settings.order) |*o, i|
            o.* = i;

        for (settings.filters_args) |*filter_args, i| {
            for (filter_args.*) |*arg, j|
                arg.* = settings.filters_bufs[i][j][0..0];
        }
    }

    const escapes = blk: {
        var res = util.default_escapes;
        res['\n'] = "\\n";
        res['\\'] = "\\\\";
        res[','] = "\\,";
        break :blk res;
    };

    fn save(settings: Settings, exes: Exes, out_stream: var) !void {
        for (settings.order) |o| {
            if (!settings.checks[o])
                continue;

            const filter = exes.filters[o];
            const args = settings.filters_args[o];
            try util.writeEscaped(out_stream, path.basename(filter.path), escapes);
            for (args) |arg, i| {
                const param = filter.params[i];
                if (arg.len == 0)
                    continue;

                try out_stream.write(",");
                const param_pre = if (param.names.long) |_| "--" else "-";
                const param_name = if (param.names.long) |long| long else (*const [1]u8)(&param.names.short.?)[0..];
                try out_stream.write(param_pre);
                try util.writeEscaped(out_stream, param_name, escapes);
                if (param.takes_value) {
                    try out_stream.write(",");
                    try util.writeEscaped(out_stream, arg, escapes);
                }
            }
            try out_stream.write("\n");
        }
    }

    fn load(settings: Settings, exes: Exes, in_stream: var) !void {
        settings.reset();

        const EscapedSeparatorArgIterator = struct {
            const Error = io.SliceOutStream.Error;
            separator: util.EscapedSeparator,
            buf: [100]u8 = undefined,

            pub fn next(iter: *@This()) Error!?[]const u8 {
                const n = iter.separator.next() orelse return null;
                var sos = io.SliceOutStream.init(&iter.buf);
                try util.writeUnEscaped(&sos.stream, n, escapes);

                return sos.getWritten();
            }
        };

        const helpers = struct {
            fn findFilterIndex(e: Exes, name: []const u8) ?usize {
                for (e.filters) |filter, i| {
                    const basename = path.basename(filter.path);
                    if (mem.eql(u8, basename, name))
                        return i;
                }

                return null;
            }
        };

        var order_i: usize = 0;
        var buf: [1024 * 2]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(&buf);
        var buf_in_stream = io.BufferedInStream(@typeOf(in_stream.read(undefined)).ErrorSet).init(in_stream);
        var buffer = try std.Buffer.initSize(&fba.allocator, 0);

        while (try readLine(&buf_in_stream, &buffer)) |line| {
            var separator = util.separateEscaped(line, "\\", ",");
            const name = separator.next() orelse continue;
            const i = helpers.findFilterIndex(exes, name) orelse continue;

            if (mem.indexOfScalar(usize, settings.order[0..order_i], i)) |_|
                return error.DuplicateEntry;

            const filter = exes.filters[i];
            const filter_args = settings.filters_args[i];
            const filter_bufs = settings.filters_bufs[i];
            settings.order[order_i] = i;
            settings.checks[i] = true;
            order_i += 1;

            var args = EscapedSeparatorArgIterator{ .separator = separator };
            var streaming_clap = clap.StreamingClap(clap.Help, EscapedSeparatorArgIterator){
                .iter = &args,
                .params = filter.params,
            };

            // TODO: Better error returned
            while (try streaming_clap.next()) |arg| {
                const param_i = util.indexOfPtr(clap.Param(clap.Help), filter.params, arg.param);
                if (filter_args[param_i].len != 0)
                    return error.DuplicateParam;

                const filter_arg = &filter_args[param_i];
                const filter_buf = &filter_bufs[param_i];

                if (arg.value) |value| {
                    if (filter_buf.len < value.len)
                        return error.OutOfMemory;

                    mem.copy(u8, filter_buf, value);
                    filter_arg.* = filter_buf[0..value.len];
                } else {
                    filter_arg.* = filter_buf[0..1];
                }
            }

            buffer.shrink(0);
        }

        for (exes.filters) |_, i| {
            if (mem.indexOfScalar(usize, settings.order[0..order_i], i)) |_|
                continue;

            settings.order[order_i] = i;
            order_i += 1;
        }
    }
};

const Exes = struct {
    allocator: *mem.Allocator,
    load: []const u8 = "",
    apply: []const u8 = "",
    filters: []const Filter = [_]Filter{},

    const Filter = struct {
        path: []const u8,
        help: []const u8,
        params: []const clap.Param(clap.Help),
    };

    fn deinit(exes: Exes) void {
        freeFilters(exes.allocator, exes.filters);
        exes.allocator.free(exes.load);
        exes.allocator.free(exes.apply);
        exes.allocator.free(exes.filters);
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
        errdefer allocator.free(filters);
        errdefer freeFilters(allocator, filters);

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

    fn findFilters(allocator: *mem.Allocator, self_exe: []const u8, self_exe_dir: []const u8, cwd: []const u8, env_map: *const std.BufMap) ![]Filter {
        var res = std.ArrayList(Filter).init(allocator);
        defer res.deinit();
        defer freeFilters(allocator, res.toSlice());

        var found_tools = std.BufSet.init(allocator);
        defer found_tools.deinit();

        // HACK: We put our own exe as found so that we hope that we don't exectute ourself again (this with be an info process spawner).
        //       This is not robust at all. Idk if we can have a better way of detecting filters though. Think about this.
        try found_tools.put(self_exe);
        defer _ = found_tools.delete(self_exe);

        // Try to find filters is "$SELF_EXE_PATH/filter" and "$SELF_EXE_PATH/"
        var fs_tmp: [fs.MAX_PATH_BYTES]u8 = undefined;
        if (join(&fs_tmp, [_][]const u8{ self_exe_dir, "filter" })) |self_filter_dir| {
            findFiltersIn(&res, &found_tools, allocator, self_filter_dir, cwd, env_map) catch {};
        } else |_| {}

        findFiltersIn(&res, &found_tools, allocator, self_exe_dir, cwd, env_map) catch {};

        // Try to find filters from "$PATH"
        const path_split = if (std.os.windows.is_the_target) ";" else ":";
        const path_list = env_map.get("PATH") orelse "";

        var it = mem.separate(path_list, path_split);
        while (it.next()) |dir|
            findFiltersIn(&res, &found_tools, allocator, dir, cwd, env_map) catch {};

        return res.toOwnedSlice();
    }

    fn findFiltersIn(filters: *std.ArrayList(Filter), found: *std.BufSet, allocator: *mem.Allocator, dir: []const u8, cwd: []const u8, env_map: *const std.BufMap) !void {
        var open_dir = try fs.Dir.open(allocator, dir);
        defer open_dir.close();

        var fs_tmp: [fs.MAX_PATH_BYTES]u8 = undefined;
        while (try open_dir.next()) |entry| {
            if (entry.kind != .File)
                continue;
            if (!mem.startsWith(u8, entry.name, "tm35-"))
                continue;
            if (found.exists(entry.name))
                continue;

            const path_to_exe = join(&fs_tmp, [_][]const u8{ dir, entry.name }) catch continue;
            const filter = pathToFilter(allocator, path_to_exe, cwd, env_map) catch continue;

            try found.put(entry.name);
            try filters.append(filter);
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

        std.sort.sort(clap.Param(clap.Help), params.toSlice(), struct {
            fn lessThan(a: clap.Param(clap.Help), b: clap.Param(clap.Help)) bool {
                if (!a.takes_value and b.takes_value)
                    return true;
                if (a.takes_value and !b.takes_value)
                    return false;
                if (a.takes_value and b.takes_value) {
                    const a_is_opt = mem.indexOfScalar(u8, a.id.value, '|') != null;
                    const b_is_opt = mem.indexOfScalar(u8, b.id.value, '|') != null;
                    if (a_is_opt and !b_is_opt)
                        return true;
                    if (!a_is_opt and b_is_opt)
                        return false;
                    if (mem.lessThan(u8, a.id.value, b.id.value))
                        return true;
                }

                const a_text = a.names.long orelse (*const [1]u8)(&a.names.short.?)[0..];
                const b_text = b.names.long orelse (*const [1]u8)(&b.names.short.?)[0..];
                return mem.lessThan(u8, a_text, b_text);
            }
        }.lessThan);

        return Filter{
            .path = try mem.dupe(allocator, u8, filter_path),
            .help = help,
            .params = params.toOwnedSlice(),
        };
    }

    fn freeFilters(allocator: *mem.Allocator, filters: []const Filter) void {
        for (filters) |filter| {
            allocator.free(filter.path);
            allocator.free(filter.help);
            allocator.free(filter.params);
        }
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
