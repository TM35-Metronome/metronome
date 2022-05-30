const builtin = @import("builtin");
const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const c = @import("c.zig");
const nk = @import("nuklear.zig");

const Executables = @import("Executables.zig");

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

const fps = 60;
const frame_time = time.ns_per_s / fps;

const platform = switch (builtin.target.os.tag) {
    .windows => struct {
        pub extern "kernel32" fn GetConsoleWindow() callconv(std.os.windows.WINAPI) std.os.windows.HWND;
    },
    else => struct {},
};

const border_group = c.NK_WINDOW_BORDER | c.NK_WINDOW_NO_SCROLLBAR;
const border_title_group = border_group | c.NK_WINDOW_TITLE;

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

    const allocator = heap.c_allocator;

    // Set up essetial state for the program to run. If any of these
    // fail, the only thing we can do is exit.
    var timer = try time.Timer.start();
    const ctx: *nk.Context = c.nkInit(800, 600) orelse return error.CouldNotInitNuklear;
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
        const ugly_red = nk.rgb(0xff, 0x00, 0x00);

        var colors: [c.NK_COLOR_COUNT]nk.Color = undefined;
        colors[c.NK_COLOR_TEXT] = black;
        colors[c.NK_COLOR_WINDOW] = white;
        colors[c.NK_COLOR_HEADER] = header_gray;
        colors[c.NK_COLOR_BORDER] = border_gray;
        colors[c.NK_COLOR_BUTTON] = light_gray1;
        colors[c.NK_COLOR_BUTTON_HOVER] = light_gray2;
        colors[c.NK_COLOR_BUTTON_ACTIVE] = light_gray4;
        colors[c.NK_COLOR_TOGGLE] = light_gray1;
        colors[c.NK_COLOR_TOGGLE_HOVER] = light_gray2;
        colors[c.NK_COLOR_TOGGLE_CURSOR] = black;
        colors[c.NK_COLOR_SELECT] = white;
        colors[c.NK_COLOR_SELECT_ACTIVE] = light_gray4;
        colors[c.NK_COLOR_SLIDER] = ugly_red;
        colors[c.NK_COLOR_SLIDER_CURSOR] = ugly_red;
        colors[c.NK_COLOR_SLIDER_CURSOR_HOVER] = ugly_red;
        colors[c.NK_COLOR_SLIDER_CURSOR_ACTIVE] = ugly_red;
        colors[c.NK_COLOR_PROPERTY] = ugly_red;
        colors[c.NK_COLOR_EDIT] = light_gray1;
        colors[c.NK_COLOR_EDIT_CURSOR] = ugly_red;
        colors[c.NK_COLOR_COMBO] = light_gray1;
        colors[c.NK_COLOR_CHART] = ugly_red;
        colors[c.NK_COLOR_CHART_COLOR] = ugly_red;
        colors[c.NK_COLOR_CHART_COLOR_HIGHLIGHT] = ugly_red;
        colors[c.NK_COLOR_SCROLLBAR] = light_gray1;
        colors[c.NK_COLOR_SCROLLBAR_CURSOR] = light_gray2;
        colors[c.NK_COLOR_SCROLLBAR_CURSOR_HOVER] = light_gray3;
        colors[c.NK_COLOR_SCROLLBAR_CURSOR_ACTIVE] = light_gray4;
        colors[c.NK_COLOR_TAB_HEADER] = ugly_red;
        c.nk_style_from_table(ctx, &colors);

        ctx.style.edit.cursor_size = 1;
        ctx.style.window.min_row_height_padding = 4;
    }

    // From this point on, we can report errors to the user. This is done
    // with this 'Popups' struct.
    var popups = Popups{ .allocator = allocator };
    defer popups.deinit();

    const exes = Executables.find(allocator) catch |err| blk: {
        popups.err("Failed to find exes: {}", .{err});
        break :blk Executables{ .arena = heap.ArenaAllocator.init(allocator) };
    };
    defer exes.deinit();

    var settings = Settings{ .arena = heap.ArenaAllocator.init(allocator) };
    defer settings.deinit();

    var rom: ?Rom = null;
    var selected: usize = 0;
    while (true) {
        timer.reset();
        if (c.nkInput(ctx) == 0)
            return;

        const window_rect = nk.rect(0, 0, @intToFloat(f32, c.width), @intToFloat(f32, c.height));
        if (nk.begin(ctx, "", window_rect, c.NK_WINDOW_NO_SCROLLBAR)) {
            const group_height = groupHeight(ctx);

            c.nk_layout_row_template_begin(ctx, group_height);
            c.nk_layout_row_template_push_static(ctx, 300);
            c.nk_layout_row_template_push_dynamic(ctx);
            c.nk_layout_row_template_end(ctx);
            selected = drawCommands(ctx, exes, &settings, selected);
            if (nk.nonPaddedGroupBegin(ctx, "opt_and_actions", c.NK_WINDOW_NO_SCROLLBAR)) {
                defer nk.nonPaddedGroupEnd(ctx);
                const action_group_height =
                    ctx.style.window.padding.y * 2 +
                    ctx.style.window.spacing.y * 1 +
                    ctx.style.button.padding.y * 4 +
                    ctx.style.font.*.height * 2 +
                    groupOuterHeight(ctx);

                c.nk_layout_row_template_begin(ctx, action_group_height);
                c.nk_layout_row_template_push_static(ctx, 250);
                c.nk_layout_row_template_push_dynamic(ctx);
                c.nk_layout_row_template_push_dynamic(ctx);
                c.nk_layout_row_template_end(ctx);
                rom = drawActions(ctx, &popups, rom, exes, &settings);
                drawInfo(ctx, rom);
                noopGroup(ctx, "");

                const options_group_height = group_height - (action_group_height +
                    ctx.style.window.spacing.y);
                c.nk_layout_row_dynamic(ctx, options_group_height, 1);
                drawOptions(ctx, &popups, exes, &settings, selected);
            }

            try drawPopups(ctx, &popups);
        }
        c.nk_end(ctx);

        c.nkRender(ctx);
        time.sleep(math.sub(u64, frame_time, timer.read()) catch 0);
    }
}

