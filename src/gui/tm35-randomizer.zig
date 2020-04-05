const builtin = @import("builtin");
const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const c = @import("c.zig");
const nk = @import("nuklear.zig");

const debug = std.debug;
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

const bug_message =
    \\Hi user. You have just hit a bug/limitation in the program.
    \\If you care about this program, please report this to the
    \\issue tracker here:
    \\https://github.com/TM35-Metronome/metronome/issues/new
    \\
;

const fps = 60;
const frame_time = time.second / fps;
const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;

usingnamespace switch (builtin.os) {
    .windows => struct {
        pub extern "user32" stdcallcc fn ShowWindow(hwnd: std.os.windows.HANDLE, nCmdShow: c_int) std.os.windows.BOOL;
        pub extern "kernel32" stdcallcc fn GetConsoleWindow() std.os.windows.HANDLE;
    },
    else => struct {},
};

const border_group = nk.WINDOW_BORDER | nk.WINDOW_NO_SCROLLBAR;
const border_title_group = border_group | nk.WINDOW_TITLE;

pub fn main() u8 {
    // HACK: I don't want to show a console to the user here is someone explaing what
    //       to pass to the C compiler to make that happen:
    //       https://stackoverflow.com/a/9619254
    //       I have no idea how to get the same behavior using the Zig compiler, so instead
    //       I use this solution:
    //       https://stackoverflow.com/a/9618984
    switch (builtin.os) {
        .windows => _ = ShowWindow(GetConsoleWindow(), 0),
        else => {},
    }

    const allocator = heap.c_allocator;

    // Set up essetial state for the program to run. If any of these
    // fail, the only thing we can do is exit.
    const stderr = std.io.getStdErr() catch |err| return errPrint("Unable to get stderr: {}\n", err);
    var timer = time.Timer.start() catch |err| return errPrint("Could not create timer: {}\n", err);
    var tmp_buf: [128]u8 = undefined;

    const ctx: *nk.Context = c.nkInit(WINDOW_WIDTH, WINDOW_HEIGHT) orelse return errPrint("Could not create nuklear context\n");
    defer c.nkDeinit(ctx);

    {
        const black = nk.rgb(0x00, 0x00, 0x00);
        const white = nk.rgb(0xff, 0xff, 0xff);
        const header_gray = nk.rgb(0xf5, 0xf5, 0xf5);
        const border_gray = nk.rgb(0xda, 0xdb, 0xdc);
        const light_gray1 = nk.rgb(0xe1, 0xe1, 0xe1);
        const light_gray2 = nk.rgb(0xd0, 0xd0, 0xd0);
        const light_gray3 = nk.rgb(0xbf, 0xbf, 0xbf);
        const light_gray4 = nk.rgb(0xaf, 0xaf, 0xaf);

        // I color all elements not used in the ui an ugly red color.
        // This will let me easily see when I need to update this color table.
        const ugly_read = nk.rgb(0xff, 0x00, 0x00);

        var colors: [nk.COLOR_COUNT]nk.Color = undefined;
        colors[nk.COLOR_TEXT] = black;
        colors[nk.COLOR_WINDOW] = white;
        colors[nk.COLOR_HEADER] = header_gray;
        colors[nk.COLOR_BORDER] = border_gray;
        colors[nk.COLOR_BUTTON] = light_gray1;
        colors[nk.COLOR_BUTTON_HOVER] = light_gray2;
        colors[nk.COLOR_BUTTON_ACTIVE] = light_gray4;
        colors[nk.COLOR_TOGGLE] = light_gray1;
        colors[nk.COLOR_TOGGLE_HOVER] = light_gray2;
        colors[nk.COLOR_TOGGLE_CURSOR] = black;
        colors[nk.COLOR_SELECT] = white;
        colors[nk.COLOR_SELECT_ACTIVE] = light_gray4;
        colors[nk.COLOR_SLIDER] = ugly_read;
        colors[nk.COLOR_SLIDER_CURSOR] = ugly_read;
        colors[nk.COLOR_SLIDER_CURSOR_HOVER] = ugly_read;
        colors[nk.COLOR_SLIDER_CURSOR_ACTIVE] = ugly_read;
        colors[nk.COLOR_PROPERTY] = ugly_read;
        colors[nk.COLOR_EDIT] = light_gray1;
        colors[nk.COLOR_EDIT_CURSOR] = ugly_read;
        colors[nk.COLOR_COMBO] = light_gray1;
        colors[nk.COLOR_CHART] = ugly_read;
        colors[nk.COLOR_CHART_COLOR] = ugly_read;
        colors[nk.COLOR_CHART_COLOR_HIGHLIGHT] = ugly_read;
        colors[nk.COLOR_SCROLLBAR] = light_gray1;
        colors[nk.COLOR_SCROLLBAR_CURSOR] = light_gray2;
        colors[nk.COLOR_SCROLLBAR_CURSOR_HOVER] = light_gray3;
        colors[nk.COLOR_SCROLLBAR_CURSOR_ACTIVE] = light_gray4;
        colors[nk.COLOR_TAB_HEADER] = ugly_read;
        c.nk_style_from_table(ctx, &colors);

        ctx.style.window.min_row_height_padding = 4;
    }

    // From this point on, we can report errors to the user. This is done
    // with this 'Popups' struct. If an error occures, it should be appended
    // with 'popups.err("error str {}", arg1, arg2...)'.
    // It is also possible to report a fatal error with
    // 'popups.fatal("error str {}", arg1, arg2...)'. A fatal error means, that
    // the only way to recover is to exit. This error is reported to the user,
    // after which the only option they have is to quit the program.
    // Finally, we can also just inform the user of something with
    // 'popups.info("info str {}", arg1, arg2...)'.
    var popups = Popups{
        .errors = std.ArrayList([]const u8).init(allocator),
        .infos = std.ArrayList([]const u8).init(allocator),
    };
    defer popups.deinit();

    const exes = Exes.find(allocator) catch |err| blk: {
        popups.err("Failed to find exes: {}", err);
        break :blk Exes{ .allocator = allocator };
    };
    defer exes.deinit();

    const settings = Settings.init(allocator, exes) catch |err| blk: {
        popups.err("Failed to create settings: {}", err);
        break :blk Settings{ .allocator = allocator };
    };
    defer settings.deinit();

    var rom_path: ?util.Path = null;
    var selected: usize = 0;
    while (true) {
        timer.reset();
        if (c.nkInput(ctx) == 0)
            return 0;

        const window_rect = nk.rect(0, 0, @intToFloat(f32, c.width), @intToFloat(f32, c.height));

        if (nk.begin(ctx, c"", window_rect, nk.WINDOW_NO_SCROLLBAR)) {
            const layout = ctx.current.*.layout;
            const min_height = layout.*.row.min_height;

            var total_space: c.struct_nk_rect = undefined;
            c.nkWindowGetContentRegion(ctx, &total_space);

            const group_height = total_space.h - ctx.style.window.padding.y * 2;
            const inner_height = group_height - groupOuterHeight(ctx);
            c.nk_layout_row_template_begin(ctx, group_height);
            c.nk_layout_row_template_push_static(ctx, 300);
            c.nk_layout_row_template_push_dynamic(ctx);
            c.nk_layout_row_template_push_static(ctx, 180);
            c.nk_layout_row_template_end(ctx);

            // +---------------------------+
            // | Commands                   |
            // +---------------------------+
            // | +-+ +-------------------+ |
            // | |^| | # tm35-rand-stats | |
            // | +-+ | # tm35-rand-wild  | |
            // | +-+ |                   | |
            // | |V| |                   | |
            // | +-+ |                   | |
            // |     +-------------------+ |
            // +---------------------------+
            if (c.nk_group_begin(ctx, c"Commands", border_title_group) != 0) {
                defer c.nk_group_end(ctx);
                c.nk_layout_row_template_begin(ctx, inner_height);
                c.nk_layout_row_template_push_static(ctx, min_height);
                c.nk_layout_row_template_push_dynamic(ctx);
                c.nk_layout_row_template_end(ctx);

                if (nk.nonPaddedGroupBegin(ctx, c"command-buttons", nk.WINDOW_NO_SCROLLBAR)) {
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
                if (c.nk_list_view_begin(ctx, &list_view, c"command-list", nk.WINDOW_BORDER, 0, @intCast(c_int, exes.commands.len)) != 0) {
                    defer c.nk_list_view_end(&list_view);
                    for (settings.order) |command_i, i| {
                        const command = exes.commands[command_i];
                        if (i < @intCast(usize, list_view.begin))
                            continue;
                        if (@intCast(usize, list_view.end) <= i)
                            break;

                        c.nk_layout_row_template_begin(ctx, 0);
                        c.nk_layout_row_template_push_static(ctx, ctx.style.font.*.height);
                        c.nk_layout_row_template_push_dynamic(ctx);
                        c.nk_layout_row_template_end(ctx);

                        const command_name = path.basename(command.path);
                        const ui_name = toUserfriendly(&tmp_buf, command_name[0..math.min(command_name.len, tmp_buf.len)]);
                        settings.checks[command_i] = c.nk_check_label(ctx, c"", @boolToInt(settings.checks[command_i])) != 0;
                        if (c.nk_select_text(ctx, ui_name.ptr, @intCast(c_int, ui_name.len), nk.TEXT_LEFT, @boolToInt(i == selected)) != 0)
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
                if (exes.commands.len == 0)
                    break :blk;

                const command = exes.commands[settings.order[selected]];
                var it = mem.separate(command.help, "\n");
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

                var biggest_width: f32 = 0;
                for (command.params) |param, i| {
                    const text = param.names.long orelse (*const [1]u8)(&param.names.short.?)[0..];
                    if (!param.takes_value)
                        continue;
                    if (mem.eql(u8, text, "help"))
                        continue;
                    if (mem.eql(u8, text, "version"))
                        continue;

                    const text_width = nk.fontWidth(ctx, text);
                    if (biggest_width < text_width)
                        biggest_width = text_width;
                }

                for (command.params) |param, i| {
                    var bounds: c.struct_nk_rect = undefined;
                    const arg = &settings.commands_args[settings.order[selected]][i];
                    const help = param.id.msg;
                    const value = param.id.value;
                    const param_name = param.names.long orelse (*const [1]u8)(&param.names.short.?)[0..];
                    const ui_name = toUserfriendly(&tmp_buf, param_name[0..math.min(param_name.len, tmp_buf.len)]);
                    if (mem.eql(u8, param_name, "help"))
                        continue;
                    if (mem.eql(u8, param_name, "version"))
                        continue;

                    if (!param.takes_value) {
                        c.nk_layout_row_dynamic(ctx, 0, 1);

                        c.nkWidgetBounds(ctx, &bounds);
                        if (c.nkInputIsMouseHoveringRect(&ctx.input, &bounds) != 0)
                            c.nk_tooltip_text(ctx, help.ptr, @intCast(c_int, help.len));

                        // For flags, we only care about whether it's checked or not. We indicate this
                        // by having a slice of len 1 instead of 0.
                        const checked = c.nk_check_text(ctx, ui_name.ptr, @intCast(c_int, ui_name.len), @boolToInt(arg.len != 0)) != 0;
                        arg.len = @boolToInt(checked);
                        continue;
                    }

                    const prompt_width = nk.fontWidth(ctx, "a" ** 30);
                    c.nk_layout_row_template_begin(ctx, 0);
                    c.nk_layout_row_template_push_static(ctx, biggest_width);
                    c.nk_layout_row_template_push_static(ctx, prompt_width);
                    c.nk_layout_row_template_push_dynamic(ctx);
                    c.nk_layout_row_template_end(ctx);

                    c.nkWidgetBounds(ctx, &bounds);
                    if (c.nkInputIsMouseHoveringRect(&ctx.input, &bounds) != 0)
                        c.nk_tooltip_text(ctx, help.ptr, @intCast(c_int, help.len));

                    c.nk_text(ctx, ui_name.ptr, @intCast(c_int, ui_name.len), nk.TEXT_LEFT);

                    if (mem.eql(u8, value, "NUM")) {
                        _ = c.nk_edit_string(ctx, nk.EDIT_SIMPLE, &arg.items, @ptrCast(*c_int, &arg.len), arg.items.len, c.nk_filter_decimal);
                        continue;
                    }
                    if (mem.indexOfScalar(u8, value, '|')) |_| {
                        const selected_name = arg.toSliceConst();
                        const selected_ui_name = toUserfriendly(&tmp_buf, selected_name[0..math.min(selected_name.len, tmp_buf.len)]);
                        if (c.nkComboBeginText(ctx, selected_ui_name.ptr, @intCast(c_int, selected_ui_name.len), &nk.vec2(prompt_width, 500)) != 0) {
                            c.nk_layout_row_dynamic(ctx, 0, 1);
                            if (c.nk_combo_item_label(ctx, c"", nk.TEXT_LEFT) != 0)
                                arg.len = 0;

                            var item_it = mem.separate(value, "|");
                            while (item_it.next()) |item| {
                                const item_ui_name = toUserfriendly(&tmp_buf, item[0..math.min(item.len, tmp_buf.len)]);
                                if (c.nk_combo_item_text(ctx, item_ui_name.ptr, @intCast(c_int, item_ui_name.len), nk.TEXT_LEFT) == 0)
                                    continue;

                                arg.* = Settings.Arg.fromSlice(item) catch {
                                    popups.err("{}", bug_message);
                                    continue;
                                };
                            }
                            c.nk_combo_end(ctx);
                        }
                        continue;
                    }

                    // It is only safe to pass arg.ptr to nk_edit_string if it is actually pointing into buf.
                    _ = c.nk_edit_string(ctx, nk.EDIT_SIMPLE, &arg.items, @ptrCast(*c_int, &arg.len), arg.items.len, c.nk_filter_default);
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
            if (c.nk_group_begin(ctx, c"Actions", border_title_group) != 0) done: {
                defer c.nk_group_end(ctx);
                c.nk_layout_row_template_begin(ctx, 0);
                c.nk_layout_row_template_push_static(ctx, min_height);
                c.nk_layout_row_template_push_dynamic(ctx);
                c.nk_layout_row_template_end(ctx);

                const FileBrowserKind = enum {
                    load_rom,
                    randomize,
                    load_settings,
                    save_settings,
                };
                var m_file_browser_kind: ?FileBrowserKind = null;

                // TODO: Draw folder icon
                if (c.nk_button_symbol(ctx, c.NK_SYMBOL_PLUS) != 0)
                    m_file_browser_kind = .load_rom;

                const rom_slice = if (rom_path) |*i| i.toSliceConst() else "< Open rom (No rom open)";
                var basename = path.basename(rom_slice);
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
                if (nk.buttonActivatable(ctx, "Randomize", rom_path != null))
                    m_file_browser_kind = .randomize;
                if (nk.button(ctx, "Load settings"))
                    m_file_browser_kind = .load_settings;
                if (nk.button(ctx, "Save settings"))
                    m_file_browser_kind = .save_settings;

                const file_browser_kind = m_file_browser_kind orelse break :done;

                var m_out_path: ?[*]u8 = null;
                const dialog_result = switch (file_browser_kind) {
                    .save_settings => c.NFD_SaveDialog(null, null, &m_out_path),
                    .load_settings => c.NFD_OpenDialog(null, null, &m_out_path),
                    .load_rom => c.NFD_OpenDialog(c"gb,gba,nds", null, &m_out_path),
                    .randomize => c.NFD_SaveDialog(c"gb,gba,nds", null, &m_out_path),
                };

                const selected_path = switch (dialog_result) {
                    .NFD_ERROR => {
                        popups.err("Could not open file browser: {s}", c.NFD_GetError());
                        break :done;
                    },
                    .NFD_CANCEL => break :done,
                    .NFD_OKAY => blk: {
                        const out_path = m_out_path.?;
                        defer std.c.free(out_path);

                        break :blk util.Path.fromSlice(mem.toSliceConst(u8, out_path)) catch {
                            popups.err("File name '{s}' is too long", out_path);
                            break :done;
                        };
                    },
                };

                switch (file_browser_kind) {
                    .load_rom => rom_path = selected_path,
                    .randomize => {
                        // in should never be null here as the "Randomize" button is inactive when
                        // it is.
                        const in_path = rom_path.?.toSliceConst();
                        const out_path = selected_path.toSliceConst();

                        outputScript(&stderr.outStream().stream, exes, settings, in_path, out_path) catch {};
                        stderr.write("\n") catch {};
                        randomize(exes, settings, in_path, out_path) catch |err| {
                            // TODO: Maybe print the stderr from the command we run in the randomizer function
                            popups.err("Failed to randomize '{}': {}", in_path, err);
                            break :done;
                        };

                        popups.info("Rom has been randomized!");
                    },
                    .load_settings => {
                        const file = fs.File.openRead(selected_path.toSliceConst()) catch |err| {
                            popups.err("Could not open '{}': {}", selected_path.toSliceConst(), err);
                            break :done;
                        };
                        defer file.close();
                        settings.load(exes, &file.inStream().stream) catch |err| {
                            popups.err("Failed to load from '{}': {}", selected_path.toSliceConst(), err);
                            break :done;
                        };
                    },
                    .save_settings => {
                        // TODO: Warn if the user tries to overwrite existing file.
                        const file = fs.File.openWrite(selected_path.toSliceConst()) catch |err| {
                            popups.err("Could not open '{}': {}", selected_path.toSliceConst(), err);
                            break :done;
                        };
                        defer file.close();
                        settings.save(exes, &file.outStream().stream) catch |err| {
                            popups.err("Failed to write to '{}': {}", selected_path.toSliceConst(), err);
                            break :done;
                        };
                    },
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
            const x = (@intToFloat(f32, c.width) / 2) - (w / 2);
            const y = (@intToFloat(f32, c.height) / 2) - (h / 2);
            const popup_rect = nk.rect(x, y, w, h);
            const fatal_err = popups.fatalError();
            const is_err = popups.errors.len != 0;
            const is_info = popups.infos.len != 0;
            if (fatal_err != null or is_err or is_info) {
                const title = if (fatal_err) |_| c"Fatal error!" else if (is_err) c"Error" else c"Info";
                if (c.nkPopupBegin(ctx, c.NK_POPUP_STATIC, title, border_title_group, &popup_rect) != 0) {
                    defer c.nk_popup_end(ctx);
                    const text = fatal_err orelse if (is_err) popups.lastError() else popups.lastInfo();

                    const padding_height = groupOuterHeight(ctx);
                    const buttons_height = ctx.style.window.spacing.y +
                        min_height;
                    const text_height = h - (padding_height + buttons_height);

                    c.nk_layout_row_dynamic(ctx, text_height, 1);
                    c.nk_text_wrap(ctx, text.ptr, @intCast(c_int, text.len));

                    switch (nk.buttons(ctx, .right, nk.buttonWidth(ctx, "Quit"), 0, [_]nk.Button{
                        nk.Button{ .text = if (fatal_err) |_| "Quit" else "Ok" },
                    })) {
                        0 => {
                            if (fatal_err) |_|
                                return 1;
                            if (is_err) {
                                popups.errors.allocator.free(popups.errors.pop());
                                c.nk_popup_close(ctx);
                            }
                            if (is_info) {
                                popups.infos.allocator.free(popups.infos.pop());
                                c.nk_popup_close(ctx);
                            }
                        },
                        else => {},
                    }
                }
            }
        }
        c.nk_end(ctx);

        c.nkRender(ctx);
        time.sleep(math.sub(u64, frame_time, timer.read()) catch 0);
    }

    return 0;
}

const Popups = struct {
    fatal_error: [128]u8 = "\x00" ** 128,
    errors: std.ArrayList([]const u8),
    infos: std.ArrayList([]const u8),

    fn err(popups: *Popups, comptime fmt: []const u8, args: ...) void {
        popups.append(&popups.errors, fmt, args);
    }

    fn lastError(popups: *Popups) []const u8 {
        return popups.errors.at(popups.errors.len - 1);
    }

    fn info(popups: *Popups, comptime fmt: []const u8, args: ...) void {
        popups.append(&popups.infos, fmt, args);
    }

    fn lastInfo(popups: *Popups) []const u8 {
        return popups.infos.at(popups.infos.len - 1);
    }

    fn append(popups: *Popups, list: *std.ArrayList([]const u8), comptime fmt: []const u8, args: ...) void {
        const msg = std.fmt.allocPrint(list.allocator, fmt, args) catch {
            return popups.fatal("Allocation failed");
        };
        list.append(msg) catch {
            list.allocator.free(msg);
            return popups.fatal("Allocation failed");
        };
    }

    fn fatal(popups: *Popups, comptime fmt: []const u8, args: ...) void {
        _ = std.fmt.bufPrint(&popups.fatal_error, fmt ++ "\x00", args) catch return;
    }

    fn fatalError(popups: *const Popups) ?[]const u8 {
        const res = mem.toSliceConst(u8, &popups.fatal_error);
        if (res.len == 0)
            return null;
        return res;
    }

    fn deinit(popups: Popups) void {
        for (popups.errors.toSlice()) |e|
            popups.errors.allocator.free(e);
        for (popups.infos.toSlice()) |i|
            popups.infos.allocator.free(i);
        popups.errors.deinit();
        popups.infos.deinit();
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
    const term = switch (builtin.os) {
        .linux => blk: {
            const sh = try std.ChildProcess.init([_][]const u8{"sh"}, std.heap.direct_allocator);
            defer sh.deinit();

            sh.stdin_behavior = .Pipe;
            try sh.spawn();

            const stream = &sh.stdin.?.outStream().stream;
            try outputScript(stream, exes, settings, in, out);

            sh.stdin.?.close();
            sh.stdin = null;

            break :blk try sh.wait();
        },
        .windows => blk: {
            const cache_dir = try util.dir.cache();
            const program_cache_dir = try util.path.join([_][]const u8{
                cache_dir.toSliceConst(),
                program_name,
            });
            const script_file_name = try util.path.join([_][]const u8{
                program_cache_dir.toSliceConst(),
                "tmp_scipt.bat",
            });
            {
                fs.makeDir(program_cache_dir.toSliceConst()) catch |err| switch (err) {
                    error.PathAlreadyExists => {},
                    else => |e| return e,
                };
                const file = try fs.File.openWrite(script_file_name.toSliceConst());
                defer file.close();
                const stream = &file.outStream().stream;
                try outputScript(stream, exes, settings, in, out);
            }

            const cmd = try std.ChildProcess.init([_][]const u8{ "cmd", "/c", "call", script_file_name.toSliceConst() }, std.heap.direct_allocator);
            defer cmd.deinit();

            break :blk try cmd.spawnAndWait();
        },
        else => @compileError("Unsupported os"),
    };
    switch (term) {
        .Exited => |code| {
            if (code != 0)
                return error.CommandFailed;
        },
        .Signal, .Stopped, .Unknown => |code| {
            return error.CommandFailed;
        },
    }
}

fn outputScript(stream: var, exes: Exes, settings: Settings, in: []const u8, out: []const u8) !void {
    const escapes = switch (builtin.os) {
        .linux => blk: {
            var res: [255][]const u8 = undefined;
            mem.copy([]const u8, res[0..], escape.default_escapes);
            res['\''] = "'\\''";
            break :blk res;
        },
        .windows => blk: {
            var res: [255][]const u8 = undefined;
            mem.copy([]const u8, res[0..], escape.default_escapes);
            res['"'] = "\"";
            break :blk res;
        },
        else => @compileError("Unsupported os"),
    };
    const quotes = switch (builtin.os) {
        .linux => "'",
        .windows => "\"",
        else => @compileError("Unsupported os"),
    };

    try stream.write(quotes);
    try escape.writeEscaped(stream, exes.load.toSliceConst(), escapes);
    try stream.write(quotes ++ " " ++ quotes);
    try escape.writeEscaped(stream, in, escapes);
    try stream.write(quotes ++ " | ");

    for (settings.order) |order| {
        const command = exes.commands[order];
        const command_args = settings.commands_args[order];
        if (!settings.checks[order])
            continue;

        try stream.write(quotes);
        try escape.writeEscaped(stream, command.path, escapes);
        try stream.write(quotes);

        for (command.params) |param, i| {
            const param_pre = if (param.names.long) |_| "--" else "-";
            const param_name = if (param.names.long) |long| long else (*const [1]u8)(&param.names.short.?)[0..];
            const arg = &command_args[i];
            if (arg.len == 0)
                continue;

            try stream.write(" " ++ quotes);
            try stream.write(param_pre);
            try escape.writeEscaped(stream, param_name, escapes);
            try stream.write(quotes);
            if (param.takes_value) {
                try stream.write(" " ++ quotes);
                try escape.writeEscaped(stream, arg.toSliceConst(), escapes);
                try stream.write(quotes);
            }
        }

        try stream.write(" | ");
    }

    try stream.write(quotes);
    try escape.writeEscaped(stream, exes.apply.toSliceConst(), escapes);
    try stream.write(quotes ++ " --replace --output " ++ quotes);
    try escape.writeEscaped(stream, out, escapes);
    try stream.write(quotes ++ " " ++ quotes);
    try escape.writeEscaped(stream, in, escapes);
    try stream.write(quotes);
    try stream.write("\n");
}

fn toUserfriendly(human_out: []u8, programmer_in: []const u8) []u8 {
    debug.assert(programmer_in.len <= human_out.len);

    const suffixes = [_][]const u8{".exe"};
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

    return result;
}

const Settings = struct {
    allocator: *mem.Allocator,

    // The order in which we call the commands. This is an array of indexes into
    // exes.commands
    order: []usize = ([*]usize)(undefined)[0..0],

    // The commands to call
    checks: []bool = ([*]bool)(undefined)[0..0],

    // Arguments for all commands parameters.
    commands_args: [][]Arg = ([*][]Arg)(undefined)[0..0],

    const Arg = util.StackArrayList(64, u8);

    fn init(allocator: *mem.Allocator, exes: Exes) !Settings {
        const order = try allocator.alloc(usize, exes.commands.len);
        errdefer allocator.free(order);

        const checks = try allocator.alloc(bool, exes.commands.len);
        errdefer allocator.free(checks);

        const commands_args = try allocator.alloc([]Arg, exes.commands.len);
        errdefer allocator.free(commands_args);

        for (commands_args) |*command_args, i| {
            errdefer {
                for (commands_args[0..i]) |f|
                    allocator.free(f);
            }

            const params = exes.commands[i].params;
            command_args.* = try allocator.alloc(Arg, params.len);
            errdefer allocator.free(command_args.*);
        }

        const settings = Settings{
            .allocator = allocator,
            .order = order,
            .checks = checks,
            .commands_args = commands_args,
        };

        settings.reset();
        return settings;
    }

    fn deinit(settings: Settings) void {
        const allocator = settings.allocator;

        for (settings.commands_args) |command_args|
            allocator.free(command_args);

        allocator.free(settings.order);
        allocator.free(settings.checks);
    }

    fn reset(settings: Settings) void {
        mem.set(bool, settings.checks, false);
        for (settings.order) |*o, i|
            o.* = i;

        for (settings.commands_args) |*command_args, i| {
            for (command_args.*) |*arg, j|
                arg.* = Arg{};
        }
    }

    const escapes = blk: {
        var res: [255][]const u8 = undefined;
        mem.copy([]const u8, res[0..], escape.default_escapes);
        res['\n'] = "\\n";
        res['\\'] = "\\\\";
        res[','] = "\\,";
        break :blk res;
    };

    fn save(settings: Settings, exes: Exes, out_stream: var) !void {
        for (settings.order) |o| {
            if (!settings.checks[o])
                continue;

            const command = exes.commands[o];
            const args = settings.commands_args[o];
            try escape.writeEscaped(out_stream, path.basename(command.path), escapes);
            for (args) |arg, i| {
                const param = command.params[i];
                if (arg.len == 0)
                    continue;

                try out_stream.write(",");
                const param_pre = if (param.names.long) |_| "--" else "-";
                const param_name = if (param.names.long) |long| long else (*const [1]u8)(&param.names.short.?)[0..];
                try out_stream.write(param_pre);
                try escape.writeEscaped(out_stream, param_name, escapes);
                if (param.takes_value) {
                    try out_stream.write(",");
                    try escape.writeEscaped(out_stream, arg.toSliceConst(), escapes);
                }
            }
            try out_stream.write("\n");
        }
    }

    fn load(settings: Settings, exes: Exes, in_stream: var) !void {
        settings.reset();

        const EscapedSeparatorArgIterator = struct {
            const Error = io.SliceOutStream.Error;
            separator: escape.EscapedSeparator,
            buf: [100]u8 = undefined,

            pub fn next(iter: *@This()) Error!?[]const u8 {
                const n = iter.separator.next() orelse return null;
                var sos = io.SliceOutStream.init(&iter.buf);
                try escape.writeUnEscaped(&sos.stream, n, escapes);

                return sos.getWritten();
            }
        };

        const helpers = struct {
            fn findCommandIndex(e: Exes, name: []const u8) ?usize {
                for (e.commands) |command, i| {
                    const basename = path.basename(command.path);
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

        while (try util.readLine(&buf_in_stream, &buffer)) |line| {
            var separator = escape.separateEscaped(line, "\\", ",");
            const name = separator.next() orelse continue;
            const i = helpers.findCommandIndex(exes, name) orelse continue;

            if (mem.indexOfScalar(usize, settings.order[0..order_i], i)) |_|
                return error.DuplicateEntry;

            const command = exes.commands[i];
            const command_args = settings.commands_args[i];
            settings.order[order_i] = i;
            settings.checks[i] = true;
            order_i += 1;

            var args = EscapedSeparatorArgIterator{ .separator = separator };
            var streaming_clap = clap.StreamingClap(clap.Help, EscapedSeparatorArgIterator){
                .iter = &args,
                .params = command.params,
            };

            // TODO: Better error returned
            while (try streaming_clap.next()) |arg| {
                const param_i = util.indexOfPtr(clap.Param(clap.Help), command.params, arg.param);
                if (command_args[param_i].len != 0)
                    return error.DuplicateParam;

                const command_arg = &command_args[param_i];

                if (arg.value) |value| {
                    command_arg.* = Arg.fromSlice(value) catch return error.OutOfMemory;
                } else {
                    command_arg.len = 1;
                }
            }

            buffer.shrink(0);
        }

        for (exes.commands) |_, i| {
            if (mem.indexOfScalar(usize, settings.order[0..order_i], i)) |_|
                continue;

            settings.order[order_i] = i;
            order_i += 1;
        }
    }
};

const path_env_seperator = switch (builtin.os) {
    .linux => ":",
    .windows => ";",
    else => @compileError("Unsupported os"),
};
const path_env_name = switch (builtin.os) {
    .linux => "PATH",
    .windows => "Path",
    else => @compileError("Unsupported os"),
};
const extension = switch (builtin.os) {
    .linux => "",
    .windows => ".exe",
    else => @compileError("Unsupported os"),
};
const program_name = "tm35-randomizer";
const command_file_name = "commands";
const default_commands = "tm35-rand-learned-moves" ++ extension ++ "\n" ++
    "tm35-rand-parties" ++ extension ++ "\n" ++
    "tm35-rand-pokeball-items" ++ extension ++ "\n" ++
    "tm35-rand-starters" ++ extension ++ "\n" ++
    "tm35-rand-static" ++ extension ++ "\n" ++
    "tm35-rand-stats" ++ extension ++ "\n" ++
    "tm35-no-trade-evolutions" ++ extension ++ "\n" ++
    "tm35-rand-wild" ++ extension ++ "\n";

const Exes = struct {
    allocator: *mem.Allocator,
    load: util.Path = util.Path{},
    apply: util.Path = util.Path{},
    commands: []const Command = [_]Command{},

    const Command = struct {
        path: []const u8,
        help: []const u8,
        params: []const clap.Param(clap.Help),
    };

    fn deinit(exes: Exes) void {
        freeCommands(exes.allocator, exes.commands);
        exes.allocator.free(exes.commands);
    }

    fn find(allocator: *mem.Allocator) !Exes {
        const load_tool = findCore("tm35-load" ++ extension) catch return error.LoadToolNotFound;
        const apply_tool = findCore("tm35-apply" ++ extension) catch return error.ApplyToolNotFound;

        const commands = try findCommands(allocator);
        errdefer allocator.free(commands);
        errdefer freeCommands(allocator, commands);

        return Exes{
            .allocator = allocator,
            .load = load_tool,
            .apply = apply_tool,
            .commands = commands,
        };
    }

    fn findCore(tool: []const u8) !util.Path {
        const self_exe_dir = (try util.dir.selfExeDir()).toSliceConst();

        return joinExists([_][]const u8{ self_exe_dir, "core", tool }) catch
            joinExists([_][]const u8{ self_exe_dir, tool }) catch
            try findInPath(tool);
    }

    fn findCommands(allocator: *mem.Allocator) ![]Command {
        const command_file = try openCommandFile();
        defer command_file.close();

        const cwd = try util.dir.cwd();
        var env_map = try process.getEnvMap(allocator);
        defer env_map.deinit();

        var res = std.ArrayList(Command).init(allocator);
        defer res.deinit();
        defer freeCommands(allocator, res.toSlice());

        var buf_stream = io.BufferedInStream(fs.File.InStream.Error).init(&command_file.inStream().stream);
        var buffer = try std.Buffer.initSize(allocator, 0);
        defer buffer.deinit();

        while (try util.readLine(&buf_stream, &buffer)) |line| {
            if (fs.path.isAbsolute(line)) {
                const command = pathToCommand(allocator, line, cwd.toSliceConst(), &env_map) catch continue;
                try res.append(command);
            } else {
                const command_path = findCommand(line) catch continue;
                const command = pathToCommand(allocator, command_path.toSliceConst(), cwd.toSliceConst(), &env_map) catch continue;
                try res.append(command);
            }
        }

        return res.toOwnedSlice();
    }

    fn findCommand(name: []const u8) !util.Path {
        const self_exe_dir = (try util.dir.selfExeDir()).toSliceConst();
        const config_dir = (try util.dir.config()).toSliceConst();
        const cwd = (try util.dir.cwd()).toSliceConst();
        return joinExists([_][]const u8{ cwd, name }) catch
            joinExists([_][]const u8{ config_dir, program_name, name }) catch
            joinExists([_][]const u8{ self_exe_dir, "randomizers", name }) catch
            joinExists([_][]const u8{ self_exe_dir, name }) catch
            try findInPath(name);
    }

    fn openCommandFile() !fs.File {
        const config_dir = (try util.dir.config()).toSliceConst();
        const command_path = (try util.path.join([_][]const u8{
            config_dir,
            program_name,
            command_file_name,
        })).toSliceConst();
        if (fs.File.openRead(command_path)) |file| {
            return file;
        } else |_| {
            var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
            var fba = heap.FixedBufferAllocator.init(&buf);
            const dirname = fs.path.dirname(command_path) orelse ".";

            try fs.makePath(&fba.allocator, dirname);
            try io.writeFile(command_path, default_commands);
            return fs.File.openRead(command_path);
        }
    }

    fn pathToCommand(allocator: *mem.Allocator, command_path: []const u8, cwd: []const u8, env_map: *const std.BufMap) !Command {
        const help = try execHelp(allocator, command_path, cwd, env_map);
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

        return Command{
            .path = try mem.dupe(allocator, u8, command_path),
            .help = help,
            .params = params.toOwnedSlice(),
        };
    }

    fn freeCommands(allocator: *mem.Allocator, commands: []const Command) void {
        for (commands) |command| {
            allocator.free(command.path);
            allocator.free(command.help);
            allocator.free(command.params);
        }
    }
};

fn findInPath(name: []const u8) !util.Path {
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);
    const path_env = try process.getEnvVarOwned(&fba.allocator, path_env_name);

    var iter = mem.tokenize(path_env, path_env_seperator);
    while (iter.next()) |dir| {
        if (joinExists([_][]const u8{ dir, name })) |res| {
            return res;
        } else |_| {}
    }

    return error.NotInPath;
}

fn joinExists(paths: []const []const u8) !util.Path {
    const res = try util.path.join(paths);
    try fs.File.access(res.toSliceConst());
    return res;
}

fn execHelp(allocator: *mem.Allocator, exe: []const u8, cwd: []const u8, env_map: *const std.BufMap) ![]u8 {
    var buf: [1024 * 40]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);

    var p = try std.ChildProcess.init([_][]const u8{ exe, "--help" }, &fba.allocator);
    defer p.deinit();

    p.stdin_behavior = .Ignore;
    p.stdout_behavior = .Pipe;
    p.stderr_behavior = .Ignore;
    p.cwd = cwd;
    p.env_map = env_map;

    try p.spawn();
    errdefer _ = p.kill() catch undefined;

    const help = try p.stdout.?.inStream().stream.readAllAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(help);

    const res = try p.wait();
    switch (res) {
        .Exited => |status| if (status != 0) return error.ProcessFailed,
        else => return error.ProcessFailed,
    }

    return help;
}