pub fn noopGroup(ctx: *nk.Context, name: [*:0]const u8) void {
    if (c.nk_group_begin(ctx, name, border_title_group) != 0) {
        defer c.nk_group_end(ctx);
    }
}

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
pub fn drawCommands(
    ctx: *nk.Context,
    exes: Executables,
    settings: *Settings,
    in_selected: usize,
) usize {
    var tmp_buf: [128]u8 = undefined;
    var selected = in_selected;
    const layout = ctx.current.*.layout;
    const min_height = layout.*.row.min_height;
    const inner_height = groupHeight(ctx) - groupOuterHeight(ctx);

    if (c.nk_group_begin(ctx, "Commands", border_title_group) == 0)
        return selected;

    defer c.nk_group_end(ctx);
    c.nk_layout_row_template_begin(ctx, inner_height);
    c.nk_layout_row_template_push_static(ctx, min_height);
    c.nk_layout_row_template_push_dynamic(ctx);
    c.nk_layout_row_template_end(ctx);

    if (nk.nonPaddedGroupBegin(ctx, "command-buttons", c.NK_WINDOW_NO_SCROLLBAR)) {
        defer nk.nonPaddedGroupEnd(ctx);
        c.nk_layout_row_dynamic(ctx, 0, 1);
        if (c.nk_button_symbol(ctx, c.NK_SYMBOL_TRIANGLE_UP) != 0 and
            settings.commands.items.len != 0)
        {
            const before = selected -| 1;
            mem.swap(
                Settings.Command,
                &settings.commands.items[before],
                &settings.commands.items[selected],
            );
            selected = before;
        }
        if (c.nk_button_symbol(ctx, c.NK_SYMBOL_TRIANGLE_DOWN) != 0 and
            settings.commands.items.len != 0)
        {
            const after = math.min(selected + 1, settings.commands.items.len - 1);
            mem.swap(
                Settings.Command,
                &settings.commands.items[selected],
                &settings.commands.items[after],
            );
            selected = after;
        }
        if (c.nk_button_symbol(ctx, c.NK_SYMBOL_MINUS) != 0 and
            settings.commands.items.len != 0)
        {
            _ = settings.commands.orderedRemove(selected);
            selected = math.min(selected, settings.commands.items.len -| 1);
        }
    }

    var list_view: c.nk_list_view = undefined;
    if (c.nk_list_view_begin(ctx, &list_view, "command-list", c.NK_WINDOW_BORDER, 0, @intCast(c_int, exes.commands.len + 1)) != 0) {
        defer c.nk_list_view_end(&list_view);
        for (settings.commands.items) |setting, i| {
            const command = exes.commands[setting.executable];
            if (i < @intCast(usize, list_view.begin))
                continue;
            if (@intCast(usize, list_view.end) <= i)
                break;

            c.nk_layout_row_dynamic(ctx, 0, 1);
            const ui_name = toUserfriendly(&tmp_buf, command.name());
            if (c.nk_select_text(ctx, ui_name.ptr, @intCast(c_int, ui_name.len), c.NK_TEXT_LEFT, @boolToInt(i == selected)) != 0)
                selected = i;
        }

        c.nk_layout_row_dynamic(ctx, 0, 1);
        var bounds: c.struct_nk_rect = undefined;
        c.nkWidgetBounds(ctx, &bounds);

        if (c.nkComboBeginText(ctx, "Add Command", @intCast(c_int, "Add Command".len), &nk.vec2(bounds.w, 500)) != 0) {
            c.nk_layout_row_dynamic(ctx, 0, 1);

            for (exes.commands) |command, i| {
                const command_name = toUserfriendly(&tmp_buf, command.name());
                if (c.nk_combo_item_text(ctx, command_name.ptr, @intCast(c_int, command_name.len), c.NK_TEXT_LEFT) != 0) {
                    // TODO: Handle memory error.
                    const setting = settings.commands.addOne(settings.arena.allocator()) catch unreachable;
                    setting.* = Settings.Command.init(settings.arena.allocator(), i, command) catch unreachable;
                }
            }

            c.nk_combo_end(ctx);
        }
    }
    return selected;
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
// +--------------------------+
pub fn drawOptions(
    ctx: *nk.Context,
    popups: *Popups,
    exes: Executables,
    settings: *Settings,
    selected: usize,
) void {
    var tmp_buf: [128]u8 = undefined;
    if (c.nk_group_begin(ctx, "Options", border_title_group) == 0)
        return;

    defer c.nk_group_end(ctx);
    if (exes.commands.len == 0)
        return;
    if (settings.commands.items.len == 0)
        return;

    const setting = settings.commands.items[selected];
    const command = exes.commands[setting.executable];

    var it = mem.split(u8, command.help, "\n");
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
        c.nk_text(ctx, line.ptr, @intCast(c_int, line.len), c.NK_TEXT_LEFT);
    }

    for (command.flags) |flag, i| {
        const param = command.params[flag.i];
        const help = param.id.msg;

        var bounds: c.struct_nk_rect = undefined;
        c.nkWidgetBounds(ctx, &bounds);
        if (c.nkInputIsMouseHoveringRect(&ctx.input, &bounds) != 0)
            c.nk_tooltip_text(ctx, help.ptr, @intCast(c_int, help.len));

        const name = param.names.long orelse @as(*const [1]u8, &param.names.short.?)[0..];
        const ui_name = toUserfriendly(&tmp_buf, name);

        c.nk_layout_row_dynamic(ctx, 0, 1);
        setting.flags[i] = c.nk_check_text(
            ctx,
            ui_name.ptr,
            @intCast(c_int, ui_name.len),
            @boolToInt(setting.flags[i]),
        ) != 0;
    }

    for (command.ints) |int, i| {
        drawOptionsLayout(ctx, command.params[int.i]);

        var buf: [32]u8 = undefined;
        var formatted = fmt.bufPrint(&buf, "{}", .{setting.ints[i]}) catch unreachable;
        var len = @intCast(c_int, formatted.len);

        _ = c.nk_edit_string(
            ctx,
            c.NK_EDIT_SIMPLE,
            formatted.ptr,
            &len,
            buf.len,
            c.nk_filter_decimal,
        );

        setting.ints[i] = fmt.parseInt(usize, buf[0..@intCast(usize, len)], 10) catch
            setting.ints[i];
    }

    for (command.floats) |float, i| {
        drawOptionsLayout(ctx, command.params[float.i]);

        var buf: [32]u8 = undefined;
        var formatted = fmt.bufPrint(&buf, "{d:.2}", .{setting.floats[i]}) catch unreachable;
        var len = @intCast(c_int, formatted.len);

        _ = c.nk_edit_string(
            ctx,
            c.NK_EDIT_SIMPLE,
            formatted.ptr,
            &len,
            buf.len,
            c.nk_filter_float,
        );

        setting.floats[i] = fmt.parseFloat(f64, buf[0..@intCast(usize, len)]) catch
            setting.floats[i];
    }

    for (command.enums) |enumeration, i| {
        drawOptionsLayout(ctx, command.params[enumeration.i]);

        const selected_enum = setting.enums[i];
        const selected_name = enumeration.options[selected_enum];
        const selected_ui = toUserfriendly(&tmp_buf, selected_name);

        var bounds: c.struct_nk_rect = undefined;
        c.nkWidgetBounds(ctx, &bounds);

        if (c.nkComboBeginText(ctx, selected_ui.ptr, @intCast(c_int, selected_ui.len), &nk.vec2(bounds.w, 500)) != 0) {
            c.nk_layout_row_dynamic(ctx, 0, 1);

            for (enumeration.options) |option, option_i| {
                const option_ui = toUserfriendly(&tmp_buf, option);
                if (c.nk_combo_item_text(ctx, option_ui.ptr, @intCast(c_int, option_ui.len), c.NK_TEXT_LEFT) != 0)
                    setting.enums[i] = option_i;
            }

            c.nk_combo_end(ctx);
        }
    }

    for (command.strings) |string, i| {
        drawOptionsLayout(ctx, command.params[string.i]);

        const value = &setting.strings[i];
        var len = @intCast(c_int, value.items.len);
        defer value.items.len = @intCast(usize, len);

        value.ensureUnusedCapacity(settings.arena.allocator(), 10) catch {};
        _ = c.nk_edit_string(
            ctx,
            c.NK_EDIT_SIMPLE,
            value.items.ptr,
            &len,
            @intCast(c_int, value.capacity),
            c.nk_filter_default,
        );
    }

    for (command.files) |file, i| {
        drawOptionsLayout(ctx, command.params[file.i]);

        const value = &setting.files[i];
        if (!nk.button(ctx, value.items))
            continue;

        var m_out_path: ?[*:0]u8 = null;
        switch (c.NFD_SaveDialog("", null, &m_out_path)) {
            c.NFD_ERROR => {
                popups.err("Could not open file browser: {s}", .{c.NFD_GetError()});
                continue;
            },
            c.NFD_CANCEL => continue,
            c.NFD_OKAY => {
                const out_path_z = m_out_path.?;
                const out_path = mem.span(out_path_z);
                defer std.c.free(out_path_z);

                value.ensureTotalCapacity(settings.arena.allocator(), out_path.len) catch {};
                value.shrinkRetainingCapacity(0);
                value.appendSliceAssumeCapacity(out_path);
            },
            else => unreachable,
        }
    }

    for (command.multi_strings) |multi, i| {
        const param = command.params[multi.i];

        var bounds: c.struct_nk_rect = undefined;
        c.nkWidgetBounds(ctx, &bounds);
        if (c.nkInputIsMouseHoveringRect(&ctx.input, &bounds) != 0)
            c.nk_tooltip_text(ctx, param.id.msg.ptr, @intCast(c_int, param.id.msg.len));

        const name = param.names.long orelse @as(*const [1]u8, &param.names.short.?)[0..];
        const ui_name = toUserfriendly(&tmp_buf, name);
        c.nk_text(ctx, ui_name.ptr, @intCast(c_int, ui_name.len), c.NK_TEXT_LEFT);

        c.nk_layout_row_dynamic(ctx, 120, 1);
        const value = &setting.multi_strings[i];
        var len = @intCast(c_int, value.items.len);
        defer value.items.len = @intCast(usize, len);

        value.ensureUnusedCapacity(settings.arena.allocator(), 10) catch {};
        _ = c.nk_edit_string(
            ctx,
            c.NK_EDIT_SIMPLE | c.NK_EDIT_MULTILINE,
            value.items.ptr,
            &len,
            @intCast(c_int, value.capacity),
            c.nk_filter_default,
        );
    }
}

pub fn drawOptionsLayout(ctx: *nk.Context, param: clap.Param(clap.Help)) void {
    const width = 185;
    c.nk_layout_row_template_begin(ctx, 0);
    c.nk_layout_row_template_push_static(ctx, width);
    c.nk_layout_row_template_push_dynamic(ctx);
    c.nk_layout_row_template_end(ctx);

    var bounds: c.struct_nk_rect = undefined;
    c.nkWidgetBounds(ctx, &bounds);
    if (c.nkInputIsMouseHoveringRect(&ctx.input, &bounds) != 0)
        c.nk_tooltip_text(ctx, param.id.msg.ptr, @intCast(c_int, param.id.msg.len));

    const name = param.names.long orelse @as(*const [1]u8, &param.names.short.?)[0..];

    var tmp_buf: [128]u8 = undefined;
    const ui_name = toUserfriendly(&tmp_buf, name);
    c.nk_text(ctx, ui_name.ptr, @intCast(c_int, ui_name.len), c.NK_TEXT_LEFT);
}

pub const Rom = struct {
    path: util.Path,
    info: util.Path,
};

// +-------------------------------------+
// | Actions                             |
// +-------------------------------------+
// | +---------------+ +---------------+ |
// | |   Open Rom    | |   Randomize   | |
// | +---------------+ +---------------+ |
// | +---------------+ +---------------+ |
// | | Load Settings | | Save Settings | |
// | +---------------+ +---------------+ |
// +-------------------------------------+
pub fn drawActions(
    ctx: *nk.Context,
    popups: *Popups,
    in_rom: ?Rom,
    exes: Executables,
    settings: *Settings,
) ?Rom {
    var rom = in_rom;
    if (c.nk_group_begin(ctx, "Actions", border_title_group) == 0)
        return rom;

    defer c.nk_group_end(ctx);

    var m_file_browser_kind: ?enum {
        load_rom,
        randomize,
        load_settings,
        save_settings,
    } = null;

    c.nk_layout_row_dynamic(ctx, 0, 2);
    if (nk.button(ctx, "Open rom"))
        m_file_browser_kind = .load_rom;
    if (nk.buttonActivatable(ctx, "Randomize", rom != null))
        m_file_browser_kind = .randomize;
    if (nk.button(ctx, "Load settings"))
        m_file_browser_kind = .load_settings;
    if (nk.button(ctx, "Save settings"))
        m_file_browser_kind = .save_settings;

    const file_browser_kind = m_file_browser_kind orelse return rom;

    var m_out_path: ?[*:0]u8 = null;
    const dialog_result = switch (file_browser_kind) {
        .save_settings => c.NFD_SaveDialog(null, null, &m_out_path),
        .load_settings => c.NFD_OpenDialog(null, null, &m_out_path),
        .load_rom => c.NFD_OpenDialog("gb,gba,nds", null, &m_out_path),
        .randomize => blk: {
            const in_rom_path = in_rom.?.path.constSlice();
            const dirname = path.dirname(in_rom_path) orelse ".";
            const ext = path.extension(in_rom_path);
            const in_name = util.path.basenameNoExt(in_rom_path);

            var default_path = util.Path{ .buffer = undefined };
            default_path.appendSlice(dirname) catch {};
            default_path.appendSlice(path.sep_str) catch {};
            default_path.appendSlice(in_name) catch {};
            default_path.appendSlice("-randomized") catch {};
            default_path.appendSlice(ext) catch {};
            default_path.append(0) catch {};

            const default = default_path.slice();
            // Ensure we are null terminated even if the above fails.
            default[default.len - 1] = 0;
            break :blk c.NFD_SaveDialog("gb,gba,nds", default.ptr, &m_out_path);
        },
    };

    const selected_path = switch (dialog_result) {
        c.NFD_ERROR => {
            popups.err("Could not open file browser: {s}", .{c.NFD_GetError()});
            return rom;
        },
        c.NFD_CANCEL => return rom,
        c.NFD_OKAY => blk: {
            const out_path = m_out_path.?;
            defer std.c.free(out_path);

            break :blk util.Path.fromSlice(mem.span(out_path)) catch {
                popups.err("File name '{s}' is too long", .{out_path});
                return rom;
            };
        },
        else => unreachable,
    };
    const selected_path_slice = selected_path.constSlice();

    switch (file_browser_kind) {
        .load_rom => {
            var buf: [1024 * 40]u8 = undefined;
            var fba = heap.FixedBufferAllocator.init(&buf);

            const result = std.ChildProcess.exec(.{
                .allocator = fba.allocator(),
                .argv = &[_][]const u8{
                    exes.identify.constSlice(),
                    selected_path_slice,
                },
            }) catch |err| {
                popups.err("Failed to identify {s}: {}", .{ selected_path_slice, err });
                rom = null;
                return rom;
            };

            const output = util.Path.fromSlice(result.stdout);
            if (result.term != .Exited or result.term.Exited != 0) {
                popups.err("{s} is not a Pokémon rom.\n{s}", .{ selected_path_slice, result.stderr });
                rom = null;
            } else if (output) |info| {
                rom = Rom{
                    .path = selected_path,
                    .info = info,
                };
            } else |_| {
                popups.err("Output too long", .{});
                rom = null;
            }
        },
        .randomize => {
            // in should never be null here as the "Randomize" button is inactive when
            // it is.
            const in_path = rom.?.path.slice();
            const out_path = selected_path.constSlice();

            const stderr = std.io.getStdErr();
            outputScript(stderr.writer(), exes, settings.*, in_path, out_path) catch {};
            stderr.writeAll("\n") catch {};

            randomize(exes, settings.*, in_path, out_path) catch |err| {
                // TODO: Maybe print the stderr from the command we run in the randomizer
                // function
                popups.err("Failed to randomize '{s}': {}", .{ in_path, err });
                return rom;
            };

            popups.info("Rom has been randomized!", .{});
        },
        .load_settings => {
            const file = fs.cwd().openFile(selected_path.constSlice(), .{}) catch |err| {
                popups.err("Could not open '{s}': {}", .{ selected_path.constSlice(), err });
                return rom;
            };
            defer file.close();

            const allocator = settings.arena.child_allocator;
            const new_settings = Settings.load(allocator, exes, file.reader()) catch |err| {
                popups.err("Failed to load from '{s}': {}", .{ selected_path.constSlice(), err });
                return rom;
            };
            settings.deinit();
            settings.* = new_settings;
        },
        .save_settings => {
            const file = fs.cwd().createFile(selected_path.constSlice(), .{}) catch |err| {
                popups.err("Could not open '{s}': {}", .{ selected_path.constSlice(), err });
                return rom;
            };
            defer file.close();
            settings.save(exes, file.writer()) catch |err| {
                popups.err("Failed to write to '{s}': {}", .{ selected_path.constSlice(), err });
                return rom;
            };
        },
    }
    return rom;
}

pub fn drawInfo(ctx: *nk.Context, m_rom: ?Rom) void {
    if (c.nk_group_begin(ctx, "Info", border_title_group) == 0)
        return;
    defer c.nk_group_end(ctx);

    const info = if (m_rom) |*rom| rom.info.constSlice() else "No rom has been opened yet.";
    var it = mem.split(u8, info, "\n");
    while (it.next()) |line_notrim| {
        const line = mem.trimRight(u8, line_notrim, " ");
        if (line.len == 0)
            continue;

        c.nk_layout_row_dynamic(ctx, 0, 1);
        c.nk_text(ctx, line.ptr, @intCast(c_int, line.len), c.NK_TEXT_LEFT);
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
pub fn drawPopups(ctx: *nk.Context, popups: *Popups) !void {
    const layout = ctx.current.*.layout;
    const min_height = layout.*.row.min_height;
    const w: f32 = 350;
    const h: f32 = 150;
    const x = (@intToFloat(f32, c.width) / 2) - (w / 2);
    const y = (@intToFloat(f32, c.height) / 2) - (h / 2);
    const popup_rect = nk.rect(x, y, w, h);
    const fatal_err = popups.fatalError();
    const is_err = popups.errors.items.len != 0;
    const is_info = popups.infos.items.len != 0;
    if (fatal_err == null and !is_err and !is_info)
        return;

    const title = if (fatal_err) |_| "Fatal error!" else if (is_err) "Error" else "Info";
    if (c.nkPopupBegin(ctx, c.NK_POPUP_STATIC, title, border_title_group, &popup_rect) == 0)
        return;

    defer c.nk_popup_end(ctx);
    const text = fatal_err orelse if (is_err) popups.lastError() else popups.lastInfo();

    const padding_height = groupOuterHeight(ctx);
    const buttons_height = ctx.style.window.spacing.y + min_height;
    const text_height = h - (padding_height + buttons_height);

    c.nk_layout_row_dynamic(ctx, text_height, 1);
    c.nk_text_wrap(ctx, text.ptr, @intCast(c_int, text.len));

    switch (nk.buttons(ctx, .right, nk.buttonWidth(ctx, "Quit"), 0, &[_]nk.Button{
        nk.Button{ .text = if (fatal_err) |_| "Quit" else "Ok" },
    })) {
        0 => {
            if (fatal_err) |_|
                return error.FatalError;
            if (is_err) {
                popups.allocator.free(popups.errors.pop());
                c.nk_popup_close(ctx);
            }
            if (is_info) {
                popups.allocator.free(popups.infos.pop());
                c.nk_popup_close(ctx);
            }
        },
        else => {},
    }
}

/// The structure that keeps track of errors that need to be reported as popups to the user.
/// If an error occurs, it should be appended with 'popups.err("error str {}", arg1, arg2...)'.
/// It is also possible to report a fatal error with
/// 'popups.fatal("error str {}", arg1, arg2...)'. A fatal error means, that the only way to
/// recover is to exit. This error is reported to the user, after which the only option they
/// have is to quit the program. Finally, we can also just inform the user of something with
/// 'popups.info("info str {}", arg1, arg2...)'.
const Popups = struct {
    allocator: mem.Allocator,
    fatal_error: [127:0]u8 = ("\x00" ** 127).*,
    errors: std.ArrayListUnmanaged([]const u8) = std.ArrayListUnmanaged([]const u8){},
    infos: std.ArrayListUnmanaged([]const u8) = std.ArrayListUnmanaged([]const u8){},

    fn err(popups: *Popups, comptime format: []const u8, args: anytype) void {
        popups.append(&popups.errors, format, args);
    }

    fn lastError(popups: *Popups) []const u8 {
        return popups.errors.items[popups.errors.items.len - 1];
    }

    fn info(popups: *Popups, comptime format: []const u8, args: anytype) void {
        popups.append(&popups.infos, format, args);
    }

    fn lastInfo(popups: *Popups) []const u8 {
        return popups.infos.items[popups.infos.items.len - 1];
    }

    fn append(
        popups: *Popups,
        list: *std.ArrayListUnmanaged([]const u8),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const msg = fmt.allocPrint(popups.allocator, format, args) catch {
            return popups.fatal("Allocation failed", .{});
        };
        list.append(popups.allocator, msg) catch {
            popups.allocator.free(msg);
            return popups.fatal("Allocation failed", .{});
        };
    }

    fn fatal(popups: *Popups, comptime format: []const u8, args: anytype) void {
        _ = fmt.bufPrint(&popups.fatal_error, format ++ "\x00", args) catch return;
    }

    fn fatalError(popups: *const Popups) ?[]const u8 {
        const res = mem.sliceTo(&popups.fatal_error, 0);
        if (res.len == 0)
            return null;
        return res;
    }

    fn deinit(popups: *Popups) void {
        for (popups.errors.items) |e|
            popups.allocator.free(e);
        for (popups.infos.items) |i|
            popups.allocator.free(i);
        popups.errors.deinit(popups.allocator);
        popups.infos.deinit(popups.allocator);
    }
};

fn groupOuterHeight(ctx: *const nk.Context) f32 {
    return headerHeight(ctx) + (ctx.style.window.group_padding.y * 2) + ctx.style.window.spacing.y;
}

fn groupHeight(ctx: *nk.Context) f32 {
    var total_space: c.struct_nk_rect = undefined;
    c.nkWindowGetContentRegion(ctx, &total_space);
    return total_space.h - ctx.style.window.padding.y * 2;
}

fn headerHeight(ctx: *const nk.Context) f32 {
    return ctx.style.font.*.height +
        (ctx.style.window.header.padding.y * 2) +
        (ctx.style.window.header.label_padding.y * 2) + 1;
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

            const cmd = std.ChildProcess.init(
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

const Settings = struct {
    arena: heap.ArenaAllocator,

    /// The options for all commands in `exes.commands`.
    commands: std.ArrayListUnmanaged(Command) = std.ArrayListUnmanaged(Command){},

    const Command = struct {
        /// Which executable does these settings belong to
        executable: usize,

        /// For boolean options like `--enable` and `--enabled=true`
        flags: []bool,

        /// For interger options like `--int-option=10`.
        ints: []usize,

        /// For float options like `--float-option=10.0`.
        floats: []f64,

        /// For enum options like `--enum-option=option_a`. This is an index into
        /// exe.commands.emums.options
        enums: []usize,

        /// For generic string options like `--string-option='this is a string'`
        strings: []String,

        /// For options taking a file path like `--file=/home/user/.config/test.conf`
        files: []String,

        /// For multi string options like `--exclude=a --exclude=b`. Stored as lines in a string
        multi_strings: []String,

        fn init(allocator: mem.Allocator, exe_i: usize, exe: Executables.Command) !Command {
            var setting = Command{
                .executable = exe_i,
                .flags = try allocator.alloc(bool, exe.flags.len),
                .ints = try allocator.alloc(usize, exe.ints.len),
                .floats = try allocator.alloc(f64, exe.floats.len),
                .enums = try allocator.alloc(usize, exe.enums.len),
                .strings = try allocator.alloc(String, exe.strings.len),
                .files = try allocator.alloc(String, exe.files.len),
                .multi_strings = try allocator.alloc(String, exe.multi_strings.len),
            };
            mem.set(bool, setting.flags, false);
            mem.set(String, setting.multi_strings, .{});

            for (setting.ints) |*int, j|
                int.* = exe.ints[j].default;
            for (setting.floats) |*float, j|
                float.* = exe.floats[j].default;
            for (setting.enums) |*enumeration, j|
                enumeration.* = exe.enums[j].default;
            for (setting.strings) |*string, j| {
                string.* = .{};
                try string.appendSlice(allocator, exe.strings[j].default);
            }
            for (setting.files) |*string, j| {
                string.* = .{};
                try string.appendSlice(allocator, exe.files[j].default);
            }

            return setting;
        }
    };

    const String = std.ArrayListUnmanaged(u8);

    fn deinit(settings: Settings) void {
        settings.arena.deinit();
    }

    const csv_escapes = escape.default_escapes ++ [_]escape.Escape{
        .{ .escaped = "\\,", .unescaped = "," },
        .{ .escaped = "\\n", .unescaped = "\n" },
    };
    const csv_escape = escape.generate(csv_escapes);

    fn save(settings: Settings, exes: Executables, writer: anytype) !void {
        for (settings.commands.items) |setting| {
            const command = exes.commands[setting.executable];
            try csv_escape.escapeWrite(writer, util.path.basenameNoExt(command.path));
            for (command.flags) |flag, i| {
                if (!setting.flags[i])
                    continue;

                const param = command.params[flag.i];
                const prefix = if (param.names.long) |_| "--" else "-";
                const name = param.names.long orelse @as(*const [1]u8, &param.names.short.?)[0..];
                try writer.writeAll(",");
                try csv_escape.escapePrint(writer, "{s}{s}", .{ prefix, name });
            }
            for (command.ints) |int, i| {
                const param = command.params[int.i];
                try writer.writeAll(",");
                try outputArgument(writer, csv_escape, param, setting.ints[i], "");
            }
            for (command.floats) |float, i| {
                const param = command.params[float.i];
                try writer.writeAll(",");
                try outputArgument(writer, csv_escape, param, setting.floats[i], "d");
            }
            for (command.enums) |enumeration, i| {
                const param = command.params[enumeration.i];
                const value = enumeration.options[setting.enums[i]];
                try writer.writeAll(",");
                try outputArgument(writer, csv_escape, param, value, "s");
            }
            for (command.strings) |string, i| {
                const param = command.params[string.i];
                try writer.writeAll(",");
                try outputArgument(writer, csv_escape, param, setting.strings[i].items, "s");
            }
            for (command.files) |file, i| {
                const param = command.params[file.i];
                try writer.writeAll(",");
                try outputArgument(writer, csv_escape, param, setting.files[i].items, "s");
            }
            for (command.multi_strings) |multi, i| {
                const param = command.params[multi.i];
                const value = setting.multi_strings[i];
                var it = mem.tokenize(u8, value.items, "\r\n");
                while (it.next()) |string| {
                    try writer.writeAll(",");
                    try outputArgument(writer, csv_escape, param, string, "s");
                }
            }

            try writer.writeAll("\n");
        }
    }

    fn load(allocator: mem.Allocator, exes: Executables, reader: anytype) !Settings {
        var arena_state = heap.ArenaAllocator.init(allocator);
        const arena = arena_state.allocator();
        errdefer arena_state.deinit();

        var settings = std.ArrayList(Command).init(arena);

        const EscapedSplitterArgIterator = struct {
            separator: escape.EscapedSplitter,
            buf: [mem.page_size]u8 = undefined,

            pub fn next(iter: *@This()) ?[]const u8 {
                const n = iter.separator.next() orelse return null;
                var fba = std.heap.FixedBufferAllocator.init(&iter.buf);
                return csv_escape.unescapeAlloc(fba.allocator(), n) catch null;
            }
        };

        var fifo = util.io.Fifo(.Dynamic).init(allocator);
        defer fifo.deinit();

        while (try util.io.readLine(reader, &fifo)) |line| {
            var separator = escape.splitEscaped(line, "\\", ",");
            const name = separator.next() orelse continue;
            const i = findCommandIndex(exes, name) orelse continue;

            const command = exes.commands[i];
            const setting = try settings.addOne();
            setting.* = try Command.init(arena, i, command);

            var args = EscapedSplitterArgIterator{ .separator = separator };
            var streaming_clap = clap.StreamingClap(clap.Help, EscapedSplitterArgIterator){
                .iter = &args,
                .params = command.params,
            };

            while (try streaming_clap.next()) |arg| {
                const param_i = util.indexOfPtr(clap.Param(clap.Help), command.params, arg.param);
                if (findParam(command.flags, param_i)) |j| {
                    setting.flags[j] = true;
                } else if (findParam(command.ints, param_i)) |j| {
                    setting.ints[j] = fmt.parseInt(usize, arg.value.?, 10) catch
                        command.ints[j].default;
                } else if (findParam(command.floats, param_i)) |j| {
                    setting.floats[j] = fmt.parseFloat(f64, arg.value.?) catch
                        command.floats[j].default;
                } else if (findParam(command.enums, param_i)) |j| {
                    for (command.enums[j].options) |option, option_i| {
                        if (mem.eql(u8, option, arg.value.?)) {
                            setting.enums[j] = option_i;
                            break;
                        }
                    } else setting.enums[j] = command.enums[j].default;
                } else if (findParam(command.strings, param_i)) |j| {
                    const entry = &setting.strings[j];
                    entry.shrinkRetainingCapacity(0);
                    try entry.appendSlice(arena, arg.value.?);
                } else if (findParam(command.files, param_i)) |j| {
                    const entry = &setting.files[j];
                    entry.shrinkRetainingCapacity(0);
                    try entry.appendSlice(arena, arg.value.?);
                } else if (findParam(command.multi_strings, param_i)) |j| {
                    const entry = &setting.multi_strings[j];
                    try entry.appendSlice(arena, arg.value.?);
                    try entry.append(arena, '\n');
                }
            }
        }

        return Settings{
            .arena = arena_state,
            .commands = settings.moveToUnmanaged(),
        };
    }

    fn findCommandIndex(e: Executables, name: []const u8) ?usize {
        for (e.commands) |command, i| {
            if (mem.eql(u8, command.name(), name))
                return i;
        }

        return null;
    }

    fn findParam(items: anytype, i: usize) ?usize {
        for (items) |item, j| {
            if (item.i == i)
                return j;
        }
        return null;
    }
};
